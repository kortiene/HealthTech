//! Storage abstraction for opaque encrypted blobs (issue #9).
//!
//! The backend is a **zero-knowledge blob proxy**: it persists and returns ciphertext keyed by an
//! anonymous UUID and **never** inspects, decrypts, or holds key material (ADR 0004). This module
//! defines the [`BlobStore`] seam decoupling the HTTP handlers from the backing store, plus the
//! non-identifying metadata recorded alongside each blob.
//!
//! Concrete enum dispatch is used instead of a `dyn`/`async_trait` object on purpose: it keeps the
//! request-path futures `Send` (so they compose with `axum::serve`) **without** pulling in an extra
//! dependency, while still giving us a single switch point for a future backing.
//!
//! - [`MemoryStore`] — process-memory backing; default in `dev` and in every test.
//! - **`ObjectMeta` (MinIO + PostgreSQL)** — durable in-country backing for `staging`/`prod`. It is
//!   **not wired yet**: the real MinIO/Postgres services are provisioned by sovereign hosting (#8,
//!   ADR 0005), so the variant lands together with that bring-up. The seam, size budget, metadata
//!   shape, error mapping, and zero-knowledge proofs all exist now so it is a drop-in. See
//!   `TODO(#9/#8)` in [`BlobStore::from_config`].

mod memory;

pub use memory::MemoryStore;

use std::error::Error;
use std::fmt;

use axum::body::Bytes;
use uuid::Uuid;

use crate::config::{AppEnv, Config};

/// Plaintext budget per medical record: **≤ 500 KB** (PRD §4 / BACKLOG #15, #24). Heavy medical
/// images never live in the record — only an ephemeral URL does (#23) — so this stays small for
/// instant download/decrypt on Edge/3G.
pub const MAX_PLAINTEXT_BYTES: usize = 500 * 1024;

/// AES-256-GCM wire-format overhead added by `crypto-core`: a prepended 12-byte nonce plus the
/// 16-byte GCM tag (`nonce || ciphertext || tag`, ADR 0003). The 16 is the fixed GCM tag length;
/// `crypto-core` does not export it as a constant, so it is named here.
pub const AES_GCM_OVERHEAD: usize = crypto_core::NONCE_LEN + 16;

/// Documented slack above the strict ciphertext size, reserved for a future record-framing / AAD
/// channel (`crypto-core` `TODO(#11)`). Kept deliberately small.
pub const BLOB_SIZE_MARGIN: usize = 1024;

/// Hard ceiling enforced on the `PUT /blob/{uuid}` body. A larger ciphertext is rejected with
/// `413 Payload Too Large` before it is ever buffered or persisted.
pub const MAX_BLOB_BYTES: usize = MAX_PLAINTEXT_BYTES + AES_GCM_OVERHEAD + BLOB_SIZE_MARGIN;

/// Non-identifying metadata recorded for a stored blob.
///
/// **By design this holds no PII, no plaintext, and no key material** — only the ciphertext size
/// and an optimistic-concurrency version (ADR 0005). It maps directly onto the future
/// `blob_metadata` Postgres row.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BlobMeta {
    /// Size of the stored ciphertext in bytes.
    pub size: usize,
    /// Monotonic version, incremented on each overwrite of the same UUID (optimistic concurrency;
    /// surfaced as `ETag`/`X-Blob-Version` for #22's offline sync).
    pub version: u64,
}

/// A blob read back from the store: the opaque ciphertext plus its [`BlobMeta`].
#[derive(Clone)]
pub struct StoredBlob {
    /// Opaque ciphertext bytes — never interpreted by the server.
    pub bytes: Bytes,
    /// Non-identifying metadata.
    pub meta: BlobMeta,
}

/// Outcome of a `put`, so the handler can answer `201 Created` vs `200 OK`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum PutOutcome {
    /// The UUID was new.
    Created(BlobMeta),
    /// An existing blob was overwritten; `version` was incremented.
    Replaced(BlobMeta),
}

/// An error surfaced by a backing store. Mapped to an HTTP status with **no internal detail**
/// (no DSN, no backend message) by [`crate::error::ApiError`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StoreError {
    /// The backing store is unreachable (e.g. MinIO/Postgres down). Mapped to `503`.
    ///
    /// Only the durable `ObjectMeta` backing produces this at runtime; the in-memory store never
    /// fails. `allow(dead_code)` until that backing lands with #8 so the not-yet-constructed
    /// variant (whose HTTP mapping is already tested) does not trip `clippy -D warnings`.
    #[allow(dead_code)]
    Unavailable,
}

impl fmt::Display for StoreError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            StoreError::Unavailable => f.write_str("blob store unavailable"),
        }
    }
}

impl Error for StoreError {}

/// The blob-store seam. Construction picks the backing; the handlers only ever see this type.
#[derive(Clone)]
pub enum BlobStore {
    /// Process-memory backing (dev/test).
    Memory(MemoryStore),
}

