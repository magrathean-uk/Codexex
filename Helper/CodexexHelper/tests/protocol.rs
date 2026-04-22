use base64::Engine;
use chrono::Utc;
use codex_app_server_protocol::AuthMode;
use codex_login::token_data::parse_chatgpt_jwt_claims;
use codex_login::{save_auth, AuthCredentialsStoreMode, AuthDotJson, TokenData};
use codexex_helper::{
    auth,
    protocol,
    protocol::{HelperRequest, HelperRequestEnvelope, HelperResponse, HelperResponseEnvelope, PROTOCOL_VERSION},
    quota,
};
use pretty_assertions::assert_eq;
use serde_json::Value;
use serial_test::serial;
use std::io::Cursor;
use tempfile::TempDir;
use wiremock::matchers::{header, method, path};
use wiremock::{Mock, MockServer, ResponseTemplate};

#[test]
fn request_round_trips() {
    let request = HelperRequestEnvelope::new(
        HelperRequest::PollDeviceAuth {
            flow_id: "flow-123".to_string(),
        },
        Some("request-123".to_string()),
    );

    let json = serde_json::to_string(&request).unwrap();
    let decoded: HelperRequestEnvelope = serde_json::from_str(&json).unwrap();

    assert_eq!(decoded, request);

    let value: Value = serde_json::from_str(&json).unwrap();
    assert_eq!(value["protocolVersion"], PROTOCOL_VERSION);
    assert_eq!(value["requestId"], "request-123");
    assert_eq!(value["method"], "pollDeviceAuth");
    assert_eq!(value["flow_id"], "flow-123");
}

#[test]
fn response_round_trips() {
    let response = HelperResponseEnvelope::from_response(
        Some("request-123".to_string()),
        HelperResponse::DeviceAuthStarted {
            flow_id: "flow-123".to_string(),
            verification_uri: "https://example.com/verify".to_string(),
            user_code: "ABCD-EFGH".to_string(),
        },
    );

    let json = serde_json::to_string(&response).unwrap();
    let decoded: HelperResponseEnvelope = serde_json::from_str(&json).unwrap();

    assert_eq!(decoded, response);

    let value: Value = serde_json::from_str(&json).unwrap();
    assert_eq!(value["protocolVersion"], PROTOCOL_VERSION);
    assert_eq!(value["requestId"], "request-123");
    assert_eq!(value["type"], "deviceAuthStarted");
    assert_eq!(value["flowId"], "flow-123");
    assert_eq!(value["verificationUri"], "https://example.com/verify");
    assert_eq!(value["userCode"], "ABCD-EFGH");
    assert!(value.get("flow_id").is_none());
    assert!(value.get("verification_uri").is_none());
    assert!(value.get("user_code").is_none());
}

#[test]
fn fetch_snapshot_without_auth_returns_signed_out_payload() {
    let response = protocol::handle_request(HelperRequest::FetchSnapshot);

    match response {
        HelperResponse::Snapshot { payload_json } => {
            let value: Value = serde_json::from_str(&payload_json).unwrap();
            assert_eq!(value["authMode"], Value::Null);
            assert_eq!(value["snapshot"], Value::Null);
        }
        other => panic!("expected snapshot payload, got {other:?}"),
    }
}

#[test]
fn quota_fetch_snapshot_returns_snapshot_variant() {
    let response = quota::fetch_snapshot().unwrap();

    assert!(matches!(response, HelperResponse::Snapshot { .. }));
}

#[test]
#[serial]
fn fetch_snapshot_keeps_chatgpt_auth_when_rate_limit_fetch_fails() {
    let _guard = EnvGuard::new();
    let temp_dir = TempDir::new().unwrap();
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .unwrap();
    let server = runtime.block_on(async {
        let server = MockServer::start().await;

        EnvGuard::set("CODEXEX_HELPER_STATE_DIR", temp_dir.path().display().to_string());
        EnvGuard::set("CODEXEX_HELPER_CHATGPT_BASE_URL", server.uri());

        Mock::given(method("GET"))
            .and(path("/api/codex/usage"))
            .and(header("authorization", "Bearer access-token-123"))
            .and(header("chatgpt-account-id", "account-123"))
            .respond_with(ResponseTemplate::new(500).set_body_string("boom"))
            .mount(&server)
            .await;

        server
    });

    persist_chatgpt_auth(temp_dir.path());

    let snapshot = quota::fetch_snapshot().unwrap();
    match snapshot {
        HelperResponse::Snapshot { payload_json } => {
            let value: Value = serde_json::from_str(&payload_json).unwrap();
            assert_eq!(value["authMode"], "chatGPT");
            assert_eq!(value["snapshot"], Value::Null);
            assert!(value["errorMessage"].as_str().unwrap().contains("boom"));
        }
        other => panic!("expected snapshot payload, got {other:?}"),
    }

    drop(server);
}

