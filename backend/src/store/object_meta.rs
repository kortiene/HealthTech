//! Durable blob store backed by MinIO (S3-compatible object storage) + PostgreSQL 16 (#103).
//!
//! This is the `staging`/`prod` backing for [`super::BlobStore`]; `dev` and all tests continue to
//! use [`super::MemoryStore`]. Both implement the same four async operations so the swap is a
//! drop-in at the enum dispatch level.
//!
//! **Zero-knowledge invariant (ADR 0004)**: blobs are stored verbatim (opaque ciphertext). This
//! module never inspects, parses, or decrypts bytes. No plaintext, key material, or PII crosses
//! the module boundary — only anonymous UUIDs, ciphertext sizes, and version counters.
//!
//! ## Consistency model
//!
//! `put` checks for an existing Postgres row first (to compute `Created` vs `Replaced`), writes
//! to MinIO, then upserts the Postgres row. If MinIO succeeds but Postgres fails, the Postgres row
//! is stale (or absent) and a subsequent `get` will return `None` — the blob is treated as not yet
//! committed. The S3 object is orphaned until the next successful `put` for the same UUID
//! overwrites it and re-creates the metadata. For a low-write medical-record proxy this is fine.

use std::sync::Arc;

use aws_credential_types::Credentials;
use aws_sdk_s3::config::Region;
use aws_sdk_s3::primitives::ByteStream;
use aws_sdk_s3::{Client, Config as S3Config};
use axum::body::Bytes;
use sqlx::postgres::PgPoolOptions;
use sqlx::{PgPool, Row};
use uuid::Uuid;

use super::{BlobMeta, PutOutcome, StoreError, StoredBlob};
use crate::config::Config;

const BLOB_BUCKET: &str = "healthtech-blobs";
const POOL_MAX_CONNECTIONS: u32 = 5;

/// Durable MinIO + PostgreSQL blob store for `staging`/`prod`.
///
/// `Clone` is cheap: the `aws-sdk-s3` client and `PgPool` are both `Arc`-backed internally.
#[derive(Clone)]
pub struct ObjectMetaStore {
    s3: Arc<Client>,
    pool: PgPool,
}

impl ObjectMetaStore {
    /// Connect to MinIO and PostgreSQL, run schema migration, ensure the S3 bucket exists.
    ///
    /// Returns `StoreError::Unavailable` if any required config is absent or the backing services
    /// are unreachable.
    pub async fn new(config: &Config) -> Result<Self, StoreError> {
        let minio_endpoint = config
            .minio_endpoint
            .as_deref()
            .ok_or(StoreError::Unavailable)?;
        let access_key = config
            .minio_access_key
            .as_ref()
            .ok_or(StoreError::Unavailable)?;
        let secret_key = config
            .minio_secret_key
            .as_ref()
            .ok_or(StoreError::Unavailable)?;
        let database_url = config
            .database_url
            .as_ref()
            .ok_or(StoreError::Unavailable)?;

        // Build the MinIO S3-compatible client. force_path_style is required for MinIO.
        let creds = Credentials::new(
            access_key.expose(),
            secret_key.expose(),
            None,
            None,
            "healthtech",
        );
        let s3_config = S3Config::builder()
            .endpoint_url(minio_endpoint)
            .credentials_provider(creds)
            .region(Region::new("us-east-1"))
            .force_path_style(true)
            .behavior_version_latest()
            .build();
        let s3 = Arc::new(Client::from_conf(s3_config));

        ensure_bucket(&s3).await?;

        // Build the Postgres connection pool.
        let pool = PgPoolOptions::new()
            .max_connections(POOL_MAX_CONNECTIONS)
            .connect(database_url.expose())
            .await
            .map_err(|e| {
                tracing::error!(%e, "failed to connect to postgres");
                StoreError::Unavailable
            })?;

        // Run idempotent schema migration (CREATE TABLE IF NOT EXISTS).
        sqlx::query(include_str!("../../migrations/001_blob_metadata.sql"))
            .execute(&pool)
            .await
            .map_err(|e| {
                tracing::error!(%e, "schema migration failed");
                StoreError::Unavailable
            })?;

        tracing::info!("ObjectMetaStore ready (MinIO + Postgres)");
        Ok(Self { s3, pool })
    }

