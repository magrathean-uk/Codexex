use anyhow::Result;
use codex_backend_client::Client as BackendClient;
use codex_login::{AuthCredentialsStoreMode, AuthManager};
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
    let auth_manager = AuthManager::shared(state::codex_home()?, false, AuthCredentialsStoreMode::File);
    let Some(auth) = auth_manager.auth().await else {
        return Ok(ServiceSnapshotPayload {
            auth_mode: None,
            snapshot: None,
            error_message: Some("Not signed in. Use the button below.".to_string()),
        });
    };

    if auth.is_chatgpt_auth() == false {
        return Ok(ServiceSnapshotPayload {
            auth_mode: None,
            snapshot: None,
            error_message: Some("Codex is not signed in with ChatGPT.".to_string()),
        });
    }

    let client = BackendClient::from_auth(state::chatgpt_base_url(), &auth)?;
    let rate_limits = match client.get_rate_limits_many().await {
        Ok(rate_limits) if rate_limits.is_empty() == false => rate_limits,
        Ok(_) => {
            return Ok(ServiceSnapshotPayload {
                auth_mode: Some("chatGPT".to_string()),
                snapshot: None,
                error_message: Some("Signed in, but no quota windows were returned for this account.".to_string()),
            })
        }
        Err(error) => {
            return Ok(ServiceSnapshotPayload {
                auth_mode: Some("chatGPT".to_string()),
                snapshot: None,
                error_message: Some(error.to_string()),
            })
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
        .filter(|limit| limit.primary.is_some() || limit.secondary.is_some() || limit.credits.is_some())
        .collect();

    if limits.is_empty() {
        return Ok(ServiceSnapshotPayload {
            auth_mode: Some("chatGPT".to_string()),
            snapshot: None,
            error_message: Some("Signed in, but no quota windows were returned for this account.".to_string()),
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
