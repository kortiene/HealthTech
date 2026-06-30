# ADR 0006 — Offline storage & key management

**Status:** Accepted (2026-06-19) · Issue [#1](https://github.com/kortiene/HealthTech/issues/1) · Implements Epics E1 (#11, #12), E2 (#21, #22)

> **Implementation note (#21, 2026-06-30).** The offline **pending-upload queue** is
> delivered for the patient/Android (Flutter) target: `drift` + `sqlcipher_flutter_libs`
> retained (not `sqflite_sqlcipher`), DB key sealed by the Keystore (envelope, #11), opened
> with `PRAGMA key` + WAL. See `app-patient/lib/src/doctor/{offline_upload_queue,sqlcipher_upload_queue}.dart`.
> The native SQLCipher binding is **not** exercised in host-only CI (the queue logic is
> covered by an in-memory impl; a device-backed e2e is a follow-up). The **web PWA variant**
> (ciphertext-in-IndexedDB) remains a deliberate, logged deviation and is **not yet delivered**
> (the doctor loop currently lives in `app-patient/`, not `app-medecin/`). The network drain
> on reconnect is #22.

## Context

A consultation must complete with **no data loss** during total network/power cuts (offline prescription
queue), and the patient must view/create their record fully offline. The master key must be sealed in
hardware; recovery must work on a new phone. The doctor's browser cannot run SQLCipher, and its decrypted
record must remain RAM-only.

## Decision

**Offline storage**
- **Patient (Flutter/Android):** **SQLCipher** (AES-256 full-DB encryption) via `drift` +
  `sqlcipher_flutter_libs` (or `sqflite_sqlcipher`) for the ≤500 KB record mirror and the pending-upload
  queue, so onboarding and viewing work offline. The SQLCipher DB key is wrapped by the Android Keystore
  master key (sealed via the Kotlin platform-channel shim, [ADR 0001](./0001-patient-app-flutter.md)),
  never stored in plaintext.
- **Android (doctor shell, if/when used):** **SQLCipher** for the offline prescription/consultation queue
  (#21), drained on reconnect (#22).
- **Doctor PWA (web):** browsers can't run SQLCipher, so the offline queue stores **only already
  AES-256-GCM ciphertext** (sealed by the Rust/WASM core) in **IndexedDB** — plaintext is never written to
  disk even without SQLCipher. *This is a deliberate, logged deviation from the literal "SQLCipher" wording
  in #21; the trust boundary is equivalent-or-stronger (the operator/store never sees plaintext).*

**Key management**
- **Patient master key:** generated inside the Rust core, sealed in the **Android Keystore** via a Kotlin
  platform-channel shim ([ADR 0001](./0001-patient-app-flutter.md)) — StrongBox (secure element) when
  present, TEE-backed fallback on devices that lack it — non-exportable, `setUserAuthenticationRequired`
  where UX allows; it wraps the SQLCipher DB key and per-record data keys.
- **Recovery (#12):** PBKDF2 from a passphrase / culturally-adapted security questions re-derives access on
  a new phone (US-1.4) without the original hardware key ever leaving the old device.

> **Implementation note (#11) — envelope encryption.** A Rust-generated key cannot itself *be* a
> non-exportable Keystore key, so the master key is sealed via **envelope encryption**: the Keystore
> generates a non-exportable hardware **KEK** (AES-256-GCM, `setIsStrongBoxBacked(true)` → TEE fallback,
> alias `healthtech.master.kek.v1`) that wraps the Rust master key; only the sealed blob
> (`version || iv || ciphertext || tag`) is persisted. **No software fallback** — absence of a
> hardware keystore fails loudly (typed `KEYSTORE_UNAVAILABLE`). `KeyPermanentlyInvalidatedException`
> maps to `KEY_INVALIDATED` → recovery (#12). The clear key lives only in RAM inside a `MasterKeyHandle`
> and is zeroized after sealing/use. (Alternative considered and rejected for #11: direct wrapped-key
> import of the Rust key as a non-exportable Keystore key — more complex, less portable.)
- **Doctor session key:** the per-session symmetric key arrives via the patient's 120 s QR, lives only in
  WASM/JS heap, and is zeroized on session end / 15-min timeout / tab close / upload completion. The QR
  grant is **single-use, short-TTL** and red-teamed in the threat model (#6).

## Consequences

**Positive**
- No plaintext on disk on any client; offline-first consultation survives network/power cuts.
- The recovery path is the resilient backstop for hardware-key loss.

**Negative / risks**
- **Android Keystore/StrongBox inconsistency** on cheap Infinix devices (many lack StrongBox; some OEM TEEs
  wipe keys on OS update → patient lockout). The PBKDF2 recovery path is the mitigation; test on a low-end
  device lab (#29).
- **PBKDF2 calibration** vs. low-entropy security answers on weak SoCs (see [ADR 0003](./0003-shared-crypto-core-rust.md)).
- The web SQLCipher substitution is a named deviation from #21's wording — track it in that issue.

## Alternatives considered

- **Plain SQLite + app-layer field encryption (Android)** — reinvents SQLCipher's full-DB encryption with
  more code; rejected.
- **Literal SQLCipher in the browser via wa-sqlite/OPFS** — heavy WASM SQLite + complex key handling for a
  small queue; the ciphertext-in-IndexedDB approach is simpler and already plaintext-free. Revisit if a
  richer offline query surface is needed.