#[test]
#[serial]
fn fetch_snapshot_returns_clear_no_quota_message_when_empty() {
    let _guard = EnvGuard::new();
    let temp_dir = TempDir::new().unwrap();
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .unwrap();
    let server = runtime.block_on(async {
        let server = MockServer::start().await;

        EnvGuard::set("CODEXEX_HELPER_STATE_DIR", temp_dir.path().display().to_string());
        EnvGuard::set("CODEXEX_HELPER_CHATGPT_BASE_URL", server.uri());

        Mock::given(method("GET"))
            .and(path("/api/codex/usage"))
            .and(header("authorization", "Bearer access-token-123"))
            .and(header("chatgpt-account-id", "account-123"))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "plan_type": "pro",
                "rate_limit": null,
                "credits": null,
                "additional_rate_limits": null
            })))
            .mount(&server)
            .await;

        server
    });

    persist_chatgpt_auth(temp_dir.path());

    let snapshot = quota::fetch_snapshot().unwrap();
    match snapshot {
        HelperResponse::Snapshot { payload_json } => {
            let value: Value = serde_json::from_str(&payload_json).unwrap();
            assert_eq!(value["authMode"], "chatGPT");
            assert_eq!(value["snapshot"], Value::Null);
            assert_eq!(
                value["errorMessage"],
                "Signed in, but no quota windows were returned for this account."
            );
        }
        other => panic!("expected snapshot payload, got {other:?}"),
    }

    drop(server);
}

#[test]
fn save_api_key_requests_are_rejected() {
    let response = protocol::handle_wire_line(
        r#"{"protocolVersion":1,"requestId":"request-1","method":"saveApiKey","api_key":"sk-test-key"}"#,
    );

    let value = serde_json::to_value(response).unwrap();
    assert_eq!(value["protocolVersion"], PROTOCOL_VERSION);
    assert_eq!(value["requestId"], "request-1");
    assert_eq!(value["type"], "error");
    assert!(value["message"].as_str().unwrap().starts_with("invalid request:"));
}

