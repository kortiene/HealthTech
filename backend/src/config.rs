//! Operational configuration loaded from the environment / injected secrets.
//!
//! Issue #4 · [ADR 0007](../../docs/adr/0007-secrets-and-environments.md). The backend reads its
//! operational config from **injected** environment variables (populated from the SOPS/age vault
//! by the IaC — never from a committed plaintext file). This module enforces three invariants:
//!
//! 1. **Fail-fast** on a missing *required* secret in `staging`/`prod` (so a misconfigured deploy
//!    never starts half-blind). In `dev`, storage secrets are optional — local dev uses throwaway
//!    credentials and the storage backend (#9) is not wired yet.
//! 2. **Redaction.** Every secret-bearing field is a [`Secret`], whose `Debug`/`Display` print
//!    `"<redacted>"`. A config dump or a `tracing` line can therefore never leak a password or key.
//! 3. **No patient key material, ever.** Per the zero-knowledge boundary (ADR 0004/0006) this
//!    struct holds **operational** secrets only — no master keys, data keys, or QR session keys.
//!
//! The loader is written against a `get(name) -> Option<String>` closure so tests can exercise it
//! without mutating the process environment (which is racy and `unsafe` on modern std).

use std::error::Error;
use std::fmt;

/// Default bind address when `BIND_ADDR` is unset (dev convenience only; ADR 0007).
pub const DEFAULT_BIND_ADDR: &str = "0.0.0.0:8080";

/// A secret string whose `Debug`/`Display` representations are **redacted**.
///
/// Wrapping every password/key in `Secret` makes it impossible to leak a value through a derived
/// `Debug`, a `tracing` field, or a `{}`/`{:?}` format — the plaintext is only reachable via the
/// explicit [`Secret::expose`] call, which is easy to grep for in review.
#[derive(Clone, PartialEq, Eq)]
pub struct Secret(String);

impl Secret {
    /// Wrap a value as a secret.
    pub fn new(value: impl Into<String>) -> Self {
        Self(value.into())
    }

    /// Reveal the underlying value. The explicit name makes every use auditable in review.
    /// Consumed by the storage wiring (#9/#23); `allow(dead_code)` until then so the redacting
    /// accessor can land now without the unused-method lint failing `clippy -D warnings`.
    #[allow(dead_code)]
    pub fn expose(&self) -> &str {
        &self.0
    }
}

impl fmt::Debug for Secret {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("Secret(<redacted>)")
    }
}

impl fmt::Display for Secret {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("<redacted>")
    }
}

impl From<String> for Secret {
    fn from(value: String) -> Self {
        Self(value)
    }
}

/// The deployment environment, selected by `APP_ENV` (default `dev`).
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AppEnv {
    /// Developer laptop: synthetic data + throwaway secrets; storage secrets optional.
    Dev,
    /// In-country staging (ARTCI residency applies); storage secrets required.
    Staging,
    /// In-country production (ARTCI residency applies); storage secrets required.
    Prod,
}

impl AppEnv {
    /// Whether storage/operational secrets are *required* (true for staging/prod).
    fn secrets_required(self) -> bool {
        matches!(self, AppEnv::Staging | AppEnv::Prod)
    }

    fn parse(raw: &str) -> Result<Self, ConfigError> {
        match raw.trim().to_ascii_lowercase().as_str() {
            "dev" | "development" | "" => Ok(AppEnv::Dev),
            "staging" | "stage" => Ok(AppEnv::Staging),
            "prod" | "production" => Ok(AppEnv::Prod),
            other => Err(ConfigError::InvalidAppEnv(other.to_string())),
        }
    }
}

impl fmt::Display for AppEnv {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let s = match self {
            AppEnv::Dev => "dev",
            AppEnv::Staging => "staging",
            AppEnv::Prod => "prod",
        };
        f.write_str(s)
    }
}

