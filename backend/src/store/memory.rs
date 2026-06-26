//! In-memory [`BlobStore`](super::BlobStore) backing.
//!
//! The default in `dev` and in every test. Values are **opaque bytes** the server cannot and must
//! not interpret. Replaces the previous `AppState` map and removes its `.expect("blob store
//! poisoned")` panics: a poisoned lock is recovered via `into_inner` so a prior panic can never
//! take the whole store down on a later request.

use std::collections::HashMap;
use std::sync::{Arc, RwLock};

use axum::body::Bytes;
use uuid::Uuid;

use super::{BlobMeta, PutOutcome, StoreError, StoredBlob};

/// One stored ciphertext plus its current version.
struct Entry {
    bytes: Bytes,
    version: u64,
}

/// Process-memory blob store. Cheap to `clone` (shared `Arc`).
#[derive(Clone, Default)]
pub struct MemoryStore {
    inner: Arc<RwLock<HashMap<Uuid, Entry>>>,
}

impl MemoryStore {
    /// Insert or overwrite the blob under `uuid`. New UUID → version 1 ([`PutOutcome::Created`]);
    /// existing UUID → version incremented ([`PutOutcome::Replaced`]).
    pub async fn put(&self, uuid: Uuid, bytes: Bytes) -> Result<PutOutcome, StoreError> {
        let size = bytes.len();
        // Recover a poisoned lock instead of panicking (no `.expect()` on the request path).
        let mut map = self.inner.write().unwrap_or_else(|e| e.into_inner());
        let (version, replaced) = match map.get(&uuid) {
            Some(prev) => (prev.version + 1, true),
            None => (1, false),
        };
        map.insert(uuid, Entry { bytes, version });
        let meta = BlobMeta { size, version };
        Ok(if replaced {
            PutOutcome::Replaced(meta)
        } else {
            PutOutcome::Created(meta)
        })
    }

    /// Return the blob under `uuid`, or `None` if unknown.
    pub async fn get(&self, uuid: Uuid) -> Result<Option<StoredBlob>, StoreError> {
        let map = self.inner.read().unwrap_or_else(|e| e.into_inner());
        Ok(map.get(&uuid).map(|e| StoredBlob {
            bytes: e.bytes.clone(),
            meta: BlobMeta {
                size: e.bytes.len(),
                version: e.version,
            },
        }))
    }

