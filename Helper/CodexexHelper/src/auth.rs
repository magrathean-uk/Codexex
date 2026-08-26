use anyhow::{Context, Result, bail};
use chrono::Utc;
use codex_client::build_reqwest_client_with_custom_ca;
use codex_login::token_data::parse_chatgpt_jwt_claims;
use codex_login::{
    AuthCredentialsStoreMode, AuthDotJson, AuthKeyringBackendKind, TokenData, logout, save_auth,
};
use codex_protocol::auth::AuthMode;
use reqwest::Response;
use reqwest::StatusCode;
use reqwest::header::RETRY_AFTER;
use serde::de::{self, Deserializer};
use serde::{Deserialize, Serialize};
use std::time::{Duration, SystemTime};
use tokio::runtime::Builder;

use crate::flow_registry;
use crate::protocol::HelperResponse;
use crate::secure_file_permissions::harden_helper_state_permissions;
use crate::state;

const PENDING_APPROVAL_MESSAGE: &str =
    "Still waiting for approval. Finish in Safari, then check again.";
const AUTH_HTTP_TIMEOUT_SECS: u64 = 12;
const _: () = assert!(flow_registry::OPERATION_LEASE_SECS >= AUTH_HTTP_TIMEOUT_SECS + 10);

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
pub(crate) struct StoredDeviceCode {
    pub(crate) verification_url: String,
    pub(crate) user_code: String,
    pub(crate) device_auth_id: String,
    pub(crate) interval: u64,
}

#[derive(Debug, Deserialize)]
struct UserCodeResp {
    device_auth_id: String,
    #[serde(alias = "user_code", alias = "usercode")]
    user_code: String,
    #[serde(default, deserialize_with = "deserialize_interval")]
    interval: u64,
}

#[derive(Debug, Serialize)]
struct UserCodeReq {
    client_id: String,
}

