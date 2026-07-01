//! In-memory [`MediaStore`](super::MediaStore) backing.
//!
//! The default in `dev` and in every test. Values are **opaque ciphertext** the server cannot and
//! must not interpret. Mirrors [`crate::store::MemoryStore`]: a poisoned lock is recovered via
//! `into_inner` so a prior panic can never take the whole store down on a later request.

use std::collections::HashMap;
use std::sync::{Arc, RwLock};

use axum::body::Bytes;
use uuid::Uuid;

use super::{MediaMeta, MediaPutOutcome, StoredMedia};
use crate::store::StoreError;

/// One stored ciphertext plus its current version.
struct Entry {
    bytes: Bytes,
    version: u64,
}

/// Process-memory media store. Cheap to `clone` (shared `Arc`).
#[derive(Clone, Default)]
pub struct MemoryMediaStore {
    inner: Arc<RwLock<HashMap<Uuid, Entry>>>,
}

impl MemoryMediaStore {
    /// Insert or overwrite the object under `uuid`. New UUID → version 1
    /// ([`MediaPutOutcome::Created`]); existing UUID → version incremented
    /// ([`MediaPutOutcome::Replaced`]).
    pub async fn put(&self, uuid: Uuid, bytes: Bytes) -> Result<MediaPutOutcome, StoreError> {
        let size = bytes.len();
        let mut map = self.inner.write().unwrap_or_else(|e| e.into_inner());
        let (version, replaced) = match map.get(&uuid) {
            Some(prev) => (prev.version + 1, true),
            None => (1, false),
        };
        map.insert(uuid, Entry { bytes, version });
        let meta = MediaMeta { size, version };
        Ok(if replaced {
            MediaPutOutcome::Replaced(meta)
        } else {
            MediaPutOutcome::Created(meta)
        })
    }

    /// Return the object under `uuid`, or `None` if unknown.
    pub async fn get(&self, uuid: Uuid) -> Result<Option<StoredMedia>, StoreError> {
        let map = self.inner.read().unwrap_or_else(|e| e.into_inner());
        Ok(map.get(&uuid).map(|e| StoredMedia {
            bytes: e.bytes.clone(),
            meta: MediaMeta {
                size: e.bytes.len(),
                version: e.version,
            },
        }))
    }

    /// Whether `uuid` is present, without cloning its bytes.
    pub async fn exists(&self, uuid: Uuid) -> Result<bool, StoreError> {
        let map = self.inner.read().unwrap_or_else(|e| e.into_inner());
        Ok(map.contains_key(&uuid))
    }

    /// Remove the object under `uuid`, returning whether it existed.
    pub async fn delete(&self, uuid: Uuid) -> Result<bool, StoreError> {
        let mut map = self.inner.write().unwrap_or_else(|e| e.into_inner());
        Ok(map.remove(&uuid).is_some())
    }

    /// Always ready: process memory is reachable and lock poisoning is recovered on access.
    pub async fn health(&self) -> Result<(), StoreError> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::MemoryMediaStore;
    use crate::media::{MediaMeta, MediaPutOutcome};
    use axum::body::Bytes;
    use uuid::Uuid;

    fn b(data: &[u8]) -> Bytes {
        Bytes::copy_from_slice(data)
    }

    #[tokio::test]
    async fn put_new_uuid_creates_version_one() {
        let store = MemoryMediaStore::default();
        let uuid = Uuid::new_v4();
        let outcome = store.put(uuid, b(b"opaque-media")).await.unwrap();
        assert_eq!(
            outcome,
            MediaPutOutcome::Created(MediaMeta {
                size: 12,
                version: 1
            })
        );
    }

    #[tokio::test]
    async fn put_get_roundtrips_opaque_bytes() {
        let store = MemoryMediaStore::default();
        let uuid = Uuid::new_v4();
        let payload = b(b"\x00\xff\xaaopaque-ciphertext\xff\x00");
        store.put(uuid, payload.clone()).await.unwrap();
        let got = store.get(uuid).await.unwrap().unwrap();
        assert_eq!(got.bytes, payload);
        assert_eq!(got.meta.size, payload.len());
        assert_eq!(got.meta.version, 1);
    }

    #[tokio::test]
    async fn get_unknown_uuid_is_none() {
        let store = MemoryMediaStore::default();
        assert!(store.get(Uuid::new_v4()).await.unwrap().is_none());
    }

    #[tokio::test]
    async fn rewrite_increments_version() {
        let store = MemoryMediaStore::default();
        let uuid = Uuid::new_v4();
        store.put(uuid, b(b"v1")).await.unwrap();
        let outcome = store.put(uuid, b(b"v2-longer")).await.unwrap();
        assert_eq!(
            outcome,
            MediaPutOutcome::Replaced(MediaMeta {
                size: 9,
                version: 2
            })
        );
    }

    #[tokio::test]
    async fn exists_reflects_presence() {
        let store = MemoryMediaStore::default();
        let uuid = Uuid::new_v4();
        assert!(!store.exists(uuid).await.unwrap());
        store.put(uuid, b(b"x")).await.unwrap();
        assert!(store.exists(uuid).await.unwrap());
    }

    #[tokio::test]
    async fn delete_removes_then_reports_absent() {
        let store = MemoryMediaStore::default();
        let uuid = Uuid::new_v4();
        store.put(uuid, b(b"to-revoke")).await.unwrap();
        assert!(store.delete(uuid).await.unwrap(), "first delete sees the object");
        assert!(
            !store.delete(uuid).await.unwrap(),
            "second delete reports it gone"
        );
        assert!(store.get(uuid).await.unwrap().is_none());
    }

    #[tokio::test]
    async fn health_always_ok() {
        assert!(MemoryMediaStore::default().health().await.is_ok());
    }
}
