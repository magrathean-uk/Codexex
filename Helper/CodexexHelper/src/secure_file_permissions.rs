use std::fs;
use std::path::Path;

use anyhow::{Context, Result};

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;

pub(crate) fn harden_helper_state_permissions(path: &Path) -> Result<()> {
    #[cfg(unix)]
    {
        fs::set_permissions(path, fs::Permissions::from_mode(0o700))
            .with_context(|| format!("failed to harden helper state dir at {}", path.display()))?;

        let auth_path = path.join("auth.json");
        if auth_path.exists() {
            fs::set_permissions(&auth_path, fs::Permissions::from_mode(0o600))
                .with_context(|| format!("failed to harden auth file at {}", auth_path.display()))?;
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[cfg(unix)]
    #[test]
    fn applies_restrictive_permissions() {
        let dir = tempfile::tempdir().unwrap();
        let auth_path = dir.path().join("auth.json");
        fs::write(&auth_path, b"{}").unwrap();

        harden_helper_state_permissions(dir.path()).unwrap();

        let dir_mode = fs::metadata(dir.path()).unwrap().permissions().mode() & 0o777;
        let file_mode = fs::metadata(auth_path).unwrap().permissions().mode() & 0o777;
        assert_eq!(dir_mode, 0o700);
        assert_eq!(file_mode, 0o600);
    }
}
