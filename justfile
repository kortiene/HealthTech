# HealthTech monorepo task runner.
# `just test` is the canonical ADW pipeline gate (MX_AGENT_TEST_CMD="just test").
set shell := ["bash", "-uc"]

# Default: list recipes
default:
    @just --list

# --- ADW pipeline ----------------------------------------------------------

# Run the ADW delivery pipeline on a GitHub issue from the repo root.
# Usage: just issue 3 --runner claude --yes   (needs a runner credential, e.g. ANTHROPIC_API_KEY)
# The test gate uses `just test` via MX_AGENT_TEST_CMD (export it first).
issue *ARGS:
    cd adw_sdlc && pnpm issue {{ARGS}}

# --- aggregate gates -------------------------------------------------------

# Run every package's test suite (the ADW pipeline test gate).
test: test-rust test-web test-flutter test-compliance-scripts test-threat-model test-residency-scripts test-homologation-scripts

# Lint/format gates — candidates for MX_AGENT_FINALIZE_GATES.
lint: lint-rust compliance-check homologation-check threat-model-check ux-check

# Decryption performance gate (issue #27, NFR §5): the deterministic,
# generous-threshold perf assertions — Rust decrypt regression + Dart CPU-chain
# timing + the compressed-blob size ceiling. These ALSO ride the aggregate
# `just test` (via `cargo test --workspace` and `flutter test`), so CI blocks a
# regression without needing `just` installed; this recipe just runs them in
# isolation for a legible local/on-demand check. The reporting-only criterion-
# free bench (`cargo bench -p crypto-core`) is intentionally NOT here (spec §E).
# See docs/perf/decryption-budget.md.
perf:
    cargo test -p crypto-core --test decrypt_perf_regression
    if command -v flutter >/dev/null 2>&1; then cd app-patient && flutter test test/perf test/record/blob_size_budget_test.dart; else echo "flutter SDK absent — skipping app-patient perf tests"; fi

# Build every package.
build: build-rust build-web

# Dependency vulnerability + license scan (SCA), mirrors the CI `sca` job.
sca: sca-rust sca-web sca-osv

# Local mirror of CI (lint+test+build+sca); APK/image artifacts are CI-only.
ci: lint test build sca

# --- Rust (crypto-core + backend) ------------------------------------------

test-rust:
    cargo test --workspace

lint-rust:
    cargo fmt --check
    cargo clippy --workspace --all-targets -- -D warnings

# Validate compliance documentation artefacts (issue #5, ADR docs/compliance).
compliance-check:
    bash scripts/check-compliance-matrix.sh

# Self-test the compliance matrix checker with synthetic fixtures (issue #5).
test-compliance-scripts:
    bash scripts/test-compliance-matrix.sh

# Self-test the homologation dossier checker with synthetic fixtures (issue #30).
test-homologation-scripts:
    bash scripts/test-homologation-dossier.sh

# Validate the ARTCI homologation dossier (issue #30, docs/compliance/homologation-artci/).
homologation-check:
    bash scripts/check-homologation-dossier.sh

# Self-test the data-residency guardrail with synthetic fixtures (issue #8).
test-residency-scripts:
    bash scripts/test-residency.sh

# Validate threat model artefacts (issue #6, docs/threat-model/).
threat-model-check:
    bash scripts/check-threat-model.sh

# Validate the doctor UX norm consistency (issue #28, docs/ux/ ↔ code source of
# truth). Doc/code drift + honesty gate; rides `just lint`. The parcours guard-rail
# and PWA smoke test themselves run in the existing CI (flutter test / npm test).
ux-check:
    bash scripts/check-ux-docs.sh

# Self-test the threat model checker with the live artefact.
test-threat-model:
    bash scripts/check-threat-model.sh

build-rust:
    cargo build --workspace

# Rust SCA: advisories + license allow-list + source/ban policy (deny.toml).
sca-rust:
    cargo deny check

# Build the backend container image (musl static -> distroless). Needs Docker.
build-image:
    docker build -f backend/Dockerfile -t healthtech-backend:local .

# --- Doctor PWA (app-medecin) ----------------------------------------------

test-web:
    cd app-medecin && npm test

build-web:
    cd app-medecin && npm run build

# PWA SCA: vulnerability scan of the shipped (prod) dependency surface.
sca-web:
    cd app-medecin && npm audit --omit=dev --audit-level=high

# --- Patient app (app-patient, Flutter) ------------------------------------
# Skipped gracefully when the Flutter SDK is absent so `just test` still runs.

test-flutter:
    if command -v flutter >/dev/null 2>&1; then cd app-patient && flutter test; else echo "flutter SDK absent — skipping app-patient tests"; fi

# --- Cross-ecosystem SCA (osv-scanner) -------------------------------------
# Scans every lockfile (Cargo, npm, pub.dev) against the OSV database.

sca-osv:
    osv-scanner scan source --lockfile=Cargo.lock --lockfile=app-medecin/package-lock.json --lockfile=app-patient/pubspec.lock --lockfile=adw_sdlc/package-lock.json

# --- Secrets & environments (ADR 0007 / issue #4) --------------------------

# Fail-closed secret-scan + leak tripwire (gitleaks + house-style guardrail).
# Wired into CI via .github/workflows/secrets.yml.
secrets-lint:
    gitleaks detect --no-banner --redact --config .gitleaks.toml
    bash scripts/check-secrets.sh

# Decrypt an environment's SOPS bundle to stdout (needs that env's age key).
# Usage: just secrets-decrypt staging
secrets-decrypt ENV:
    sops -d secrets/{{ENV}}/services.sops.yaml

# Edit an environment's SOPS bundle in place (re-encrypts on save).
# Usage: just secrets-edit staging
secrets-edit ENV:
    sops secrets/{{ENV}}/services.sops.yaml

# Validate the IaC for every environment with NO cloud credentials.
# (terraform validate needs Terraform >= 1.9; see infra/terraform/main.tf.)
# Runs the residency guardrail first so a foreign-cloud regression fails fast,
# even before Terraform/Ansible are installed.
infra-validate: infra-residency
    terraform -chdir=infra/terraform fmt -check
    terraform -chdir=infra/terraform init -backend=false
    terraform -chdir=infra/terraform validate
    for e in dev staging prod; do ansible-playbook --syntax-check -i infra/ansible/inventories/$e infra/ansible/playbook.yml; done

# Data-residency anti-regression guardrail (issue #8, ADR 0005 / ARTCI). Fails
# closed if a foreign provider / state backend / cloud endpoint, or a non-CI
# `country` override, ever enters infra/. Credential-free, no network; mirrors
# secrets-lint. Wired into CI via .github/workflows/secrets.yml.
infra-residency:
    bash scripts/check-residency.sh

# Bring the local dev stack (Postgres + MinIO) up (throwaway creds, synthetic data).
dev-up:
    test -f .env || cp .env.example .env
    docker compose -f infra/dev/compose.yaml --env-file .env up -d

# Tear the local dev stack down.
dev-down:
    docker compose -f infra/dev/compose.yaml down
