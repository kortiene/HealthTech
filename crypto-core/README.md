# crypto-core

The **single** cryptography crate for the HealthTech platform. AES-256-GCM and
PBKDF2-HMAC-SHA256 live here and **only** here — every client (Flutter patient app via
`flutter_rust_bridge`, doctor PWA via WASM, backend test harness) calls the same
high-level functions. Platform crypto (`javax.crypto`, WebCrypto AES) is forbidden so
there is exactly one audit surface for the zero-knowledge boundary.

## Purpose

Provide auditable, client-side encryption primitives:

| Function | Role |
| --- | --- |
| `generate_master_key() -> [u8; 32]` | fresh 256-bit key from the OS CSPRNG |
| `encrypt_record(key, &[u8]) -> Result<Vec<u8>>` | AES-256-GCM; random 96-bit nonce **prepended** (`nonce \|\| ciphertext \|\| tag`) |
| `decrypt_record(key, &[u8]) -> Result<Vec<u8>>` | authenticated decrypt of that blob |
| `derive_key(passphrase, salt, iters) -> [u8; 32]` | PBKDF2-HMAC-SHA256 recovery-key derivation |
| `wipe(&mut [u8])` | zeroize a secret buffer in place |

## ADR implemented

[ADR 0003 — Shared cryptography core: one Rust crate](../docs/adr/0003-shared-crypto-core-rust.md)
(Epic E5: issues #10, #11, #12).

## Status

Scaffold for issue **#2** — structure plus minimal *compiling* stubs. The cipher wiring
is real and round-trips, but is **not** production-ready until the deferred work lands:

- `TODO(#10)` — official **NIST AES-GCM** known-answer vectors as gating CI tests.
- `TODO(#11)` — bind record metadata as AES-GCM **associated data (AAD)**.
- `TODO(#12)` — **PBKDF2 iteration calibration** on entry-level Android + RFC 6070 / NIST
  PBKDF2 gating vectors.

## Build & test

This crate is a member of the root cargo workspace (its `Cargo.toml` has `[package]` but
no `[workspace]`). From the crate directory:

```sh
# Build
cargo build -p crypto-core

# Test (runs the encrypt -> decrypt round-trip + tamper/short/derive/wipe checks)
cargo test -p crypto-core
```
