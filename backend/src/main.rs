//! HealthTech backend — zero-knowledge blob proxy.
//!
//! ADR 0004 (Rust + Axum). This service is deliberately *dumb and auditable*: it stores and
//! returns **opaque ciphertext** indexed by an anonymous UUID. It **never** holds key material
//! and has **no decrypt path**. It depends on `crypto-core` only for shared types and
//! test-vector (KAT) verification — never to decrypt a blob.
//!
//! Storage lives behind the [`store::BlobStore`] seam. The in-memory backing is wired here and in
//! `dev`; the durable MinIO (object) + PostgreSQL 16 (non-identifying metadata) backing lands with
//! sovereign hosting — see `TODO(#9/#8)` in [`store::BlobStore::from_config`] and ADR 0005.
//!
//! Heavy medical media (#23) is offloaded the same way: opaque ciphertext under an anonymous media
//! UUID, read through a short-TTL, per-object, **revocable** capability URL signed with
//! [`config::Config::presigned_url_signing_key`] (ADR 0005/0007). See the [`media`] module.
//!
//! TODO(#23): HTTP range / resumable (tus) uploads for large media on degraded links (else #24).
//! TODO(#8): wire to sovereign in-country hosting (TLS reverse proxy, HA).

mod config;
mod error;
mod media;
mod store;

use axum::{
    body::Bytes,
    extract::{DefaultBodyLimit, Path, RawQuery, State},
    http::{header, HeaderName, HeaderValue, StatusCode},
    response::{IntoResponse, Response},
    routing::{get, post},
    Router,
};
use uuid::Uuid;

use config::Config;
use error::ApiError;
use media::access::{now_unix, unix_to_iso8601, MediaAccess};
use media::{MediaPutOutcome, MediaStore, StoredMedia, MAX_MEDIA_BYTES};
use store::{BlobStore, PutOutcome, StoredBlob, MAX_BLOB_BYTES};

/// Shared handler state: the blob-store seam (#9), the media-store seam (#23), and the media
/// access-URL signer (#23).
#[derive(Clone)]
struct AppState {
    store: BlobStore,
    media: MediaStore,
    access: MediaAccess,
}

/// Build the `ETag` + `X-Blob-Version` headers carrying the optimistic-concurrency version (#22).
///
/// The values are numeric, so the header parses are infallible; the `unwrap_or` fallbacks keep the
/// request path panic-free regardless.
fn version_headers(version: u64) -> [(HeaderName, HeaderValue); 2] {
    version_headers_named(version, "x-blob-version")
}

/// Build the `ETag` + a numeric version header (named per resource: `x-blob-version` for blobs,
/// `x-media-version` for media). Numeric values parse infallibly; the `unwrap_or` fallbacks keep
/// the request path panic-free regardless.
fn version_headers_named(
    version: u64,
    version_header: &'static str,
) -> [(HeaderName, HeaderValue); 2] {
    let raw = HeaderValue::from_str(&version.to_string())
        .unwrap_or_else(|_| HeaderValue::from_static("0"));
    let etag = HeaderValue::from_str(&format!("\"{version}\""))
        .unwrap_or_else(|_| HeaderValue::from_static("\"0\""));
    [
        (header::ETAG, etag),
        (HeaderName::from_static(version_header), raw),
    ]
}

/// Readiness probe. `200 "ok"` when the backing store answers, `503` otherwise.
async fn health(State(state): State<AppState>) -> Response {
    match state.store.health().await {
        Ok(()) => (StatusCode::OK, "ok").into_response(),
        Err(_) => (StatusCode::SERVICE_UNAVAILABLE, "unavailable").into_response(),
    }
}

/// Store an opaque encrypted blob under an anonymous UUID.
///
/// The body is persisted **verbatim**; the server never inspects or decrypts it. An invalid UUID
/// is rejected with `400` by the `Path<Uuid>` extractor; a body over [`MAX_BLOB_BYTES`] is rejected
/// with `413` by the body-limit layer — both before any persistence. Logs carry only
/// non-identifying fields (UUID, ciphertext size, version) — never the body.
async fn put_blob(State(state): State<AppState>, Path(uuid): Path<Uuid>, body: Bytes) -> Response {
    match state.store.put(uuid, body).await {
        Ok(PutOutcome::Created(meta)) => {
            tracing::debug!(%uuid, size = meta.size, version = meta.version, "blob created");
            (StatusCode::CREATED, version_headers(meta.version)).into_response()
        }
        Ok(PutOutcome::Replaced(meta)) => {
            tracing::debug!(%uuid, size = meta.size, version = meta.version, "blob replaced");
            (StatusCode::OK, version_headers(meta.version)).into_response()
        }
        Err(err) => ApiError::from(err).into_response(),
    }
}

