//! Heavy-media store + ephemeral access (issue #23).
//!
//! Radiographs / scans are too large for the ≤ 500 KB text record and must never live on the
//! patient phone (PRD §4, BACKLOG #23). They are encrypted **client-side** (AES-256-GCM,
//! `crypto-core`) under a per-media content key, then offloaded here as **opaque ciphertext**
//! keyed by an anonymous media UUID. Like the blob proxy (#9), this server **never** holds a
//! content key and has **no decrypt path** — it stores and returns ciphertext, nothing more.
//!
//! Two concerns live under this module:
//!
//! - **[`MediaStore`]** — the storage seam (a sibling of [`crate::store::BlobStore`], but a
//!   **separate** bucket + size budget): `put` / `get` / `delete` / `health` of opaque bytes.
//! - **[`access::MediaAccess`]** — minting + verifying **short-TTL, per-object, revocable**
//!   capability URLs signed with `PRESIGNED_URL_SIGNING_KEY` (ADR 0005). An expired URL is
//!   refused — issue #23 acceptance criterion #2.
//!
//! The durable MinIO (object) + PostgreSQL (`media_metadata`, non-identifying only) backing lands
//! with sovereign hosting (#8), exactly as for the blob store — see `TODO(#8)` in
//! [`MediaStore::from_config`]. The seam, the distinct size budget, the metadata shape, the error
//! mapping (reusing [`crate::store::StoreError`]) and the zero-knowledge proofs all exist now so it
//! is a drop-in.

pub mod access;
mod memory;

pub use memory::MemoryMediaStore;

use axum::body::Bytes;
use uuid::Uuid;

use crate::config::{AppEnv, Config};
use crate::store::StoreError;

/// Hard ceiling enforced on the `PUT /media/{uuid}` body. Distinct from (and far above) the
/// record blob budget [`crate::store::MAX_BLOB_BYTES`]: a radiograph is megabytes, not kilobytes.
/// Still **bounded** — a body larger than this is rejected with `413 Payload Too Large` before it
/// is buffered or persisted, so the path stays sustainable on an Edge/3G link (#24 tunes it). The
/// budget covers the AES-256-GCM ciphertext (plaintext + the 28-byte `crypto-core` overhead).
pub const MAX_MEDIA_BYTES: usize = 25 * 1024 * 1024;

/// Non-identifying metadata recorded for a stored media object.
///
/// **By design this holds no PII, no plaintext, and no key material** — only the ciphertext size
/// and an optimistic-concurrency version. The per-media content key, MIME type and integrity hash
/// all live **inside the client's encrypted record** (the media descriptor), never here. This maps
/// directly onto the future `media_metadata` Postgres row.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MediaMeta {
    /// Size of the stored ciphertext in bytes.
    pub size: usize,
    /// Monotonic version, incremented on each overwrite of the same UUID.
    pub version: u64,
}

/// A media object read back from the store: the opaque ciphertext plus its [`MediaMeta`].
#[derive(Clone)]
pub struct StoredMedia {
    /// Opaque ciphertext bytes — never interpreted by the server.
    pub bytes: Bytes,
    /// Non-identifying metadata.
    pub meta: MediaMeta,
}

/// Outcome of a `put`, so the handler can answer `201 Created` vs `200 OK`.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum MediaPutOutcome {
    /// The UUID was new.
    Created(MediaMeta),
    /// An existing object was overwritten; `version` was incremented.
    Replaced(MediaMeta),
}

/// The media-store seam. Construction picks the backing; the handlers only ever see this type.
#[derive(Clone)]
pub enum MediaStore {
    /// Process-memory backing (dev/test).
    Memory(MemoryMediaStore),
}