/// Validated backend operational configuration.
///
/// Non-secret fields are plain; every secret-bearing field is a [`Secret`], so the derived `Debug`
/// is safe to log. Storage fields are `Option` because the storage backend (#9) is not wired yet:
/// they are *required* in staging/prod and *optional* in dev. They become unconditionally required
/// once #9/#23 consume them.
#[derive(Clone, Debug)]
pub struct Config {
    /// Selected environment (`APP_ENV`).
    pub app_env: AppEnv,
    /// TCP bind address (`BIND_ADDR`, default [`DEFAULT_BIND_ADDR`]). Not a secret.
    pub bind_addr: String,
    /// PostgreSQL DSN incl. password (`DATABASE_URL`). Consumed by #9.
    pub database_url: Option<Secret>,
    /// MinIO endpoint (`MINIO_ENDPOINT`). Not a secret (an address, not a credential).
    pub minio_endpoint: Option<String>,
    /// MinIO access key id (`MINIO_ACCESS_KEY`). Consumed by #9/#23.
    pub minio_access_key: Option<Secret>,
    /// MinIO secret key (`MINIO_SECRET_KEY`). Consumed by #9/#23.
    pub minio_secret_key: Option<Secret>,
    /// Key that signs short-TTL presigned media URLs (`PRESIGNED_URL_SIGNING_KEY`). Consumed by #23.
    pub presigned_url_signing_key: Option<Secret>,
}

impl Config {
    /// Load and validate config from the process environment. Fails fast on any error.
    pub fn from_env() -> Result<Self, ConfigError> {
        Self::load(|name| std::env::var(name).ok())
    }

    /// Names of the storage secrets that were injected (present). Returns variable **names**
    /// only — never values — so a startup log line can confirm injection without leaking anything.
    /// Also makes the not-yet-consumed storage fields (#9/#23) genuinely read until then.
    pub fn injected_storage_secrets(&self) -> Vec<&'static str> {
        let mut present = Vec::new();
        if self.database_url.is_some() {
            present.push("DATABASE_URL");
        }
        if self.minio_endpoint.is_some() {
            present.push("MINIO_ENDPOINT");
        }
        if self.minio_access_key.is_some() {
            present.push("MINIO_ACCESS_KEY");
        }
        if self.minio_secret_key.is_some() {
            present.push("MINIO_SECRET_KEY");
        }
        if self.presigned_url_signing_key.is_some() {
            present.push("PRESIGNED_URL_SIGNING_KEY");
        }
        present
    }

    /// Load from an arbitrary source. Generic over `get` so tests need not touch the real env.
    pub fn load(get: impl Fn(&str) -> Option<String>) -> Result<Self, ConfigError> {
        let non_empty = |name: &str| get(name).filter(|v| !v.trim().is_empty());

        let app_env = AppEnv::parse(&non_empty("APP_ENV").unwrap_or_default())?;
        let bind_addr = non_empty("BIND_ADDR").unwrap_or_else(|| DEFAULT_BIND_ADDR.to_string());

        // In staging/prod a missing storage secret is a hard error (fail-fast); in dev it is fine.
        let required = app_env.secrets_required();
        let secret = |name: &'static str| -> Result<Option<Secret>, ConfigError> {
            match non_empty(name) {
                Some(v) => Ok(Some(Secret::new(v))),
                None if required => Err(ConfigError::MissingRequired(name)),
                None => Ok(None),
            }
        };
        let plain = |name: &'static str| -> Result<Option<String>, ConfigError> {
            match non_empty(name) {
                Some(v) => Ok(Some(v)),
                None if required => Err(ConfigError::MissingRequired(name)),
                None => Ok(None),
            }
        };

        Ok(Config {
            app_env,
            bind_addr,
            database_url: secret("DATABASE_URL")?,
            minio_endpoint: plain("MINIO_ENDPOINT")?,
            minio_access_key: secret("MINIO_ACCESS_KEY")?,
            minio_secret_key: secret("MINIO_SECRET_KEY")?,
            presigned_url_signing_key: secret("PRESIGNED_URL_SIGNING_KEY")?,
        })
    }
}

/// A configuration error. Its `Display` names the offending **variable** but never a secret value.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum ConfigError {
    /// `APP_ENV` was set to something other than dev/staging/prod.
    InvalidAppEnv(String),
    /// A required secret/variable was missing in staging/prod.
    MissingRequired(&'static str),
}

impl fmt::Display for ConfigError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            ConfigError::InvalidAppEnv(v) => {
                write!(f, "invalid APP_ENV '{v}' (expected dev | staging | prod)")
            }
            ConfigError::MissingRequired(name) => {
                write!(f, "missing required configuration: {name} (inject it via the secrets vault — ADR 0007)")
            }
        }
    }
}

impl Error for ConfigError {}

