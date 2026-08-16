//! Durable media store backed by MinIO (S3-compatible object storage) + PostgreSQL 16 (#23/#8).
//!
//! This is the `staging`/`prod` backing for [`super::MediaStore`]; `dev` and all tests continue to
//! use [`super::MemoryMediaStore`]. Both implement the same five async operations so the swap is a
//! drop-in at the enum dispatch level — identical architecture to [`crate::store::ObjectMetaStore`]
//! but on a **dedicated** `healthtech-media` bucket and `media_metadata` table.
//!
//! **Zero-knowledge invariant (ADR 0004)**: media blobs are stored verbatim (opaque ciphertext).
//! This module never inspects, parses, or decrypts bytes. No plaintext, content key, MIME type,
//! or PII crosses the module boundary — only anonymous UUIDs, ciphertext sizes, and versions.
//!
//! ## Consistency model
//!
//! Identical to the blob store: `put` checks Postgres first (Created vs Replaced), writes to
//! MinIO, then upserts Postgres. MinIO success + Postgres failure → row absent → `get` returns
//! `None` (orphaned S3 object). Acceptable for a low-write medical proxy.

use std::sync::Arc;

use aws_credential_types::Credentials;
use aws_sdk_s3::config::Region;
use aws_sdk_s3::primitives::ByteStream;
use aws_sdk_s3::{Client, Config as S3Config};
use axum::body::Bytes;
use sqlx::postgres::PgPoolOptions;
use sqlx::{PgPool, Row};
use uuid::Uuid;

use super::{MediaMeta, MediaPutOutcome, StoredMedia};
use crate::config::Config;
use crate::store::StoreError;

const MEDIA_BUCKET: &str = "healthtech-media";
const POOL_MAX_CONNECTIONS: u32 = 5;

/// Durable MinIO + PostgreSQL media store for `staging`/`prod`.
///
/// `Clone` is cheap: the `aws-sdk-s3` client and `PgPool` are both `Arc`-backed internally.
#[derive(Clone)]
pub struct ObjectMetaMediaStore {
    s3: Arc<Client>,
    pool: PgPool,
}

impl ObjectMetaMediaStore {
    /// Connect to MinIO and PostgreSQL, run schema migration, ensure the S3 bucket exists.
    ///
    /// Returns `StoreError::Unavailable` if any required config is absent or the backing services
    /// are unreachable. Called from `MediaStore::from_config` in staging/prod — fail-fast so a
    /// misconfigured deploy never starts half-blind.
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

        let pool = PgPoolOptions::new()
            .max_connections(POOL_MAX_CONNECTIONS)
            .connect(database_url.expose())
            .await
            .map_err(|e| {
                tracing::error!(%e, "failed to connect to postgres (media store)");
                StoreError::Unavailable
            })?;

        sqlx::query(include_str!("../../migrations/002_media_metadata.sql"))
            .execute(&pool)
            .await
            .map_err(|e| {
                tracing::error!(%e, "media schema migration failed");
                StoreError::Unavailable
            })?;

