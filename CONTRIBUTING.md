# Contributing to HealthTech

## Commit conventions — [Conventional Commits](https://www.conventionalcommits.org)

```
<type>(<scope>): <subject>
```

**Types:** `feat` · `fix` · `docs` · `refactor` · `test` · `ci` · `chore`

**Scopes** (the package or area): `crypto-core`, `backend`, `app-patient`, `app-medecin`, `infra`, `adw`,
`docs`.

End commit bodies that were AI-assisted with a `Co-Authored-By:` trailer.

## Branch naming

Branches are derived by the ADW pipeline as `{prefix}/{issue}-{slug}` where the prefix maps from the issue
label (`bug`→`fix`, `docs`→`docs`, `tech-debt`→`refactor`, `infra`→`ci`, …; default `feat`). Manual branches
should follow the same shape, e.g. `feat/16-qr-code-temporaire`.

## Non-negotiable invariants (from the PRD & ADRs)

- **One crypto implementation.** All AES-256-GCM / PBKDF2 lives in `crypto-core` (Rust). Never write cipher
  code in Dart, Kotlin, or TypeScript — call the shared core via `flutter_rust_bridge` / WASM
  ([ADR 0003](./docs/adr/0003-shared-crypto-core-rust.md)).
- **Zero-knowledge.** The backend never holds keys or a decrypt path; it stores only opaque ciphertext.
- **No secrets, no plaintext in git.** Never commit keys, tokens, real patient data, or decrypted records.
- **Data residency.** Nothing in the data path may use a foreign managed cloud
  ([ADR 0005](./docs/adr/0005-storage-and-sovereign-hosting.md)).

## Secret hygiene (ADR 0007 / #4)

- **Never commit a secret.** No keys, tokens, passwords, real patient data, decrypted records,
  `*.tfstate`, or a real `.env`. Only **encrypted** bundles (`secrets/**/*.sops.yaml`), public age
  recipients (`/.sops.yaml`), and `*.example` placeholder templates are committed.
- **Operational secrets only.** Patient master keys / per-record data keys / QR session keys are
  client-side and **must never** enter `secrets/`, the IaC, env files, or CI (zero-knowledge
  boundary, ADR 0004/0006/0007).
- **Get dev secrets locally:** `cp .env.example .env` then `just dev-up` (throwaway Postgres +
  MinIO). No real credential is ever needed for dev. For staging/prod bundles, decrypt with
  `just secrets-decrypt <env>` (needs that env's in-country age key).
- **What CI enforces:** `.github/workflows/secrets.yml` runs `gitleaks` + `scripts/check-secrets.sh`
  on every PR — fail-closed if a plaintext secret, `*.tfstate`, real `.env`, or private key is
  staged. Run it yourself with `just secrets-lint`.
- **Optional pre-commit hook** (catch leaks before they land):
  ```sh
  printf '#!/usr/bin/env bash\ngitleaks protect --staged --no-banner --redact --config .gitleaks.toml\nbash scripts/check-secrets.sh\n' \
    > .git/hooks/pre-commit && chmod +x .git/hooks/pre-commit
  ```

## Before you push

- `just test` is green (the ADW pipeline gate; `MX_AGENT_TEST_CMD="just test"`).
- `just lint` passes (`cargo fmt --check`, `cargo clippy -D warnings`).
- `just secrets-lint` is green (no plaintext secret introduced).
- `just sca` passes (dependency vulnerability + license scan).
- `just ci` mirrors the GitHub Actions pipeline locally (lint + test + build + sca).
- The orchestrator owns git/gh in automated runs — do not script merges.

## Quality gates

CI ([`.github/workflows/ci.yml`](./.github/workflows/ci.yml), [ADR 0008](./docs/adr/0008-ci-cd-pipeline.md))
runs on every PR: per-package **lint + unit tests + build**, **dependency scanning (SCA)** —
`cargo deny check` plus `osv-scanner` over the Cargo/npm/pub lockfiles and `npm audit` — and produces the
**patient APK** and the **backend image** as artifacts. The aggregate **`CI success`** check must be enabled
as a *required status check* in branch protection so a red pipeline blocks merge. New advisories are also
surfaced as update PRs by [`dependabot.yml`](./.github/dependabot.yml).

Pre-merge gates for the ADW orchestrator are configured via `MX_AGENT_FINALIZE_GATES` (e.g. `cargo fmt
--check`, `cargo clippy … -D warnings`, `cargo deny check`).