#[test]
fn missing_protocol_version_is_rejected() {
    let response = protocol::handle_wire_line(r#"{"requestId":"request-1","method":"signOut"}"#);

    let value = serde_json::to_value(response).unwrap();
    assert_eq!(value["protocolVersion"], PROTOCOL_VERSION);
    assert_eq!(value["type"], "error");
    assert!(value["message"].as_str().unwrap().contains("protocolVersion"));
}

#[test]
fn unsupported_protocol_version_returns_error_with_request_id() {
    let response = protocol::handle_wire_line(
        r#"{"protocolVersion":99,"requestId":"request-99","method":"signOut"}"#,
    );

    let value = serde_json::to_value(response).unwrap();
    assert_eq!(value["protocolVersion"], PROTOCOL_VERSION);
    assert_eq!(value["requestId"], "request-99");
    assert_eq!(value["type"], "error");
    assert_eq!(
        value["message"],
        format!("unsupported protocol version 99 (expected {PROTOCOL_VERSION})")
    );
}

#[test]
fn poll_device_auth_does_not_succeed_for_random_flow_id() {
    let error = auth::poll_device_auth("flow-123").unwrap_err();

    assert_eq!(error.to_string(), "unknown flow id");
}

#[test]
fn poll_device_auth_does_not_succeed_for_empty_flow_id() {
    let error = auth::poll_device_auth("").unwrap_err();

    assert_eq!(error.to_string(), "flow id is empty");
}

#[test]
fn sign_out_returns_signed_out() {
    let response = auth::sign_out().unwrap();

    assert_eq!(response, HelperResponse::SignedOut);
}

#[test]
fn malformed_input_becomes_error_response() {
    let response = codexex_helper::protocol::handle_line("not-json");

    assert!(matches!(
        response,
        HelperResponse::Error {
            message
        } if message.starts_with("invalid request:")
    ));
}

#[test]
fn stream_continues_after_invalid_line() {
    let input = Cursor::new(
        br#"not-json
{"protocolVersion":1,"requestId":"request-2","method":"signOut"}
"#
        .as_slice(),
    );
    let mut output = Vec::new();

    codexex_helper::protocol::process_stream(input, &mut output).unwrap();

    let output = String::from_utf8(output).unwrap();
    let lines: Vec<&str> = output.lines().collect();

    assert_eq!(lines.len(), 2);
    let first: Value = serde_json::from_str(lines[0]).unwrap();
    assert_eq!(first["protocolVersion"], PROTOCOL_VERSION);
    assert_eq!(first["type"], "error");
    assert!(first["message"].as_str().unwrap().starts_with("invalid request:"));

    let second: Value = serde_json::from_str(lines[1]).unwrap();
    assert_eq!(second["protocolVersion"], PROTOCOL_VERSION);
    assert_eq!(second["requestId"], "request-2");
    assert_eq!(second["type"], "signedOut");
}

#[test]
#[serial]
fn device_auth_flow_can_poll_pending_without_losing_flow_state() {
    let _guard = EnvGuard::new();
    let temp_dir = TempDir::new().unwrap();
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .unwrap();
    let server = runtime.block_on(async {
        let server = MockServer::start().await;

        EnvGuard::set("CODEXEX_HELPER_STATE_DIR", temp_dir.path().display().to_string());
        EnvGuard::set("CODEXEX_HELPER_ISSUER", server.uri());
        EnvGuard::set("CODEXEX_HELPER_CHATGPT_BASE_URL", server.uri());

        Mock::given(method("POST"))
            .and(path("/api/accounts/deviceauth/usercode"))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "device_auth_id": "device-auth-123",
                "user_code": "CODE-12345",
                "interval": "0"
            })))
            .mount(&server)
            .await;

        Mock::given(method("POST"))
            .and(path("/api/accounts/deviceauth/token"))
            .respond_with(ResponseTemplate::new(404))
            .mount(&server)
            .await;

        server
    });

    let flow_id = match auth::begin_device_auth().unwrap() {
        HelperResponse::DeviceAuthStarted { flow_id, .. } => flow_id,
        other => panic!("expected device auth start, got {other:?}"),
    };

    let first = auth::poll_device_auth(&flow_id).unwrap();
    let second = auth::poll_device_auth(&flow_id).unwrap();

    assert_eq!(
        first,
        HelperResponse::DeviceAuthPending {
            message: "Still waiting for approval. Finish in Safari, then check again.".to_string(),
        }
    );
    assert_eq!(second, first);
    drop(server);
}

