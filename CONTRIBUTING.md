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

## Before you push

- `just test` is green (the ADW pipeline gate; `MX_AGENT_TEST_CMD="just test"`).
- `just lint` passes (`cargo fmt --check`, `cargo clippy -D warnings`).
- The orchestrator owns git/gh in automated runs — do not script merges.

## Quality gates

CI (`.github/workflows/`) runs the package test suites on every PR. Pre-merge gates are configured via
`MX_AGENT_FINALIZE_GATES` (e.g. `cargo fmt --check`, `cargo clippy … -D warnings`, `cargo deny check`).
