# ADR 0003 — Shared cryptography core: one Rust crate

**Status:** Accepted (2026-06-19) · Issue [#1](https://github.com/kortiene/HealthTech/issues/1) · Implements Epic E5 (#10, #11, #12)

## Context

Zero-knowledge correctness is the platform's defining property: AES-256-GCM encryption happens **client-side
before any transit**, the server only ever holds opaque ciphertext, and PBKDF2 derives recovery keys from a
passphrase / culturally-adapted security questions. The PRD's threat model demands that the secret boundary
be **auditable**. Duplicating the cipher across Kotlin (Android) and JavaScript (web) would mean two
independent crypto implementations — two audit surfaces and two failure modes — which is a zero-knowledge
risk we must avoid.

## Decision

Implement **one** Rust crate, `crypto-core`, as the **only** place AES/PBKDF2 logic exists. It uses
**RustCrypto**: `aes-gcm` (AES-256-GCM AEAD), `pbkdf2` + `sha2` (PBKDF2-HMAC-SHA256), `getrandom` for
nonces/salts, `zeroize` for secret wiping. It is exposed from the same source to every client:

1. **Flutter patient app** → `flutter_rust_bridge` (Dart↔Rust FFI) over the JNI `.so` (see [ADR 0001](./0001-patient-app-flutter.md)).
2. **Doctor PWA** → `wasm-bindgen` WASM module in a Web Worker.
3. **Any native shell / the backend's test harness** → the same UniFFI/native bindings.

Clients call only high-level functions (`generate_master_key`, `encrypt_record`, `decrypt_record`,
`derive_key`, `wipe`). **Platform crypto is explicitly forbidden** — no `javax.crypto` AES, no WebCrypto
AES — because each would be a second implementation. The only platform-specific code is *key storage*
(Android Keystore), which seals/unseals the key the Rust core produces but never reimplements the cipher.

## Consequences

**Positive**
- **One implementation = one crypto review** (#26) covers every client; the secret boundary is provable by
  reading one crate.
- The PBKDF2 iteration count is **benchmarked on entry-level Android** and stored alongside the salt
  (public by design) so it is forward-tunable without breaking existing records.
- NIST AES-GCM + PBKDF2-HMAC-SHA256 **test vectors are gating CI tests** on the crate.

**Negative / risks**
- **Supply-chain SPOF**: a poisoned dependency or build poisons Android, web, and backend at once. Mitigate
  with pinned versions, `cargo-audit` + `cargo-deny`, `deny(warnings)`, and reproducible builds.
- **PBKDF2 calibration trap** (#12): iterations strong enough to resist offline brute-force of a low-entropy
  recovery answer may be slow on weak Infinix SoCs. Benchmark per-device class; consider a memory-hard KDF
  (Argon2id) as a future option if the PRD's "PBKDF2" wording is relaxed.
- Polyglot build (Rust → JNI/UniFFI + WASM) adds toolchain complexity to CI.

## Alternatives considered

- **Per-platform crypto (Tink on Android + WebCrypto on web)** — two implementations, two audits; rejected
  as a zero-knowledge risk per PRD constraint.
- **libsodium via FFI everywhere** — viable, but RustCrypto keeps a single Rust workspace shared with the
  backend ([ADR 0004](./0004-backend-rust-axum.md)) and first-class WASM/UniFFI tooling.
