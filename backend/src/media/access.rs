//! Ephemeral media access — short-TTL, per-object, revocable capability URLs (issue #23, #2).
//!
//! A media object is read through a **capability URL** the backend mints on demand:
//! `GET /media/{uuid}?exp=<unix>&sig=<hex>`. The signature is an HMAC-SHA256 over `uuid:exp` keyed
//! by `PRESIGNED_URL_SIGNING_KEY` (ADR 0007), so the URL is:
//!
//! - **short-TTL** — it carries an absolute expiry (`exp`); past it, [`MediaAccess::verify`]
//!   refuses the request (issue #23 acceptance criterion #2 — *URL éphémère révoquée après
//!   expiration*);
//! - **per-object** — the signature binds the exact `uuid`, so a URL for one object cannot be
//!   replayed against another;
//! - **revocable** — globally by rotating `PRESIGNED_URL_SIGNING_KEY` (every outstanding signature
//!   becomes invalid), and per-object by `DELETE /media/{uuid}`.
//!
//! Keeping MinIO private behind a backend-minted capability URL (rather than a native presigned S3
//! URL) is the variant ADR 0005's existing `PRESIGNED_URL_SIGNING_KEY` config field points to: it
//! gives the backend a single audit/revocation point and never exposes the object store to clients.
//!
//! The signature/URL is a **bearer secret**: it is never logged here (handlers log only the
//! anonymous UUID + status), and the client never persists it.

use std::time::{SystemTime, UNIX_EPOCH};

use hmac::{Hmac, Mac};
use sha2::Sha256;
use uuid::Uuid;

use crate::config::Config;

type HmacSha256 = Hmac<Sha256>;

/// Time-to-live of a minted access URL. A few minutes: long enough to fetch + decrypt a scan on a
/// degraded link, short enough to stay ephemeral. Bounded above the 120 s QR window (#16) because a
/// large image can take longer to pull than the session-key handshake. Tunable with #6/#28.
pub const MEDIA_URL_TTL_SECS: u64 = 300;

/// Throwaway signing key used **only in dev** when `PRESIGNED_URL_SIGNING_KEY` is not injected.
/// Staging/prod fail fast on a missing key (see [`crate::config`]), so this is never reached there.
const DEV_FALLBACK_SIGNING_KEY: &[u8] =
    b"healthtech-dev-throwaway-presign-key-not-for-staging-or-prod";

/// Current wall-clock time as whole Unix seconds. Monotonic enough for TTL comparison; a clock that
/// is somehow before the epoch degrades safely to `0` (every URL then reads as long-expired).
pub fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

/// A minted capability grant: the query string to append to the object URL, plus the absolute
/// expiry (for the `expires_at` field of the access response).
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AccessGrant {
    /// `exp=<unix>&sig=<hex>` — appended to `/media/{uuid}` to form the capability URL.
    pub query: String,
    /// Absolute expiry as Unix seconds.
    pub expires_at_unix: u64,
}

/// Mints and verifies media capability URLs with the injected signing key.
#[derive(Clone)]
pub struct MediaAccess {
    signing_key: Vec<u8>,
    ttl_secs: u64,
}

impl MediaAccess {
    /// Build with an explicit signing key + TTL (used by tests for determinism).
    pub fn new(signing_key: Vec<u8>, ttl_secs: u64) -> Self {
        Self {
            signing_key,
            ttl_secs,
        }
    }

    /// Build from the injected config. Uses `PRESIGNED_URL_SIGNING_KEY` when present; in dev (where
    /// it is optional) falls back to a clearly-labelled throwaway key and warns. The `Secret` is
    /// exposed exactly once, here, to seed the HMAC — never logged.
    pub fn from_config(config: &Config) -> Self {
        match config.presigned_url_signing_key.as_ref() {
            Some(secret) => Self::new(secret.expose().as_bytes().to_vec(), MEDIA_URL_TTL_SECS),
            None => {
                tracing::warn!(
                    "PRESIGNED_URL_SIGNING_KEY not injected; using a throwaway dev signing key — \
                     never reached in staging/prod (config fails fast there)"
                );
                Self::new(DEV_FALLBACK_SIGNING_KEY.to_vec(), MEDIA_URL_TTL_SECS)
            }
        }
    }