#[cfg(test)]
mod tests {
    use super::*;
    use std::collections::HashMap;

    /// Build a `get` closure from a list of pairs.
    fn env(pairs: &[(&str, &str)]) -> impl Fn(&str) -> Option<String> {
        let map: HashMap<String, String> = pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect();
        move |name: &str| map.get(name).cloned()
    }

    #[test]
    fn defaults_to_dev_with_optional_secrets() {
        let cfg = Config::load(env(&[])).expect("dev config loads with no secrets");
        assert_eq!(cfg.app_env, AppEnv::Dev);
        assert_eq!(cfg.bind_addr, DEFAULT_BIND_ADDR);
        assert!(cfg.database_url.is_none());
        assert!(cfg.presigned_url_signing_key.is_none());
    }

    #[test]
    fn invalid_app_env_is_rejected() {
        let err = Config::load(env(&[("APP_ENV", "qa")])).unwrap_err();
        assert_eq!(err, ConfigError::InvalidAppEnv("qa".to_string()));
    }

    #[test]
    fn staging_fails_fast_on_missing_required_secret() {
        // staging requires the storage secrets; the first missing one trips fail-fast.
        let err = Config::load(env(&[("APP_ENV", "staging")])).unwrap_err();
        match err {
            ConfigError::MissingRequired(name) => assert_eq!(name, "DATABASE_URL"),
            other => panic!("expected MissingRequired, got {other:?}"),
        }
    }

    #[test]
    fn staging_loads_when_all_required_secrets_present() {
        let cfg = Config::load(env(&[
            ("APP_ENV", "staging"),
            ("DATABASE_URL", "postgres://app:pw@db/health"),
            ("MINIO_ENDPOINT", "https://minio.internal:9000"),
            ("MINIO_ACCESS_KEY", "ak"),
            ("MINIO_SECRET_KEY", "sk"),
            ("PRESIGNED_URL_SIGNING_KEY", "sign"),
        ]))
        .expect("staging config loads when complete");
        assert_eq!(cfg.app_env, AppEnv::Staging);
        assert_eq!(
            cfg.database_url.as_ref().unwrap().expose(),
            "postgres://app:pw@db/health"
        );
    }

    #[test]
    fn blank_value_counts_as_missing() {
        // An injected-but-empty var must not satisfy a required secret.
        let err = Config::load(env(&[("APP_ENV", "prod"), ("DATABASE_URL", "   ")])).unwrap_err();
        assert_eq!(err, ConfigError::MissingRequired("DATABASE_URL"));
    }

    #[test]
    fn debug_redacts_every_secret_field() {
        let cfg = Config::load(env(&[
            ("APP_ENV", "prod"),
            ("DATABASE_URL", "postgres://app:SUPERSECRETPW@db/health"),
            ("MINIO_ENDPOINT", "https://minio.internal:9000"),
            ("MINIO_ACCESS_KEY", "AKIA_LEAKME"),
            ("MINIO_SECRET_KEY", "MINIOSECRETLEAK"),
            ("PRESIGNED_URL_SIGNING_KEY", "PRESIGNLEAK"),
        ]))
        .unwrap();

        let dumped = format!("{cfg:?}");
        for leak in [
            "SUPERSECRETPW",
            "AKIA_LEAKME",
            "MINIOSECRETLEAK",
            "PRESIGNLEAK",
        ] {
            assert!(
                !dumped.contains(leak),
                "secret '{leak}' leaked into Debug: {dumped}"
            );
        }
        assert!(dumped.contains("<redacted>"));
        // Non-secret fields are still visible for diagnostics (derived Debug → `Prod`).
        assert!(dumped.contains("Prod"));
        assert!(dumped.contains("minio.internal"));
    }

    #[test]
    fn secret_display_and_debug_are_redacted() {
        let s = Secret::new("hunter2");
        assert_eq!(format!("{s}"), "<redacted>");
        assert_eq!(format!("{s:?}"), "Secret(<redacted>)");
        assert_eq!(s.expose(), "hunter2");
    }

    // --- aliases & edge-cases for APP_ENV parsing ----------------------------

