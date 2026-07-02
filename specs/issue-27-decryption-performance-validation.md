# Validation des performances — déchiffrement + affichage < 3 s en 3G (issue #27)

## Problem Statement

The PRD sets a hard non-functional requirement (§5): after a doctor scans a
patient's QR code, the record must be **downloaded, decrypted, and displayed on
the doctor's screen in ≤ 3 seconds under stable 3G coverage**. This is the
felt-speed promise behind Dr. Koné's persona (30 patients/day, no time to
waste) and behind US-2.1.

Today the *functional* pipeline exists (scan → GET blob → decrypt in RAM →
deserialize → render, `ScanService` + `MedicalRecordStore`, issues #17/#24) and
#24 shipped the two enablers that make the target reachable (gzip-before-encrypt
+ exponential-backoff retry). What is **missing** is the thing issue #27 asks
for:

1. a **reproducible measurement bench** that confirms the 3 s target is actually
   met, and
2. a **CI regression gate** that fails the build if a future change pushes the
   pipeline back over budget.

Without (2), the target can silently regress (a heavier schema, a slower KDF on
the hot path, an accidental disk write, a dropped compression step) and nobody
notices until the field pilot (#31).

The core difficulty: **CI runners cannot reproduce a real 3G radio.** A gate
that depends on physical network conditions is non-deterministic and flaky. The
spec below resolves this by *decomposing* the 3 s budget into a
CPU/size-bounded part that CI **can** measure deterministically, plus a
physical-transfer part that is **modeled analytically** from a documented,
agreed "stable 3G" reference profile and **verified out-of-band** on throttled
links / real devices.

## Goals

1. **G1 — Budget model.** Define and document the end-to-end latency budget as a
   decomposition of measurable stages, anchored to a single documented "stable
   3G" reference profile (throughput + RTT), so "≤ 3 s" becomes a checkable
   inequality rather than a vibe.
2. **G2 — Reproducible bench.** Provide a deterministic, re-runnable benchmark
   for the CPU-bound stages (AES-256-GCM decrypt, gzip decompress, JSON
   deserialize) on representative fixtures (a full ~500 Kio plaintext record and
   its compressed blob), reporting stable percentile timings.
3. **G3 — Size budget guard.** Assert that the transferred (compressed,
   encrypted) blob stays under a ceiling derived from the budget model, so the
   *modeled* transfer time over the reference 3G profile stays within budget.
   This is the deterministic proxy for the network term.
4. **G4 — CI regression gate.** Wire G2 + G3 into `just` and CI so a regression
   past the thresholds fails the pipeline (acceptance criterion: "régression
   bloquée en CI").
5. **G5 — Out-of-band field protocol.** Document a reproducible procedure to
   measure the *real* wall-clock (throttled link / emulator / device) and record
   the observed numbers, so the analytical model is validated against reality
   (feeds the pilot #31 and the ARTCI/perf evidence).

## Non-Goals

- **Optimising** the pipeline further. #24 already delivered compression +
  retry. #27 is *measure + gate*, not *make faster*. If a measurement shows the
  budget is missed, that spawns a follow-up optimisation issue — it is not fixed
  here.
- **Real on-device 3G in CI.** Hosted GitHub runners cannot emulate a cellular
  radio deterministically; physical-link measurement stays out-of-band (G5).
- **Doctor-PWA (`app-medecin`) decrypt benchmarking.** The PWA WASM decrypt path
  is still `TODO(#17)` (`app-medecin/src/session.ts` has *no* crypto wired yet).
  Benchmarking it is out of scope until that path exists; this spec must not
  imply it does. A hook is left for it (see Risks).
- **UI render micro-profiling** (Flutter frame/jank analysis, #28/#29 territory)
  beyond a coarse "deserialize → widget-ready" allowance in the budget.
- **Media/heavy-image latency.** Radiographies are never on-device; only an
  ephemeral URL sits in the text record (#23). Fetching the image is a separate,
  post-display action and is out of the "scan → record displayed" budget.

## Relevant Repository Context

**Stack is finalised (backlog #1 is resolved for the affected packages).**
Despite the backlog's greenfield note, ADRs already fix the toolchain, so this
spec names concrete tech rather than leaving it open:

- **ADR 0001** — patient app: **Flutter/Dart 3.x** (`app-patient/`).
- **ADR 0002** — doctor interface: **Preact + TypeScript PWA** (`app-medecin/`).
- **ADR 0003** — **`crypto-core/`**: the single Rust crypto crate (AES-256-GCM +
  PBKDF2), consumed by Flutter via FFI/FRB and by the PWA via WASM. RustCrypto
  `aes-gcm = "0.10"`. No `[[bench]]`/criterion harness exists yet.
- **ADR 0004** — backend: Rust/Axum, zero-knowledge blob store (#9).

**The measured pipeline (scan → display), as it exists today:**

| Stage | Code | Nature |
|---|---|---|
| QR parse + expiry check | `app-patient/lib/src/doctor/scan_service.dart` (`ScanService.parseQr`) | CPU, trivial |
| GET `/blob/{uuid}` | `app-patient/lib/src/cloud/backend_client.dart` (+ `NetworkRetry`, #24) | **network (3G)** |
| Wrap session key | `ScanService.fetchAndDecrypt` → `crypto_core_bindings.dart` `handleFromUnsealed` | CPU, trivial |
| AES-256-GCM decrypt (RAM) | `crypto-core` `decryptRecord` via FRB | CPU |
| gzip decompress | `app-patient/lib/src/record/plaintext_compressor.dart` `decodeIfCompressed` (#24) | CPU |
| JSON deserialize | `MedicalRecord.fromJson` (`record/medical_record.dart`) | CPU |
| Wipe key handle | `crypto.wipe(handle)` in `finally` | CPU, trivial |
| Render | `app-patient/lib/src/ui/record_view_screen.dart` | UI |

Relevant existing anchors:
- **`RecordSizeGuard`** (`record/record_size_guard.dart`, #15) enforces the
  ≤ 500 Kio *plaintext* budget — the upper bound on decrypt/deserialize work.
- **`PlaintextCompressor`** (#24) — gzip magic-byte detection; the transferred
  blob is `AES-256-GCM(gzip(plaintext))`.
- **`consultation_loop_harness.dart`** (`test/support/`) — shared fakes wiring
  the real #16→#19 services; a natural base for an end-to-end timing test.

**CI / task-runner conventions:**
- `justfile`: `just test` is the canonical ADW gate (aggregates
  `test-rust`, `test-web`, `test-flutter`, plus `*-scripts` self-tests);
  `just lint` aggregates the doc/guardrail checkers. Bash guardrail scripts live
  in `scripts/` and each has a synthetic-fixture self-test (`scripts/test-*.sh`).
- `.github/workflows/ci.yml`: per-package jobs (`rust`, `web`, `flutter`, …)
  fan into a single required `ci-success` check. `flutter` runs on
  `ubuntu-latest`, Flutter pinned `3.41.5`; `rust` uses stable + `rust-cache`.
- **Convention to mirror:** guardrails are *deterministic, credential-free, and
  self-tested*. The perf gate must follow the same shape (a self-tested checker,
  not a flaky wall-clock assertion).

**Still open (decisions to confirm — see Risks):** the exact numeric "stable 3G"
reference profile; the Rust bench framework (criterion vs a std harness); the
absolute CPU-time thresholds (must tolerate CI hardware variance); and the
out-of-band throttling tool for G5.

## Proposed Implementation

### Overview

Split "≤ 3 s" into a **budget model** (documented) + three artefacts: a **Rust
decrypt bench** (G2), a **Flutter end-to-end pipeline timing test** (G2/G4), and
a **blob-size budget guard** (G3), all wired into a `just perf` recipe and CI
(G4). Physical-link timing (G5) is a documented manual protocol whose results
are recorded in a perf report doc — never in the CI gate.

### A — Budget model & reference profile (`docs/perf/decryption-budget.md`)

Author a document that defines:

- **Reference "stable 3G" profile** — a single named constant, e.g.
  `3G-STABLE = { goodput: <X> kbps, rtt: <Y> ms }`. Pick a *defensible,
  conservative* value and cite the source. Note the tension with #24, which
  modelled *Edge/3G unstable* at 100–300 kbps; "stable 3G" (UMTS/HSPA) is
  higher. **This number is a decision to confirm (see Risks)** — the whole gate
  hangs off it, so it must be agreed and written down, not assumed silently.
- **Budget decomposition** (illustrative; fill with the agreed profile):

  ```
  T_total = T_rtt_setup + T_transfer(blob) + T_decrypt + T_decompress
            + T_deserialize + T_render   ≤ 3000 ms
  where T_transfer(blob) = blob_bytes * 8 / goodput_bps
  ```

- **Derived size ceiling** `MAX_BLOB_BYTES` — the largest compressed+encrypted
  blob whose modelled `T_transfer` still leaves headroom for the measured CPU +
  render terms under the 3 s cap (with an explicit safety margin, e.g. target
  ≤ 2.4 s modelled so 600 ms is reserved for variance). This ceiling is what G3
  enforces.
- The **measured** CPU numbers (from G2) and **field** numbers (from G5), kept
  up to date as evidence.

### B — Rust decrypt benchmark (G2) — `crypto-core/benches/decrypt_record.rs`

- Add a bench (criterion recommended for stable percentile stats; a plain
  `#[bench]`-style harness is an acceptable lower-dep fallback — decision to
  confirm). Add `criterion` under `[dev-dependencies]` and a `[[bench]]` entry
  with `harness = false` in `crypto-core/Cargo.toml` if criterion is chosen.
- Bench `decryptRecord` (and the `gzip → decrypt` inverse if the crate owns
  decompression; today gzip lives in Dart, so bench decrypt only) on:
  - a **worst-case** fixture: AES-256-GCM(gzip(500 Kio synthetic JSON)), and
  - a **typical** fixture (compressed blob ~80–120 Kio).
- Emit p50/p95. The bench is *reported*; the **assertion** lives in a
  regression test (below) so it can fail the build.
- **Regression assertion:** a `#[test]` (or a tiny `scripts/check-perf-budget`
  step that parses bench output) that decrypts the worst-case fixture N times
  and asserts median CPU time < `DECRYPT_BUDGET_MS`. Use a **generous** threshold
  (e.g. 3–5× the observed p95 on CI hardware) so it catches *order-of-magnitude*
  regressions (e.g. an accidental O(n²) or a KDF wrongly on the hot path)
  without flaking on runner jitter.

### C — Flutter end-to-end pipeline timing test (G2/G4) — `app-patient/test/perf/decrypt_pipeline_perf_test.dart`

- Using the `consultation_loop_harness` fakes (network stubbed to return a
  pre-encrypted worst-case blob instantly), time the **in-process** chain:
  `parseQr → fetchAndDecrypt (decrypt + wipe) → decodeIfCompressed →
  MedicalRecord.fromJson`.
- Assert wall-clock for the CPU chain < `PIPELINE_CPU_BUDGET_MS` (generous,
  margin-protected). The network term is **excluded** here (fake is instant) —
  it is covered by G3's size guard + the model.
- Warm-up iterations then measure median-of-N to damp JIT/GC noise. Keep it a
  standard `flutter test` (runs in the existing `flutter` CI job) — no new
  device/emulator dependency.

### D — Blob-size budget guard (G3) — deterministic

- Add a constant `maxCompressedBlobBytes` (from `docs/perf/decryption-budget.md`)
  next to the record pipeline (e.g. `record/record_size_guard.dart` or a new
  `record/perf_budget.dart`).
- Test: encrypt+compress the worst-case ~500 Kio plaintext fixture through the
  real `MedicalRecordStore.write` path and assert the produced blob ≤
  `maxCompressedBlobBytes`. This ties the *modelled* network time to a hard,
  deterministic check. If a schema change (#15) or a lost compression step
  blows the blob up, this fails.
- This complements — does not replace — the existing plaintext ≤ 500 Kio
  `RecordSizeGuard`.

### E — `just` recipes + CI wiring (G4)

- `justfile`: add `perf` recipe running the Rust bench-regression test + the
  Flutter perf test + the size guard test; add a `test-perf` self-test if a
  bash checker is introduced, mirroring the `test-*-scripts` convention.
- Fold perf assertions into the **existing** jobs where cheapest:
  the Rust regression `#[test]` runs under `cargo test --workspace` (already in
  the `rust` job); the Flutter perf test + size guard run under `flutter test`
  (already in the `flutter` job). Optionally surface a dedicated `just perf`
  step so failures are legible. **Avoid** a separate long criterion run in the
  required path (slow, noisy) — keep criterion as an on-demand/reporting bench
  and put only the cheap, generous-threshold assertions in the required gate.
- Ensure the aggregate `just test` (the ADW gate) transitively runs the
  assertions.

### F — Out-of-band field protocol (G5) — documented, not in CI

- Document (in `docs/perf/decryption-budget.md` or a sibling
  `docs/perf/measurement-protocol.md`) a reproducible procedure to measure real
  wall-clock under a throttled link, e.g.:
  - Android emulator / device with `tc qdisc … netem` or the emulator's network
    throttling set to the agreed 3G profile; run a scripted scan→display and
    record timings.
  - (When the PWA decrypt lands) Chrome DevTools network throttling for
    `app-medecin`.
- Record observed p50/p95 in the doc as evidence for the ARTCI/perf dossier and
  the pilot (#31). Explicitly label these as manual/periodic, not CI-gated.

## Affected Files / Packages / Modules

| File | Action |
|---|---|
| `docs/perf/decryption-budget.md` | **create** — budget model, reference 3G profile, derived ceilings, measured + field numbers |
| `docs/perf/measurement-protocol.md` | **create** (or fold into the above) — G5 manual protocol |
| `crypto-core/benches/decrypt_record.rs` | **create** — decrypt bench (worst-case + typical fixtures) |
| `crypto-core/Cargo.toml` | **modify** — add `criterion` dev-dep + `[[bench]]` (if criterion chosen) |
| `crypto-core/tests/decrypt_perf_regression.rs` | **create** — generous-threshold median-time assertion (the CI gate part) |
| `app-patient/test/perf/decrypt_pipeline_perf_test.dart` | **create** — in-process CPU-chain timing |
| `app-patient/lib/src/record/perf_budget.dart` | **create** — `maxCompressedBlobBytes` constant (or add to `record_size_guard.dart`) |
| `app-patient/test/record/blob_size_budget_test.dart` | **create** — real write-path blob ≤ ceiling |
| `app-patient/test/support/consultation_loop_harness.dart` | **read/possibly extend** — reuse fakes for the perf test |
| `justfile` | **modify** — add `perf` recipe; ensure `test`/`ci` cover the assertions |
| `.github/workflows/ci.yml` | **modify (light)** — optional explicit `just perf` step; otherwise assertions ride existing `rust`/`flutter` jobs |
| `BACKLOG.md` | **modify** — mark #27 progress |
| `PRD_HealthTech.md` | **read** — NFR §5 is the source of truth (no change expected) |

## API / Interface Changes

**None** to any public/product surface. No CLI, no network endpoint, no QR /
access-token change. New surfaces are internal only: a `just perf` recipe, a
Rust bench target, test files, and a `maxCompressedBlobBytes` constant.

## Data Model / Protocol Changes

**None.** The blob wire format is unchanged (`AES-256-GCM(gzip(plaintext))`,
frozen by #10/#24). This issue introduces a *derived* size ceiling
(`maxCompressedBlobBytes`) as a guard constant, but no record schema,
encrypted-blob layout, or serialization change. Fixtures used by benches/tests
are **synthetic** and must not alter production schemas.

## Security & Compliance Considerations

- **No crypto weakening.** Measurement only — the AES-256-GCM path, GCM auth
  tag, nonce handling, and PBKDF2 parameters are untouched. A perf gate must
  never tempt anyone to drop authentication or lower KDF cost to "hit the
  number"; if the budget is missed, the fix is optimisation elsewhere or a
  documented profile change, not weaker crypto. Call this out in the budget doc.
- **In-RAM-only decrypt preserved.** The Flutter perf test exercises the real
  `ScanService.fetchAndDecrypt` path, which wipes the Rust key handle in a
  `finally` and keeps plaintext on the heap only. Benches/tests must **not**
  write decrypted plaintext to disk or temp files.
- **No plaintext / key / PII in fixtures, logs, or bench output.** All fixtures
  are synthetic, non-nominative filler sized to the budget. Bench/test output
  may report **sizes and timings only** — never record contents, keys, or
  nonces. Test keys are ephemeral, generated in-test.
- **Zero-knowledge boundary unaffected.** No server-side change; the size guard
  operates client-side before upload. The server still stores an opaque blob
  keyed by an anonymous UUID.
- **Data residency (ARTCI / loi n°2013-450).** Measurement is local/client-side
  and introduces no new data flow or hosting dependency; residency posture is
  unchanged. The recorded perf evidence can feed the ARTCI homologation dossier
  (#30) as proof of the NFR being met.
- **≤ 500 Kio plaintext budget** is the anchor for the worst-case fixture; the
  new compressed-blob ceiling is derived from it. Keep both guards independent.
- **Ephemeral media** (#23): heavy images stay off-device (URL only) and are
  excluded from the scan-to-display budget — do not fetch them in the bench.

## Testing Plan

1. **Rust decrypt bench** (`decrypt_record.rs`): reports p50/p95 for worst-case
   (500 Kio) and typical fixtures. On-demand / reporting, not required-gate.
2. **Rust decrypt regression test** (`decrypt_perf_regression.rs`): median
   decrypt time on the worst-case fixture < `DECRYPT_BUDGET_MS` (generous,
   order-of-magnitude guard). Runs under `cargo test --workspace` → in CI.
3. **Flutter pipeline perf test** (`decrypt_pipeline_perf_test.dart`): in-process
   `parseQr → decrypt → decompress → deserialize` median wall-clock <
   `PIPELINE_CPU_BUDGET_MS`, network faked instant, warm-up + median-of-N.
4. **Blob-size budget test** (`blob_size_budget_test.dart`): real
   `MedicalRecordStore.write` on a ~500 Kio synthetic record produces a blob ≤
   `maxCompressedBlobBytes`.
5. **Threshold self-consistency**: a small doc/test note asserting the chosen
   thresholds are consistent with the budget model (modelled T_transfer at the
   ceiling + measured CPU budgets ≤ 3 s with margin).
6. **Existing suites stay green**: no regression to `medical_record_store_test`,
   `scan_service_test`, `consultation_loop_e2e_test`, crypto vectors.
7. **Out-of-band (manual, G5)**: run the throttled-link protocol; record
   observed numbers in the perf doc. Not part of `just test`.

## Documentation Updates

- **Create** `docs/perf/decryption-budget.md` (budget model, reference 3G
  profile + citation, derived ceilings, measured CPU + field numbers, the
  "never weaken crypto to hit the number" note).
- **Create/fold** `docs/perf/measurement-protocol.md` (G5 procedure).
- **Update** `BACKLOG.md` #27 with an *Avancement* note (what landed: model +
  bench + size guard + CI assertions; what remains: field measurement, PWA
  decrypt benchmarking once #17-WASM lands).
- **Consider** an ADR only if the reference 3G profile / bench-framework choice
  is contentious enough to warrant one (`docs/adr/`); otherwise the budget doc
  suffices.
- **Homologation (#30):** reference the perf evidence as proof of NFR §5 in the
  ARTCI dossier if/when the field numbers confirm the target.
- No PRD change (NFR §5 is already the source of truth).

## Risks and Open Questions

1. **Reference "stable 3G" number (blocking decision).** The entire gate is
   anchored to one goodput/RTT profile. #24 used Edge/3G unstable (100–300 kbps);
   "stable 3G" is higher (UMTS/HSPA, commonly ~384 kbps–2 Mbps goodput). **Must
   be agreed and documented** (product + a source, ideally Ivorian field data).
   Too optimistic → the gate passes but the field misses 3 s; too pessimistic →
   the size ceiling becomes infeasibly tight.
2. **CI hardware variance.** Wall-clock/CPU thresholds on shared runners are
   noisy. Mitigation: generous (order-of-magnitude) thresholds + median-of-N +
   warm-up; the *deterministic* blob-size guard (G3) is the primary, stable
   defence and the timing tests are a secondary safety net.
3. **Bench framework choice (decision to confirm).** criterion (better stats,
   extra dev-dep + SCA surface via `cargo deny`/osv) vs a minimal std harness
   (fewer deps, coarser stats). Keep criterion *out* of the required fast path
   regardless.
4. **PWA decrypt path does not exist yet.** `app-medecin` has no WASM crypto
   (`session.ts`, `TODO(#17)`). This spec deliberately does **not** benchmark it
   and must not imply it works. When #17's WASM decrypt lands, add a mirror perf
   test + a DevTools-throttling entry in the protocol (follow-up).
5. **Render term is coarse.** The budget reserves a fixed allowance for
   deserialize→widget-ready; deep Flutter frame profiling is #28/#29 scope. If
   render turns out to dominate on low-end devices (#29, Infinix), that is a
   separate optimisation issue.
6. **Model vs reality drift.** The analytical network term is only as good as
   the profile. G5 field measurement is what validates it; schedule it before
   the pilot (#31) and record the delta in the perf doc.
7. **Where does the "doctor screen" pipeline canonically live?** Today the real
   scan/decrypt is in `app-patient/lib/src/doctor/` (Flutter), while the
   product's doctor UI is the PWA (`app-medecin`). Confirm which surface the
   3 s target is measured on for homologation (likely both eventually; Flutter
   now, PWA after #17-WASM).

## Implementation Checklist

- [ ] Agree and document the **reference "stable 3G" profile** (goodput + RTT +
      source) in `docs/perf/decryption-budget.md` — unblock everything else.
- [ ] Write the **budget decomposition** and derive `MAX_BLOB_BYTES` /
      `DECRYPT_BUDGET_MS` / `PIPELINE_CPU_BUDGET_MS` with an explicit safety
      margin; add the "never weaken crypto" note.
- [ ] Add `maxCompressedBlobBytes` constant (`record/perf_budget.dart` or
      `record_size_guard.dart`) sourced from the doc.
- [ ] Create `app-patient/test/record/blob_size_budget_test.dart` — real
      write-path 500 Kio fixture → blob ≤ ceiling (deterministic gate).
- [ ] Create `app-patient/test/perf/decrypt_pipeline_perf_test.dart` — in-process
      CPU-chain median-of-N < `PIPELINE_CPU_BUDGET_MS`, network faked, using the
      consultation-loop harness fakes; synthetic data only, no disk writes.
- [ ] Create `crypto-core/benches/decrypt_record.rs` (worst-case + typical
      fixtures); add `criterion` dev-dep + `[[bench]] harness = false` to
      `crypto-core/Cargo.toml` (if criterion chosen).
- [ ] Create `crypto-core/tests/decrypt_perf_regression.rs` — generous-threshold
      median decrypt-time assertion (rides `cargo test --workspace`).
- [ ] Add `just perf` recipe; ensure `just test` / `just ci` transitively run
      the size guard + timing + regression assertions.
- [ ] (Optional) add an explicit `just perf` step to `.github/workflows/ci.yml`
      for legible failures; keep criterion off the required fast path.
- [ ] Write `docs/perf/measurement-protocol.md` (G5) and run it once
      (throttled emulator/device) — record observed p50/p95 in the budget doc.
- [ ] Verify existing suites stay green (`cargo test`, `flutter test`,
      `app-medecin` tests, crypto vectors); run `dart format` + `flutter
      analyze` + `cargo fmt --check` + `cargo clippy`.
- [ ] Update `BACKLOG.md` #27 *Avancement* (landed vs remaining: field
      measurement + PWA-decrypt benchmarking after #17-WASM).
