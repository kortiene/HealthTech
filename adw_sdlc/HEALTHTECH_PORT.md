# adw_sdlc — HealthTech standalone port

This package is a port of the **ADW (Agentic Developer Workflow) SDLC** control plane from the
`mx-agent` monorepo into the HealthTech project. It drives a GitHub issue through a phased,
multi-agent software-delivery pipeline:

```
setup → classify → plan → implement → tests → resolve(loop) → e2e(gated)
      → review → patch(loop) → document(gated) → finalize → ci-fix(loop) → merge → report
```

The orchestrator owns **all** git/gh and withholds secrets from the agent (deny-by-default env
allowlist); each phase runs on one of four interchangeable runner backends
(`claude` | `codex` | `opencode` | `pi`) behind a single `AgentRunner.runPhase()` seam. See
[`PLAN.md`](./PLAN.md) for the full architecture and [`PARITY.md`](./PARITY.md) for the parity
checklist.

## What changed for the standalone HealthTech port

The original was a pnpm-workspace member with a sibling Python `adw/` engine. This port is
**TypeScript-only and self-contained**. Changes from upstream:

| Area | Upstream (mx-agent) | HealthTech port |
| --- | --- | --- |
| Default engine | `--engine py` (delegates to `python3 adw/issue.py`) | **`--engine ts`** (the Python sibling is not bundled; `py` stays selectable but fails loudly) |
| Test gate (`DEFAULT_TEST_CMD`) | `cargo test --all` | **empty** — skipped until configured (set `MX_AGENT_TEST_CMD`) |
| Pre-merge gates (`DEFAULT_FINALIZE_GATES`) | hardcoded `cargo fmt/clippy/build` | **empty/configurable** via `MX_AGENT_FINALIZE_GATES` (newline-separated); empty repo can merge |
| Branch prefixes (`TYPE_PREFIX`) | `type:bug`/`type:docs`/… | also maps HealthTech's plain labels (`bug`, `docs`, `tech-debt`, `infra`, …), case-insensitive |
| Branch slugs | ASCII only | **de-accented** (French issue titles slug cleanly) |
| Phase preamble | "mx-agent ADW pipeline… Python performs all git/gh" | engine-neutral ("the ADW pipeline… the orchestrator performs all git/gh") |
| Conditional-gate hints | mx-agent vocab (ipc, daemon, matrix…) | + HealthTech domain (crypto, encryption, auth, consent, qr, offline…) |
| Prompt templates (`.claude/commands`, `.pi/prompts`) | Rust/Cargo + Matrix/daemon context | rewritten for HealthTech (local-first / zero-knowledge, AES-256-GCM, ARTCI, ≤500 KB, PRD/BACKLOG context) |

The **cross-language state contract** is preserved at `../adw/state.schema.json` (+ fixtures under
`../adw/fixtures/cross_language/`) — JSON-only, no Python code.

## Status

- `npm install && npm run typecheck` → clean.
- `npm test` → **320 tests pass** (24 files).
- `npm run lint:env` → secret-withholding lint gate passes.

## Usage

```bash
cd adw_sdlc
npm install

# Preview the plan for issue #N (no runner SDK needed):
npx tsx src/cli.ts <N> --dry-run

# Run the full pipeline on issue #N with the claude runner:
MX_AGENT_TEST_CMD="<your test command>" \
  npx tsx src/cli.ts <N> --runner claude --yes
```

Requires `gh` authenticated for the `kortiene/HealthTech` repo. Set a runner credential
(e.g. `ANTHROPIC_API_KEY`) for the selected runner. Optionally set `PROJECT_NUMBER=2` so the
setup phase can move the issue's card on the GitHub Project board.

## Test gate (stack chosen — see `docs/adr/`)

Backlog #1 is decided: a polyglot monorepo — Rust `crypto-core` + `backend` (one cargo workspace),
Kotlin/Android `app-patient`, Preact/TS PWA `app-medecin`. The pipeline test gate:

- **`MX_AGENT_TEST_CMD="just test"`** — a justfile target aggregating `cargo test --workspace` + the web
  `vitest` + the Android `gradlew test`. Until the monorepo + justfile are scaffolded (#2), use the
  concrete first gate **`cargo test --workspace`** (the Rust workspace lands first).
- **`MX_AGENT_FINALIZE_GATES`** (newline-separated) for extra pre-merge gates, e.g.
  `cargo fmt --check`, `cargo clippy --all-targets -- -D warnings`, `cargo deny check`.

These go live once #2 scaffolds the harness; until then the empty default correctly skips the gate.
