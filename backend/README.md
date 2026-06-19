# backend

Zero-knowledge **blob proxy** for HealthTech.

## Purpose

A deliberately dumb, auditable HTTP service that stores and returns **opaque encrypted blobs**
indexed by an anonymous UUID. The server **never holds key material and has no decrypt path** —
clients encrypt with `crypto-core` (AES-256-GCM) before any transit, and the backend only ever
sees ciphertext.

Current scaffold (issue #9, structure only):

- `GET  /health` → `200 "ok"` (liveness)
- `PUT  /blob/{uuid}` → stores opaque bytes (`201 Created`)
- `GET  /blob/{uuid}` → returns the stored opaque bytes (`200`) or `404`

Storage is an in-memory map. `TODO(#9)` replaces it with MinIO + PostgreSQL; `TODO(#23)` adds
presigned ephemeral media URLs and HTTP range / resumable (tus) transfers; `TODO(#8)` wires the
sovereign in-country hosting / TLS reverse proxy.

The dependency on `crypto-core` is for **shared types and test-vector (KAT) verification only** —
not to decrypt.

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