    /// Always ready: process memory is reachable and lock poisoning is recovered on access, so the
    /// in-memory backing never reports unavailable.
    pub async fn health(&self) -> Result<(), StoreError> {
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::MemoryStore;
    use crate::store::{BlobMeta, PutOutcome};
    use axum::body::Bytes;
    use uuid::Uuid;

    fn b(data: &[u8]) -> Bytes {
        Bytes::copy_from_slice(data)
    }

    #[tokio::test]
    async fn put_new_uuid_creates_version_one() {
        let store = MemoryStore::default();
        let uuid = Uuid::new_v4();
        let outcome = store.put(uuid, b(b"opaque")).await.unwrap();
        assert_eq!(
            outcome,
            PutOutcome::Created(BlobMeta { size: 6, version: 1 })
        );
    }

    #[tokio::test]
    async fn put_existing_uuid_replaces_and_increments_version() {
        let store = MemoryStore::default();
        let uuid = Uuid::new_v4();
        store.put(uuid, b(b"v1")).await.unwrap();
        let outcome = store.put(uuid, b(b"v2-longer")).await.unwrap();
        assert_eq!(
            outcome,
            PutOutcome::Replaced(BlobMeta { size: 9, version: 2 })
        );
    }

    #[tokio::test]
    async fn get_returns_none_for_unknown_uuid() {
        let store = MemoryStore::default();
        assert!(store.get(Uuid::new_v4()).await.unwrap().is_none());
    }

    #[tokio::test]
    async fn get_returns_exact_bytes_and_correct_meta() {
        let store = MemoryStore::default();
        let uuid = Uuid::new_v4();
        let payload = b(b"\x00\xff\xaasecret\xff\x00");
        store.put(uuid, payload.clone()).await.unwrap();
        let got = store.get(uuid).await.unwrap().unwrap();
        assert_eq!(got.bytes, payload);
        assert_eq!(got.meta.size, payload.len());
        assert_eq!(got.meta.version, 1);
    }

    #[tokio::test]
    async fn get_after_replace_returns_latest_bytes_and_version() {
        let store = MemoryStore::default();
        let uuid = Uuid::new_v4();
        store.put(uuid, b(b"original")).await.unwrap();
        store.put(uuid, b(b"updated-value")).await.unwrap();
        let got = store.get(uuid).await.unwrap().unwrap();
        assert_eq!(&got.bytes[..], b"updated-value");
        assert_eq!(got.meta.version, 2);
    }

    #[tokio::test]
    async fn version_increments_monotonically_across_multiple_rewrites() {
        let store = MemoryStore::default();
        let uuid = Uuid::new_v4();
        for i in 1u64..=5 {
            let outcome = store.put(uuid, b(&[i as u8])).await.unwrap();
            let version = match outcome {
                PutOutcome::Created(m) | PutOutcome::Replaced(m) => m.version,
            };
            assert_eq!(version, i, "expected version {i} on write #{i}");
        }
    }

    #[tokio::test]
    async fn different_uuids_hold_independent_blobs_and_versions() {
        let store = MemoryStore::default();
        let uuid_a = Uuid::new_v4();
        let uuid_b = Uuid::new_v4();
        store.put(uuid_a, b(b"blob-a")).await.unwrap();
        store.put(uuid_b, b(b"blob-b")).await.unwrap();
        let a = store.get(uuid_a).await.unwrap().unwrap();
        let bv = store.get(uuid_b).await.unwrap().unwrap();
        assert_eq!(&a.bytes[..], b"blob-a");
        assert_eq!(&bv.bytes[..], b"blob-b");
        // Each UUID has its own independent version counter.
        assert_eq!(a.meta.version, 1);
        assert_eq!(bv.meta.version, 1);
    }

    #[tokio::test]
    async fn rewriting_one_uuid_does_not_affect_another() {
        let store = MemoryStore::default();
        let uuid_a = Uuid::new_v4();
        let uuid_b = Uuid::new_v4();
        store.put(uuid_a, b(b"a-v1")).await.unwrap();
        store.put(uuid_b, b(b"b-v1")).await.unwrap();
        // Overwrite A twice.
        store.put(uuid_a, b(b"a-v2")).await.unwrap();
        store.put(uuid_a, b(b"a-v3")).await.unwrap();
        // B must remain at version 1 with its original bytes.
        let bv = store.get(uuid_b).await.unwrap().unwrap();
        assert_eq!(&bv.bytes[..], b"b-v1");
        assert_eq!(bv.meta.version, 1);
    }

    #[tokio::test]
    async fn empty_body_is_stored_and_retrieved() {
        let store = MemoryStore::default();
        let uuid = Uuid::new_v4();
        let outcome = store.put(uuid, Bytes::new()).await.unwrap();
        assert_eq!(
            outcome,
            PutOutcome::Created(BlobMeta { size: 0, version: 1 })
        );
        let got = store.get(uuid).await.unwrap().unwrap();
        assert_eq!(got.bytes.len(), 0);
        assert_eq!(got.meta.size, 0);
    }

    #[tokio::test]
    async fn all_zero_bytes_stored_verbatim() {
        let store = MemoryStore::default();
        let uuid = Uuid::new_v4();
        let payload = b(&[0u8; 64]);
        store.put(uuid, payload.clone()).await.unwrap();
        assert_eq!(store.get(uuid).await.unwrap().unwrap().bytes, payload);
    }

    #[tokio::test]
    async fn all_ff_bytes_stored_verbatim() {
        let store = MemoryStore::default();
        let uuid = Uuid::new_v4();
        let payload = b(&[0xffu8; 64]);
        store.put(uuid, payload.clone()).await.unwrap();
        assert_eq!(store.get(uuid).await.unwrap().unwrap().bytes, payload);
    }

    #[tokio::test]
    async fn size_meta_reflects_actual_byte_count() {
        let store = MemoryStore::default();
        let uuid = Uuid::new_v4();
        let outcome = store.put(uuid, b(&[0u8; 42])).await.unwrap();
        let meta = match outcome {
            PutOutcome::Created(m) | PutOutcome::Replaced(m) => m,
        };
        assert_eq!(meta.size, 42);
    }

    #[tokio::test]
    async fn health_always_returns_ok() {
        assert!(MemoryStore::default().health().await.is_ok());
    }

    /// After overwriting a blob with a **different-sized** payload, `get` must return the new
    /// bytes and a `meta.size` reflecting the replacement blob, not the original.
    #[tokio::test]
    async fn size_meta_updates_correctly_after_overwrite() {
        let store = MemoryStore::default();
        let uuid = Uuid::new_v4();
        store.put(uuid, b(&[0u8; 100])).await.unwrap();
        store.put(uuid, b(&[1u8; 40])).await.unwrap();
        let got = store.get(uuid).await.unwrap().unwrap();
        assert_eq!(got.bytes.len(), 40, "GET must return the latest blob bytes");
        assert_eq!(
            got.meta.size,
            40,
            "meta.size must reflect the replacement blob size"
        );
        assert_eq!(got.meta.version, 2);
    }

    /// Concurrent writes from multiple Tokio tasks to the same UUID must produce a complete,
    /// gap-free monotonic version sequence. Each write must observe a unique version; no two
    /// writes may claim the same version, and no version in `1..=N` may be skipped.
    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    async fn concurrent_puts_to_same_uuid_produce_monotonic_versions() {
        let store = MemoryStore::default();
        let uuid = Uuid::new_v4();
        let n: usize = 8;

        let handles: Vec<tokio::task::JoinHandle<PutOutcome>> = (0..n)
            .map(|i| {
                let s = store.clone(); // cheap Arc clone — all tasks share the same store
                tokio::spawn(async move {
                    s.put(
                        uuid,
                        Bytes::from(format!("concurrent-payload-{i}").into_bytes()),
                    )
                    .await
                    .unwrap()
                })
            })
            .collect();

        let mut versions = Vec::with_capacity(n);
        for handle in handles {
            let outcome = handle.await.expect("spawned task must not panic");
            let v = match outcome {
                PutOutcome::Created(m) | PutOutcome::Replaced(m) => m.version,
            };
            versions.push(v);
        }
        versions.sort_unstable();
        assert_eq!(
            versions,
            (1..=n as u64).collect::<Vec<_>>(),
            "concurrent writes must produce a complete, gap-free version sequence 1..={n}"
        );
    }
}
