use std::env;

pub(crate) fn development_env_var(name: &str) -> Option<String> {
    #[cfg(any(debug_assertions, test, feature = "internal-env-overrides"))]
    {
        env::var(name)
            .ok()
            .map(|value| value.trim().trim_end_matches('/').to_string())
            .filter(|value| value.is_empty() == false)
    }

    #[cfg(not(any(debug_assertions, test, feature = "internal-env-overrides")))]
    {
        let _ = name;
        None
    }
}

pub(crate) fn development_env_path(name: &str) -> Option<std::path::PathBuf> {
    #[cfg(any(debug_assertions, test, feature = "internal-env-overrides"))]
    {
        env::var_os(name).map(std::path::PathBuf::from)
    }

    #[cfg(not(any(debug_assertions, test, feature = "internal-env-overrides")))]
    {
        let _ = name;
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn debug_or_test_build_can_read_override() {
        unsafe { env::set_var("CODEXEX_TEST_OVERRIDE", " https://example.test/ ") };
        assert_eq!(
            development_env_var("CODEXEX_TEST_OVERRIDE").as_deref(),
            Some("https://example.test")
        );
        unsafe { env::remove_var("CODEXEX_TEST_OVERRIDE") };
    }
}
