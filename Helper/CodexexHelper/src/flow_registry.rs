use std::collections::HashMap;
use std::fs::File;
use std::io::Read;
use std::sync::{LazyLock, Mutex};
use std::time::{Duration, Instant};

use anyhow::{Context, Result, bail};
use base64::Engine;

use crate::auth::StoredDeviceCode;

const FLOW_ID_BYTES: usize = 32;
pub const FLOW_TTL: Duration = Duration::from_secs(10 * 60);

#[derive(Debug, Clone)]
struct PendingFlow {
    device_code: StoredDeviceCode,
    created_at: Instant,
    expires_at: Instant,
}

static FLOWS: LazyLock<Mutex<HashMap<String, PendingFlow>>> =
    LazyLock::new(|| Mutex::new(HashMap::new()));

pub(crate) fn insert(device_code: StoredDeviceCode) -> Result<String> {
    let now = Instant::now();
    let mut flows = FLOWS
        .lock()
        .map_err(|_| anyhow::anyhow!("flow registry is unavailable"))?;
    prune_locked(&mut flows, now);

    for _ in 0..4 {
        let flow_id = random_flow_id()?;
        if flows.contains_key(&flow_id) == false {
            flows.insert(
                flow_id.clone(),
                PendingFlow {
                    device_code,
                    created_at: now,
                    expires_at: now + FLOW_TTL,
                },
            );
            return Ok(flow_id);
        }
    }

    bail!("could not allocate sign-in flow");
}

pub(crate) fn get(flow_id: &str) -> Result<StoredDeviceCode> {
    let now = Instant::now();
    let mut flows = FLOWS
        .lock()
        .map_err(|_| anyhow::anyhow!("flow registry is unavailable"))?;
    prune_locked(&mut flows, now);
    let Some(flow) = flows.get(flow_id) else {
        bail!("Sign-in code expired. Start again.");
    };
    Ok(flow.device_code.clone())
}

pub(crate) fn remove(flow_id: &str) {
    if let Ok(mut flows) = FLOWS.lock() {
        flows.remove(flow_id);
    }
}

pub(crate) fn clear_all() {
    if let Ok(mut flows) = FLOWS.lock() {
        flows.clear();
    }
}

fn prune_locked(flows: &mut HashMap<String, PendingFlow>, now: Instant) {
    flows.retain(|_, flow| flow.expires_at > now && flow.created_at <= now);
}

fn random_flow_id() -> Result<String> {
    let mut bytes = [0_u8; FLOW_ID_BYTES];
    File::open("/dev/urandom")
        .context("failed to open system random source")?
        .read_exact(&mut bytes)
        .context("failed to read system random source")?;
    Ok(base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(bytes))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_code() -> StoredDeviceCode {
        StoredDeviceCode {
            verification_url: "https://auth.openai.com/codex/device".to_string(),
            user_code: "ABCD-1234".to_string(),
            device_auth_id: "device-secret".to_string(),
            interval: 3,
        }
    }

    #[test]
    fn flow_id_is_opaque_and_resolves_to_stored_device_code() {
        clear_all();
        let flow_id = insert(sample_code()).unwrap();
        assert!(flow_id.len() >= 32);
        assert!(!flow_id.contains("device-secret"));
        assert!(!flow_id.contains("ABCD-1234"));
        assert!(!flow_id.contains('{'));
        let resolved = get(&flow_id).unwrap();
        assert_eq!(resolved.user_code, "ABCD-1234");
    }

    #[test]
    fn removed_flow_cannot_be_replayed() {
        clear_all();
        let flow_id = insert(sample_code()).unwrap();
        remove(&flow_id);
        assert!(get(&flow_id).is_err());
    }
}