#[derive(Debug, Serialize)]
struct TokenPollReq {
    device_auth_id: String,
    user_code: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
pub(crate) struct ApprovedDeviceCode {
    pub(crate) authorization_code: String,
    #[serde(rename = "code_challenge")]
    pub(crate) _code_challenge: String,
    pub(crate) code_verifier: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
pub(crate) struct TokenExchangeResp {
    pub(crate) id_token: String,
    pub(crate) access_token: String,
    pub(crate) refresh_token: String,
}

enum PollOutcome {
    Pending {
        retry_after: Option<Duration>,
        slow_down: bool,
    },
    Approved(ApprovedDeviceCode),
    RetryableFailure {
        message: String,
        retry_after: Option<Duration>,
        slow_down: bool,
    },
    TerminalFailure {
        message: String,
    },
}

enum ExchangeOutcome {
    Exchanged(TokenExchangeResp),
    RetryableFailure {
        message: String,
        retry_after: Option<Duration>,
        slow_down: bool,
    },
    TerminalFailure {
        message: String,
    },
}

fn deserialize_interval<'de, D>(deserializer: D) -> Result<u64, D::Error>
where
    D: Deserializer<'de>,
{
    let s = String::deserialize(deserializer)?;
    s.trim().parse::<u64>().map_err(de::Error::custom)
}

fn runtime() -> Result<tokio::runtime::Runtime> {
    Builder::new_current_thread()
        .enable_all()
        .build()
        .context("failed to create helper runtime")
}

fn client() -> Result<reqwest::Client> {
    build_reqwest_client_with_custom_ca(
        reqwest::Client::builder().timeout(Duration::from_secs(AUTH_HTTP_TIMEOUT_SECS)),
    )
    .map_err(Into::into)
}

pub fn begin_device_auth() -> Result<HelperResponse> {
    let opts = state::server_options()?;
    let device_code = runtime()?.block_on(request_device_code(&opts))?;
    let flow_id = flow_registry::insert(device_code.clone())?;
    Ok(HelperResponse::DeviceAuthStarted {
        flow_id,
        verification_uri: device_code.verification_url,
        user_code: device_code.user_code,
    })
}

pub fn poll_device_auth(flow_id: &str) -> Result<HelperResponse> {
    let trimmed = flow_id.trim();
    if trimmed.is_empty() || trimmed.len() > 96 {
        bail!("Sign-in code expired. Start again.");
    }

    let opts = state::server_options()?;
    match flow_registry::begin_poll(trimmed)? {
        flow_registry::FlowAction::Wait { .. } => Ok(pending_response()),
        flow_registry::FlowAction::Poll(device_code, claim) => {
            let outcome = match runtime()
                .and_then(|runtime| runtime.block_on(poll_for_token_once(&opts, &device_code)))
            {
                Ok(outcome) => outcome,
                Err(error) => {
                    let _ = flow_registry::defer(trimmed, claim, None, false);
                    return Err(error);
                }
            };
            match outcome {
                PollOutcome::Pending {
                    retry_after,
                    slow_down,
                } => {
                    let _ = apply_backoff(trimmed, claim, retry_after, slow_down)?;
                    Ok(pending_response())
                }
                PollOutcome::Approved(code) => {
                    if !flow_registry::mark_approved(trimmed, claim, code.clone())? {
                        return Ok(pending_response());
                    }
                    exchange_and_finish(trimmed, claim, &opts, code)
                }
                PollOutcome::RetryableFailure {
                    message,
                    retry_after,
                    slow_down,
                } => retryable_failure(trimmed, claim, message, retry_after, slow_down),
                PollOutcome::TerminalFailure { message } => {
                    terminal_failure(trimmed, claim, message)
                }
            }
        }
        flow_registry::FlowAction::Exchange(code, claim) => {
            exchange_and_finish(trimmed, claim, &opts, code)
        }
        flow_registry::FlowAction::Persist(tokens, claim) => {
            persist_and_finish(trimmed, claim, &opts, tokens)
        }
    }
}

pub fn cancel_device_auth(flow_id: &str) -> Result<HelperResponse> {
    let trimmed = flow_id.trim();
    if trimmed.is_empty() || trimmed.len() > 96 {
        bail!("Sign-in code expired. Start again.");
    }
    flow_registry::remove(trimmed)?;
    Ok(HelperResponse::DeviceAuthCancelled)
}

pub fn sign_out() -> Result<HelperResponse> {
    let codex_home = state::codex_home()?;
    flow_registry::clear_all_with(|| {
        let _ = logout(
            &codex_home,
            AuthCredentialsStoreMode::File,
            AuthKeyringBackendKind::default(),
        )?;
        Ok(())
    })?;
    Ok(HelperResponse::SignedOut)
}

fn pending_response() -> HelperResponse {
    HelperResponse::DeviceAuthPending {
        message: PENDING_APPROVAL_MESSAGE.to_string(),
    }
}

fn exchange_and_finish(
    flow_id: &str,
    claim: flow_registry::FlowClaim,
    opts: &codex_login::ServerOptions,
    code: ApprovedDeviceCode,
) -> Result<HelperResponse> {
    let outcome =
        match runtime().and_then(|runtime| runtime.block_on(exchange_approved_login(opts, code))) {
            Ok(outcome) => outcome,
            Err(error) => {
                let _ = flow_registry::defer(flow_id, claim, None, false);
                return Err(error);
            }
        };
    match outcome {
        ExchangeOutcome::Exchanged(tokens) => {
            if !flow_registry::mark_exchanged(flow_id, claim, tokens.clone())? {
                return Ok(pending_response());
            }
            persist_and_finish(flow_id, claim, opts, tokens)
        }
        ExchangeOutcome::RetryableFailure {
            message,
            retry_after,
            slow_down,
        } => retryable_failure(flow_id, claim, message, retry_after, slow_down),
        ExchangeOutcome::TerminalFailure { message } => terminal_failure(flow_id, claim, message),
    }
}

fn persist_and_finish(
    flow_id: &str,
    claim: flow_registry::FlowClaim,
    opts: &codex_login::ServerOptions,
    tokens: TokenExchangeResp,
) -> Result<HelperResponse> {
    if flow_registry::finish_if_claimed(flow_id, claim, || persist_tokens(opts, tokens))? {
        Ok(HelperResponse::SignedIn)
    } else {
        Ok(pending_response())
    }
}

fn apply_backoff(
    flow_id: &str,
    claim: flow_registry::FlowClaim,
    retry_after: Option<Duration>,
    slow_down: bool,
) -> Result<bool> {
    flow_registry::defer(flow_id, claim, retry_after, slow_down)
}

fn retryable_failure(
    flow_id: &str,
    claim: flow_registry::FlowClaim,
    message: String,
    retry_after: Option<Duration>,
    slow_down: bool,
) -> Result<HelperResponse> {
    if apply_backoff(flow_id, claim, retry_after, slow_down)? {
        bail!(message)
    }
    Ok(pending_response())
}

fn terminal_failure(
    flow_id: &str,
    claim: flow_registry::FlowClaim,
    message: String,
) -> Result<HelperResponse> {
    if flow_registry::remove_if_claimed(flow_id, claim)? {
        bail!(message)
    }
    Ok(pending_response())
}

async fn request_device_code(opts: &codex_login::ServerOptions) -> Result<StoredDeviceCode> {
    let client = client()?;
    let base_url = opts.issuer.trim_end_matches('/');
    let api_base_url = format!("{base_url}/api/accounts");
    let url = format!("{api_base_url}/deviceauth/usercode");
    let body = serde_json::to_string(&UserCodeReq {
        client_id: opts.client_id.clone(),
    })?;

    let resp = client
        .post(url)
        .header("Content-Type", "application/json")
        .body(body)
        .send()
        .await
        .map_err(std::io::Error::other)?;

    if !resp.status().is_success() {
        let status = resp.status();
        if status == StatusCode::NOT_FOUND {
            bail!(
                "device code login is not enabled for this Codex server. Use the browser login or verify the server URL."
            );
        }
        bail!("device code request failed with status {status}");
    }

    let body = resp.text().await.map_err(std::io::Error::other)?;
    let user_code: UserCodeResp = serde_json::from_str(&body).map_err(std::io::Error::other)?;

    Ok(StoredDeviceCode {
        verification_url: format!("{base_url}/codex/device"),
        user_code: user_code.user_code,
        device_auth_id: user_code.device_auth_id,
        interval: user_code.interval,
    })
}

async fn poll_for_token_once(
    opts: &codex_login::ServerOptions,
    device_code: &StoredDeviceCode,
) -> Result<PollOutcome> {
    let client = client()?;
    let base_url = opts.issuer.trim_end_matches('/');
    let api_base_url = format!("{base_url}/api/accounts");
    let url = format!("{api_base_url}/deviceauth/token");
    let body = serde_json::to_string(&TokenPollReq {
        device_auth_id: device_code.device_auth_id.clone(),
        user_code: device_code.user_code.clone(),
    })?;

    let resp = client
        .post(url)
        .header("Content-Type", "application/json")
        .body(body)
        .send()
        .await
        .map_err(std::io::Error::other)?;

    let status = resp.status();
    if status.is_success() {
        let payload = resp
            .json::<ApprovedDeviceCode>()
            .await
            .map_err(std::io::Error::other)?;
        return Ok(PollOutcome::Approved(payload));
    }

    let retry_after = retry_after(&resp, SystemTime::now());
    let body = resp.text().await.unwrap_or_default();
    let error_code = device_auth_error_code(&body);

    if status == StatusCode::FORBIDDEN
        || status == StatusCode::NOT_FOUND
        || error_code == Some("authorization_pending")
    {
        return Ok(PollOutcome::Pending {
            retry_after,
            slow_down: false,
        });
    }

    if error_code == Some("slow_down") || status == StatusCode::TOO_MANY_REQUESTS {
        return Ok(PollOutcome::Pending {
            retry_after,
            slow_down: error_code == Some("slow_down") || retry_after.is_none(),
        });
    }

    if retryable_status(status) {
        return Ok(PollOutcome::RetryableFailure {
            message: format!("device auth temporarily failed with status {status}"),
            retry_after,
            slow_down: false,
        });
    }

    Ok(PollOutcome::TerminalFailure {
        message: format!("device auth failed with status {status}. Start again."),
    })
}

async fn exchange_approved_login(
    opts: &codex_login::ServerOptions,
    code: ApprovedDeviceCode,
) -> Result<ExchangeOutcome> {
    let base_url = opts.issuer.trim_end_matches('/');
    let client = client()?;
    let redirect_uri = format!("{base_url}/deviceauth/callback");
    let body = format!(
        "grant_type=authorization_code&code={}&redirect_uri={}&client_id={}&code_verifier={}",
        urlencoding::encode(&code.authorization_code),
        urlencoding::encode(&redirect_uri),
        urlencoding::encode(&opts.client_id),
        urlencoding::encode(&code.code_verifier)
    );

    let resp = client
        .post(format!("{base_url}/oauth/token"))
        .header("Content-Type", "application/x-www-form-urlencoded")
        .body(body)
        .send()
        .await
        .map_err(std::io::Error::other)?;

    let status = resp.status();
    if !status.is_success() {
        let retry_after = retry_after(&resp, SystemTime::now());
        if retryable_status(status) {
            return Ok(ExchangeOutcome::RetryableFailure {
                message: format!("token endpoint temporarily failed with status {status}"),
                retry_after,
                slow_down: status == StatusCode::TOO_MANY_REQUESTS && retry_after.is_none(),
            });
        }
        return Ok(ExchangeOutcome::TerminalFailure {
            message: format!("token endpoint returned status {status}. Start again."),
        });
    }

    let tokens = resp
        .json::<TokenExchangeResp>()
        .await
        .map_err(std::io::Error::other)?;
    Ok(ExchangeOutcome::Exchanged(tokens))
}

fn retryable_status(status: StatusCode) -> bool {
    status == StatusCode::REQUEST_TIMEOUT
        || status == StatusCode::TOO_EARLY
        || status == StatusCode::TOO_MANY_REQUESTS
        || status.is_server_error()
}

fn device_auth_error_code(body: &str) -> Option<&str> {
    #[derive(Deserialize)]
    struct ErrorPayload<'a> {
        #[serde(borrow)]
        error: Option<&'a str>,
    }

