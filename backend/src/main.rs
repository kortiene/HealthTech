//! HealthTech backend — zero-knowledge blob proxy.
//!
//! ADR 0004 (Rust + Axum). This service is deliberately *dumb and auditable*: it stores and
//! returns **opaque ciphertext** indexed by an anonymous UUID. It **never** holds key material
//! and has **no decrypt path**. It depends on `crypto-core` only for shared types and
//! test-vector (KAT) verification — never to decrypt a blob.
//!
//! TODO(#9): replace the in-memory `BlobStore` with MinIO (object store) + PostgreSQL 16
//!           (non-identifying metadata: anonymous UUID, ciphertext size/version, timestamps,
//!           KDF params). See ADR 0005. Credentials come from [`config::Config`] (ADR 0007).
//! TODO(#23): presigned short-TTL ephemeral media URLs + HTTP range / resumable (tus) uploads.
//!           The signing key comes from [`config::Config::presigned_url_signing_key`] (ADR 0007).
//! TODO(#8): wire to sovereign in-country hosting (TLS reverse proxy, HA).

mod config;

use std::collections::HashMap;
use std::sync::{Arc, RwLock};

use config::Config;

use axum::{
    body::Bytes,
    extract::{Path, State},
    http::StatusCode,
    routing::get,
    Router,
};
use uuid::Uuid;

/// In-memory placeholder for the encrypted-blob store.
///
/// The map values are **opaque bytes**: the server cannot and must not interpret them.
/// TODO(#9): back this with MinIO + Postgres instead of process memory.
#[derive(Clone, Default)]
struct AppState {
    blobs: Arc<RwLock<HashMap<Uuid, Bytes>>>,
}

/// Liveness probe. Returns `200 "ok"`.
async fn health() -> &'static str {
    "ok"
}

/// Store an opaque encrypted blob under an anonymous UUID.
///
/// The body is persisted verbatim; the server never inspects or decrypts it.
async fn put_blob(
    State(state): State<AppState>,
    Path(uuid): Path<Uuid>,
    body: Bytes,
) -> StatusCode {
    // TODO(#9): stream to MinIO + record non-identifying metadata in Postgres (ADR 0005).
    state
        .blobs
        .write()
        .expect("blob store poisoned")
        .insert(uuid, body);
    StatusCode::CREATED
}

/// Return a previously stored opaque blob, or `404` if unknown.
async fn get_blob(
    State(state): State<AppState>,
    Path(uuid): Path<Uuid>,
) -> Result<Bytes, StatusCode> {
    // TODO(#23): support HTTP range requests for resumable ≤500 KB downloads on degraded networks.
    state
        .blobs
        .read()
        .expect("blob store poisoned")
        .get(&uuid)
        .cloned()
        .ok_or(StatusCode::NOT_FOUND)
}

/// Build the Axum router. Kept separate from `main` so tests can exercise it in-process.
fn app() -> Router {
    Router::new()
        .route("/health", get(health))
        .route("/blob/:uuid", get(get_blob).put(put_blob))
        .with_state(AppState::default())
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env().unwrap_or_else(|_| "info".into()),
        )
        .init();

    // Operational config is injected from the secrets vault via the environment (ADR 0007).
    // Fail fast on a missing required secret; never log a secret value (every secret field in
    // `Config` redacts in Debug/Display, and we only ever log `app_env` and the bind address).
    let config = Config::from_env().unwrap_or_else(|err| {
        tracing::error!(%err, "invalid backend configuration");
        std::process::exit(1);
    });

    // TODO(#8): TLS termination handled by the in-country reverse proxy (ADR 0005).
    let addr = config.bind_addr.clone();
    let listener = tokio::net::TcpListener::bind(&addr)
        .await
        .expect("failed to bind backend listener");
    tracing::info!(
        env = %config.app_env,
        %addr,
        injected_secrets = ?config.injected_storage_secrets(),
        "HealthTech zero-knowledge blob proxy listening"
    );

    axum::serve(listener, app())
        .await
        .expect("backend server error");
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::Request;
    use http_body_util::BodyExt;
    use tower::ServiceExt; // for `oneshot`

    #[tokio::test]
    async fn health_returns_ok() {
        let resp = app()
            .oneshot(
                Request::builder()
                    .uri("/health")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        let body = resp.into_body().collect().await.unwrap().to_bytes();
        assert_eq!(&body[..], b"ok");
    }

    #[tokio::test]
    async fn put_then_get_roundtrips_opaque_bytes() {
        let app = app();
        let uuid = Uuid::new_v4();
        let ciphertext = b"\x00\x01opaque-ciphertext\xff";

        let put = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/blob/{uuid}"))
                    .body(Body::from(&ciphertext[..]))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(put.status(), StatusCode::CREATED);

        let got = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri(format!("/blob/{uuid}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(got.status(), StatusCode::OK);
        let body = got.into_body().collect().await.unwrap().to_bytes();
        assert_eq!(&body[..], &ciphertext[..]);
    }

    #[tokio::test]
    async fn get_unknown_blob_is_404() {
        let resp = app()
            .oneshot(
                Request::builder()
                    .uri(format!("/blob/{}", Uuid::new_v4()))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
    }
}
