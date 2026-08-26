use std::collections::HashMap;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result, bail};
use base64::Engine;
use serde::{Deserialize, Serialize};

#[cfg(unix)]
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};

use crate::auth::{ApprovedDeviceCode, StoredDeviceCode, TokenExchangeResp};
use crate::secure_file_permissions::harden_helper_state_permissions;
use crate::state;

const FLOW_ID_BYTES: usize = 32;
const REGISTRY_VERSION: u8 = 1;
const REGISTRY_FILE_NAME: &str = "pending-device-auth.json";
const REGISTRY_LOCK_NAME: &str = ".pending-device-auth.lock";
const MAX_REGISTRY_BYTES: u64 = 256 * 1024;
const MAX_ACTIVE_FLOWS: usize = 1;
const MIN_POLL_INTERVAL_SECS: u64 = 1;
const MAX_POLL_INTERVAL_SECS: u64 = 60;
const MAX_VERIFICATION_URL_BYTES: usize = 2 * 1024;
const MAX_USER_CODE_BYTES: usize = 128;
const MAX_DEVICE_AUTH_ID_BYTES: usize = 8 * 1024;
const MAX_AUTHORIZATION_CODE_BYTES: usize = 16 * 1024;
const MAX_CODE_CHALLENGE_BYTES: usize = 8 * 1024;
const MAX_CODE_VERIFIER_BYTES: usize = 8 * 1024;
const MAX_TOKEN_BYTES: usize = 64 * 1024;
const SLOW_DOWN_INCREMENT: Duration = Duration::from_secs(5);
pub(crate) const OPERATION_LEASE_SECS: u64 = 30;
pub const FLOW_TTL: Duration = Duration::from_secs(10 * 60);

static PROCESS_LOCK: Mutex<()> = Mutex::new(());

