use anyhow::{Context, Result, bail};
use codex_login::{AuthCredentialsStoreMode, complete_device_code_login, logout, request_device_code};
use std::collections::HashMap;
use std::sync::{LazyLock, Mutex};
use tokio::runtime::Builder;
use uuid::Uuid;

use crate::protocol::HelperResponse;
use crate::state;

static ACTIVE_DEVICE_FLOWS: LazyLock<Mutex<HashMap<String, codex_login::DeviceCode>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

fn runtime() -> Result<tokio::runtime::Runtime> {
    Builder::new_current_thread()
        .enable_all()
        .build()
        .context("failed to create helper runtime")
}

pub fn begin_device_auth() -> Result<HelperResponse> {
    let opts = state::server_options()?;
    let device_code = runtime()?.block_on(request_device_code(&opts))?;
    let flow_id = Uuid::new_v4().to_string();
    ACTIVE_DEVICE_FLOWS
        .lock()
        .expect("active device flows lock poisoned")
        .insert(flow_id.clone(), device_code.clone());

    Ok(HelperResponse::DeviceAuthStarted {
        flow_id,
        verification_uri: device_code.verification_url,
        user_code: device_code.user_code,
    })
}

pub fn poll_device_auth(flow_id: &str) -> Result<HelperResponse> {
    if flow_id.trim().is_empty() {
        bail!("flow id is empty");
    }

    let opts = state::server_options()?;
    let device_code = ACTIVE_DEVICE_FLOWS
        .lock()
        .expect("active device flows lock poisoned")
        .remove(flow_id)
        .with_context(|| format!("unknown flow id: {flow_id}"))?;
    runtime()?.block_on(complete_device_code_login(opts, device_code))?;
    Ok(HelperResponse::SignedIn)
}

pub fn sign_out() -> Result<HelperResponse> {
    let codex_home = state::codex_home()?;
    let _ = logout(&codex_home, AuthCredentialsStoreMode::File)?;
    ACTIVE_DEVICE_FLOWS
        .lock()
        .expect("active device flows lock poisoned")
        .clear();
    Ok(HelperResponse::SignedOut)
}
