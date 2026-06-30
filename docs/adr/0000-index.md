# Architecture Decision Records — HealthTech

This directory records the major technical decisions for the HealthTech platform, one ADR per
decision (the stack ADRs 0001–0006 from issue [#1](https://github.com/kortiene/HealthTech/issues/1); the
secrets & environments ADR 0007 from issue [#4](https://github.com/kortiene/HealthTech/issues/4); the
CI/CD pipeline ADR 0008 from issue [#3](https://github.com/kortiene/HealthTech/issues/3); the sovereign
operator selection ADR 0009 from issue [#8](https://github.com/kortiene/HealthTech/issues/8)). Each ADR
follows: **Status · Context · Decision · Consequences · Alternatives**.

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
| Patient app | **Flutter (Dart, minSdk 24)** — Rust crypto via `flutter_rust_bridge` | [0001](./0001-patient-app-flutter.md) |
| Doctor interface | **Installable PWA (Preact + TypeScript + Vite), RAM-only WASM decrypt** | [0002](./0002-doctor-interface-pwa.md) |
| Cryptography core | **One shared Rust crate (RustCrypto) → UniFFI/JNI + WASM; no platform crypto** | [0003](./0003-shared-crypto-core-rust.md) |
| Backend | **Rust + Axum**, same cargo workspace as the crypto core | [0004](./0004-backend-rust-axum.md) |
| Storage & hosting | **MinIO (blobs) + PostgreSQL (metadata), self-hosted in Côte d'Ivoire** | [0005](./0005-storage-and-sovereign-hosting.md) |
| Offline & keys | **SQLCipher (Android) + AEAD-ciphertext IndexedDB (web); Android Keystore + PBKDF2 recovery** | [0006](./0006-offline-storage-and-keys.md) |
| Secrets & environments | **SOPS + age (in-country keys); per-env dev/staging/prod; OpenBao deferred for prod** | [0007](./0007-secrets-and-environments.md) |
| CI/CD pipeline | **GitHub Actions: per-package lint/test/build, cargo-deny + osv-scanner SCA, APK + distroless backend image artifacts** | [0008](./0008-ci-cd-pipeline.md) |
| Sovereign operator | **National ARTCI-eligible operator selected against a criteria grid (final pick pending procurement)** | [0009](./0009-sovereign-operator-selection.md) |
| Offline-sync conflicts | **Blind last-writer-wins + idempotent at-least-once drain (A); divergence-detection hooks wired-but-inactive (B); patient reconciliation deferred (C)** | [0010](./0010-offline-sync-conflict-resolution.md) |

## Security documentation

The STRIDE threat model and security policy produced by issue [#6](https://github.com/kortiene/HealthTech/issues/6) are security artifacts (not ADRs), stored alongside this index:

| Document | Description | Issue |
| --- | --- | --- |
| [`docs/threat-model/stride-threat-model.md`](../threat-model/stride-threat-model.md) | Full STRIDE model: 8 threat categories, countermeasures traced to backlog issues, residual risks | [#6](https://github.com/kortiene/HealthTech/issues/6) |
| [`SECURITY.md`](../../SECURITY.md) | Responsible disclosure policy, severity classification, authorized test scope | [#6](https://github.com/kortiene/HealthTech/issues/6) |

These documents are **PREUVE-16** in the compliance catalogue (`docs/compliance/controles.md`, CTRL-20) and form part of the ARTCI homologation dossier ([#30](https://github.com/kortiene/HealthTech/issues/30)).

## The repository will become a polyglot monorepo

```
app-patient/    # Flutter (Dart) — flutter_rust_bridge -> crypto-core
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
   reproducible builds, gate on NIST test vectors. (Now **three** binding targets after the Flutter
   re-decision: UniFFI + wasm-bindgen + `flutter_rust_bridge`.)
7. **Flutter patient-app footprint** ([ADR 0001](./0001-patient-app-flutter.md), revised) must pass a
   **device-lab gate** on a real near-full low-end Infinix *before* build-out (installed size, RAM, cold
   start); native Kotlin is the documented fallback if it regresses.
