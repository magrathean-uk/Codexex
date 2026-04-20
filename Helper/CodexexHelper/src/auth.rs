use anyhow::{Context, Result, bail};
use base64::Engine;
use chrono::Utc;
use codex_app_server_protocol::AuthMode;
use codex_client::build_reqwest_client_with_custom_ca;
use codex_login::{
    AuthCredentialsStoreMode, AuthDotJson, TokenData, logout, save_auth,
};
use codex_login::token_data::parse_chatgpt_jwt_claims;
use reqwest::StatusCode;
use serde::{Deserialize, Serialize};
use serde::de::{self, Deserializer};
use tokio::runtime::Builder;

use crate::protocol::HelperResponse;
use crate::state;

const PENDING_APPROVAL_MESSAGE: &str = "Still waiting for approval. Finish in Safari, then check again.";

#[derive(Debug, Clone, PartialEq, Eq, Deserialize, Serialize)]
struct StoredDeviceCode {
    verification_url: String,
    user_code: String,
    device_auth_id: String,
    interval: u64,
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

#[derive(Debug, Deserialize)]
struct CodeSuccessResp {
    authorization_code: String,
    #[serde(rename = "code_challenge")]
    _code_challenge: String,
    code_verifier: String,
}

#[derive(Debug, Deserialize)]
struct TokenExchangeResp {
    id_token: String,
    access_token: String,
    refresh_token: String,
}

enum PollOutcome {
    Pending,
    Approved(CodeSuccessResp),
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
    build_reqwest_client_with_custom_ca(reqwest::Client::builder()).map_err(Into::into)
}

pub fn begin_device_auth() -> Result<HelperResponse> {
    let opts = state::server_options()?;
    let device_code = runtime()?.block_on(request_device_code(&opts))?;
    Ok(HelperResponse::DeviceAuthStarted {
        flow_id: encode_flow_id(&device_code)?,
        verification_uri: device_code.verification_url,
        user_code: device_code.user_code,
    })
}

pub fn poll_device_auth(flow_id: &str) -> Result<HelperResponse> {
    if flow_id.trim().is_empty() {
        bail!("flow id is empty");
    }

    let opts = state::server_options()?;
    let device_code = decode_flow_id(flow_id)?;

    match runtime()?.block_on(poll_for_token_once(&opts, &device_code))? {
        PollOutcome::Pending => Ok(HelperResponse::DeviceAuthPending {
            message: PENDING_APPROVAL_MESSAGE.to_string(),
        }),
        PollOutcome::Approved(code) => {
            runtime()?.block_on(persist_approved_login(&opts, code))?;
            Ok(HelperResponse::SignedIn)
        }
    }
}

pub fn sign_out() -> Result<HelperResponse> {
    let codex_home = state::codex_home()?;
    let _ = logout(&codex_home, AuthCredentialsStoreMode::File)?;
    Ok(HelperResponse::SignedOut)
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
            bail!("device code login is not enabled for this Codex server. Use the browser login or verify the server URL.");
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
            .json::<CodeSuccessResp>()
            .await
            .map_err(std::io::Error::other)?;
        return Ok(PollOutcome::Approved(payload));
    }

    if status == StatusCode::FORBIDDEN || status == StatusCode::NOT_FOUND {
        return Ok(PollOutcome::Pending);
    }

    bail!("device auth failed with status {status}");
}

async fn persist_approved_login(
    opts: &codex_login::ServerOptions,
    code: CodeSuccessResp,
) -> Result<()> {
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

    if !resp.status().is_success() {
        let status = resp.status();
        let body = resp.text().await.map_err(std::io::Error::other)?;
        bail!("token endpoint returned status {status}: {body}");
    }

    let tokens = resp
        .json::<TokenExchangeResp>()
        .await
        .map_err(std::io::Error::other)?;
    persist_tokens(opts, tokens)?;
    Ok(())
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
    };
    save_auth(&opts.codex_home, &auth, AuthCredentialsStoreMode::File)
        .context("failed to persist approved ChatGPT login")?;
    Ok(())
}

fn encode_flow_id(device_code: &StoredDeviceCode) -> Result<String> {
    let data = serde_json::to_vec(device_code)?;
    Ok(base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(data))
}

fn decode_flow_id(flow_id: &str) -> Result<StoredDeviceCode> {
    let bytes = base64::engine::general_purpose::URL_SAFE_NO_PAD
        .decode(flow_id)
        .context("unknown flow id")?;
    serde_json::from_slice(&bytes).context("unknown flow id")
}