#[derive(Debug, Clone, PartialEq, Eq)]
pub(crate) enum FlowAction {
    Wait { retry_after: Duration },
    Poll(StoredDeviceCode, FlowClaim),
    Exchange(ApprovedDeviceCode, FlowClaim),
    Persist(TokenExchangeResp, FlowClaim),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct FlowClaim {
    generation: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct PendingFlow {
    device_code: StoredDeviceCode,
    approved_code: Option<ApprovedDeviceCode>,
    exchanged_tokens: Option<TokenExchangeResp>,
    created_at_unix_secs: u64,
    expires_at_unix_secs: u64,
    next_poll_at_unix_secs: u64,
    poll_interval_secs: u64,
    #[serde(default)]
    operation_generation: u64,
    #[serde(default)]
    operation_lease_until_unix_secs: u64,
}

#[derive(Debug, Default, Serialize, Deserialize)]
struct RegistryState {
    version: u8,
    flows: HashMap<String, PendingFlow>,
}

#[derive(Debug, Clone)]
struct FlowRegistry {
    root: PathBuf,
}

impl FlowRegistry {
    fn helper() -> Result<Self> {
        Ok(Self {
            root: state::codex_home()?,
        })
    }

    #[cfg(test)]
    fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    fn insert(&self, device_code: StoredDeviceCode, now: u64) -> Result<String> {
        let device_code = normalized_device_code(device_code)?;
        self.with_lock(|| {
            let mut state = self.load(now)?;
            state.flows.clear();
            for _ in 0..4 {
                let flow_id = random_flow_id()?;
                if !state.flows.contains_key(&flow_id) {
                    let poll_interval_secs = device_code.interval;
                    state.flows.insert(
                        flow_id.clone(),
                        PendingFlow {
                            device_code: device_code.clone(),
                            approved_code: None,
                            exchanged_tokens: None,
                            created_at_unix_secs: now,
                            expires_at_unix_secs: now.saturating_add(FLOW_TTL.as_secs()),
                            next_poll_at_unix_secs: now,
                            poll_interval_secs,
                            operation_generation: 0,
                            operation_lease_until_unix_secs: 0,
                        },
                    );
                    self.save(&state)?;
                    return Ok(flow_id);
                }
            }

            bail!("could not allocate sign-in flow")
        })
    }

    fn begin_poll(&self, flow_id: &str, now: u64) -> Result<FlowAction> {
        validate_flow_id(flow_id)?;
        self.with_lock(|| {
            let mut state = self.load(now)?;
            let action = state.flows.get_mut(flow_id).map(|flow| {
                if now < flow.operation_lease_until_unix_secs {
                    return FlowAction::Wait {
                        retry_after: Duration::from_secs(
                            flow.operation_lease_until_unix_secs - now,
                        ),
                    };
                }
                if now < flow.next_poll_at_unix_secs {
                    return FlowAction::Wait {
                        retry_after: Duration::from_secs(flow.next_poll_at_unix_secs - now),
                    };
                }

                let claim = claim_operation(flow, now);
                flow.next_poll_at_unix_secs =
                    now.saturating_add(flow.poll_interval_secs.min(FLOW_TTL.as_secs()));
                if let Some(tokens) = flow.exchanged_tokens.clone() {
                    FlowAction::Persist(tokens, claim)
                } else if let Some(code) = flow.approved_code.clone() {
                    FlowAction::Exchange(code, claim)
                } else {
                    FlowAction::Poll(flow.device_code.clone(), claim)
                }
            });
            // A throttled poll changes no state. Avoid rewriting and fsyncing
            // the registry on every UI status check.
            if !matches!(action, Some(FlowAction::Wait { .. })) {
                self.save(&state)?;
            }
            action.ok_or_else(expired_error)
        })
    }

    fn defer(
        &self,
        flow_id: &str,
        claim: FlowClaim,
        retry_after: Option<Duration>,
        slow_down: bool,
        now: u64,
    ) -> Result<bool> {
        validate_flow_id(flow_id)?;
        self.with_lock(|| {
            let mut state = self.load(now)?;
            let Some(flow) = state.flows.get_mut(flow_id) else {
                return Ok(false);
            };
            if !claim_matches(flow, claim) {
                return Ok(false);
            }

            if slow_down {
                flow.poll_interval_secs = flow
                    .poll_interval_secs
                    .saturating_add(SLOW_DOWN_INCREMENT.as_secs())
                    .min(MAX_POLL_INTERVAL_SECS);
            }
            let requested_delay = retry_after.map(duration_secs_ceil).unwrap_or_default();
            let delay = flow.poll_interval_secs.max(requested_delay);
            flow.next_poll_at_unix_secs = flow
                .next_poll_at_unix_secs
                .max(now.saturating_add(delay.min(FLOW_TTL.as_secs())));
            flow.operation_lease_until_unix_secs = 0;
            self.save(&state)?;
            Ok(true)
        })
    }

    fn mark_approved(
        &self,
        flow_id: &str,
        claim: FlowClaim,
        approved_code: ApprovedDeviceCode,
        now: u64,
    ) -> Result<bool> {
        validate_flow_id(flow_id)?;
        validate_approved_code(&approved_code)?;
        self.with_lock(|| {
            let mut state = self.load(now)?;
            let Some(flow) = state.flows.get_mut(flow_id) else {
                return Ok(false);
            };
            if !claim_matches(flow, claim) {
                return Ok(false);
            }
            flow.approved_code = Some(approved_code);
            renew_claim(flow, now);
            self.save(&state)?;
            Ok(true)
        })
    }

    fn mark_exchanged(
        &self,
        flow_id: &str,
        claim: FlowClaim,
        tokens: TokenExchangeResp,
        now: u64,
    ) -> Result<bool> {
        validate_flow_id(flow_id)?;
        validate_tokens(&tokens)?;
        self.with_lock(|| {
            let mut state = self.load(now)?;
            let Some(flow) = state.flows.get_mut(flow_id) else {
                return Ok(false);
            };
            if !claim_matches(flow, claim) || flow.approved_code.is_none() {
                return Ok(false);
            }
            flow.exchanged_tokens = Some(tokens);
            renew_claim(flow, now);
            self.save(&state)?;
            Ok(true)
        })
    }

    fn remove_if_claimed(&self, flow_id: &str, claim: FlowClaim, now: u64) -> Result<bool> {
        validate_flow_id(flow_id)?;
        self.with_lock(|| {
            let mut state = self.load(now)?;
            let is_current = state
                .flows
                .get(flow_id)
                .is_some_and(|flow| claim_matches(flow, claim));
            if !is_current {
                return Ok(false);
            }
            state.flows.remove(flow_id);
            self.save(&state)?;
            Ok(true)
        })
    }

    fn finish_if_claimed(
        &self,
        flow_id: &str,
        claim: FlowClaim,
        now: u64,
        operation: impl FnOnce() -> Result<()>,
    ) -> Result<bool> {
        validate_flow_id(flow_id)?;
        self.with_lock(|| {
            let mut state = self.load(now)?;
            let is_current_persist = state.flows.get(flow_id).is_some_and(|flow| {
                claim_matches(flow, claim) && flow.exchanged_tokens.is_some()
            });
            if !is_current_persist {
                return Ok(false);
            }

            if let Err(error) = operation() {
                if let Some(flow) = state.flows.get_mut(flow_id) {
                    flow.operation_lease_until_unix_secs = 0;
                    flow.next_poll_at_unix_secs = flow.next_poll_at_unix_secs.max(
                        now.saturating_add(flow.poll_interval_secs.min(FLOW_TTL.as_secs())),
                    );
                }
                if let Err(release_error) = self.save(&state) {
                    return Err(error.context(format!(
                        "failed to release sign-in operation after persistence failure: {release_error:#}"
                    )));
                }
                return Err(error);
            }

            state.flows.remove(flow_id);
            self.save(&state)?;
            Ok(true)
        })
    }

    fn remove(&self, flow_id: &str, now: u64) -> Result<()> {
        validate_flow_id(flow_id)?;
        self.with_lock(|| {
            let mut state = self.load(now)?;
            state.flows.remove(flow_id);
            self.save(&state)
        })
    }

    fn clear_with(&self, operation: impl FnOnce() -> Result<()>) -> Result<()> {
        self.with_lock(|| {
            let operation_result = operation();
            let clear_result = self.remove_state_file();
            operation_result?;
            clear_result
        })
    }

    fn with_lock<T>(&self, operation: impl FnOnce() -> Result<T>) -> Result<T> {
        let _process_guard = PROCESS_LOCK
            .lock()
            .map_err(|_| anyhow::anyhow!("flow registry is unavailable"))?;
        fs::create_dir_all(&self.root).with_context(|| {
            format!(
                "failed to create helper state dir at {}",
                self.root.display()
            )
        })?;
        harden_helper_state_permissions(&self.root)?;

        let lock_path = self.root.join(REGISTRY_LOCK_NAME);
        let mut options = OpenOptions::new();
        options.read(true).write(true).create(true);
        #[cfg(unix)]
        options.mode(0o600).custom_flags(libc::O_NOFOLLOW);
        let lock_file = options.open(&lock_path).with_context(|| {
            format!(
                "failed to open sign-in state lock at {}",
                lock_path.display()
            )
        })?;
        set_owner_only_file_permissions(&lock_file, &lock_path)?;
        lock_file
            .lock()
            .context("failed to lock pending sign-in state")?;

        operation()
    }

    fn load(&self, now: u64) -> Result<RegistryState> {
        let path = self.state_path();
        let metadata = match fs::symlink_metadata(&path) {
            Ok(metadata) => metadata,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Ok(RegistryState {
                    version: REGISTRY_VERSION,
                    flows: HashMap::new(),
                });
            }
            Err(error) => return Err(error).context("failed to inspect pending sign-in state"),
        };
        if metadata.file_type().is_symlink() {
            self.remove_state_file()?;
            return Ok(empty_state());
        }
        if !metadata.is_file() {
            bail!("pending sign-in state is not a regular file")
        }
        if metadata.len() > MAX_REGISTRY_BYTES {
            self.remove_state_file()?;
            return Ok(empty_state());
        }

        let mut options = OpenOptions::new();
        options.read(true);
        #[cfg(unix)]
        options.custom_flags(libc::O_NOFOLLOW);
        let file = options
            .open(&path)
            .context("failed to open pending sign-in state")?;
        set_owner_only_file_permissions(&file, &path)?;
        let opened_metadata = file
            .metadata()
            .context("failed to inspect opened pending sign-in state")?;
        if !opened_metadata.is_file() || opened_metadata.len() > MAX_REGISTRY_BYTES {
            self.remove_state_file()?;
            return Ok(empty_state());
        }

        // Bound the descriptor read too. The path can grow after the earlier
        // metadata check, and pending auth state must never cause an
        // unbounded allocation.
        let mut bytes = Vec::with_capacity(opened_metadata.len() as usize);
        file.take(MAX_REGISTRY_BYTES.saturating_add(1))
            .read_to_end(&mut bytes)
            .context("failed to read pending sign-in state")?;
        if bytes.len() as u64 > MAX_REGISTRY_BYTES {
            self.remove_state_file()?;
            return Ok(empty_state());
        }
        let mut state = match serde_json::from_slice::<RegistryState>(&bytes) {
            Ok(state) => state,
            Err(_) => {
                self.remove_state_file()?;
                return Ok(empty_state());
            }
        };
        if state.version != REGISTRY_VERSION {
            bail!("pending sign-in state uses an unsupported version")
        }
        state.flows.retain(|flow_id, flow| {
            valid_flow_id(flow_id)
                && flow.created_at_unix_secs <= now
                && flow.expires_at_unix_secs > now
                && flow.expires_at_unix_secs >= flow.created_at_unix_secs
                && flow
                    .expires_at_unix_secs
                    .saturating_sub(flow.created_at_unix_secs)
                    <= FLOW_TTL.as_secs()
                && valid_pending_flow(flow)
        });
        while state.flows.len() > MAX_ACTIVE_FLOWS {
            let Some(oldest_flow_id) = state
                .flows
                .iter()
                .min_by_key(|(_, flow)| flow.created_at_unix_secs)
                .map(|(flow_id, _)| flow_id.clone())
            else {
                break;
            };
            state.flows.remove(&oldest_flow_id);
        }
        Ok(state)
    }

    fn save(&self, state: &RegistryState) -> Result<()> {
        if state.flows.is_empty() {
            return self.remove_state_file();
        }

        let payload =
            serde_json::to_vec(state).context("failed to encode pending sign-in state")?;
        let temp_path = self
            .root
            .join(format!(".{REGISTRY_FILE_NAME}.{}.tmp", random_flow_id()?));
        let write_result = (|| -> Result<()> {
            let mut options = OpenOptions::new();
            options.write(true).create_new(true);
            #[cfg(unix)]
            options.mode(0o600).custom_flags(libc::O_NOFOLLOW);
            let mut file = options.open(&temp_path).with_context(|| {
                format!(
                    "failed to create pending sign-in state at {}",
                    temp_path.display()
                )
            })?;
            file.write_all(&payload)
                .context("failed to write pending sign-in state")?;
            file.sync_all()
                .context("failed to sync pending sign-in state")?;
            drop(file);
            fs::rename(&temp_path, self.state_path())
                .context("failed to replace pending sign-in state")?;
            let state_path = self.state_path();
            let mut options = OpenOptions::new();
            options.read(true);
            #[cfg(unix)]
            options.custom_flags(libc::O_NOFOLLOW);
            let state_file = options
                .open(&state_path)
                .context("failed to reopen pending sign-in state")?;
            set_owner_only_file_permissions(&state_file, &state_path)?;
            sync_directory(&self.root)
        })();
        if write_result.is_err() {
            let _ = fs::remove_file(&temp_path);
        }
        write_result
    }

    fn remove_state_file(&self) -> Result<()> {
        match fs::remove_file(self.state_path()) {
            Ok(()) => sync_directory(&self.root),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error).context("failed to clear pending sign-in state"),
        }
    }