    #[test]
    fn app_env_aliases_are_accepted() {
        // "development" → Dev (no secrets required)
        let cfg = Config::load(env(&[("APP_ENV", "development")])).unwrap();
        assert_eq!(cfg.app_env, AppEnv::Dev);

        // "stage" → Staging (requires storage secrets)
        let cfg = Config::load(env(&[
            ("APP_ENV", "stage"),
            ("DATABASE_URL", "postgres://app:pw@db/health"),
            ("MINIO_ENDPOINT", "https://minio:9000"),
            ("MINIO_ACCESS_KEY", "ak"),
            ("MINIO_SECRET_KEY", "sk"),
            ("PRESIGNED_URL_SIGNING_KEY", "sign"),
        ]))
        .unwrap();
        assert_eq!(cfg.app_env, AppEnv::Staging);

        // "production" → Prod (requires storage secrets)
        let cfg = Config::load(env(&[
            ("APP_ENV", "production"),
            ("DATABASE_URL", "postgres://app:pw@db/health"),
            ("MINIO_ENDPOINT", "https://minio:9000"),
            ("MINIO_ACCESS_KEY", "ak"),
            ("MINIO_SECRET_KEY", "sk"),
            ("PRESIGNED_URL_SIGNING_KEY", "sign"),
        ]))
        .unwrap();
        assert_eq!(cfg.app_env, AppEnv::Prod);
    }

    #[test]
    fn whitespace_only_app_env_defaults_to_dev() {
        // A value that trims to empty must not be treated as a valid env name.
        let cfg = Config::load(env(&[("APP_ENV", "   ")])).unwrap();
        assert_eq!(cfg.app_env, AppEnv::Dev);
    }

    #[test]
    fn app_env_display_all_variants() {
        assert_eq!(format!("{}", AppEnv::Dev), "dev");
        assert_eq!(format!("{}", AppEnv::Staging), "staging");
        assert_eq!(format!("{}", AppEnv::Prod), "prod");
    }

    // --- custom BIND_ADDR ----------------------------------------------------

    #[test]
    fn custom_bind_addr_is_preserved() {
        let cfg = Config::load(env(&[("BIND_ADDR", "127.0.0.1:9999")])).unwrap();
        assert_eq!(cfg.bind_addr, "127.0.0.1:9999");
    }

    // --- prod fail-fast & happy-path -----------------------------------------

    #[test]
    fn prod_fails_fast_on_missing_secret() {
        let err = Config::load(env(&[("APP_ENV", "prod")])).unwrap_err();
        assert_eq!(err, ConfigError::MissingRequired("DATABASE_URL"));
    }

    #[test]
    fn prod_loads_with_all_required_secrets() {
        let cfg = Config::load(env(&[
            ("APP_ENV", "prod"),
            ("DATABASE_URL", "postgres://app:pw@db/health"),
            ("MINIO_ENDPOINT", "https://minio.internal:9000"),
            ("MINIO_ACCESS_KEY", "ak"),
            ("MINIO_SECRET_KEY", "sk"),
            ("PRESIGNED_URL_SIGNING_KEY", "sign"),
        ]))
        .unwrap();
        assert_eq!(cfg.app_env, AppEnv::Prod);
    }

    // --- every required secret is individually enforced in staging -----------

    /// Verifies that each of the 5 storage secrets is individually required in
    /// staging: supplying all others still fails when one is absent.
    #[test]
    fn each_required_secret_is_enforced_in_staging() {
        let all: &[(&str, &str)] = &[
            ("APP_ENV", "staging"),
            ("DATABASE_URL", "postgres://app:pw@db/health"),
            ("MINIO_ENDPOINT", "https://minio:9000"),
            ("MINIO_ACCESS_KEY", "ak"),
            ("MINIO_SECRET_KEY", "sk"),
            ("PRESIGNED_URL_SIGNING_KEY", "sign"),
        ];
        // DATABASE_URL is already covered by staging_fails_fast_on_missing_required_secret.
        for skip in [
            "MINIO_ENDPOINT",
            "MINIO_ACCESS_KEY",
            "MINIO_SECRET_KEY",
            "PRESIGNED_URL_SIGNING_KEY",
        ] {
            let partial: Vec<_> = all.iter().filter(|(k, _)| *k != skip).copied().collect();
            let err = Config::load(env(&partial)).unwrap_err();
            assert_eq!(
                err,
                ConfigError::MissingRequired(skip),
                "expected MissingRequired({skip}) when it is absent from staging config"
            );
        }
    }

