# ADR 0001 — Patient app: native Android (Kotlin)

**Status:** Accepted (2026-06-19) · Issue [#1](https://github.com/kortiene/HealthTech/issues/1) · Implements Epic E1

## Context

The patient app is mobile-first with an **entry-level Android** target (PRD persona Awa: Infinix, 32 GB
often near-full, ~2 GB RAM, Edge/3G). It must: generate and hold a master key in hardware, encrypt the
record client-side, work fully offline, and stay small and fast on a constrained device. The dominant
size/perf constraint is the entry-level device on a flaky network.

## Decision

Build the patient app as a **native Android app in Kotlin with Jetpack Compose, `minSdk 24` (Android 7)**.
All cryptography is delegated to the shared Rust crypto core ([ADR 0003](./0003-shared-crypto-core-rust.md))
over **JNI/UniFFI**; no crypto in Kotlin. Distribute as an Android App Bundle with per-ABI splits
(arm64-v8a primary, armeabi-v7a fallback), R8 full-mode + resource shrinking.

## Consequences

**Positive**
- Smallest, most predictable footprint: target installed APK **~8–15 MB** (arm64 download ~6–10 MB) and the
  lowest cold-start/steady-state RAM — no Flutter engine (~4–7 MB `libflutter.so` + Skia/Impeller) and no
  JS/Hermes bridge to warm up. This directly serves the entry-level-device size/perf constraint.
- Zero-copy, low-overhead access to the **Android Keystore (StrongBox/TEE)** and to the Rust core over JNI
  with no extra FFI marshalling layer.
- One language for the whole Android client; native platform integration (camera/QR, background work).

**Negative / risks**
- No code sharing with the doctor web client at the UI layer (mitigated: crypto IS shared via the Rust
  core; the doctor side is web — [ADR 0002](./0002-doctor-interface-pwa.md)).
- iOS would need a separate client later (acceptable: the PRD targets Android first; the Rust core already
  compiles for iOS when needed).
- Requires Kotlin + Android expertise on the team.

## Alternatives considered

- **Flutter** — one codebase for patient + doctor mobile, but adds engine size/RAM and an FFI hop with no
  security upside; weaker fit for the near-full low-RAM Infinix target. Rejected on the size/perf axis.
- **React Native** — JS bridge cold-start and RSS cost on low-end devices; rejected for the same reason.
- **Kotlin Multiplatform** — attractive for sharing logic, but the crypto core is already shared via Rust;
  KMP would add complexity without removing the Rust core. Revisit only if non-crypto logic sharing grows.