    fn state_path(&self) -> PathBuf {
        self.root.join(REGISTRY_FILE_NAME)
    }
}

pub(crate) fn insert(device_code: StoredDeviceCode) -> Result<String> {
    FlowRegistry::helper()?.insert(device_code, now_unix_secs()?)
}

pub(crate) fn begin_poll(flow_id: &str) -> Result<FlowAction> {
    FlowRegistry::helper()?.begin_poll(flow_id, now_unix_secs()?)
}

pub(crate) fn defer(
    flow_id: &str,
    claim: FlowClaim,
    retry_after: Option<Duration>,
    slow_down: bool,
) -> Result<bool> {
    FlowRegistry::helper()?.defer(flow_id, claim, retry_after, slow_down, now_unix_secs()?)
}

pub(crate) fn mark_approved(
    flow_id: &str,
    claim: FlowClaim,
    approved_code: ApprovedDeviceCode,
) -> Result<bool> {
    FlowRegistry::helper()?.mark_approved(flow_id, claim, approved_code, now_unix_secs()?)
}

pub(crate) fn mark_exchanged(
    flow_id: &str,
    claim: FlowClaim,
    tokens: TokenExchangeResp,
) -> Result<bool> {
    FlowRegistry::helper()?.mark_exchanged(flow_id, claim, tokens, now_unix_secs()?)
}

