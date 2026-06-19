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
- The **StrongBox/TEE master-key sealing is a Kotlin platform-channel shim** and is
  **`TODO(#11)`** — Flutter plugins do not expose `setIsStrongBoxBacked` / TEE fallback.
  `flutter_secure_storage` is used **only** for non-critical items, never the master key.
- The SQLCipher DB key is unsealed from the Keystore-wrapped blob **in-memory only**
  (`TODO(#14)`).

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