#[test]
#[serial]
fn device_auth_flow_persists_login_and_fetches_live_snapshot() {
    let _guard = EnvGuard::new();
    let temp_dir = TempDir::new().unwrap();
    let runtime = tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
        .unwrap();
    let server = runtime.block_on(async {
        let server = MockServer::start().await;

        EnvGuard::set("CODEXEX_HELPER_STATE_DIR", temp_dir.path().display().to_string());
        EnvGuard::set("CODEXEX_HELPER_ISSUER", server.uri());
        EnvGuard::set("CODEXEX_HELPER_CHATGPT_BASE_URL", server.uri());

        Mock::given(method("POST"))
            .and(path("/api/accounts/deviceauth/usercode"))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "device_auth_id": "device-auth-123",
                "user_code": "CODE-12345",
                "interval": "0"
            })))
            .mount(&server)
            .await;

        Mock::given(method("POST"))
            .and(path("/api/accounts/deviceauth/token"))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "authorization_code": "poll-code-321",
                "code_challenge": "code-challenge-321",
                "code_verifier": "code-verifier-321"
            })))
            .mount(&server)
            .await;

        Mock::given(method("POST"))
            .and(path("/oauth/token"))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "id_token": fake_jwt(serde_json::json!({
                    "email": "user@example.com",
                    "https://api.openai.com/auth": {
                        "chatgpt_account_id": "account-123",
                        "chatgpt_plan_type": "pro"
                    }
                })),
                "access_token": "access-token-123",
                "refresh_token": "refresh-token-123"
            })))
            .mount(&server)
            .await;

        Mock::given(method("GET"))
            .and(path("/api/codex/usage"))
            .and(header("authorization", "Bearer access-token-123"))
            .and(header("chatgpt-account-id", "account-123"))
            .respond_with(ResponseTemplate::new(200).set_body_json(serde_json::json!({
                "plan_type": "pro",
                "rate_limit": {
                    "allowed": true,
                    "limit_reached": false,
                    "primary_window": {
                        "used_percent": 42,
                        "limit_window_seconds": 18000,
                        "reset_after_seconds": 120,
                        "reset_at": 1735689720
                    },
                    "secondary_window": {
                        "used_percent": 5,
                        "limit_window_seconds": 604800,
                        "reset_after_seconds": 3600,
                        "reset_at": 1736294400
                    }
                },
                "additional_rate_limits": [
                    {
                        "limit_name": "Codex Spark",
                        "metered_feature": "spark",
                        "rate_limit": {
                            "allowed": true,
                            "limit_reached": false,
                            "primary_window": {
                                "used_percent": 88,
                                "limit_window_seconds": 18000,
                                "reset_after_seconds": 600,
                                "reset_at": 1735693200
                            }
                        }
                    }
                ]
            })))
            .mount(&server)
            .await;

        server
    });

    let started = auth::begin_device_auth().unwrap();
    let flow_id = match started {
        HelperResponse::DeviceAuthStarted {
            flow_id,
            verification_uri,
            user_code,
        } => {
            assert_eq!(verification_uri, format!("{}/codex/device", server.uri()));
            assert_eq!(user_code, "CODE-12345");
            flow_id
        }
        other => panic!("expected device auth start, got {other:?}"),
    };

    let completion = auth::poll_device_auth(&flow_id).unwrap();
    assert_eq!(completion, HelperResponse::SignedIn);

    let snapshot = quota::fetch_snapshot().unwrap();
    match snapshot {
        HelperResponse::Snapshot { payload_json } => {
            let value: Value = serde_json::from_str(&payload_json).unwrap();
            assert_eq!(value["authMode"], "chatGPT");
            assert_eq!(value["snapshot"]["account"]["email"], "user@example.com");
            assert_eq!(value["snapshot"]["limits"][0]["bucket"], "codex");
        }
        other => panic!("expected service snapshot payload, got {other:?}"),
    }
}

fn fake_jwt(payload: Value) -> String {
    let header = serde_json::json!({ "alg": "none", "typ": "JWT" });
    let encode = |value: &Value| -> String {
        base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(serde_json::to_vec(value).unwrap())
    };
    format!("{}.{}.sig", encode(&header), encode(&payload))
}

fn persist_chatgpt_auth(codex_home: &std::path::Path) {
    let id_token = fake_jwt(serde_json::json!({
        "email": "user@example.com",
        "https://api.openai.com/auth": {
            "chatgpt_account_id": "account-123",
            "chatgpt_plan_type": "pro"
        }
    }));

    let auth = AuthDotJson {
        auth_mode: Some(AuthMode::Chatgpt),
        openai_api_key: None,
        tokens: Some(TokenData {
            id_token: parse_chatgpt_jwt_claims(&id_token).unwrap(),
            access_token: "access-token-123".to_string(),
            refresh_token: "refresh-token-123".to_string(),
            account_id: Some("account-123".to_string()),
        }),
        last_refresh: Some(Utc::now()),
    };

    save_auth(codex_home, &auth, AuthCredentialsStoreMode::File).unwrap();
}

struct EnvGuard;

impl EnvGuard {
    fn new() -> Self {
        Self
    }

    fn set(key: &str, value: String) {
        unsafe { std::env::set_var(key, value) }
    }
}

impl Drop for EnvGuard {
    fn drop(&mut self) {
        unsafe {
            std::env::remove_var("CODEXEX_HELPER_STATE_DIR");
            std::env::remove_var("CODEXEX_HELPER_ISSUER");
            std::env::remove_var("CODEXEX_HELPER_CHATGPT_BASE_URL");
        }
    }
}