pub(crate) fn remove_if_claimed(flow_id: &str, claim: FlowClaim) -> Result<bool> {
    FlowRegistry::helper()?.remove_if_claimed(flow_id, claim, now_unix_secs()?)
}

pub(crate) fn finish_if_claimed(
    flow_id: &str,
    claim: FlowClaim,
    operation: impl FnOnce() -> Result<()>,
) -> Result<bool> {
    FlowRegistry::helper()?.finish_if_claimed(flow_id, claim, now_unix_secs()?, operation)
}

pub(crate) fn remove(flow_id: &str) -> Result<()> {
    FlowRegistry::helper()?.remove(flow_id, now_unix_secs()?)
}

pub(crate) fn clear_all_with(operation: impl FnOnce() -> Result<()>) -> Result<()> {
    FlowRegistry::helper()?.clear_with(operation)
}

fn now_unix_secs() -> Result<u64> {
    Ok(SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .context("system clock is before the Unix epoch")?
        .as_secs())
}

fn duration_secs_ceil(duration: Duration) -> u64 {
    duration
        .as_secs()
        .saturating_add(u64::from(duration.subsec_nanos() > 0))
}

fn empty_state() -> RegistryState {
    RegistryState {
        version: REGISTRY_VERSION,
        flows: HashMap::new(),
    }
}

fn next_operation_generation(current: u64) -> u64 {
    let next = current.wrapping_add(1);
    if next == 0 { 1 } else { next }
}

fn claim_operation(flow: &mut PendingFlow, now: u64) -> FlowClaim {
    flow.operation_generation = next_operation_generation(flow.operation_generation);
    renew_claim(flow, now);
    FlowClaim {
        generation: flow.operation_generation,
    }
}

fn renew_claim(flow: &mut PendingFlow, now: u64) {
    flow.operation_lease_until_unix_secs = now
        .saturating_add(OPERATION_LEASE_SECS)
        .min(flow.expires_at_unix_secs);
}

fn claim_matches(flow: &PendingFlow, claim: FlowClaim) -> bool {
    claim.generation != 0
        && flow.operation_generation == claim.generation
        && flow.operation_lease_until_unix_secs != 0
}

fn normalized_device_code(mut device_code: StoredDeviceCode) -> Result<StoredDeviceCode> {
    if !valid_bounded_value(&device_code.verification_url, MAX_VERIFICATION_URL_BYTES)
        || !(device_code.verification_url.starts_with("https://")
            || device_code.verification_url.starts_with("http://"))
        || !valid_bounded_value(&device_code.user_code, MAX_USER_CODE_BYTES)
        || !valid_bounded_value(&device_code.device_auth_id, MAX_DEVICE_AUTH_ID_BYTES)
    {
        bail!("device auth server returned invalid sign-in data")
    }
    device_code.interval = device_code
        .interval
        .clamp(MIN_POLL_INTERVAL_SECS, MAX_POLL_INTERVAL_SECS);
    Ok(device_code)
}

fn validate_approved_code(code: &ApprovedDeviceCode) -> Result<()> {
    if !valid_approved_code(code) {
        bail!("device auth server returned an invalid approval")
    }
    Ok(())
}

fn valid_approved_code(code: &ApprovedDeviceCode) -> bool {
    valid_bounded_value(&code.authorization_code, MAX_AUTHORIZATION_CODE_BYTES)
        && valid_bounded_value(&code._code_challenge, MAX_CODE_CHALLENGE_BYTES)
        && valid_bounded_value(&code.code_verifier, MAX_CODE_VERIFIER_BYTES)
}

fn validate_tokens(tokens: &TokenExchangeResp) -> Result<()> {
    if !valid_tokens(tokens) {
        bail!("token endpoint returned invalid credentials")
    }
    Ok(())
}

fn valid_tokens(tokens: &TokenExchangeResp) -> bool {
    valid_bounded_value(&tokens.id_token, MAX_TOKEN_BYTES)
        && valid_bounded_value(&tokens.access_token, MAX_TOKEN_BYTES)
        && valid_bounded_value(&tokens.refresh_token, MAX_TOKEN_BYTES)
}