    /// Store `bytes` under `uuid`; returns [`PutOutcome::Created`] or [`PutOutcome::Replaced`].
    pub async fn put(&self, uuid: Uuid, bytes: Bytes) -> Result<PutOutcome, StoreError> {
        let size = bytes.len();

        // Check if UUID exists in Postgres to determine Created vs Replaced.
        let existing: Option<i64> =
            sqlx::query("SELECT version FROM blob_metadata WHERE uuid = $1")
                .bind(uuid)
                .fetch_optional(&self.pool)
                .await
                .map_err(|_| StoreError::Unavailable)?
                .map(|r| r.get::<i64, _>(0));

        // Write opaque ciphertext to MinIO (verbatim, zero-knowledge).
        self.s3
            .put_object()
            .bucket(BLOB_BUCKET)
            .key(uuid.to_string())
            .body(ByteStream::from(bytes.to_vec()))
            .send()
            .await
            .map_err(|e| {
                tracing::error!(%e, %uuid, "MinIO put_object failed");
                StoreError::Unavailable
            })?;

        // Upsert non-identifying metadata in Postgres.
        let (version, replaced) = if let Some(prev) = existing {
            let new_version = prev as u64 + 1;
            sqlx::query(
                "UPDATE blob_metadata SET size = $2, version = $3, updated_at = NOW() WHERE uuid = $1",
            )
            .bind(uuid)
            .bind(size as i64)
            .bind(new_version as i64)
            .execute(&self.pool)
            .await
            .map_err(|_| StoreError::Unavailable)?;
            (new_version, true)
        } else {
            sqlx::query("INSERT INTO blob_metadata (uuid, size, version) VALUES ($1, $2, 1)")
                .bind(uuid)
                .bind(size as i64)
                .execute(&self.pool)
                .await
                .map_err(|_| StoreError::Unavailable)?;
            (1u64, false)
        };

        let meta = BlobMeta { size, version };
        Ok(if replaced {
            PutOutcome::Replaced(meta)
        } else {
            PutOutcome::Created(meta)
        })
    }

    /// Fetch the blob under `uuid`, or `None` if unknown.
    pub async fn get(&self, uuid: Uuid) -> Result<Option<StoredBlob>, StoreError> {
        // Metadata absence means the blob is not committed (or was deleted).
        let row = sqlx::query("SELECT size, version FROM blob_metadata WHERE uuid = $1")
            .bind(uuid)
            .fetch_optional(&self.pool)
            .await
            .map_err(|_| StoreError::Unavailable)?;

        let (size, version) = match row {
            None => return Ok(None),
            Some(r) => (r.get::<i64, _>(0), r.get::<i64, _>(1)),
        };

        // Fetch opaque ciphertext from MinIO.
        use aws_sdk_s3::error::SdkError;

        let result = self
            .s3
            .get_object()
            .bucket(BLOB_BUCKET)
            .key(uuid.to_string())
            .send()
            .await;

        match result {
            Err(SdkError::ServiceError(ref se)) if se.err().is_no_such_key() => Ok(None),
            Err(e) => {
                tracing::error!(%e, %uuid, "MinIO get_object failed");
                Err(StoreError::Unavailable)
            }
            Ok(obj) => {
                let data = obj
                    .body
                    .collect()
                    .await
                    .map_err(|_| StoreError::Unavailable)?;
                Ok(Some(StoredBlob {
                    bytes: Bytes::copy_from_slice(&data.into_bytes()),
                    meta: BlobMeta {
                        size: size as usize,
                        version: version as u64,
                    },
                }))
            }
        }
    }

    /// Delete the blob under `uuid`. Returns `true` if it existed.
    pub async fn delete(&self, uuid: Uuid) -> Result<bool, StoreError> {
        // S3 delete is idempotent: deleting a non-existent object is not an error.
        self.s3
            .delete_object()
            .bucket(BLOB_BUCKET)
            .key(uuid.to_string())
            .send()
            .await
            .map_err(|e| {
                tracing::error!(%e, %uuid, "MinIO delete_object failed");
                StoreError::Unavailable
            })?;

        let result = sqlx::query("DELETE FROM blob_metadata WHERE uuid = $1")
            .bind(uuid)
            .execute(&self.pool)
            .await
            .map_err(|_| StoreError::Unavailable)?;

        Ok(result.rows_affected() > 0)
    }

    /// Readiness probe: pings both Postgres and MinIO.
    pub async fn health(&self) -> Result<(), StoreError> {
        sqlx::query("SELECT 1")
            .execute(&self.pool)
            .await
            .map_err(|_| StoreError::Unavailable)?;

        self.s3
            .head_bucket()
            .bucket(BLOB_BUCKET)
            .send()
            .await
            .map_err(|_| StoreError::Unavailable)?;

        Ok(())
    }
}

/// Ensure the blob bucket exists. Head-bucket first (O(1), no side-effects); create only if missing.
async fn ensure_bucket(s3: &Client) -> Result<(), StoreError> {
    if s3.head_bucket().bucket(BLOB_BUCKET).send().await.is_ok() {
        return Ok(());
    }
    s3.create_bucket()
        .bucket(BLOB_BUCKET)
        .send()
        .await
        .map(|_| ())
        .map_err(|e| {
            tracing::error!(%e, bucket = BLOB_BUCKET, "failed to create MinIO bucket");
            StoreError::Unavailable
        })
}