        tracing::info!("ObjectMetaMediaStore ready (MinIO + Postgres)");
        Ok(Self { s3, pool })
    }

    /// Store `bytes` (opaque ciphertext) under `uuid`; returns Created or Replaced.
    pub async fn put(&self, uuid: Uuid, bytes: Bytes) -> Result<MediaPutOutcome, StoreError> {
        let size = bytes.len();

        let existing: Option<i64> =
            sqlx::query("SELECT version FROM media_metadata WHERE uuid = $1")
                .bind(uuid)
                .fetch_optional(&self.pool)
                .await
                .map_err(|_| StoreError::Unavailable)?
                .map(|r| r.get::<i64, _>(0));

        self.s3
            .put_object()
            .bucket(MEDIA_BUCKET)
            .key(uuid.to_string())
            .body(ByteStream::from(bytes.to_vec()))
            .send()
            .await
            .map_err(|e| {
                tracing::error!(%e, %uuid, "MinIO put_object failed (media)");
                StoreError::Unavailable
            })?;

        let (version, replaced) = if let Some(prev) = existing {
            let new_version = prev as u64 + 1;
            sqlx::query(
                "UPDATE media_metadata SET size = $2, version = $3, updated_at = NOW() WHERE uuid = $1",
            )
            .bind(uuid)
            .bind(size as i64)
            .bind(new_version as i64)
            .execute(&self.pool)
            .await
            .map_err(|_| StoreError::Unavailable)?;
            (new_version, true)
        } else {
            sqlx::query("INSERT INTO media_metadata (uuid, size, version) VALUES ($1, $2, 1)")
                .bind(uuid)
                .bind(size as i64)
                .execute(&self.pool)
                .await
                .map_err(|_| StoreError::Unavailable)?;
            (1u64, false)
        };

        let meta = MediaMeta { size, version };
        Ok(if replaced {
            MediaPutOutcome::Replaced(meta)
        } else {
            MediaPutOutcome::Created(meta)
        })
    }

    /// Fetch the media object under `uuid`, or `None` if unknown.
    pub async fn get(&self, uuid: Uuid) -> Result<Option<StoredMedia>, StoreError> {
        let row = sqlx::query("SELECT size, version FROM media_metadata WHERE uuid = $1")
            .bind(uuid)
            .fetch_optional(&self.pool)
            .await
            .map_err(|_| StoreError::Unavailable)?;

        let (size, version) = match row {
            None => return Ok(None),
            Some(r) => (r.get::<i64, _>(0), r.get::<i64, _>(1)),
        };

        use aws_sdk_s3::error::SdkError;

        let result = self
            .s3
            .get_object()
            .bucket(MEDIA_BUCKET)
            .key(uuid.to_string())
            .send()
            .await;

        match result {
            Err(SdkError::ServiceError(ref se)) if se.err().is_no_such_key() => Ok(None),
            Err(e) => {
                tracing::error!(%e, %uuid, "MinIO get_object failed (media)");
                Err(StoreError::Unavailable)
            }
            Ok(obj) => {
                let data = obj
                    .body
                    .collect()
                    .await
                    .map_err(|_| StoreError::Unavailable)?;
                Ok(Some(StoredMedia {
                    bytes: Bytes::copy_from_slice(&data.into_bytes()),
                    meta: MediaMeta {
                        size: size as usize,
                        version: version as u64,
                    },
                }))
            }
        }
    }

    /// Whether `uuid` is present, without fetching its (potentially large) bytes.
    pub async fn exists(&self, uuid: Uuid) -> Result<bool, StoreError> {
        let row = sqlx::query("SELECT 1 FROM media_metadata WHERE uuid = $1")
            .bind(uuid)
            .fetch_optional(&self.pool)
            .await
            .map_err(|_| StoreError::Unavailable)?;
        Ok(row.is_some())
    }

    /// Delete the media object under `uuid`. Returns `true` if it existed.
    pub async fn delete(&self, uuid: Uuid) -> Result<bool, StoreError> {
        self.s3
            .delete_object()
            .bucket(MEDIA_BUCKET)
            .key(uuid.to_string())
            .send()
            .await
            .map_err(|e| {
                tracing::error!(%e, %uuid, "MinIO delete_object failed (media)");
                StoreError::Unavailable
            })?;

        let result = sqlx::query("DELETE FROM media_metadata WHERE uuid = $1")
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
            .bucket(MEDIA_BUCKET)
            .send()
            .await
            .map_err(|_| StoreError::Unavailable)?;

        Ok(())
    }
}

async fn ensure_bucket(s3: &Client) -> Result<(), StoreError> {
    if s3.head_bucket().bucket(MEDIA_BUCKET).send().await.is_ok() {
        return Ok(());
    }
    s3.create_bucket()
        .bucket(MEDIA_BUCKET)
        .send()
        .await
        .map(|_| ())
        .map_err(|e| {
            tracing::error!(%e, bucket = MEDIA_BUCKET, "failed to create MinIO bucket");
            StoreError::Unavailable
        })
}