fn valid_pending_flow(flow: &PendingFlow) -> bool {
    valid_bounded_value(
        &flow.device_code.verification_url,
        MAX_VERIFICATION_URL_BYTES,
    ) && (flow.device_code.verification_url.starts_with("https://")
        || flow.device_code.verification_url.starts_with("http://"))
        && valid_bounded_value(&flow.device_code.user_code, MAX_USER_CODE_BYTES)
        && valid_bounded_value(&flow.device_code.device_auth_id, MAX_DEVICE_AUTH_ID_BYTES)
        && (MIN_POLL_INTERVAL_SECS..=MAX_POLL_INTERVAL_SECS).contains(&flow.device_code.interval)
        && (MIN_POLL_INTERVAL_SECS..=MAX_POLL_INTERVAL_SECS).contains(&flow.poll_interval_secs)
        && flow.approved_code.as_ref().is_none_or(valid_approved_code)
        && flow.exchanged_tokens.as_ref().is_none_or(valid_tokens)
        && (flow.exchanged_tokens.is_none() || flow.approved_code.is_some())
        && flow.operation_lease_until_unix_secs <= flow.expires_at_unix_secs
        && (flow.operation_lease_until_unix_secs == 0 || flow.operation_generation != 0)
}

fn valid_bounded_value(value: &str, max_bytes: usize) -> bool {
    !value.is_empty() && value.len() <= max_bytes && !value.chars().any(char::is_control)
}

fn validate_flow_id(flow_id: &str) -> Result<()> {
    if !valid_flow_id(flow_id) {
        return Err(expired_error());
    }
    Ok(())
}

fn valid_flow_id(flow_id: &str) -> bool {
    flow_id.len() == 43
        && flow_id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || byte == b'-' || byte == b'_')
}

fn expired_error() -> anyhow::Error {
    anyhow::anyhow!("Sign-in code expired. Start again.")
}

fn random_flow_id() -> Result<String> {
    let mut bytes = [0_u8; FLOW_ID_BYTES];
    File::open("/dev/urandom")
        .context("failed to open system random source")?
        .read_exact(&mut bytes)
        .context("failed to read system random source")?;
    Ok(base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes))
}

#[cfg(unix)]
fn set_owner_only_file_permissions(file: &File, path: &Path) -> Result<()> {
    file.set_permissions(fs::Permissions::from_mode(0o600))
        .with_context(|| format!("failed to harden helper state file at {}", path.display()))
}

#[cfg(not(unix))]
fn set_owner_only_file_permissions(_file: &File, _path: &Path) -> Result<()> {
    Ok(())
}

#[cfg(unix)]
fn sync_directory(path: &Path) -> Result<()> {
    File::open(path)
        .and_then(|directory| directory.sync_all())
        .with_context(|| format!("failed to sync helper state dir at {}", path.display()))
}

