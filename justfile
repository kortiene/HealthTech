# HealthTech monorepo task runner.
# `just test` is the canonical ADW pipeline gate (MX_AGENT_TEST_CMD="just test").
set shell := ["bash", "-uc"]

# Default: list recipes
default:
    @just --list

# --- aggregate gates -------------------------------------------------------

# Run every package's test suite (the ADW pipeline test gate).
test: test-rust test-web test-flutter

# Lint/format gates — candidates for MX_AGENT_FINALIZE_GATES.
lint: lint-rust

# Build every package.
build: build-rust build-web

# --- Rust (crypto-core + backend) ------------------------------------------

test-rust:
    cargo test --workspace

lint-rust:
    cargo fmt --check
    cargo clippy --workspace --all-targets -- -D warnings

build-rust:
    cargo build --workspace

# --- Doctor PWA (app-medecin) ----------------------------------------------

test-web:
    cd app-medecin && npm test

build-web:
    cd app-medecin && npm run build

# --- Patient app (app-patient, Flutter) ------------------------------------
# Skipped gracefully when the Flutter SDK is absent so `just test` still runs.

test-flutter:
    if command -v flutter >/dev/null 2>&1; then cd app-patient && flutter test; else echo "flutter SDK absent — skipping app-patient tests"; fi
