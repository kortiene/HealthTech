# backend

Zero-knowledge **blob proxy** for HealthTech.

## Purpose

A deliberately dumb, auditable HTTP service that stores and returns **opaque encrypted blobs**
indexed by an anonymous UUID. The server **never holds key material and has no decrypt path** —
clients encrypt with `crypto-core` (AES-256-GCM) before any transit, and the backend only ever
sees ciphertext.

## HTTP API (issue #9)

| Method | Path | Body | Responses |
| --- | --- | --- | --- |
| `GET` | `/health` | — | `200 "ok"` (readiness) · `503` if the backing store is down |
| `PUT` | `/blob/{uuid}` | opaque ciphertext (`application/octet-stream`) | `201 Created` (new) · `200 OK` (overwrite) · `400` invalid UUID · `413` over the size budget · `503` store down |
| `GET` | `/blob/{uuid}` | — | `200` (ciphertext + `Content-Type: application/octet-stream`, `Content-Length`, `ETag`, `X-Blob-Version`) · `400` invalid UUID · `404` unknown · `503` store down |

## Heavy-media API (issue #23)

Radiographs / scans are too large for the ≤ 500 KB record and never live on the patient phone.
They are encrypted **client-side** under a per-media content key, offloaded here as **opaque
ciphertext** keyed by an anonymous media UUID, and read through a **short-TTL, per-object,
revocable** capability URL.

| Method | Path | Body | Responses |
| --- | --- | --- | --- |
| `PUT` | `/media/{uuid}` | opaque ciphertext (`application/octet-stream`) | `201 Created` · `200 OK` (overwrite) · `400` invalid UUID · `413` over `media::MAX_MEDIA_BYTES` · `503` store down |
| `POST` | `/media/{uuid}/access` | — | `200 { "url", "expires_at" }` (ephemeral URL minted) · `404` unknown object · `503` |
| `GET` | `/media/{uuid}?exp=…&sig=…` | — | `200` (ciphertext + `ETag`, `X-Media-Version`) · `400` missing/garbage params · `403` invalid **or expired** URL · `404` unknown/deleted · `503` |
| `DELETE` | `/media/{uuid}` | — | `204` (revoked/erased) · `404` · `503` |