    // --- injected_storage_secrets() ------------------------------------------

    #[test]
    fn injected_storage_secrets_returns_present_variable_names() {
        let cfg = Config::load(env(&[
            ("APP_ENV", "prod"),
            ("DATABASE_URL", "postgres://app:pw@db/health"),
            ("MINIO_ENDPOINT", "https://minio.internal:9000"),
            ("MINIO_ACCESS_KEY", "ak"),
            ("MINIO_SECRET_KEY", "sk"),
            ("PRESIGNED_URL_SIGNING_KEY", "sign"),
        ]))
        .unwrap();
        let names = cfg.injected_storage_secrets();
        assert_eq!(names.len(), 5, "all 5 storage secrets should be reported");
        for expected in [
            "DATABASE_URL",
            "MINIO_ENDPOINT",
            "MINIO_ACCESS_KEY",
            "MINIO_SECRET_KEY",
            "PRESIGNED_URL_SIGNING_KEY",
        ] {
            assert!(
                names.contains(&expected),
                "expected {expected} in injected_storage_secrets()"
            );
        }
    }

    #[test]
    fn injected_storage_secrets_is_empty_when_none_present() {
        let cfg = Config::load(env(&[])).unwrap(); // dev, no secrets
        assert!(cfg.injected_storage_secrets().is_empty());
    }

    /// The method must return variable *names*, never the secret *values*. A
    /// startup log line can therefore safely include the returned list.
    #[test]
    fn injected_storage_secrets_never_leaks_values() {
        let cfg = Config::load(env(&[
            ("APP_ENV", "prod"),
            ("DATABASE_URL", "UNIQUESECRETPGPASSWORD"),
            ("MINIO_ENDPOINT", "https://minio.internal:9000"),
            ("MINIO_ACCESS_KEY", "UNIQUEACCESSKEYVALUE"),
            ("MINIO_SECRET_KEY", "UNIQUESECRETMINIOVAL"),
            ("PRESIGNED_URL_SIGNING_KEY", "UNIQUEPRESIGNKEYVAL"),
        ]))
        .unwrap();
        let names = cfg.injected_storage_secrets();
        let joined = names.join(",");
        for leaked in [
            "UNIQUESECRETPGPASSWORD",
            "UNIQUEACCESSKEYVALUE",
            "UNIQUESECRETMINIOVAL",
            "UNIQUEPRESIGNKEYVAL",
        ] {
            assert!(
                !joined.contains(leaked),
                "secret value '{leaked}' leaked into injected_storage_secrets(): {joined}"
            );
        }
    }

    // --- ConfigError Display -------------------------------------------------

    #[test]
    fn config_error_display_includes_offending_name_and_guidance() {
        // InvalidAppEnv: includes the bad value and acceptable alternatives.
        let e = ConfigError::InvalidAppEnv("canary".to_string());
        let s = format!("{e}");
        assert!(
            s.contains("canary"),
            "Display should echo the bad value: {s}"
        );
        assert!(
            s.contains("dev") || s.contains("staging") || s.contains("prod"),
            "Display should mention the acceptable values: {s}"
        );

        // MissingRequired: names the variable and references the vault / ADR.
        let e = ConfigError::MissingRequired("DATABASE_URL");
        let s = format!("{e}");
        assert!(
            s.contains("DATABASE_URL"),
            "Display must name the variable: {s}"
        );
        assert!(
            s.contains("ADR") || s.contains("vault") || s.contains("secret"),
            "Display must point to the injection mechanism: {s}"
        );
    }

    // --- Secret::from(String) ------------------------------------------------

    #[test]
    fn secret_from_string_impl() {
        let s: Secret = String::from("hunter2").into();
        assert_eq!(s.expose(), "hunter2");
        assert_eq!(format!("{s}"), "<redacted>");
    }

    // --- partial injection in dev --------------------------------------------

    /// In dev, supplying only some storage secrets is valid (the others default to None).
    #[test]
    fn partial_dev_config_with_some_secrets_succeeds() {
        let cfg = Config::load(env(&[
            ("APP_ENV", "dev"),
            ("DATABASE_URL", "postgres://app:throwaway@localhost/health"),
            // MINIO_* and PRESIGNED_URL_SIGNING_KEY deliberately absent
        ]))
        .expect("dev config must accept partial secret injection");
        assert_eq!(cfg.app_env, AppEnv::Dev);
        assert!(cfg.database_url.is_some());
        assert!(cfg.minio_access_key.is_none());
        assert!(cfg.minio_secret_key.is_none());
        assert!(cfg.presigned_url_signing_key.is_none());
    }

