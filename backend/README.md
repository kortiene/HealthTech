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

## ADR

- Implements [ADR 0004 — Backend: Rust + Axum](../docs/adr/0004-backend-rust-axum.md).
- Consumes the shared crate per [ADR 0003 — Shared crypto core](../docs/adr/0003-shared-crypto-core-rust.md).
- Storage/hosting per [ADR 0005 — Storage & sovereign hosting](../docs/adr/0005-storage-and-sovereign-hosting.md).

This crate is a member of the root cargo workspace (alongside `crypto-core`).

## Build & test

```sh
# Build
cargo build -p backend

# Test
cargo test -p backend
```

Run locally: `cargo run -p backend` (listens on `0.0.0.0:8080`).
