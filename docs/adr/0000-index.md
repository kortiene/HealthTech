# Architecture Decision Records — HealthTech

This directory records the major technical decisions for the HealthTech platform, one ADR per
decision (issue [#1](https://github.com/kortiene/HealthTech/issues/1)). Each ADR follows:
**Status · Context · Decision · Consequences · Alternatives**.

## How these were chosen

The stack was selected via a structured design review: three independent full-stack proposals
(optimization lenses: *security-first*, *device/network-first*, *velocity/ops-first*) were scored by an
adversarial panel of three judges (crypto-auditor, mobile-architect, devops-pragmatist) against the PRD's
hard constraints. **`device/network-first` was the consensus winner** (top-ranked by 2 of 3 judges,
highest average score); all three proposals independently converged on the same load-bearing crypto
choices. The backend-language tie-break (Rust over Go) and several hardening details were grafted from
the runner-up proposals per the judges' recommendations.

## Decision summary

| Dimension | Decision | ADR |
| --- | --- | --- |
| Patient app | **Native Android (Kotlin + Jetpack Compose, minSdk 24)** | [0001](./0001-patient-app-native-android.md) |
| Doctor interface | **Installable PWA (Preact + TypeScript + Vite), RAM-only WASM decrypt** | [0002](./0002-doctor-interface-pwa.md) |
| Cryptography core | **One shared Rust crate (RustCrypto) → UniFFI/JNI + WASM; no platform crypto** | [0003](./0003-shared-crypto-core-rust.md) |
| Backend | **Rust + Axum**, same cargo workspace as the crypto core | [0004](./0004-backend-rust-axum.md) |
| Storage & hosting | **MinIO (blobs) + PostgreSQL (metadata), self-hosted in Côte d'Ivoire** | [0005](./0005-storage-and-sovereign-hosting.md) |
| Offline & keys | **SQLCipher (Android) + AEAD-ciphertext IndexedDB (web); Android Keystore + PBKDF2 recovery** | [0006](./0006-offline-storage-and-keys.md) |

## The repository will become a polyglot monorepo

```
app-patient/    # Kotlin/Android (Gradle)
app-medecin/    # Preact/TypeScript PWA (Vite)
crypto-core/    # Rust crate (RustCrypto) — UniFFI + wasm-bindgen targets
backend/        # Rust/Axum service (same cargo workspace as crypto-core)
infra/          # Terraform + Ansible (sovereign in-country hosting)
docs/adr/       # these records
```

## Open risks carried forward (raised by the judge panel)

1. **Browser RAM-only decrypt is best-effort, not provable** to an ARTCI auditor (JS GC may copy/page
   plaintext). Mitigations: page-reload-to-drop-heap on session end, minimal plaintext lifetime, WASM
   buffer zeroize; flag for the pentest (#25); a native doctor shell remains a fallback for high assurance.
2. **Doctor-web offline queue deviates from the literal "SQLCipher"** (#21): browsers can't run SQLCipher,
   so the web queue stores only already-AES-256-GCM ciphertext in IndexedDB (same/stronger trust boundary).
   Logged explicitly in [0006](./0006-offline-storage-and-keys.md).
3. **PBKDF2 calibration trap** (#12) on weak Infinix SoCs: iteration count high enough to resist offline
   brute-force vs. acceptable UX. Benchmark on-device; store the iteration count with the salt.
4. **Android Keystore/StrongBox inconsistency** on cheap devices (many lack StrongBox; some TEEs wipe keys
   on OS update → patient lockout). The PBKDF2 recovery path (#12) is the real backstop.
5. **Sovereign single-datacenter is an availability SPOF** (no foreign failover allowed). Mitigate with
   in-country HA (primary+replica, warm standby) and offline-first so consultations survive outages.
6. **One-core × three-targets is a crypto supply-chain SPOF**: pin deps, `cargo-audit`/`cargo-deny`,
   reproducible builds, gate on NIST test vectors.
