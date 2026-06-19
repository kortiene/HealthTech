# ADR 0004 — Backend: Rust + Axum (zero-knowledge blob service)

**Status:** Accepted (2026-06-19) · Issue [#1](https://github.com/kortiene/HealthTech/issues/1) · Implements Epic E7 (#9)

## Context

The backend is a deliberately **dumb, auditable zero-knowledge service**: store/fetch opaque encrypted
blobs by anonymous UUID, issue ephemeral URLs for heavy media, and relay the offline-sync queue. It must
**never** hold key material or a decrypt path, deploy easily in-country on a small footprint, and scale to
50k patients / 500 doctors.

## Decision

Build the backend in **Rust with Axum (Tokio)**, compiled to a single static (musl) binary, in the **same
cargo workspace as `crypto-core`** ([ADR 0003](./0003-shared-crypto-core-rust.md)). Endpoints: `PUT/GET
/blob/{uuid}`, presigned ephemeral media URLs, and the sync relay. Plain REST/JSON over HTTP/2 + TLS, with
**HTTP range requests + resumable uploads (tus)** so a ≤500 KB blob download/upload resumes on Edge/3G.

## Consequences

**Positive**
- **One language end-to-end** (crypto core + backend): a single toolchain and SCA surface, and reviewers
  can prove "the server has no keys and no decrypt path" by reading one workspace. The backend reuses the
  exact Rust crypto crate for server-side test-vector / KAT verification with **no second language**.
- Tiny memory/CPU footprint, no GC pauses, one easy-to-deploy artifact → simple in-country self-hosting and
  a minimal attack surface; handles the target scale on one modest node + a warm standby.
- Range/tus support directly addresses the degraded-network constraint.

**Negative / risks**
- Rust hiring is harder than Go/Node around Abidjan (mitigated: the backend is small and stable; most
  engineering effort is in the clients).
- Shared workspace couples backend and crypto-core release cadence (acceptable; both are first-party).

## Alternatives considered

- **Go** (the `velocity-ops-first` proposal) — easier hiring/ops, but introduces a **second language**:
  the crypto crate can only be reused server-side via cgo, and it forfeits the single-language
  zero-knowledge audit story. Two of three judges penalized this on the crypto-auditability axis. Kept as a
  documented fallback if Rust hiring proves blocking and server-side crypto reuse is dropped.
- **Node/TypeScript** — shares language with the doctor PWA but not with the crypto core, larger runtime
  footprint, and a GC; rejected for a secrets-adjacent, residency-hosted service.
