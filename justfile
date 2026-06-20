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
test: test-rust test-web test-flutter test-compliance-scripts

# Lint/format gates — candidates for MX_AGENT_FINALIZE_GATES.
lint: lint-rust compliance-check

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
infra-validate:
    terraform -chdir=infra/terraform fmt -check
    terraform -chdir=infra/terraform init -backend=false
    terraform -chdir=infra/terraform validate
    for e in dev staging prod; do ansible-playbook --syntax-check -i infra/ansible/inventories/$e infra/ansible/playbook.yml; done

# Bring the local dev stack (Postgres + MinIO) up (throwaway creds, synthetic data).
dev-up:
    test -f .env || cp .env.example .env
    docker compose -f infra/dev/compose.yaml --env-file .env up -d

# Tear the local dev stack down.
dev-down:
    docker compose -f infra/dev/compose.yaml down