/// Return a previously stored opaque blob, or `404` if unknown.
///
/// `200` carries the opaque bytes with `Content-Type: application/octet-stream`, `Content-Length`
/// (both set by the `Bytes` response), and the `ETag`/`X-Blob-Version` headers.
async fn get_blob(State(state): State<AppState>, Path(uuid): Path<Uuid>) -> Response {
    // TODO(#23): support HTTP range requests for resumable ≤500 KB downloads on degraded networks.
    match state.store.get(uuid).await {
        Ok(Some(StoredBlob { bytes, meta })) => {
            (version_headers(meta.version), bytes).into_response()
        }
        Ok(None) => StatusCode::NOT_FOUND.into_response(),
        Err(err) => ApiError::from(err).into_response(),
    }
}

// --- Heavy-media offload (#23) -----------------------------------------------------------------

/// Parse `exp=<u64>&sig=<hex>` from the raw query string of a media capability URL.
///
/// Returns `None` on any failure (missing, empty, or malformed params). The caller maps `None` to
/// `403 Forbidden`, deliberately giving no oracle distinguishing "missing params" from "invalid
/// signature" — both result in the same refusal.
fn parse_access_query(raw: Option<&str>) -> Option<(u64, String)> {
    let raw = raw?;
    let mut exp = None::<u64>;
    let mut sig = None::<String>;
    for kv in raw.split('&') {
        if let Some((k, v)) = kv.split_once('=') {
            match k {
                "exp" => exp = v.parse().ok(),
                "sig" => sig = Some(v.to_owned()),
                _ => {}
            }
        }
    }
    Some((exp?, sig?))
}

/// Store an opaque encrypted media object under an anonymous UUID (`PUT /media/{uuid}`).
///
/// Persisted **verbatim**; the server never inspects or decrypts it. An invalid UUID → `400` (path
/// extractor); a body over [`MAX_MEDIA_BYTES`] → `413` (body-limit layer) before any persistence.
/// Logs carry only non-identifying fields — never the body.
async fn put_media(State(state): State<AppState>, Path(uuid): Path<Uuid>, body: Bytes) -> Response {
    match state.media.put(uuid, body).await {
        Ok(MediaPutOutcome::Created(meta)) => {
            tracing::debug!(%uuid, size = meta.size, version = meta.version, "media created");
            (
                StatusCode::CREATED,
                version_headers_named(meta.version, "x-media-version"),
            )
                .into_response()
        }
        Ok(MediaPutOutcome::Replaced(meta)) => {
            tracing::debug!(%uuid, size = meta.size, version = meta.version, "media replaced");
            (
                StatusCode::OK,
                version_headers_named(meta.version, "x-media-version"),
            )
                .into_response()
        }
        Err(err) => ApiError::from(err).into_response(),
    }
}

