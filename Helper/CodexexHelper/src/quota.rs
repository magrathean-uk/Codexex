use anyhow::Result;
use codex_backend_client::Client as BackendClient;
use codex_login::{
    AuthCredentialsStoreMode, AuthKeyringBackendKind, AuthManager, RefreshTokenError,
};
use serde::Serialize;
use tokio::runtime::Builder;

use crate::protocol::HelperResponse;
use crate::state;

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct ServiceSnapshotPayload {
    auth_mode: Option<String>,
    snapshot: Option<SnapshotPayload>,
    error_message: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct SnapshotPayload {
    captured_at: f64,
    executable_path: String,
    account: AccountPayload,
    limits: Vec<LimitPayload>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct AccountPayload {
    auth_type: String,
    email: Option<String>,
    plan_type: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct LimitPayload {
    id: String,
    raw_limit_name: Option<String>,
    bucket: String,
    primary: Option<WindowPayload>,
    secondary: Option<WindowPayload>,
    credits: Option<CreditsPayload>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct WindowPayload {
    used_percent: f64,
    window_duration_minutes: Option<i64>,
    resets_at: Option<f64>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct CreditsPayload {
    has_credits: bool,
    unlimited: bool,
    balance: Option<String>,
}

fn runtime() -> Result<tokio::runtime::Runtime> {
    Builder::new_current_thread()
        .enable_all()
        .build()
        .map_err(Into::into)
}

pub fn fetch_snapshot() -> Result<HelperResponse> {
    let payload = runtime()?.block_on(fetch_snapshot_payload())?;
    Ok(HelperResponse::Snapshot {
        payload_json: serde_json::to_string(&payload)?,
    })
}

async fn fetch_snapshot_payload() -> Result<ServiceSnapshotPayload> {
    let http_client_factory = state::http_client_factory();
    let auth_manager = AuthManager::shared(
        state::codex_home()?,
        false,
        AuthCredentialsStoreMode::File,
        None,
        Some(state::chatgpt_base_url()),
        AuthKeyringBackendKind::default(),
        state::auth_route_config(),
    )
    .await;
    let Some(mut auth) = auth_manager.auth().await else {
        return Ok(ServiceSnapshotPayload {
            auth_mode: None,
            snapshot: None,
            error_message: Some("Not signed in. Use the button below.".to_string()),
        });
    };

    if !auth.is_chatgpt_auth() {
        return Ok(ServiceSnapshotPayload {
            auth_mode: None,
            snapshot: None,
            error_message: Some("Codex is not signed in with ChatGPT.".to_string()),
        });
    }

    let client = BackendClient::from_auth(state::chatgpt_base_url(), &auth, http_client_factory);
    let mut rate_limits_result = client.get_rate_limits_many().await;
    if rate_limits_result
        .as_ref()
        .is_err_and(|error| backend_http_status(error) == Some(401))
    {
        let mut recovery = auth_manager.unauthorized_recovery();
        let recovery_result = async {
            while recovery.has_next() {
                let step = recovery.next().await?;
                if step.auth_state_changed() == Some(true) {
                    break;
                }
            }
            Ok::<(), RefreshTokenError>(())
        }
        .await;

        match recovery_result {
            Ok(()) => {
                let Some(refreshed_auth) = auth_manager.auth_cached() else {
                    return Ok(signed_out_payload());
                };
                if !refreshed_auth.is_chatgpt_auth() {
                    return Ok(signed_out_payload());
                }
                auth = refreshed_auth;
                let retry_client = BackendClient::from_auth(
                    state::chatgpt_base_url(),
                    &auth,
                    state::http_client_factory(),
                );
                // Exactly one backend retry with the recovered credential.
                rate_limits_result = retry_client.get_rate_limits_many().await;
            }
            Err(RefreshTokenError::Permanent(_)) => {
                return Ok(expired_sign_in_payload());
            }
            Err(RefreshTokenError::Transient(_)) => {
                return Ok(signed_in_error_payload(
                    "Could not refresh ChatGPT sign-in. Check your connection and try again.",
                ));
            }
        }
    }

    let rate_limits = match rate_limits_result {
        Ok(rate_limits) if !rate_limits.is_empty() => rate_limits,
        Ok(_) => {
            return Ok(ServiceSnapshotPayload {
                auth_mode: Some("chatGPT".to_string()),
                snapshot: None,
                error_message: Some(
                    "Signed in, but no quota windows were returned for this account.".to_string(),
                ),
            });
        }
        Err(error) => {
            return Ok(signed_in_error_payload(backend_user_message(&error)));
        }
    };

    let limits: Vec<LimitPayload> = rate_limits
        .into_iter()
        .map(|limit| {
            let id = limit.limit_id.unwrap_or_else(|| "codex".to_string());
            let raw_limit_name = limit.limit_name;
            LimitPayload {
                bucket: infer_bucket(&id, raw_limit_name.as_deref()).to_string(),
                id,
                raw_limit_name,
                primary: limit.primary.map(|window| WindowPayload {
                    used_percent: window.used_percent,
                    window_duration_minutes: window.window_minutes,
                    resets_at: window.resets_at.map(|value| value as f64),
                }),
                secondary: limit.secondary.map(|window| WindowPayload {
                    used_percent: window.used_percent,
                    window_duration_minutes: window.window_minutes,
                    resets_at: window.resets_at.map(|value| value as f64),
                }),
                credits: limit.credits.map(|credits| CreditsPayload {
                    has_credits: credits.has_credits,
                    unlimited: credits.unlimited,
                    balance: credits.balance,
                }),
            }
        })
        .filter(|limit| {
            limit.primary.is_some() || limit.secondary.is_some() || limit.credits.is_some()
        })
        .collect();

    if limits.is_empty() {
        return Ok(ServiceSnapshotPayload {
            auth_mode: Some("chatGPT".to_string()),
            snapshot: None,
            error_message: Some(
                "Signed in, but no quota windows were returned for this account.".to_string(),
            ),
        });
    }

    let snapshot = SnapshotPayload {
        captured_at: std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)?
            .as_secs_f64(),
        executable_path: state::executable_path(),
        account: AccountPayload {
            auth_type: "chatGPT".to_string(),
            email: auth.get_account_email(),
            plan_type: auth.account_plan_type().map(|plan| format!("{plan:?}")),
        },
        limits,
    };

    Ok(ServiceSnapshotPayload {
        auth_mode: Some("chatGPT".to_string()),
        snapshot: Some(snapshot),
        error_message: None,
    })
}

fn signed_out_payload() -> ServiceSnapshotPayload {
    ServiceSnapshotPayload {
        auth_mode: None,
        snapshot: None,
        error_message: Some("Not signed in. Use the button below.".to_string()),
    }
}

fn expired_sign_in_payload() -> ServiceSnapshotPayload {
    ServiceSnapshotPayload {
        auth_mode: None,
        snapshot: None,
        error_message: Some(
            "Your ChatGPT sign-in expired or was revoked. Sign in again.".to_string(),
        ),
    }
}

fn signed_in_error_payload(message: &str) -> ServiceSnapshotPayload {
    ServiceSnapshotPayload {
        auth_mode: Some("chatGPT".to_string()),
        snapshot: None,
        error_message: Some(message.to_string()),
    }
}

fn backend_user_message(error: &anyhow::Error) -> &'static str {
    match backend_http_status(error) {
        Some(403) => {
            "Quota access is unavailable for this account. Your ChatGPT sign-in is still active."
        }
        Some(429) => "Quota refresh is rate-limited. Try again shortly.",
        Some(500..=599) => "OpenAI quota service is temporarily unavailable. Try again shortly.",
        Some(401) => {
            "Quota access is temporarily unavailable. Your ChatGPT sign-in is still active."
        }
        _ => "Quota is temporarily unavailable. Refresh again shortly.",
    }
}

fn backend_http_status(error: &anyhow::Error) -> Option<u16> {
    error.chain().find_map(|cause| {
        let message = cause.to_string();
        let status_prefix = message
            .split_once("; content-type=")
            .map_or(message.as_str(), |(prefix, _)| prefix);
        let (_, status) = status_prefix.rsplit_once(" failed: ")?;
        status.split_whitespace().next()?.parse().ok()
    })
}

fn infer_bucket(limit_id: &str, limit_name: Option<&str>) -> &'static str {
    let haystack = format!("{} {}", limit_id, limit_name.unwrap_or_default()).to_lowercase();
    if haystack.contains("spark") {
        "spark"
    } else if haystack.contains("codex") {
        "codex"
    } else {
        "other"
    }
}
