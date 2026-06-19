# ADR 0008 — CI/CD pipeline

**Status:** Accepted (2026-06-19) · Issue [#3](https://github.com/kortiene/HealthTech/issues/3) · Implements Epic E0 (#3)

## Context

The monorepo is polyglot (Rust, Flutter/Dart, Preact/TypeScript — see [ADR 0000](./0000-index.md)). Issue #3
requires, on **every PR**: lint, unit tests, builds of the apps and backend, and dependency (SCA) scanning;
a **green CI is mandatory before merge**; and the pipeline must produce a **patient APK** and a **backend
container image** as artifacts. Because this is a security/residency-sensitive health platform with a single
shared crypto core fanned out to three binding targets, the dependency-vulnerability surface is a
first-class risk ([ADR 0000](./0000-index.md), risk #6).

## Decision

A single **GitHub Actions** workflow ([`.github/workflows/ci.yml`](../../.github/workflows/ci.yml)) runs on
`pull_request` and `push: main`, with one job per package plus SCA and artifact jobs:

- **`rust`** — `cargo fmt --check`, `cargo clippy -D warnings`, `cargo test --workspace`, `cargo build`
  (`--locked` everywhere; cached via `Swatinem/rust-cache`).
- **`web`** — `npm ci`, `tsc --noEmit`, `vitest`, `vite build`, `npm audit --omit=dev --audit-level=high`,
  on a Node 20/22 matrix.
- **`flutter`** — `flutter pub get`, `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`,
  then `flutter build apk --debug` → **APK artifact**.
- **`backend-image`** — `docker buildx build` of [`backend/Dockerfile`](../../backend/Dockerfile) →
  **image tarball artifact** (`docker save | gzip`).
- **`sca`** — `cargo-deny check` (advisories + license allow-list + source/ban policy via
  [`deny.toml`](../../deny.toml)) **and** `osv-scanner` over every lockfile (Cargo, npm, **pub.dev**).
- **`ci-success`** — an aggregate gate that fails if any job failed; this is the **single required status
  check** to enable in branch protection (the "green before merge" rule).

Ongoing scanning is reinforced by [`.github/dependabot.yml`](../../.github/dependabot.yml) (cargo, npm, pub,
github-actions, docker).

### Notable choices

- **Backend image = static (musl) binary on `distroless/static:nonroot`** (per [ADR 0004](./0004-backend-rust-axum.md)):
  no shell, no package manager, non-root — a minimal attack surface for a residency-hosted, secrets-adjacent
  service. The image is built from the **repo root** so the cargo workspace (crypto-core) is in context.
- **SCA = cargo-deny + osv-scanner (+ npm audit).** cargo-deny gives Rust advisories *and* a license
  allow-list (a surprise copyleft dependency is a blocker); osv-scanner is the one tool that also covers
  **pub.dev**, which has no strong native SCA. Together they cover all three ecosystems.
- **Ephemeral Android scaffolding for the APK.** The patient app skeleton has no committed `android/` folder
  yet (that lands with onboarding, #13). Rather than commit platform scaffolding in a CI-scoped change, CI
  runs `flutter create --platforms=android` ephemerally before `flutter build apk`. The APK is therefore a
  **debug** build for now; release signing is deferred to the app-build-out / launch work (#13, M4).
- **Third-party Actions are pinned to exact versions** and bumped by Dependabot — the CI is itself part of
  the supply chain.

## Consequences

**Positive**
- One required check (`CI success`) makes branch protection trivial and the merge rule unambiguous.
- Every PR gets lint + tests + build + a cross-ecosystem CVE scan; both required release artifacts are
  produced on every run, so they are continuously known-buildable.
- Local parity: `just lint`, `just test`, `just build`, and `just sca` mirror the CI jobs.

**Negative / risks**
- The APK build depends on the runner's Android SDK and on ephemeral `flutter create`; it is a **debug**,
  unsigned-for-release artifact. Real signing + a committed `android/` are follow-ups (#13). Flutter is
  pinned (`flutter-version`) to remove version drift, but the build still requests the NDK that pinned
  Flutter selects, which today is a non-default extra on the runner image; pinning the NDK explicitly is
  deferred to #13 (when a real `android/` with a committed `ndkVersion` lands).
- `osv-scanner` / `cargo-deny` can turn a previously-green PR red when a **new** advisory is published for an
  already-pinned dependency. That is the intended SCA behaviour; triage via a Dependabot bump or a scoped,
  reviewed `deny.toml` `ignore`.
- Branch protection (the "required check") is a **repository setting**, not in this repo's files; it must be
  enabled by an admin/the orchestrator pointing at `CI success`.

## Alternatives considered

- **One monolithic job** — simpler file, but loses per-package parallelism, clear failure attribution, and
  per-ecosystem caching. Rejected.
- **glibc image on `debian:slim`** — easier to build than musl/distroless but a larger runtime with a shell
  and package manager; rejected for the minimal-attack-surface goal (ADR 0004).
- **`npm audit` / `cargo audit` only (no osv-scanner)** — leaves **pub.dev** (the patient app) unscanned;
  rejected because the patient app is the most exposed client.
- **A native GitLab/Jenkins runner in-country** — the *data* must stay in-country (ADR 0005), but CI builds
  no patient data and may run on GitHub-hosted runners; revisit only if build provenance must be sovereign.
