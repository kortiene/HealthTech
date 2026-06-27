# crypto-core

The **single** cryptography crate for the HealthTech platform. AES-256-GCM and
PBKDF2-HMAC-SHA256 live here and **only** here — every client (Flutter patient app via
`flutter_rust_bridge`, doctor PWA via WASM, backend test harness) calls the same
high-level functions. Platform crypto (`javax.crypto`, WebCrypto AES) is forbidden so
there is exactly one audit surface for the zero-knowledge boundary.

## Purpose

Provide auditable, client-side encryption primitives:

| Function / const | Role |
| --- | --- |
| `generate_master_key() -> [u8; 32]` | fresh 256-bit key from the OS CSPRNG |
| `MasterKeyHandle::generate() -> MasterKeyHandle` | master key generated **inside the core**, held in a self-zeroizing `Zeroizing` buffer (#11, G1/G8) |
| `MasterKeyHandle::export_sealable() -> Zeroizing<[u8; 32]>` | clear key **for immediate hardware sealing only** — the one sanctioned FFI crossing (#11, G8) |
| `MasterKeyHandle::from_unsealed([u8; 32]) -> MasterKeyHandle` | re-wrap hardware-unsealed bytes back into a handle (#14 unseal path) |
| `MasterKeyHandle::wipe(self)` | zeroize + consume the handle (also done on `Drop`) |
| `encrypt_record(key, &[u8]) -> Result<Vec<u8>, CryptoError>` | AES-256-GCM; fresh random 96-bit nonce **prepended** (`nonce \|\| ciphertext \|\| tag`) |
| `decrypt_record(key, &[u8]) -> Result<Vec<u8>, CryptoError>` | authenticated decrypt of that blob; coarse `Decrypt` error (no oracle) |
| `derive_key(passphrase, salt, iters) -> [u8; 32]` | PBKDF2-HMAC-SHA256 recovery-key derivation (calibration deferred to #12) |
| `wipe(&mut [u8])` | zeroize a secret buffer in place |
| `KEY_LEN` (32) · `NONCE_LEN` (12) · `TAG_LEN` (16) · `OVERHEAD_LEN` (28) | public layout constants |
| `enum CryptoError { Rng, Decrypt }` | coarse, secret-independent error model |

### Wire format (stable contract — frozen by #10)

```text
nonce (12 bytes) || ciphertext (= plaintext length) || GCM tag (16 bytes)
```

Fixed overhead **28 bytes** (`OVERHEAD_LEN`) — the storage budget of #9/#15 (plaintext
≤ 500 KB) accounts for it. **No version byte in v1** (kept consistent with the 28-byte
overhead already budgeted by the merged #9 blob store); future evolution (AAD #11, future
algorithm) is introduced *additively*, never by re-interpreting these bytes. Nonces are
freshly random per call and never reused under a key; a CSPRNG failure aborts with
`CryptoError::Rng` rather than emitting a degenerate nonce. Full rationale + the crypto
review checklist: [`docs/security/crypto-core-review.md`](../docs/security/crypto-core-review.md).

## Master-key sealing boundary (#11)

The master key is **generated in this core** and **never leaves the device in clear**. It
crosses the FFI exactly once, through `MasterKeyHandle::export_sealable`, whose only caller
is the platform Keystore shim that seals it immediately:

- **Android (StrongBox/TEE):** a non-exportable hardware **KEK** wraps the master key
  (envelope encryption, ADR 0006); only the sealed blob is persisted, never the clear key.
  There is **no software-key fallback** — if no hardware keystore exists, sealing fails
  loudly. The shim lives in the patient app (`KeystoreSealer.kt`), not here.
- **Clear-key lifetime:** the clear key exists only in RAM, inside a `MasterKeyHandle`, for
  the duration of sealing/use, then is `wipe()`-d (acceptance criterion #2 — no persistent
  leak). The hardware-sealed blob format is device-internal and **separate** from the
  `encrypt_record` wire format.

## ADR implemented

[ADR 0003 — Shared cryptography core: one Rust crate](../docs/adr/0003-shared-crypto-core-rust.md)
(Epic E5: issues #10, #11, #12).

## Status

AES-256-GCM module **hardened (#10)**: the official AES-256-GCM known-answer vectors pass
as gating CI tests, the nonce policy is documented and enforced, and the public API + wire
format are frozen. Vector provenance:
[`tests/vectors/PROVENANCE.md`](./tests/vectors/PROVENANCE.md). Security review:
[`docs/security/crypto-core-review.md`](../docs/security/crypto-core-review.md).

Still deferred to their own issues (do not assume implemented):

- `TODO(#11)` — bind record metadata as AES-GCM **associated data (AAD)**, added as an
  *additive* function so this API stays stable (the AAD path is already vector-tested).
- `TODO(#12)` — **PBKDF2 iteration calibration** on entry-level Android + RFC 6070 / NIST
  PBKDF2 gating vectors (`derive_key` is currently smoke-tested only).
- Independent external crypto review (**#26**) before production.

## Build & test

This crate is a member of the root cargo workspace (its `Cargo.toml` has `[package]` but
no `[workspace]`). From the crate directory:

```sh
# Build
cargo build -p crypto-core

# Test — runs the NIST AES-256-GCM known-answer vectors (gating), the public-API
# conformance + input-robustness suite, and the round-trip/tamper/derive/wipe checks.
cargo test -p crypto-core

# The canonical ADW gate runs them across the workspace:
cargo test --workspace      # == `just test-rust`, part of `just test`
```