    /// injected_storage_secrets() must return only the names that are actually present.
    #[test]
    fn injected_storage_secrets_partial_injection() {
        let cfg = Config::load(env(&[
            ("DATABASE_URL", "postgres://app:throwaway@localhost/health"),
            ("MINIO_ENDPOINT", "http://localhost:9000"),
            // MINIO_ACCESS_KEY, MINIO_SECRET_KEY, PRESIGNED_URL_SIGNING_KEY absent
        ]))
        .unwrap();
        let names = cfg.injected_storage_secrets();
        assert_eq!(names.len(), 2, "only 2 of the 5 secrets are present");
        assert!(names.contains(&"DATABASE_URL"));
        assert!(names.contains(&"MINIO_ENDPOINT"));
        assert!(!names.contains(&"MINIO_ACCESS_KEY"));
        assert!(!names.contains(&"PRESIGNED_URL_SIGNING_KEY"));
    }

    // --- APP_ENV case-insensitivity ------------------------------------------

    /// `to_ascii_lowercase()` means "DEV", "STAGING", "PROD" must be accepted.
    #[test]
    fn app_env_uppercase_aliases_accepted() {
        let cfg = Config::load(env(&[("APP_ENV", "DEV")])).unwrap();
        assert_eq!(cfg.app_env, AppEnv::Dev);

        let cfg = Config::load(env(&[
            ("APP_ENV", "STAGING"),
            ("DATABASE_URL", "postgres://app:pw@db/health"),
            ("MINIO_ENDPOINT", "https://minio:9000"),
            ("MINIO_ACCESS_KEY", "ak"),
            ("MINIO_SECRET_KEY", "sk"),
            ("PRESIGNED_URL_SIGNING_KEY", "sign"),
        ]))
        .unwrap();
        assert_eq!(cfg.app_env, AppEnv::Staging);

        let cfg = Config::load(env(&[
            ("APP_ENV", "PROD"),
            ("DATABASE_URL", "postgres://app:pw@db/health"),
            ("MINIO_ENDPOINT", "https://minio:9000"),
            ("MINIO_ACCESS_KEY", "ak"),
            ("MINIO_SECRET_KEY", "sk"),
            ("PRESIGNED_URL_SIGNING_KEY", "sign"),
        ]))
        .unwrap();
        assert_eq!(cfg.app_env, AppEnv::Prod);
    }

    // --- Secret PartialEq ----------------------------------------------------

    #[test]
    fn secret_eq_same_value() {
        let a = Secret::new("hunter2");
        let b = Secret::new("hunter2");
        assert_eq!(a, b, "Secret with identical values must be equal");
    }

    #[test]
    fn secret_ne_different_values() {
        let a = Secret::new("hunter2");
        let b = Secret::new("swordfish");
        assert_ne!(a, b, "Secret with different values must not be equal");
    }

    // --- Config::clone() preserves redaction ---------------------------------

    /// Cloning a Config must not unredact secret fields: the clone's Debug output
    /// must still print `<redacted>`, not the raw value.
    #[test]
    fn config_clone_redacts_in_debug() {
        let cfg = Config::load(env(&[
            ("APP_ENV", "prod"),
            ("DATABASE_URL", "postgres://app:CLONESECRETPW@db/health"),
            ("MINIO_ENDPOINT", "https://minio.internal:9000"),
            ("MINIO_ACCESS_KEY", "CLONEAKVAL"),
            ("MINIO_SECRET_KEY", "CLONESKVAL"),
            ("PRESIGNED_URL_SIGNING_KEY", "CLONESIGNVAL"),
        ]))
        .unwrap();
        let cloned = cfg.clone();
        let dumped = format!("{cloned:?}");
        for leak in ["CLONESECRETPW", "CLONEAKVAL", "CLONESKVAL", "CLONESIGNVAL"] {
            assert!(
                !dumped.contains(leak),
                "cloned Config must not leak '{leak}' in Debug: {dumped}"
            );
        }
        assert!(dumped.contains("<redacted>"));
    }
}
