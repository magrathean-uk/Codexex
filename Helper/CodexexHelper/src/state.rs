use anyhow::{Context, Result};
use codex_login::{AuthCredentialsStoreMode, CLIENT_ID, ServerOptions};
use std::fs;
use std::path::PathBuf;

use crate::release_environment_gating::{development_env_path, development_env_var};
use crate::secure_file_permissions::harden_helper_state_permissions;

const STATE_DIR_ENV: &str = "CODEXEX_HELPER_STATE_DIR";
const ISSUER_ENV: &str = "CODEXEX_HELPER_ISSUER";
const CHATGPT_BASE_URL_ENV: &str = "CODEXEX_HELPER_CHATGPT_BASE_URL";
const DEFAULT_ISSUER: &str = "https://auth.openai.com";
const DEFAULT_CHATGPT_BASE_URL: &str = "https://chatgpt.com";

pub fn codex_home() -> Result<PathBuf> {
    let path = if let Some(override_path) = development_env_path(STATE_DIR_ENV) {
        PathBuf::from(override_path)
    } else {
        let home = std::env::var_os("HOME").context("HOME is not set")?;
        PathBuf::from(home)
            .join("Library")
            .join("Application Support")
            .join("Codexex")
            .join("Helper")
    };

    fs::create_dir_all(&path)
        .with_context(|| format!("failed to create helper state dir at {}", path.display()))?;
    harden_helper_state_permissions(&path)?;
    Ok(path)
}

pub fn executable_path() -> String {
    std::env::current_exe()
        .ok()
        .map(|path| path.display().to_string())
        .unwrap_or_else(|| "codexex-helper".to_string())
}

pub fn chatgpt_base_url() -> String {
    development_env_var(CHATGPT_BASE_URL_ENV)
        .unwrap_or_else(|| DEFAULT_CHATGPT_BASE_URL.to_string())
}

pub fn server_options() -> Result<ServerOptions> {
    let mut opts = ServerOptions::new(
        codex_home()?,
        CLIENT_ID.to_string(),
        /*forced_chatgpt_workspace_id*/ None,
        AuthCredentialsStoreMode::File,
    );
    if let Some(issuer) = development_env_var(ISSUER_ENV) {
        opts.issuer = issuer;
    } else {
        opts.issuer = DEFAULT_ISSUER.to_string();
    }
    opts.open_browser = false;
    Ok(opts)
}