impl MediaStore {
    /// Select the backing for the running environment.
    ///
    /// `dev` uses the in-memory store. `staging`/`prod` will use the durable MinIO + PostgreSQL
    /// backing once it is wired — see the `TODO(#8)` below; until then they fall back to the
    /// in-memory store and log a loud warning, since the real services do not exist before #8
    /// (same posture as [`crate::store::BlobStore::from_config`]).
    pub fn from_config(config: &Config) -> Self {
        match config.app_env {
            AppEnv::Dev => MediaStore::Memory(MemoryMediaStore::default()),
            AppEnv::Staging | AppEnv::Prod => {
                // TODO(#8): construct the durable object backing (MinIO put/get/remove of the
                // opaque ciphertext in a DEDICATED media bucket with SSE-at-rest, plus a Postgres
                // `media_metadata` pool holding non-identifying columns only) from `config`'s
                // injected storage secrets, once sovereign hosting (#8, ADR 0005) is provisioned.
                tracing::warn!(
                    env = %config.app_env,
                    "durable MinIO+Postgres media backing is not wired yet (tracked under #23/#8); \
                     falling back to the in-memory store"
                );
                MediaStore::Memory(MemoryMediaStore::default())
            }
        }
    }

    /// Store `bytes` (opaque ciphertext) under `uuid`, returning whether it was created or replaced.
    pub async fn put(&self, uuid: Uuid, bytes: Bytes) -> Result<MediaPutOutcome, StoreError> {
        match self {
            MediaStore::Memory(s) => s.put(uuid, bytes).await,
        }
    }

    /// Fetch the media object stored under `uuid`, or `None` if unknown.
    pub async fn get(&self, uuid: Uuid) -> Result<Option<StoredMedia>, StoreError> {
        match self {
            MediaStore::Memory(s) => s.get(uuid).await,
        }
    }

    /// Whether an object exists under `uuid`, without copying its (potentially large) bytes.
    /// Used by `POST /media/{uuid}/access` to refuse minting for an unknown object (`404`).
    pub async fn exists(&self, uuid: Uuid) -> Result<bool, StoreError> {
        match self {
            MediaStore::Memory(s) => s.exists(uuid).await,
        }
    }

    /// Delete the object under `uuid` (forced per-object revocation / erasure). Returns whether it
    /// existed, so the handler can answer `204 No Content` vs `404 Not Found`.
    pub async fn delete(&self, uuid: Uuid) -> Result<bool, StoreError> {
        match self {
            MediaStore::Memory(s) => s.delete(uuid).await,
        }
    }

    /// Readiness probe for the backing store.
    pub async fn health(&self) -> Result<(), StoreError> {
        match self {
            MediaStore::Memory(s) => s.health().await,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{MediaMeta, MediaPutOutcome, MediaStore, MAX_MEDIA_BYTES};
    use crate::config::Config;

    #[test]
    fn max_media_bytes_far_exceeds_record_blob_budget() {
        // The media budget must dwarf the ≤500 KB record ciphertext budget: a scan is megabytes.
        assert!(MAX_MEDIA_BYTES > crate::store::MAX_BLOB_BYTES);
        assert_eq!(MAX_MEDIA_BYTES, 25 * 1024 * 1024);
    }

    #[test]
    fn media_meta_equality_and_debug() {
        let a = MediaMeta {
            size: 2_300_000,
            version: 1,
        };
        let b = MediaMeta {
            size: 2_300_000,
            version: 1,
        };
        let c = MediaMeta {
            size: 2_300_000,
            version: 2,
        };
        assert_eq!(a, b);
        assert_ne!(a, c);
        let _ = format!("{a:?}");
    }

    #[test]
    fn put_outcome_variants_are_distinct() {
        let meta = MediaMeta {
            size: 10,
            version: 1,
        };
        assert_eq!(
            MediaPutOutcome::Created(meta.clone()),
            MediaPutOutcome::Created(meta.clone())
        );
        assert_ne!(
            MediaPutOutcome::Created(meta.clone()),
            MediaPutOutcome::Replaced(meta)
        );
    }

    /// `from_config` with a dev config (no env vars) must construct a working memory-backed store.
    #[test]
    fn from_config_dev_returns_functional_memory_store() {
        let config = Config::load(|_| None).expect("dev config must load with no env vars");
        let store = MediaStore::from_config(&config);
        let rt = tokio::runtime::Builder::new_current_thread()
            .build()
            .unwrap();
        rt.block_on(store.health())
            .expect("memory media store must always report healthy");
    }
}