impl BlobStore {
    /// Select the backing for the running environment.
    ///
    /// `dev` uses the in-memory store. `staging`/`prod` will use the durable MinIO + PostgreSQL
    /// backing once it is wired — see the `TODO(#9/#8)` below; until then they fall back to the
    /// in-memory store and log a loud warning, since the real services do not exist before #8.
    pub fn from_config(config: &Config) -> Self {
        match config.app_env {
            AppEnv::Dev => BlobStore::Memory(MemoryStore::default()),
            AppEnv::Staging | AppEnv::Prod => {
                // TODO(#9/#8): construct the durable `ObjectMeta` backing (MinIO put/get of the
                // opaque ciphertext with SSE-at-rest + a Postgres `blob_metadata` pool) from
                // `config`'s injected storage secrets, once sovereign hosting (#8, ADR 0005) is
                // provisioned. The non-identifying metadata shape and size budget are already
                // defined above so this is a drop-in.
                tracing::warn!(
                    env = %config.app_env,
                    "durable MinIO+Postgres blob backing is not wired yet (tracked under #9/#8); \
                     falling back to the in-memory store"
                );
                BlobStore::Memory(MemoryStore::default())
            }
        }
    }

    /// Store `bytes` (opaque ciphertext) under `uuid`, returning whether it was created or replaced.
    pub async fn put(&self, uuid: Uuid, bytes: Bytes) -> Result<PutOutcome, StoreError> {
        match self {
            BlobStore::Memory(s) => s.put(uuid, bytes).await,
        }
    }

    /// Fetch the blob stored under `uuid`, or `None` if unknown.
    pub async fn get(&self, uuid: Uuid) -> Result<Option<StoredBlob>, StoreError> {
        match self {
            BlobStore::Memory(s) => s.get(uuid).await,
        }
    }

    /// Readiness probe for the backing store.
    pub async fn health(&self) -> Result<(), StoreError> {
        match self {
            BlobStore::Memory(s) => s.health().await,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{
        BlobMeta, BlobStore, PutOutcome, StoreError, AES_GCM_OVERHEAD, BLOB_SIZE_MARGIN,
        MAX_BLOB_BYTES, MAX_PLAINTEXT_BYTES,
    };

    #[test]
    fn max_plaintext_bytes_is_500_kib() {
        assert_eq!(MAX_PLAINTEXT_BYTES, 500 * 1024);
    }

    #[test]
    fn aes_gcm_overhead_matches_wire_format_spec() {
        // wire format: nonce (12 bytes) || ciphertext || GCM tag (16 bytes) — ADR 0003.
        assert_eq!(AES_GCM_OVERHEAD, crypto_core::NONCE_LEN + 16);
        assert_eq!(AES_GCM_OVERHEAD, 28);
    }

    #[test]
    fn max_blob_bytes_equals_sum_of_its_components() {
        assert_eq!(
            MAX_BLOB_BYTES,
            MAX_PLAINTEXT_BYTES + AES_GCM_OVERHEAD + BLOB_SIZE_MARGIN
        );
    }

    #[test]
    fn max_blob_bytes_exceeds_plaintext_budget() {
        const { assert!(MAX_BLOB_BYTES > MAX_PLAINTEXT_BYTES) };
    }

    #[test]
    fn blob_meta_equality_and_debug() {
        let a = BlobMeta {
            size: 32,
            version: 1,
        };
        let b = BlobMeta {
            size: 32,
            version: 1,
        };
        let c = BlobMeta {
            size: 32,
            version: 2,
        };
        assert_eq!(a, b);
        assert_ne!(a, c);
        let _ = format!("{a:?}");
    }

    #[test]
    fn store_error_display_is_non_empty_and_opaque() {
        let msg = StoreError::Unavailable.to_string();
        assert!(!msg.is_empty());
        // Generic text only — no DSN, IP, or port number.
        assert!(
            !msg.contains("://"),
            "display must not contain a connection string"
        );
        assert!(
            !msg.contains("127."),
            "display must not contain an IP address"
        );
    }

    #[test]
    fn put_outcome_variants_are_not_equal() {
        let meta = BlobMeta {
            size: 10,
            version: 1,
        };
        assert_eq!(
            PutOutcome::Created(meta.clone()),
            PutOutcome::Created(meta.clone())
        );
        assert_ne!(
            PutOutcome::Created(meta.clone()),
            PutOutcome::Replaced(meta.clone())
        );
        assert_eq!(
            PutOutcome::Replaced(meta.clone()),
            PutOutcome::Replaced(meta)
        );
    }

    /// `BlobStore::from_config` with a dev config (no env vars) must construct a working
    /// memory-backed store. This exercises the factory branch without touching the real env.
    #[test]
    fn from_config_dev_returns_functional_memory_store() {
        use crate::config::Config;
        let config = Config::load(|_| None).expect("dev config must load with no env vars");
        let store = BlobStore::from_config(&config);
        // Health check must succeed: the in-memory backing is always reachable.
        let rt = tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap();
        rt.block_on(store.health())
            .expect("memory store must always report healthy");
    }

    /// `StoreError::Unavailable` is a leaf error with no underlying cause — no internal
    /// detail to chain. This verifies the `std::error::Error::source()` contract so that
    /// error-reporting infrastructure never exposes an unexpected inner error to callers.
    #[test]
    fn store_error_source_is_none() {
        use std::error::Error;
        assert!(
            StoreError::Unavailable.source().is_none(),
            "StoreError must have no source (leaf error, no internal detail to leak)"
        );
    }

    /// `BLOB_SIZE_MARGIN` must be positive: a zero margin would leave no slack above the strict
    /// plaintext + AES-GCM overhead ceiling, which would be fragile against future wire-format
    /// additions (e.g. AAD channel — `TODO(#11)`).
    #[test]
    fn blob_size_margin_is_positive() {
        const {
            assert!(
                BLOB_SIZE_MARGIN > 0,
                "BLOB_SIZE_MARGIN must leave headroom above the strict overhead"
            )
        };
    }
}