    /// The signed message binds the object UUID and the absolute expiry, so a signature is valid
    /// for exactly one `(uuid, exp)` pair.
    fn mac(&self, uuid: &Uuid, exp: u64) -> HmacSha256 {
        // `new_from_slice` accepts any key length for HMAC; the error type is `Infallible`-like.
        let mut mac =
            HmacSha256::new_from_slice(&self.signing_key).expect("HMAC accepts any key length");
        mac.update(uuid.as_bytes());
        mac.update(b":");
        mac.update(exp.to_string().as_bytes());
        mac
    }

    /// Mint a capability grant for `uuid`, valid until `now_unix + ttl`.
    pub fn mint(&self, uuid: &Uuid, now_unix: u64) -> AccessGrant {
        let exp = now_unix.saturating_add(self.ttl_secs);
        let sig = hex::encode(self.mac(uuid, exp).finalize().into_bytes());
        AccessGrant {
            query: format!("exp={exp}&sig={sig}"),
            expires_at_unix: exp,
        }
    }

    /// Verify a presented `(uuid, exp, sig)` at time `now_unix`.
    ///
    /// Returns `true` only when the signature authenticates **and** the URL has not expired. A
    /// forged/tampered signature and an expired URL both return `false` — the caller maps either to
    /// `403`, deliberately giving no oracle distinguishing "expired" from "forged". The signature
    /// check is constant-time (`Mac::verify_slice`).
    pub fn verify(&self, uuid: &Uuid, exp: u64, sig_hex: &str, now_unix: u64) -> bool {
        let Ok(provided) = hex::decode(sig_hex) else {
            return false;
        };
        if self.mac(uuid, exp).verify_slice(&provided).is_err() {
            return false;
        }
        now_unix <= exp
    }
}

/// Format a Unix timestamp (seconds) as an ISO-8601 UTC string `YYYY-MM-DDThh:mm:ssZ`.
///
/// Dependency-free civil-date conversion (Howard Hinnant's `civil_from_days`, epoch 1970-01-01) so
/// the access response can report a human `expires_at` without pulling in a date crate.
pub fn unix_to_iso8601(secs: u64) -> String {
    let days = (secs / 86_400) as i64;
    let rem = secs % 86_400;
    let (hh, mm, ss) = (rem / 3600, (rem % 3600) / 60, rem % 60);

    // civil_from_days: days since 1970-01-01 → (year, month, day).
    let z = days + 719_468;
    let era = (if z >= 0 { z } else { z - 146_096 }) / 146_097;
    let doe = z - era * 146_097; // [0, 146096]
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365; // [0, 399]
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100); // [0, 365]
    let mp = (5 * doy + 2) / 153; // [0, 11]
    let d = doy - (153 * mp + 2) / 5 + 1; // [1, 31]
    let m = if mp < 10 { mp + 3 } else { mp - 9 }; // [1, 12]
    let year = if m <= 2 { y + 1 } else { y };

    format!("{year:04}-{m:02}-{d:02}T{hh:02}:{mm:02}:{ss:02}Z")
}

#[cfg(test)]
mod tests {
    use super::*;

    fn access() -> MediaAccess {
        MediaAccess::new(b"unit-test-signing-key".to_vec(), MEDIA_URL_TTL_SECS)
    }

    /// Split a minted query `exp=..&sig=..` into its two parts.
    fn parts(query: &str) -> (u64, String) {
        let mut exp = None;
        let mut sig = None;
        for kv in query.split('&') {
            let (k, v) = kv.split_once('=').unwrap();
            match k {
                "exp" => exp = Some(v.parse().unwrap()),
                "sig" => sig = Some(v.to_string()),
                _ => {}
            }
        }
        (exp.unwrap(), sig.unwrap())
    }

