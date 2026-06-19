# ADR 0001 — Patient app: Flutter

**Status:** Accepted (2026-06-19) — *supersedes the initial native-Android (Kotlin) decision* ·
Issue [#1](https://github.com/kortiene/HealthTech/issues/1) · Implements Epic E1

## Context

The patient app is mobile-first with an **entry-level Android** target (PRD persona Awa: Infinix, 32 GB
often near-full, ~2 GB RAM, Edge/3G). It must generate and hold a master key in hardware, encrypt the
record client-side, work fully offline, and stay small and fast. The initial decision was native Android
(Kotlin), chosen **solely** on device footprint. Two stakeholder drivers reframe the choice:

1. **The team already has Flutter/Dart expertise** — native Kotlin would be slower and riskier for them.
2. **Cross-platform reach is a goal** — iOS later (and possibly a future doctor *mobile* app) from one
   codebase, which native Android does not provide.

This re-decision was validated by an adversarial evaluation (Flutter feasibility + skeptic + devil's-
advocate-for-native): **no hard constraint actually fails**; footprint and CI complexity "strain" but are
not disqualifying; and even the pro-native analysis concluded **native no longer wins** given the drivers.

## Decision

Build the patient app with **Flutter (Dart)**, `minSdk 24`. All cryptography is delegated to the shared
Rust crypto core ([ADR 0003](./0003-shared-crypto-core-rust.md)) via **`flutter_rust_bridge`** (Dart↔Rust
FFI) — **no cipher code in Dart** (no `pointycastle`/`dart:crypto` AES), exactly as Kotlin/JS are forbidden
it. Hardware key sealing uses the **Android Keystore (StrongBox/TEE)** through a **mandatory, security-
critical Kotlin platform-channel shim** (Flutter plugins do not expose `setIsStrongBoxBacked` / TEE
fallback). Concrete stack:

| Concern | Choice |
| --- | --- |
| Crypto core binding | `flutter_rust_bridge` 2.x → the same Rust `crypto-core`; only the audited high-level fns cross FFI |
| Key sealing | **Custom Kotlin `MethodChannel`**: `KeyGenParameterSpec` + `setIsStrongBoxBacked(true)` → TEE fallback, non-exportable. (`flutter_secure_storage` only for non-critical items.) |
| Offline DB | SQLCipher via `drift` + `sqlcipher_flutter_libs` (or `sqflite_sqlcipher`); DB key unsealed from the Keystore-wrapped blob, in-memory only |
| QR | `qr_flutter` (generate, 120 s TTL in app logic) + `mobile_scanner` (scan — one package Android+iOS) |
| Build | **`--split-per-abi` (mandatory)**, R8 full-mode + resource shrink, `--tree-shake-icons`, `--obfuscate`, stripped Rust `.so`, Impeller |

## Consequences

**Positive**
- **Plays to the team's velocity** (driver 1) and gives **patient-iOS UI reuse** from one Dart codebase
  (driver 2); the Rust core already builds for iOS, so iOS needs only a Keychain shim.
- **Zero-knowledge intact:** `flutter_rust_bridge` calls the *same* Rust crypto core — one audited
  implementation ([ADR 0003](./0003-shared-crypto-core-rust.md)); NIST AES-GCM/PBKDF2 vectors still gate CI.
- Network constraints unaffected by the UI framework: the ≤500 KB decrypt runs in native Rust (sub-ms, off
  the UI isolate), comfortably inside the 3 s/3G budget.

**Negative / risks (the trade we are accepting)**
- **Larger footprint** (the sole axis the native choice optimized): per-ABI **arm64 install ~12–20 MB**
  (download ~9–15 MB, ~+4–8 MB over native), **steady RAM ~120–180 MB vs ~70–110 MB native (+40–90 MB)**,
  **cold start ~1.2–2.5 s vs ~0.4–1.0 s** (engine/isolate warm-up). Per-ABI splits are **mandatory** (a
  universal bundle is ~30–45 MB).
- **Native code is not eliminated on the security-critical path:** StrongBox/TEE sealing, the
  Keystore-wrapped SQLCipher DB key, and key-wipe-on-OS-update all stay in Kotlin — so the team's Dart
  advantage is partially negated exactly where a learning curve is most dangerous. Treat this shim as
  pentest scope (#25, #29).
- **Best-effort Dart-heap zeroization:** Dart `Uint8List` plaintext can't be wiped deterministically like
  Rust `zeroize` — keep plaintext inside the Rust core, return only what the UI renders, minimize Dart
  copies. Same caveat class as the web PWA ([ADR 0002](./0002-doctor-interface-pwa.md)); document for ARTCI.
- **Triple binding surface** on `crypto-core` (UniFFI + wasm-bindgen + **FRB**) widens the supply-chain SPOF
  ([ADR 0003](./0003-shared-crypto-core-rust.md) risk): pin FRB, vet upgrades, keep the FFI surface tiny.
- **Impeller** on old Adreno/Mali/Unisoc GPUs can jank/crash — validate on the device lab (#29), keep the
  Skia fallback.
- **Cross-platform payoff is narrower than the pitch:** the doctor *mobile* need is largely already met by
  the PWA ([ADR 0002](./0002-doctor-interface-pwa.md)); the genuine net-new win is **patient-iOS reuse +
  team velocity**, not a saved doctor app.

## Condition before committing (gate)

Run a **footprint gate on a real near-full low-end Infinix** (~2 GB RAM, 32 GB) *before* building out the
app: measure per-ABI installed size, cold start, and steady RSS against hard budgets (e.g. installed
≤ ~25–30 MB arm64, no OOM/jank under storage pressure). **If the device-lab numbers regress unacceptably,
fall back to native Kotlin** (the superseded decision) and meet cross-platform reach via the PWA (doctor) +
a future Rust-core-backed iOS client. Footprint is a hard PRD constraint (#3) — this gate is non-negotiable.

## Alternatives considered

- **Native Android (Kotlin + Jetpack Compose)** — *the superseded decision.* Smallest APK/RAM and most
  direct Keystore/JNI access, but given the two drivers it forfeits the team's Flutter velocity and forces a
  separate Swift iOS app. The devil's-advocate analysis concluded native no longer wins here. Retained as
  the fallback if the footprint gate fails.
- **React Native** — JS-bridge cold-start/RSS cost and weaker FFI-to-Rust story than `flutter_rust_bridge`.
- **Kotlin Multiplatform** — crypto is already shared via Rust; does not deliver a Flutter team's velocity.