/// Mint a short-TTL ephemeral capability URL for `uuid` (`POST /media/{uuid}/access`).
///
/// `404` if the object is unknown (so a URL is never minted for a non-existent / revoked object).
/// The minted signature/URL is a bearer secret — never logged (only the UUID + status are).
async fn post_media_access(State(state): State<AppState>, Path(uuid): Path<Uuid>) -> Response {
    match state.media.exists(uuid).await {
        Ok(true) => {
            let grant = state.access.mint(&uuid, now_unix());
            tracing::debug!(%uuid, expires_at = grant.expires_at_unix, "media access URL minted");
            let url = format!("/media/{uuid}?{}", grant.query);
            let expires_at = unix_to_iso8601(grant.expires_at_unix);
            let json = format!(r#"{{"url":"{url}","expires_at":"{expires_at}"}}"#);
            (
                StatusCode::OK,
                [(
                    header::CONTENT_TYPE,
                    HeaderValue::from_static("application/json"),
                )],
                json,
            )
                .into_response()
        }
        Ok(false) => StatusCode::NOT_FOUND.into_response(),
        Err(err) => ApiError::from(err).into_response(),
    }
}

/// Return a stored opaque media object via a capability URL (`GET /media/{uuid}?exp=…&sig=…`).
///
/// The signature + expiry are verified first: a forged, **expired**, or **missing** capability →
/// `403` (no oracle distinguishing the cases — issue #23 acceptance criterion #2). Only then is
/// the object fetched; an unknown / deleted object → `404`. Decryption is exclusively client-side.
async fn get_media(
    State(state): State<AppState>,
    Path(uuid): Path<Uuid>,
    RawQuery(raw_query): RawQuery,
) -> Response {
    let (exp, sig) = match parse_access_query(raw_query.as_deref()) {
        Some(pair) => pair,
        None => return StatusCode::FORBIDDEN.into_response(),
    };
    if !state.access.verify(&uuid, exp, &sig, now_unix()) {
        return StatusCode::FORBIDDEN.into_response();
    }
    match state.media.get(uuid).await {
        Ok(Some(StoredMedia { bytes, meta })) => (
            version_headers_named(meta.version, "x-media-version"),
            bytes,
        )
            .into_response(),
        Ok(None) => StatusCode::NOT_FOUND.into_response(),
        Err(err) => ApiError::from(err).into_response(),
    }
}

/// Forced per-object revocation / erasure (`DELETE /media/{uuid}`). `204` if it existed, `404`
/// otherwise. After deletion, any outstanding capability URL for this UUID resolves to `404`.
async fn delete_media(State(state): State<AppState>, Path(uuid): Path<Uuid>) -> Response {
    match state.media.delete(uuid).await {
        Ok(true) => StatusCode::NO_CONTENT.into_response(),
        Ok(false) => StatusCode::NOT_FOUND.into_response(),
        Err(err) => ApiError::from(err).into_response(),
    }
}

/// Build the Axum router over a chosen backing. Kept separate from `main` so tests can exercise it
/// in-process. Per-route body-limit layers enforce the distinct ciphertext budgets (→ `413`): the
/// small record budget on `/blob`, the much larger media budget on `/media`.
fn app(store: BlobStore, media: MediaStore, access: MediaAccess) -> Router {
    let blob_routes = Router::new()
        .route("/blob/:uuid", get(get_blob).put(put_blob))
        .layer(DefaultBodyLimit::max(MAX_BLOB_BYTES));
    let media_routes = Router::new()
        .route(
            "/media/:uuid",
            get(get_media).put(put_media).delete(delete_media),
        )
        .route("/media/:uuid/access", post(post_media_access))
        .layer(DefaultBodyLimit::max(MAX_MEDIA_BYTES));
    Router::new()
        .route("/health", get(health))
        .merge(blob_routes)
        .merge(media_routes)
        .with_state(AppState {
            store,
            media,
            access,
        })
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

    // Pick the backing stores for this environment (in-memory in dev; MinIO+Postgres lands with
    // #8). The media access signer takes the injected `PRESIGNED_URL_SIGNING_KEY` (ADR 0005/0007).
    let store = BlobStore::from_config(&config);
    let media = MediaStore::from_config(&config);
    let access = MediaAccess::from_config(&config);

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

    axum::serve(listener, app(store, media, access))
        .await
        .expect("backend server error");
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::body::Body;
    use axum::http::Request;
    use http_body_util::BodyExt;
    use media::access::MEDIA_URL_TTL_SECS;
    use media::MemoryMediaStore;
    use store::{MemoryStore, StoreError};
    use tower::ServiceExt; // for `oneshot`

    /// A fresh router over empty in-memory stores with a fixed test signing key.
    fn test_app() -> Router {
        app(
            BlobStore::Memory(MemoryStore::default()),
            MediaStore::Memory(MemoryMediaStore::default()),
            MediaAccess::new(b"handler-test-signing-key".to_vec(), MEDIA_URL_TTL_SECS),
        )
    }

    /// True if `haystack` contains `needle` as a contiguous sub-slice.
    fn contains_subslice(haystack: &[u8], needle: &[u8]) -> bool {
        !needle.is_empty()
            && haystack.len() >= needle.len()
            && haystack
                .windows(needle.len())
                .any(|window| window == needle)
    }

    #[tokio::test]
    async fn health_returns_ok() {
        let resp = test_app()
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
        let app = test_app();
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
        assert_eq!(
            got.headers().get(header::CONTENT_TYPE).unwrap(),
            "application/octet-stream"
        );
        let body = got.into_body().collect().await.unwrap().to_bytes();
        assert_eq!(&body[..], &ciphertext[..]);
    }

    #[tokio::test]
    async fn get_unknown_blob_is_404() {
        let resp = test_app()
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

    #[tokio::test]
    async fn invalid_uuid_is_400() {
        let resp = test_app()
            .oneshot(
                Request::builder()
                    .uri("/blob/not-a-uuid")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::BAD_REQUEST);
    }

    #[tokio::test]
    async fn rewrite_returns_200_and_increments_version() {
        let app = test_app();
        let uuid = Uuid::new_v4();
        let uri = format!("/blob/{uuid}");

        let first = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(&uri)
                    .body(Body::from(&b"v1"[..]))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(first.status(), StatusCode::CREATED);
        assert_eq!(first.headers().get("x-blob-version").unwrap(), "1");

        let second = app
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(&uri)
                    .body(Body::from(&b"v2-newer"[..]))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(second.status(), StatusCode::OK);
        assert_eq!(second.headers().get("x-blob-version").unwrap(), "2");
    }

    #[tokio::test]
    async fn oversized_body_is_413() {
        let app = test_app();
        let uuid = Uuid::new_v4();
        let too_big = vec![0u8; MAX_BLOB_BYTES + 1];

        let resp = app
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/blob/{uuid}"))
                    .body(Body::from(too_big))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::PAYLOAD_TOO_LARGE);
    }

    #[tokio::test]
    async fn body_at_limit_is_accepted() {
        let app = test_app();
        let uuid = Uuid::new_v4();
        let at_limit = vec![0u8; MAX_BLOB_BYTES];

        let resp = app
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/blob/{uuid}"))
                    .body(Body::from(at_limit))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::CREATED);
    }

    /// Mapping a backing-store failure must yield `503` with no internal detail. Also constructs
    /// `StoreError::Unavailable`, which only the (future) durable backing produces at runtime.
    #[test]
    fn store_unavailable_maps_to_503() {
        let resp = ApiError::from(StoreError::Unavailable).into_response();
        assert_eq!(resp.status(), StatusCode::SERVICE_UNAVAILABLE);
    }

    // --- Zero-knowledge acceptance proofs (issue #9 acceptance criterion) --------------------

    /// Encrypt a known plaintext marker client-side via `crypto-core`, `PUT` the ciphertext, then
    /// read back exactly what the server holds and prove (a) the marker is absent (no plaintext
    /// persisted) and (b) the server cannot decrypt without the key, while the key holder can.
    #[tokio::test]
    async fn no_plaintext_persisted_and_server_cannot_decrypt() {
        use crypto_core::{
            decrypt_record, encrypt_record, generate_master_key, CryptoError, KEY_LEN,
        };

        let key = generate_master_key();
        let marker = b"PLAINTEXT-MARKER blood-type:O- allergy:penicillin";
        let ciphertext = encrypt_record(&key, marker).expect("client-side encrypt");

        let app = test_app();
        let uuid = Uuid::new_v4();
        let uri = format!("/blob/{uuid}");

        let put = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(&uri)
                    .body(Body::from(ciphertext.clone()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(put.status(), StatusCode::CREATED);

        let got = app
            .oneshot(
                Request::builder()
                    .method("GET")
                    .uri(&uri)
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let stored = got.into_body().collect().await.unwrap().to_bytes();

        // (a) No plaintext persisted: the marker never appears in what the server holds.
        assert!(
            !contains_subslice(&stored, marker),
            "plaintext marker leaked into the stored bytes"
        );
        // The server stores the ciphertext verbatim.
        assert_eq!(&stored[..], &ciphertext[..]);

        // (b) Server-cannot-decrypt: from the persisted bytes alone, a wrong key fails to decrypt...
        let wrong_key = [0u8; KEY_LEN];
        assert_eq!(
            decrypt_record(&wrong_key, &stored),
            Err(CryptoError::Decrypt)
        );
        // ...but the key holder (the client) recovers the exact plaintext — only they can read it.
        assert_eq!(decrypt_record(&key, &stored).unwrap(), marker);
    }

    /// Static guard: the request-path modules must never reference a decrypt path. The backend
    /// depends on `crypto-core` for shared types/KAT only — never to decrypt (ADR 0004, G4).
    #[test]
    fn request_path_modules_have_no_decrypt_symbol() {
        for src in [
            include_str!("store.rs"),
            include_str!("store/memory.rs"),
            include_str!("error.rs"),
            include_str!("config.rs"),
            include_str!("media/mod.rs"),
            include_str!("media/memory.rs"),
            include_str!("media/access.rs"),
        ] {
            assert!(
                !src.contains("decrypt_record"),
                "a request-path module references `decrypt_record` — zero-knowledge boundary breach"
            );
        }
    }

    // --- Additional handler coverage ------------------------------------------------------------

    /// An empty body (zero-byte ciphertext) is valid: the server stores verbatim, never inspects.
    #[tokio::test]
    async fn empty_body_put_is_accepted() {
        let resp = test_app()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/blob/{}", Uuid::new_v4()))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::CREATED);
    }

    /// Arbitrary binary payloads (all-zero, all-0xFF, sequential) round-trip byte-for-byte.
    /// This is a lightweight pseudo-property test covering opaque storage of edge-case bytes.
    #[tokio::test]
    async fn binary_opaque_blobs_roundtrip_verbatim() {
        let payloads: &[&[u8]] = &[
            &[0u8; 32],
            &[0xffu8; 32],
            &[
                0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0x0c, 0x0d,
                0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b,
                0x1c, 0x1d, 0x1e, 0x1f,
            ],
        ];
        for &payload in payloads {
            let app = test_app();
            let uuid = Uuid::new_v4();
            let put = app
                .clone()
                .oneshot(
                    Request::builder()
                        .method("PUT")
                        .uri(format!("/blob/{uuid}"))
                        .body(Body::from(payload.to_vec()))
                        .unwrap(),
                )
                .await
                .unwrap();
            assert_eq!(put.status(), StatusCode::CREATED);
            let got = app
                .oneshot(
                    Request::builder()
                        .uri(format!("/blob/{uuid}"))
                        .body(Body::empty())
                        .unwrap(),
                )
                .await
                .unwrap();
            let body = got.into_body().collect().await.unwrap().to_bytes();
            assert_eq!(&body[..], payload, "round-trip failed for payload pattern");
        }
    }

    /// Two distinct UUIDs stored in the same app instance are completely isolated.
    #[tokio::test]
    async fn separate_uuids_are_isolated() {
        let app = test_app();
        let uuid_a = Uuid::new_v4();
        let uuid_b = Uuid::new_v4();
        let blob_a: &[u8] = b"blob-alpha";
        let blob_b: &[u8] = b"blob-beta";

        app.clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/blob/{uuid_a}"))
                    .body(Body::from(blob_a.to_vec()))
                    .unwrap(),
            )
            .await
            .unwrap();
        app.clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/blob/{uuid_b}"))
                    .body(Body::from(blob_b.to_vec()))
                    .unwrap(),
            )
            .await
            .unwrap();

        let got_a = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/blob/{uuid_a}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            &got_a.into_body().collect().await.unwrap().to_bytes()[..],
            blob_a
        );

        let got_b = app
            .oneshot(
                Request::builder()
                    .uri(format!("/blob/{uuid_b}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(
            &got_b.into_body().collect().await.unwrap().to_bytes()[..],
            blob_b
        );
    }

    /// GET response must carry `ETag` and `X-Blob-Version` so clients can detect concurrent writes.
    #[tokio::test]
    async fn get_response_carries_version_headers() {
        let app = test_app();
        let uuid = Uuid::new_v4();
        app.clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/blob/{uuid}"))
                    .body(Body::from(&b"any-ciphertext"[..]))
                    .unwrap(),
            )
            .await
            .unwrap();
        let got = app
            .oneshot(
                Request::builder()
                    .uri(format!("/blob/{uuid}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(got.status(), StatusCode::OK);
        assert_eq!(got.headers().get("x-blob-version").unwrap(), "1");
        assert_eq!(got.headers().get(header::ETAG).unwrap(), "\"1\"");
    }

    /// Three consecutive PUTs to the same UUID must produce version 3.
    #[tokio::test]
    async fn three_writes_reach_version_three() {
        let app = test_app();
        let uuid = Uuid::new_v4();
        let uri = format!("/blob/{uuid}");
        for i in 1u64..=3 {
            let resp = app
                .clone()
                .oneshot(
                    Request::builder()
                        .method("PUT")
                        .uri(&uri)
                        .body(Body::from(format!("payload-{i}").into_bytes()))
                        .unwrap(),
                )
                .await
                .unwrap();
            assert_eq!(
                resp.headers().get("x-blob-version").unwrap(),
                i.to_string().as_str()
            );
        }
    }

    /// Unit test for the `version_headers` helper: exact ETag and X-Blob-Version values.
    #[test]
    fn version_headers_fn_produces_correct_values() {
        let headers = version_headers(7);
        let (ref name0, ref val0) = headers[0];
        let (ref name1, ref val1) = headers[1];
        assert_eq!(name0, &header::ETAG);
        assert_eq!(val0.to_str().unwrap(), "\"7\"");
        assert_eq!(name1.as_str(), "x-blob-version");
        assert_eq!(val1.to_str().unwrap(), "7");

        let zero = version_headers(0);
        assert_eq!(zero[0].1.to_str().unwrap(), "\"0\"");
        assert_eq!(zero[1].1.to_str().unwrap(), "0");
    }

    // --- ZK boundary: tampered ciphertext -------------------------------------------------------

    /// A ciphertext with a flipped tag byte is stored verbatim (server is opaque, no validation).
    /// When the client attempts to decrypt the returned bytes, AES-GCM authentication rejects them.
    /// This proves end-to-end: (a) server does not validate/transform blobs, (b) GCM integrity
    /// protection catches corruption when the key holder decrypts.
    #[tokio::test]
    async fn tampered_ciphertext_stored_verbatim_then_fails_decrypt() {
        use crypto_core::{decrypt_record, encrypt_record, generate_master_key, CryptoError};

        let key = generate_master_key();
        let mut ciphertext =
            encrypt_record(&key, b"sensitive-record").expect("client-side encrypt");
        // Flip one bit in the GCM tag (the last byte of the wire format: nonce || ct || tag).
        let last = ciphertext.len() - 1;
        ciphertext[last] ^= 0x01;

        let app = test_app();
        let uuid = Uuid::new_v4();
        let uri = format!("/blob/{uuid}");

        // Server accepts tampered bytes without any validation.
        let put = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(&uri)
                    .body(Body::from(ciphertext.clone()))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(put.status(), StatusCode::CREATED);

        // Server returns exactly the bytes it received — no transformation.
        let got = app
            .oneshot(Request::builder().uri(&uri).body(Body::empty()).unwrap())
            .await
            .unwrap();
        let stored = got.into_body().collect().await.unwrap().to_bytes();
        assert_eq!(
            &stored[..],
            &ciphertext[..],
            "server must return bytes verbatim"
        );

        // Decryption fails: AES-GCM authentication catches the tampered tag.
        assert_eq!(
            decrypt_record(&key, &stored),
            Err(CryptoError::Decrypt),
            "AES-GCM must reject a blob with a corrupted authentication tag"
        );
    }

    // --- HTTP contract completeness -------------------------------------------------------

    /// A `PUT 200 OK` response (overwrite of an existing blob) must also have an empty body —
    /// the same guarantee as `PUT 201 Created`. The handler has two code paths (Created /
    /// Replaced), and both must return status + headers only, never the ciphertext.
    #[tokio::test]
    async fn put_overwrite_response_body_is_empty() {
        let app = test_app();
        let uuid = Uuid::new_v4();
        let uri = format!("/blob/{uuid}");
        app.clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(&uri)
                    .body(Body::from(&b"v1-ciphertext"[..]))
                    .unwrap(),
            )
            .await
            .unwrap();
        let resp = app
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(&uri)
                    .body(Body::from(&b"v2-ciphertext"[..]))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::OK);
        let body = resp.into_body().collect().await.unwrap().to_bytes();
        assert!(
            body.is_empty(),
            "PUT 200 overwrite response must carry no body"
        );
    }

    /// The `ETag` returned by `PUT` and the `ETag` returned by the subsequent `GET` for the same
    /// UUID must be identical. Clients rely on this for optimistic-concurrency checks (#22).
    #[tokio::test]
    async fn put_and_get_etag_are_consistent() {
        let app = test_app();
        let uuid = Uuid::new_v4();
        let put = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/blob/{uuid}"))
                    .body(Body::from(&b"etag-consistency-test"[..]))
                    .unwrap(),
            )
            .await
            .unwrap();
        let put_etag = put
            .headers()
            .get(header::ETAG)
            .expect("PUT response must carry ETag")
            .clone();

        let got = app
            .oneshot(
                Request::builder()
                    .uri(format!("/blob/{uuid}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let get_etag = got
            .headers()
            .get(header::ETAG)
            .expect("GET response must carry ETag");
        assert_eq!(
            &put_etag, get_etag,
            "ETag from PUT and ETag from GET must match for the same blob version"
        );
    }

    /// Unsupported HTTP methods on `/blob/{uuid}` must return `405 Method Not Allowed`.
    /// Axum enforces this for any method not registered on the route.
    #[tokio::test]
    async fn post_to_blob_is_method_not_allowed() {
        let resp = test_app()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/blob/{}", Uuid::new_v4()))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::METHOD_NOT_ALLOWED);
    }

    /// A successful `PUT 201 Created` response must have an empty body. The server carries only
    /// status + version headers; transmitting the ciphertext back would double the network cost.
    #[tokio::test]
    async fn put_created_response_body_is_empty() {
        let resp = test_app()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/blob/{}", Uuid::new_v4()))
                    .body(Body::from(&b"any-ciphertext"[..]))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::CREATED);
        let body = resp.into_body().collect().await.unwrap().to_bytes();
        assert!(body.is_empty(), "PUT 201 response must carry no body");
    }

    // --- ZK: nonce freshness & wire-format proofs -------------------------------------------------

    /// ZK: encrypting the same plaintext twice under the same key must produce distinct ciphertexts.
    /// AES-256-GCM generates a fresh random 96-bit nonce per call; reusing a nonce would break
    /// confidentiality by revealing the XOR of plaintexts. This test guards against a nonce-reuse
    /// regression in `crypto-core`.
    #[test]
    fn nonce_freshness_same_plaintext_produces_distinct_ciphertexts() {
        use crypto_core::{encrypt_record, generate_master_key};
        let key = generate_master_key();
        let plaintext = b"nonce-freshness-probe";
        let ct1 = encrypt_record(&key, plaintext).unwrap();
        let ct2 = encrypt_record(&key, plaintext).unwrap();
        assert_ne!(
            ct1, ct2,
            "two encryptions of the same plaintext must yield different ciphertexts (random nonce)"
        );
    }

    /// ZK wire-format proof: `len(encrypt_record(key, pt)) == len(pt) + AES_GCM_OVERHEAD`.
    /// This asserts the wire format is exactly `nonce(12) || ciphertext || tag(16)` and nothing
    /// more — no padding, no extra framing. The server therefore cannot infer plaintext structure
    /// from ciphertext size alone (structure is hidden behind the fixed 28-byte overhead).
    #[test]
    fn ciphertext_length_equals_plaintext_plus_aes_gcm_overhead() {
        use crypto_core::{encrypt_record, generate_master_key};
        use store::AES_GCM_OVERHEAD;
        let key = generate_master_key();
        let plaintext = b"wire-format-length-probe-exact";
        let ct = encrypt_record(&key, plaintext).unwrap();
        assert_eq!(
            ct.len(),
            plaintext.len() + AES_GCM_OVERHEAD,
            "ciphertext must be exactly plaintext + nonce(12) + GCM_tag(16) = {AES_GCM_OVERHEAD} bytes overhead"
        );
    }

    // --- Heavy-media offload (#23) -------------------------------------------------------------

    /// PUT media, mint an access URL, then GET it back byte-for-byte — the happy path.
    #[tokio::test]
    async fn media_put_access_get_roundtrips_opaque_bytes() {
        let app = test_app();
        let uuid = Uuid::new_v4();
        let ciphertext = b"\x00\x01opaque-media-ciphertext\xff";

        let put = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/media/{uuid}"))
                    .body(Body::from(&ciphertext[..]))
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(put.status(), StatusCode::CREATED);
        assert_eq!(put.headers().get("x-media-version").unwrap(), "1");

        let access = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/media/{uuid}/access"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(access.status(), StatusCode::OK);
        let body = access.into_body().collect().await.unwrap().to_bytes();
        let body_str = std::str::from_utf8(&body).unwrap();
        let url_val: String = body_str
            .split("\"url\":\"")
            .nth(1)
            .and_then(|s| s.split('"').next())
            .expect("url field in access response")
            .to_owned();
        assert!(url_val.starts_with(&format!("/media/{uuid}?exp=")));
        let expires_str = body_str
            .split("\"expires_at\":\"")
            .nth(1)
            .and_then(|s| s.split('"').next())
            .expect("expires_at field in access response");
        assert!(expires_str.ends_with('Z'));

        let got = app
            .oneshot(
                Request::builder()
                    .uri(url_val.as_str())
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(got.status(), StatusCode::OK);
        let fetched = got.into_body().collect().await.unwrap().to_bytes();
        assert_eq!(&fetched[..], &ciphertext[..]);
    }

    /// Acceptance criterion #2: a GET with an **expired** capability URL is refused with `403`,
    /// even though its signature is valid. Minted here with an expiry far in the past.
    #[tokio::test]
    async fn media_get_with_expired_url_is_403() {
        let app = test_app();
        let uuid = Uuid::new_v4();
        app.clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/media/{uuid}"))
                    .body(Body::from(&b"ciphertext"[..]))
                    .unwrap(),
            )
            .await
            .unwrap();

        // Mint with the same key the test app uses, but anchored in 1970 — long expired by now.
        let signer = MediaAccess::new(b"handler-test-signing-key".to_vec(), MEDIA_URL_TTL_SECS);
        let grant = signer.mint(&uuid, 1_000);
        let url = format!("/media/{uuid}?{}", grant.query);

        let got = app
            .oneshot(Request::builder().uri(&url).body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(got.status(), StatusCode::FORBIDDEN);
    }

    /// A GET with a forged/tampered signature is refused with `403`.
    #[tokio::test]
    async fn media_get_with_forged_signature_is_403() {
        let app = test_app();
        let uuid = Uuid::new_v4();
        app.clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/media/{uuid}"))
                    .body(Body::from(&b"ciphertext"[..]))
                    .unwrap(),
            )
            .await
            .unwrap();
        let got = app
            .oneshot(
                Request::builder()
                    .uri(format!("/media/{uuid}?exp=9999999999&sig=deadbeef"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(got.status(), StatusCode::FORBIDDEN);
    }

    /// `GET /media/{uuid}` without capability query params is refused with `403` — same response
    /// as an expired or forged URL, giving no oracle about what specifically is missing.
    #[tokio::test]
    async fn media_get_without_capability_params_is_403() {
        let resp = test_app()
            .oneshot(
                Request::builder()
                    .uri(format!("/media/{}", Uuid::new_v4()))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::FORBIDDEN);
    }

    /// Minting an access URL for an unknown media object is `404`.
    #[tokio::test]
    async fn media_access_for_unknown_object_is_404() {
        let resp = test_app()
            .oneshot(
                Request::builder()
                    .method("POST")
                    .uri(format!("/media/{}/access", Uuid::new_v4()))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(resp.status(), StatusCode::NOT_FOUND);
    }

    /// Forced per-object revocation: after `DELETE`, an otherwise-valid capability URL → `404`.
    #[tokio::test]
    async fn media_delete_revokes_object() {
        let app = test_app();
        let uuid = Uuid::new_v4();
        app.clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/media/{uuid}"))
                    .body(Body::from(&b"ciphertext"[..]))
                    .unwrap(),
            )
            .await
            .unwrap();
        let signer = MediaAccess::new(b"handler-test-signing-key".to_vec(), MEDIA_URL_TTL_SECS);
        let url = format!("/media/{uuid}?{}", signer.mint(&uuid, now_unix()).query);

        let del = app
            .clone()
            .oneshot(
                Request::builder()
                    .method("DELETE")
                    .uri(format!("/media/{uuid}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(del.status(), StatusCode::NO_CONTENT);

        // The capability is still cryptographically valid, but the object is gone.
        let got = app
            .oneshot(Request::builder().uri(&url).body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(got.status(), StatusCode::NOT_FOUND);
    }

    /// Zero-knowledge for media: a known plaintext marker, encrypted client-side and PUT as media,
    /// never appears in the bytes the server holds; the server cannot decrypt it.
    #[tokio::test]
    async fn media_no_plaintext_persisted_and_server_cannot_decrypt() {
        use crypto_core::{decrypt_record, encrypt_record, generate_master_key, CryptoError};

        let content_key = generate_master_key();
        let marker = b"PLAINTEXT-MARKER radiograph chest-pa patient:awa";
        let ciphertext = encrypt_record(&content_key, marker).expect("client-side encrypt");

        let app = test_app();
        let uuid = Uuid::new_v4();
        app.clone()
            .oneshot(
                Request::builder()
                    .method("PUT")
                    .uri(format!("/media/{uuid}"))
                    .body(Body::from(ciphertext.clone()))
                    .unwrap(),
            )
            .await
            .unwrap();

        let signer = MediaAccess::new(b"handler-test-signing-key".to_vec(), MEDIA_URL_TTL_SECS);
        let url = format!("/media/{uuid}?{}", signer.mint(&uuid, now_unix()).query);
        let got = app
            .oneshot(Request::builder().uri(&url).body(Body::empty()).unwrap())
            .await
            .unwrap();
        let stored = got.into_body().collect().await.unwrap().to_bytes();

        assert!(
            !contains_subslice(&stored, marker),
            "plaintext marker leaked into the stored media bytes"
        );
        assert_eq!(&stored[..], &ciphertext[..], "media stored verbatim");
        // Server holds no content key: a wrong key fails, the client's key recovers the marker.
        assert!(matches!(
            decrypt_record(&[0u8; 32], &stored),
            Err(CryptoError::Decrypt)
        ));
        assert_eq!(decrypt_record(&content_key, &stored).unwrap(), marker);
    }
}
