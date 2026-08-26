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
        match fs::symlink_metadata(&auth_path) {
            Ok(metadata) => {
                anyhow::ensure!(
                    !metadata.file_type().is_symlink(),
                    "refusing symlinked auth file at {}",
                    auth_path.display()
                );
                fs::set_permissions(&auth_path, fs::Permissions::from_mode(0o600)).with_context(
                    || format!("failed to harden auth file at {}", auth_path.display()),
                )?;
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => {
                return Err(error).with_context(|| {
                    format!("failed to inspect auth file at {}", auth_path.display())
                });
            }
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

    #[cfg(unix)]
    #[test]
    fn refuses_symlinked_auth_file_without_touching_target() {
        use std::os::unix::fs::symlink;

        let dir = tempfile::tempdir().unwrap();
        let target_dir = tempfile::tempdir().unwrap();
        let target_path = target_dir.path().join("target");
        fs::write(&target_path, b"secret").unwrap();
        fs::set_permissions(&target_path, fs::Permissions::from_mode(0o644)).unwrap();
        symlink(&target_path, dir.path().join("auth.json")).unwrap();

        let error = harden_helper_state_permissions(dir.path()).unwrap_err();

        assert!(error.to_string().contains("refusing symlinked auth file"));
        let target_mode = fs::metadata(target_path).unwrap().permissions().mode() & 0o777;
        assert_eq!(target_mode, 0o644);
    }
}