#[cfg(not(unix))]
fn sync_directory(_path: &Path) -> Result<()> {
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_code(interval: u64) -> StoredDeviceCode {
        StoredDeviceCode {
            verification_url: "https://auth.openai.com/codex/device".to_string(),
            user_code: "ABCD-1234".to_string(),
            device_auth_id: "device-secret".to_string(),
            interval,
        }
    }

    fn poll_claim(action: FlowAction) -> FlowClaim {
        match action {
            FlowAction::Poll(_, claim) => claim,
            other => panic!("expected poll claim, got {other:?}"),
        }
    }

    fn approved_code() -> ApprovedDeviceCode {
        ApprovedDeviceCode {
            authorization_code: "authorization-code".to_string(),
            _code_challenge: "code-challenge".to_string(),
            code_verifier: "code-verifier".to_string(),
        }
    }

    fn exchanged_tokens() -> TokenExchangeResp {
        TokenExchangeResp {
            id_token: "id-token".to_string(),
            access_token: "access-token".to_string(),
            refresh_token: "refresh-token".to_string(),
        }
    }

    #[test]
    fn flow_id_is_opaque_and_resolves_to_stored_device_code() {
        let temp_dir = tempfile::tempdir().unwrap();
        let registry = FlowRegistry::new(temp_dir.path());
        let flow_id = registry.insert(sample_code(3), 100).unwrap();

        assert_eq!(flow_id.len(), 43);
        assert!(!flow_id.contains("device-secret"));
        assert!(!flow_id.contains("ABCD-1234"));
        assert!(matches!(
            registry.begin_poll(&flow_id, 100).unwrap(),
            FlowAction::Poll(StoredDeviceCode { user_code, .. }, _) if user_code == "ABCD-1234"
        ));
    }

    #[test]
    fn persisted_flow_survives_a_new_registry_instance() {
        let temp_dir = tempfile::tempdir().unwrap();
        let first_registry = FlowRegistry::new(temp_dir.path());
        let flow_id = first_registry.insert(sample_code(3), 100).unwrap();
        drop(first_registry);

        let restarted_registry = FlowRegistry::new(temp_dir.path());
        assert!(matches!(
            restarted_registry.begin_poll(&flow_id, 100).unwrap(),
            FlowAction::Poll(..)
        ));
    }

    #[test]
    fn issuer_interval_is_enforced_without_an_extra_transport_call() {
        let temp_dir = tempfile::tempdir().unwrap();
        let registry = FlowRegistry::new(temp_dir.path());
        let flow_id = registry.insert(sample_code(5), 100).unwrap();

        let claim = poll_claim(registry.begin_poll(&flow_id, 100).unwrap());
        assert!(registry.defer(&flow_id, claim, None, false, 100).unwrap());
        assert_eq!(
            registry.begin_poll(&flow_id, 104).unwrap(),
            FlowAction::Wait {
                retry_after: Duration::from_secs(1)
            }
        );
        assert!(matches!(
            registry.begin_poll(&flow_id, 105).unwrap(),
            FlowAction::Poll(..)
        ));
    }

    #[cfg(unix)]
    #[test]
    fn throttled_poll_does_not_rewrite_registry_file() {
        use std::os::unix::fs::MetadataExt;

        let temp_dir = tempfile::tempdir().unwrap();
        let registry = FlowRegistry::new(temp_dir.path());
        let flow_id = registry.insert(sample_code(5), 100).unwrap();
        let claim = poll_claim(registry.begin_poll(&flow_id, 100).unwrap());
        assert!(registry.defer(&flow_id, claim, None, false, 100).unwrap());
        let inode_before = fs::metadata(registry.state_path()).unwrap().ino();

        assert!(matches!(
            registry.begin_poll(&flow_id, 101).unwrap(),
            FlowAction::Wait { .. }
        ));
        let inode_after = fs::metadata(registry.state_path()).unwrap().ino();

        assert_eq!(inode_after, inode_before);
    }

    #[test]
    fn issuer_interval_is_clamped_to_sane_nonzero_bounds() {
        let temp_dir = tempfile::tempdir().unwrap();
        let registry = FlowRegistry::new(temp_dir.path());
        let minimum_flow = registry.insert(sample_code(0), 100).unwrap();
        let minimum_claim = poll_claim(registry.begin_poll(&minimum_flow, 100).unwrap());
        assert!(
            registry
                .defer(&minimum_flow, minimum_claim, None, false, 100)
                .unwrap()
        );
        assert_eq!(
            registry.begin_poll(&minimum_flow, 100).unwrap(),
            FlowAction::Wait {
                retry_after: Duration::from_secs(MIN_POLL_INTERVAL_SECS)
            }
        );

        let maximum_flow = registry.insert(sample_code(u64::MAX), 200).unwrap();
        let maximum_claim = poll_claim(registry.begin_poll(&maximum_flow, 200).unwrap());
        assert!(
            registry
                .defer(&maximum_flow, maximum_claim, None, false, 200)
                .unwrap()
        );
        assert_eq!(
            registry
                .begin_poll(&maximum_flow, 200 + MAX_POLL_INTERVAL_SECS - 1)
                .unwrap(),
            FlowAction::Wait {
                retry_after: Duration::from_secs(1)
            }
        );
    }

    #[test]
    fn slow_down_increases_all_later_poll_intervals() {
        let temp_dir = tempfile::tempdir().unwrap();
        let registry = FlowRegistry::new(temp_dir.path());
        let flow_id = registry.insert(sample_code(2), 100).unwrap();

        let first_claim = poll_claim(registry.begin_poll(&flow_id, 100).unwrap());
        assert!(
            registry
                .defer(&flow_id, first_claim, None, true, 100)
                .unwrap()
        );
        assert_eq!(
            registry.begin_poll(&flow_id, 106).unwrap(),
            FlowAction::Wait {
                retry_after: Duration::from_secs(1)
            }
        );
        let second_claim = poll_claim(registry.begin_poll(&flow_id, 107).unwrap());
        assert!(
            registry
                .defer(&flow_id, second_claim, None, false, 107)
                .unwrap()
        );
        assert_eq!(
            registry.begin_poll(&flow_id, 113).unwrap(),
            FlowAction::Wait {
                retry_after: Duration::from_secs(1)
            }
        );
    }

    #[test]
    fn retry_after_extends_the_next_poll_deadline() {
        let temp_dir = tempfile::tempdir().unwrap();
        let registry = FlowRegistry::new(temp_dir.path());
        let flow_id = registry.insert(sample_code(2), 100).unwrap();

        let claim = poll_claim(registry.begin_poll(&flow_id, 100).unwrap());
        assert!(
            registry
                .defer(&flow_id, claim, Some(Duration::from_secs(9)), false, 100,)
                .unwrap()
        );
        assert_eq!(
            registry.begin_poll(&flow_id, 108).unwrap(),
            FlowAction::Wait {
                retry_after: Duration::from_secs(1)
            }
        );
        assert!(matches!(
            registry.begin_poll(&flow_id, 109).unwrap(),
            FlowAction::Poll(..)
        ));
    }

    #[test]
    fn expired_flow_is_removed_from_persistent_state() {
        let temp_dir = tempfile::tempdir().unwrap();
        let registry = FlowRegistry::new(temp_dir.path());
        let flow_id = registry.insert(sample_code(3), 100).unwrap();

        assert_eq!(
            registry
                .begin_poll(&flow_id, 100 + FLOW_TTL.as_secs())
                .unwrap_err()
                .to_string(),
            "Sign-in code expired. Start again."
        );
        assert!(!registry.state_path().exists());
    }

    #[test]
    fn removed_flow_cannot_be_replayed() {
        let temp_dir = tempfile::tempdir().unwrap();
        let registry = FlowRegistry::new(temp_dir.path());
        let flow_id = registry.insert(sample_code(3), 100).unwrap();

        registry.remove(&flow_id, 101).unwrap();

        assert!(registry.begin_poll(&flow_id, 101).is_err());
    }

    #[test]
    fn starting_a_new_flow_invalidates_the_previous_flow() {
        let temp_dir = tempfile::tempdir().unwrap();
        let registry = FlowRegistry::new(temp_dir.path());
        let first_flow_id = registry.insert(sample_code(3), 100).unwrap();
        let second_flow_id = registry.insert(sample_code(3), 101).unwrap();

        assert!(registry.begin_poll(&first_flow_id, 101).is_err());
        assert!(matches!(
            registry.begin_poll(&second_flow_id, 101).unwrap(),
            FlowAction::Poll(..)
        ));
    }

    #[test]
    fn oversized_server_fields_are_not_persisted() {
        let temp_dir = tempfile::tempdir().unwrap();
        let registry = FlowRegistry::new(temp_dir.path());
        let mut device_code = sample_code(3);
        device_code.device_auth_id = "x".repeat(MAX_DEVICE_AUTH_ID_BYTES + 1);

        assert!(registry.insert(device_code, 100).is_err());
        assert!(!registry.state_path().exists());
    }

    #[test]
    fn malformed_and_oversized_registry_files_are_cleaned_up() {
        let temp_dir = tempfile::tempdir().unwrap();
        let registry = FlowRegistry::new(temp_dir.path());
        fs::write(registry.state_path(), b"not-json").unwrap();
        let flow_id = registry.insert(sample_code(3), 100).unwrap();
        assert!(matches!(
            registry.begin_poll(&flow_id, 100).unwrap(),
            FlowAction::Poll(..)
        ));

        fs::write(
            registry.state_path(),
            vec![b'x'; MAX_REGISTRY_BYTES as usize + 1],
        )
        .unwrap();
        assert_eq!(
            registry.begin_poll(&flow_id, 101).unwrap_err().to_string(),
            "Sign-in code expired. Start again."
        );
        assert!(!registry.state_path().exists());
    }

    #[test]
    fn oversized_persisted_secret_invalidates_the_flow() {
        let temp_dir = tempfile::tempdir().unwrap();
        let registry = FlowRegistry::new(temp_dir.path());
        let flow_id = registry.insert(sample_code(3), 100).unwrap();
        let mut state: serde_json::Value =
            serde_json::from_slice(&fs::read(registry.state_path()).unwrap()).unwrap();
        state["flows"][&flow_id]["device_code"]["device_auth_id"] =
            serde_json::Value::String("x".repeat(MAX_DEVICE_AUTH_ID_BYTES + 1));
        fs::write(registry.state_path(), serde_json::to_vec(&state).unwrap()).unwrap();

        assert_eq!(
            registry.begin_poll(&flow_id, 101).unwrap_err().to_string(),
            "Sign-in code expired. Start again."
        );
        assert!(!registry.state_path().exists());
    }

    #[test]
    fn staged_credentials_are_removed_at_the_original_flow_expiry() {
        let temp_dir = tempfile::tempdir().unwrap();
        let registry = FlowRegistry::new(temp_dir.path());
        let flow_id = registry.insert(sample_code(3), 100).unwrap();
        let claim = poll_claim(registry.begin_poll(&flow_id, 100).unwrap());
        assert!(
            registry
                .mark_approved(&flow_id, claim, approved_code(), 101)
                .unwrap()
        );
        assert!(
            registry
                .mark_exchanged(&flow_id, claim, exchanged_tokens(), 102)
                .unwrap()
        );

        assert_eq!(
            registry
                .begin_poll(&flow_id, 100 + FLOW_TTL.as_secs())
                .unwrap_err()
                .to_string(),
            "Sign-in code expired. Start again."
        );
        assert!(!registry.state_path().exists());
    }

    #[test]
    fn approved_and_exchanged_stages_resume_without_repolling() {
        let temp_dir = tempfile::tempdir().unwrap();
        let registry = FlowRegistry::new(temp_dir.path());
        let flow_id = registry.insert(sample_code(1), 100).unwrap();
        let poll_claim = poll_claim(registry.begin_poll(&flow_id, 100).unwrap());
        let approved_code = approved_code();
        assert!(
            registry
                .mark_approved(&flow_id, poll_claim, approved_code.clone(), 100)
                .unwrap()
        );
        assert_eq!(
            registry.begin_poll(&flow_id, 129).unwrap(),
            FlowAction::Wait {
                retry_after: Duration::from_secs(1)
            }
        );
        let exchange_claim = match registry.begin_poll(&flow_id, 130).unwrap() {
            FlowAction::Exchange(actual_code, claim) => {
                assert_eq!(actual_code, approved_code);
                claim
            }
            other => panic!("expected exchange claim, got {other:?}"),
        };

        let tokens = exchanged_tokens();
        assert!(
            registry
                .mark_exchanged(&flow_id, exchange_claim, tokens.clone(), 130)
                .unwrap()
        );
        assert_eq!(
            registry.begin_poll(&flow_id, 159).unwrap(),
            FlowAction::Wait {
                retry_after: Duration::from_secs(1)
            }
        );
        match registry.begin_poll(&flow_id, 160).unwrap() {
            FlowAction::Persist(actual_tokens, _) => assert_eq!(actual_tokens, tokens),
            other => panic!("expected persist claim, got {other:?}"),
        }
    }

    #[test]
    fn active_operation_lease_blocks_duplicate_work_and_expired_lease_reclaims() {
        let temp_dir = tempfile::tempdir().unwrap();
        let first_registry = FlowRegistry::new(temp_dir.path());
        let second_registry = FlowRegistry::new(temp_dir.path());
        let flow_id = first_registry.insert(sample_code(1), 100).unwrap();
        let first_claim = poll_claim(first_registry.begin_poll(&flow_id, 100).unwrap());

        assert_eq!(
            second_registry.begin_poll(&flow_id, 129).unwrap(),
            FlowAction::Wait {
                retry_after: Duration::from_secs(1)
            }
        );
        let reclaimed_claim = poll_claim(second_registry.begin_poll(&flow_id, 130).unwrap());

        assert_ne!(first_claim, reclaimed_claim);
        assert!(
            !first_registry
                .defer(&flow_id, first_claim, None, false, 130)
                .unwrap()
        );
        assert!(
            !first_registry
                .mark_approved(&flow_id, first_claim, approved_code(), 130)
                .unwrap()
        );
        assert!(
            !first_registry
                .remove_if_claimed(&flow_id, first_claim, 130)
                .unwrap()
        );
        assert!(
            second_registry
                .mark_approved(&flow_id, reclaimed_claim, approved_code(), 130)
                .unwrap()
        );
    }

    #[test]
    fn cancelled_claim_cannot_run_token_persistence() {
        use std::cell::Cell;

        let temp_dir = tempfile::tempdir().unwrap();
        let registry = FlowRegistry::new(temp_dir.path());
        let flow_id = registry.insert(sample_code(1), 100).unwrap();
        let claim = poll_claim(registry.begin_poll(&flow_id, 100).unwrap());
        assert!(
            registry
                .mark_approved(&flow_id, claim, approved_code(), 100)
                .unwrap()
        );
        assert!(
            registry
                .mark_exchanged(&flow_id, claim, exchanged_tokens(), 100)
                .unwrap()
        );
        registry.remove(&flow_id, 101).unwrap();

        let operation_ran = Cell::new(false);
        let finished = registry
            .finish_if_claimed(&flow_id, claim, 101, || {
                operation_ran.set(true);
                Ok(())
            })
            .unwrap();

        assert!(!finished);
        assert!(!operation_ran.get());
    }

    #[test]
    fn current_claim_persists_once_and_removes_flow_atomically() {
        use std::cell::Cell;

        let temp_dir = tempfile::tempdir().unwrap();
        let registry = FlowRegistry::new(temp_dir.path());
        let flow_id = registry.insert(sample_code(1), 100).unwrap();
        let claim = poll_claim(registry.begin_poll(&flow_id, 100).unwrap());
        assert!(
            registry
                .mark_approved(&flow_id, claim, approved_code(), 100)
                .unwrap()
        );
        assert!(
            registry
                .mark_exchanged(&flow_id, claim, exchanged_tokens(), 100)
                .unwrap()
        );

        let operation_ran = Cell::new(false);
        assert!(
            registry
                .finish_if_claimed(&flow_id, claim, 101, || {
                    operation_ran.set(true);
                    Ok(())
                })
                .unwrap()
        );

        assert!(operation_ran.get());
        assert!(!registry.state_path().exists());
        assert!(registry.begin_poll(&flow_id, 101).is_err());
    }

    #[test]
    fn failed_token_persistence_releases_claim_for_retry() {
        let temp_dir = tempfile::tempdir().unwrap();
        let registry = FlowRegistry::new(temp_dir.path());
        let flow_id = registry.insert(sample_code(3), 100).unwrap();
        let claim = poll_claim(registry.begin_poll(&flow_id, 100).unwrap());
        assert!(
            registry
                .mark_approved(&flow_id, claim, approved_code(), 100)
                .unwrap()
        );
        assert!(
            registry
                .mark_exchanged(&flow_id, claim, exchanged_tokens(), 100)
                .unwrap()
        );

        assert!(
            registry
                .finish_if_claimed(&flow_id, claim, 101, || bail!(
                    "simulated persistence failure"
                ))
                .is_err()
        );
        assert_eq!(
            registry.begin_poll(&flow_id, 103).unwrap(),
            FlowAction::Wait {
                retry_after: Duration::from_secs(1)
            }
        );
        assert!(matches!(
            registry.begin_poll(&flow_id, 104).unwrap(),
            FlowAction::Persist(..)
        ));
    }

    #[test]
    fn sign_out_cleanup_removes_flow_even_when_logout_operation_fails() {
        let temp_dir = tempfile::tempdir().unwrap();
        let registry = FlowRegistry::new(temp_dir.path());
        registry.insert(sample_code(3), 100).unwrap();

        assert!(
            registry
                .clear_with(|| bail!("simulated logout failure"))
                .is_err()
        );
        assert!(!registry.state_path().exists());
    }

    #[cfg(unix)]
    #[test]
    fn registry_symlink_is_replaced_without_touching_its_target() {
        use std::os::unix::fs::symlink;

        let temp_dir = tempfile::tempdir().unwrap();
        let target_dir = tempfile::tempdir().unwrap();
        let target = target_dir.path().join("target");
        fs::write(&target, b"do-not-touch").unwrap();
        let registry = FlowRegistry::new(temp_dir.path());
        symlink(&target, registry.state_path()).unwrap();

        registry.insert(sample_code(3), 100).unwrap();

        assert_eq!(fs::read(&target).unwrap(), b"do-not-touch");
        assert!(
            !fs::symlink_metadata(registry.state_path())
                .unwrap()
                .file_type()
                .is_symlink()
        );
    }

    #[cfg(unix)]
    #[test]
    fn persistent_registry_and_lock_are_owner_only() {
        let temp_dir = tempfile::tempdir().unwrap();
        let registry = FlowRegistry::new(temp_dir.path());
        registry.insert(sample_code(3), 100).unwrap();

        let state_mode = fs::metadata(registry.state_path())
            .unwrap()
            .permissions()
            .mode()
            & 0o777;
        let lock_mode = fs::metadata(temp_dir.path().join(REGISTRY_LOCK_NAME))
            .unwrap()
            .permissions()
            .mode()
            & 0o777;
        assert_eq!(state_mode, 0o600);
        assert_eq!(lock_mode, 0o600);
    }
}