    serde_json::from_str::<ErrorPayload<'_>>(body)
        .ok()
        .and_then(|payload| payload.error)
}

fn retry_after(response: &Response, now: SystemTime) -> Option<Duration> {
    let value = response.headers().get(RETRY_AFTER)?.to_str().ok()?.trim();
    parse_retry_after(value, now)
}

fn parse_retry_after(value: &str, now: SystemTime) -> Option<Duration> {
    if let Ok(seconds) = value.parse::<u64>() {
        return Some(Duration::from_secs(seconds));
    }
    let deadline = httpdate::parse_http_date(value).ok()?;
    deadline.duration_since(now).ok()
}

fn persist_tokens(opts: &codex_login::ServerOptions, tokens: TokenExchangeResp) -> Result<()> {
    let mut token_data = TokenData {
        id_token: parse_chatgpt_jwt_claims(&tokens.id_token).map_err(std::io::Error::other)?,
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
        account_id: None,
    };
    token_data.account_id = token_data.id_token.chatgpt_account_id.clone();

    let auth = AuthDotJson {
        auth_mode: Some(AuthMode::Chatgpt),
        openai_api_key: None,
        tokens: Some(token_data),
        last_refresh: Some(Utc::now()),
        agent_identity: None,
        personal_access_token: None,
        bedrock_api_key: None,
    };
    save_auth(
        &opts.codex_home,
        &auth,
        AuthCredentialsStoreMode::File,
        AuthKeyringBackendKind::default(),
    )
    .context("failed to persist approved ChatGPT login")?;
    harden_helper_state_permissions(&opts.codex_home)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::UNIX_EPOCH;

    #[test]
    fn parses_retry_after_seconds_and_http_date() {
        let now = UNIX_EPOCH + Duration::from_secs(1_700_000_000);
        let deadline = now + Duration::from_secs(17);

        assert_eq!(parse_retry_after("9", now), Some(Duration::from_secs(9)));
        assert_eq!(
            parse_retry_after(&httpdate::fmt_http_date(deadline), now),
            Some(Duration::from_secs(17))
        );
    }

    #[test]
    fn recognizes_standard_device_auth_pending_codes() {
        assert_eq!(
            device_auth_error_code(r#"{"error":"authorization_pending"}"#),
            Some("authorization_pending")
        );
        assert_eq!(
            device_auth_error_code(r#"{"error":"slow_down"}"#),
            Some("slow_down")
        );
    }
}
