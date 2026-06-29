# app-patient

Patient-facing mobile app for the HealthTech platform. Mobile-first, offline-first,
entry-level Android target (`minSdk 24`), iOS later from the same Dart codebase.

This package is a **scaffold only** (issue #2): compiling stubs with `TODO(#N)`
markers, not features.

## Purpose

- Generate/hold the patient master key in hardware and encrypt the medical record
  **client-side before any transit** (zero-knowledge).
- View and create the record fully offline (≤500 KB mirror + pending-upload queue).
- Share a short-lived QR grant so a doctor can read the record during a consultation.

## ADRs implemented

- **[ADR 0001](../docs/adr/0001-patient-app-flutter.md)** — Patient app: Flutter
  (`flutter_rust_bridge` to crypto-core, `--split-per-abi` build, Kotlin Keystore shim).
- **[ADR 0006](../docs/adr/0006-offline-storage-and-keys.md)** — Offline storage & keys
  (SQLCipher via `drift` + `sqlcipher_flutter_libs`, Keystore-wrapped DB key).
- Crypto contract from **[ADR 0003](../docs/adr/0003-shared-crypto-core-rust.md)**.

## Crypto boundary (non-negotiable)

- **All cryptography comes ONLY from the Rust `crypto-core`** via `flutter_rust_bridge`.
  There is **no Dart cipher** — no `pointycastle`, no `dart:crypto` AES (forbidden by
  ADR 0001/0003). Dart holds only what the UI renders; plaintext stays in Rust.
- The **StrongBox/TEE master-key sealing is a Kotlin platform-channel shim** (#11), in
  `android/app/src/main/kotlin/com/healthtech/patient/` (`KeystoreSealer.kt` +
  `MainActivity.kt`). Flutter plugins do not expose `setIsStrongBoxBacked` / TEE fallback,
  so this shim is mandatory. `flutter_secure_storage` is used **only** for non-critical
  items, never the master key.
- The SQLCipher DB key is unsealed from the Keystore-wrapped blob **in-memory only**
  (`TODO(#14)`).

### Master-key flow (#11)

`lib/src/secure/master_key_service.dart` orchestrates the lifecycle:

```
generateMasterKey (Rust core) → exportSealable → KeystoreChannel.seal (hardware KEK)
  → persist ONLY the sealed blob → wipe the clear copy
```

- `KeystoreChannel` (`lib/src/secure/keystore_channel.dart`) is the Dart side of the
  `healthtech/keystore` `MethodChannel`. Contract: `seal(clearKey) -> sealedBlob`,
  `unseal(sealedBlob) -> clearKey` (RAM-only), `exists() -> bool`, `clear()`. Native error
  codes `KEYSTORE_UNAVAILABLE` / `STRONGBOX_UNSUPPORTED` / `KEY_INVALIDATED` map to typed
  `KeystoreException`s. **No software fallback** (G3): keystore unavailability throws, it
  never returns a software key.
- The sealed blob (already hardware-wrapped, not a clear secret) is persisted via
  `SealedBlobStore` (`lib/src/secure/sealed_blob_store.dart`) — a private app file by
  default. The clear master key never touches disk.
- `MasterKeyService.probeState()` routes at startup: absent → onboarding (#13); present →
  open; `KEY_INVALIDATED` → recovery (#12, PBKDF2).
- iOS is an **amorce** stub (`ios/Runner/KeystoreChannelPlugin.swift`, `TODO(#11/iOS)`):
  same channel contract, fails loudly until the Secure Enclave path is hardened
  (ADR 0001 — Android first).
- The Rust↔Dart FRB seam (`lib/src/rust/crypto_core_bindings.dart`) defines `CryptoCore`
  with an opaque `MasterKeyHandle`; the generated bindings are produced by FRB codegen.

## Gate before build-out (ADR 0001)

A **device-lab footprint gate on a real near-full low-end Infinix** (~2 GB RAM, 32 GB)
**precedes** building out this app: measure per-ABI installed size, cold start, and steady
RSS against the hard budgets (installed ≤ ~25–30 MB arm64, no OOM/jank under storage
pressure). If the numbers regress unacceptably, the fallback is native Kotlin (#29). This
gate is non-negotiable.

## TODO map (backlog)

| TODO | Issue | What |
| --- | --- | --- |
| `#11` | keygen | Master key in Rust core, sealed via Kotlin Keystore (StrongBox/TEE) shim |
| `#13` | onboarding | First-run flow, recovery passphrase/security questions |
| `#16` | QR | Generate (`qr_flutter`, 120 s TTL) + scan (`mobile_scanner`) |
| `#14` | backup | SQLCipher mirror + pending-upload queue, recovery restore |
| `#17` | scan | Scan QR → fetch blob → decrypt **in RAM only** → read-only viewer |
| `#18` | edit | Quick-edit note/ordonnance → append-only merge → **session-key re-encryption in RAM** |

### Doctor consultation edit (#18)

During an open consultation the doctor taps **« Ajouter une note / ordonnance »** in the
record viewer. The note + structured prescription are merged **append-only** into the in-RAM
record (`mergeConsultation` never overwrites existing history), then the updated record is
**re-encrypted in RAM with the ephemeral session key** held in the `QrPayload`
(`ConsultationEditService.reEncrypt`) — the doctor never holds the patient master key, and the
transient key handle is wiped in a `finally` block. The plaintext lives only in the
`TextEditingController`s and the in-RAM `MedicalRecord`; nothing is written to disk or logged.
The `RecordSizeGuard` 500 Kio budget is enforced before encryption and guarantees the
newly added consultation is never the entry truncated (it fails loudly with "dossier plein"
instead). The re-encrypted blob is held on a RAM-only `ConsultationSession`; the cloud upload
and the end-of-session RAM wipe are **#19's** responsibility.

## Build & test

> Flutter SDK is **not installed in the scaffolding environment**, so these files were
> created structurally and cannot be run here. The exact commands are:

```sh
# Build (per-ABI split is MANDATORY — ADR 0001)
flutter build appbundle --split-per-abi

# Test
flutter test
```

First-time setup (once an SDK is available): `flutter pub get`, then run the
`flutter_rust_bridge` codegen + `dart run build_runner build` to generate the
`lib/src/rust/**` bindings and drift `*.g.dart` (`TODO(#11)`, `TODO(#14)`).