- **Ephemeral URL (acceptance #2).** `POST …/access` mints `/media/{uuid}?exp=<unix>&sig=<hmac>`,
  signed (HMAC-SHA256 over `uuid:exp`) with `PRESIGNED_URL_SIGNING_KEY` and valid for
  `media::access::MEDIA_URL_TTL_SECS` (5 min). `GET` verifies the signature **and** expiry: a forged
  or expired URL is `403` (uniform — no oracle distinguishing the two). The signature binds the
  exact UUID (per-object scope). **Revocation:** by expiry (time), by rotating the signing key
  (global), or by `DELETE /media/{uuid}` (per-object) — after which an outstanding URL resolves to
  `404`. The minted URL is a **bearer secret**: never logged, never persisted client-side.
- **Distinct size budget.** `media::MAX_MEDIA_BYTES` (25 MiB) is far above the record blob budget; a
  larger body is rejected with `413` before buffering. The text record stays ≤ 500 KB (media is
  off-record).
- **Zero-knowledge.** The server holds no per-media content key and has **no decrypt path**; the key
  lives inside the patient's encrypted record (the client-side media descriptor). The `media_metadata`
  Postgres row (durable backing, lands with #8) holds **only** non-identifying columns (anonymous
  UUID, ciphertext size, version, timestamps) — no PII, no plaintext, no key, no MIME/hash.

- **`{uuid}`** is an **anonymous index** (UUID v4), never derived from PII. A malformed UUID is
  rejected with `400` by the path extractor.
- **Size budget.** The plaintext record is **≤ 500 KB** (PRD §4); the server enforces this as a
  ciphertext ceiling of `500 KB + AES-GCM overhead (12-byte nonce + 16-byte tag) + a small margin`
  (`store::MAX_BLOB_BYTES`). A larger body is rejected with `413` before it is buffered or stored.
- **Versioning.** Overwriting a UUID increments a monotonic version, surfaced as `ETag` and
  `X-Blob-Version` for optimistic concurrency / offline sync (#22).
- **Errors leak nothing.** A store failure maps to `503` with only a generic reason phrase — no DSN,
  no backend detail. The request path never panics.

## Storage backing

Storage lives behind the `store::BlobStore` seam:

- **`MemoryStore`** — process memory; the default in `dev` and in every test.
- **`ObjectMeta` (MinIO + PostgreSQL 16)** — the durable in-country backing for `staging`/`prod`
  (ADR 0005): the opaque ciphertext as a MinIO object (SSE-at-rest, defence in depth *under* the
  client encryption) plus a `blob_metadata` Postgres row holding **only non-identifying** columns
  (anonymous UUID, ciphertext size, version, timestamps, public KDF params — **no PII, no
  plaintext, no keys**). It is **not wired yet**: the real MinIO/Postgres services are provisioned
  by sovereign hosting (#8), so this variant + its SQL migration land with that bring-up. The seam,
  size budget, metadata shape, error mapping, and zero-knowledge proofs already exist so it is a
  drop-in — see `TODO(#9/#8)` in `src/store.rs`.

Heavy media (#23) uses a **sibling** seam, `media::MediaStore` (a **dedicated** bucket + size
budget), with the same posture: `MemoryMediaStore` in dev/test, durable MinIO + Postgres
`media_metadata` landing with #8. The ephemeral capability-URL signer (`media::access::MediaAccess`)
is wired now. `TODO(#23)` still leaves HTTP range / resumable (tus) transfers for large media on
degraded links (else #24); `TODO(#8)` wires the sovereign in-country hosting / TLS reverse proxy.

## Zero-knowledge guarantees

The server **never holds key material and has no decrypt path**. Clients encrypt with `crypto-core`
(AES-256-GCM) before any transit; the backend only ever sees and stores **opaque bytes**. The
dependency on `crypto-core` is limited to **shared types/constants and test-vector (KAT)
verification** — never to decrypt. This is proven by tests (`cargo test -p backend`):

- **no-plaintext-persisted** — a known plaintext marker, encrypted client-side, never appears in the
  bytes the server holds;
- **server-cannot-decrypt** — from the persisted bytes alone, decryption fails without the patient
  key and succeeds only for the key holder;
- **no-decrypt-symbol** — a static guard asserts the request-path modules never reference
  `decrypt_record`.

## Configuration (injected from the secrets vault)

Operational config is read from the **environment** by [`src/config.rs`](./src/config.rs)
([ADR 0007](../docs/adr/0007-secrets-and-environments.md), issue #4). Values are injected by the
IaC from the SOPS/age vault — **never** from a committed plaintext file. The config type **fails
fast** on a missing required secret and **redacts** every secret field in `Debug`/`Display`, so a
config dump or a `tracing` line can never leak a password or key. For local dev, copy
[`../.env.example`](../.env.example) to `.env` and run `just dev-up`.

| Variable | Required | Secret | Default | Consumer |
| --- | --- | --- | --- | --- |
| `APP_ENV` | no | no | `dev` | selects dev / staging / prod |
| `BIND_ADDR` | no | no | `0.0.0.0:8080` | TCP listener |
| `DATABASE_URL` | staging/prod | **yes** | — | PostgreSQL DSN (#9) |
| `MINIO_ENDPOINT` | staging/prod | no | — | MinIO address (#9) |
| `MINIO_ACCESS_KEY` | staging/prod | **yes** | — | MinIO access key (#9/#23) |
| `MINIO_SECRET_KEY` | staging/prod | **yes** | — | MinIO secret key (#9/#23) |
| `PRESIGNED_URL_SIGNING_KEY` | staging/prod | **yes** | — | signs presigned media URLs (#23) |

In `dev` the storage secrets are **optional** (throwaway local stack, storage not wired until #9);
in `staging`/`prod` a missing required secret aborts startup. **No patient key material** is ever
read here — this is the zero-knowledge operational boundary (ADR 0004/0007).

## ADR

- Implements [ADR 0004 — Backend: Rust + Axum](../docs/adr/0004-backend-rust-axum.md).
- Consumes the shared crate per [ADR 0003 — Shared crypto core](../docs/adr/0003-shared-crypto-core-rust.md).
- Storage/hosting per [ADR 0005 — Storage & sovereign hosting](../docs/adr/0005-storage-and-sovereign-hosting.md).
- Config/secrets/environments per [ADR 0007 — Secrets & environments](../docs/adr/0007-secrets-and-environments.md).

This crate is a member of the root cargo workspace (alongside `crypto-core`).

## Build & test

```sh
# Build
cargo build -p backend

# Test
cargo test -p backend
```

Run locally: `cargo run -p backend` (defaults to `APP_ENV=dev`, binds `0.0.0.0:8080`; override
with `BIND_ADDR`). See **Configuration** above for the injected env/secret contract.