    #[test]
    fn freshly_minted_url_verifies() {
        let a = access();
        let uuid = Uuid::new_v4();
        let now = 1_700_000_000;
        let grant = a.mint(&uuid, now);
        let (exp, sig) = parts(&grant.query);
        assert_eq!(exp, now + MEDIA_URL_TTL_SECS);
        assert!(a.verify(&uuid, exp, &sig, now));
    }

    #[test]
    fn expired_url_is_refused() {
        // Acceptance criterion #2: a URL past its expiry is rejected even though the signature is
        // perfectly valid.
        let a = access();
        let uuid = Uuid::new_v4();
        let now = 1_700_000_000;
        let grant = a.mint(&uuid, now);
        let (exp, sig) = parts(&grant.query);
        // One second past expiry.
        assert!(!a.verify(&uuid, exp, &sig, exp + 1));
        // Exactly at expiry is still allowed (inclusive bound).
        assert!(a.verify(&uuid, exp, &sig, exp));
    }

    #[test]
    fn tampered_signature_is_refused() {
        let a = access();
        let uuid = Uuid::new_v4();
        let now = 1_700_000_000;
        let (exp, mut sig) = parts(&a.mint(&uuid, now).query);
        // Flip the last hex nibble.
        let last = sig.pop().unwrap();
        sig.push(if last == '0' { '1' } else { '0' });
        assert!(!a.verify(&uuid, exp, &sig, now));
    }

    #[test]
    fn signature_for_one_uuid_does_not_verify_for_another() {
        // Per-object scope: a capability minted for uuid_a must not authorise uuid_b.
        let a = access();
        let uuid_a = Uuid::new_v4();
        let uuid_b = Uuid::new_v4();
        let now = 1_700_000_000;
        let (exp, sig) = parts(&a.mint(&uuid_a, now).query);
        assert!(a.verify(&uuid_a, exp, &sig, now));
        assert!(!a.verify(&uuid_b, exp, &sig, now));
    }

    #[test]
    fn rotating_the_signing_key_revokes_outstanding_urls() {
        // Global forced revocation: a URL minted under the old key fails under a rotated key.
        let uuid = Uuid::new_v4();
        let now = 1_700_000_000;
        let old = MediaAccess::new(b"old-key".to_vec(), MEDIA_URL_TTL_SECS);
        let (exp, sig) = parts(&old.mint(&uuid, now).query);
        let rotated = MediaAccess::new(b"new-rotated-key".to_vec(), MEDIA_URL_TTL_SECS);
        assert!(!rotated.verify(&uuid, exp, &sig, now));
    }

    #[test]
    fn non_hex_signature_is_refused_without_panic() {
        let a = access();
        assert!(!a.verify(&Uuid::new_v4(), 1_700_000_300, "not-hex!!", 1_700_000_000));
    }

    #[test]
    fn unix_to_iso8601_known_timestamps() {
        assert_eq!(unix_to_iso8601(0), "1970-01-01T00:00:00Z");
        // 2023-11-14T22:13:20Z
        assert_eq!(unix_to_iso8601(1_700_000_000), "2023-11-14T22:13:20Z");
        // A leap-day: 2024-02-29T12:00:00Z
        assert_eq!(unix_to_iso8601(1_709_208_000), "2024-02-29T12:00:00Z");
    }

    #[test]
    fn from_config_dev_falls_back_to_throwaway_key() {
        let config = Config::load(|_| None).expect("dev config loads with no secrets");
        let a = MediaAccess::from_config(&config);
        // The fallback still mints/verifies coherently.
        let uuid = Uuid::new_v4();
        let (exp, sig) = parts(&a.mint(&uuid, 1_000).query);
        assert!(a.verify(&uuid, exp, &sig, 1_000));
    }
}
