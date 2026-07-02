# Decryption performance budget — scan → display ≤ 3 s on stable 3G (issue #27)

> **NFR (PRD §5).** After a doctor scans a patient's QR code, the record must be
> **downloaded, decrypted, and displayed on the doctor's screen in ≤ 3 s under
> stable 3G coverage.** This is the felt-speed promise behind Dr. Koné's persona
> (US-2.1) — 30 patients/day, no time to waste.

This document is the **single source of truth** for the budget model that turns
"≤ 3 s" into a set of checkable inequalities, plus the reference network profile
everything hangs off. The numeric constants live in code and mirror this doc:

| Constant | Code location |
|---|---|
| profile, allowances, thresholds, size ceiling | `app-patient/lib/src/record/perf_budget.dart` (`PerfBudget`) |
| `DECRYPT_BUDGET_MS`, `MAX_BLOB_BYTES` (Rust mirror) | `crypto-core/tests/decrypt_perf_regression.rs` |

**Keep this doc and those constants in sync.**

## Why the budget is decomposed

Hosted CI runners **cannot reproduce a real 3G radio** deterministically — a gate
that depends on physical network conditions is flaky and non-reproducible. So the
3 s cap is split into:

1. a **network transfer term**, modelled analytically from the reference profile
   and bounded deterministically by a **compressed-blob size ceiling** (the CI
   proxy for the network — `test/record/blob_size_budget_test.dart`);
2. **CPU terms** (AES-256-GCM decrypt, gzip decompress, JSON deserialize) bounded
   by generous, order-of-magnitude guard thresholds measured deterministically in
   CI (`crypto-core/tests/decrypt_perf_regression.rs`,
   `app-patient/test/perf/decrypt_pipeline_perf_test.dart`);
3. a coarse **render allowance** (deep Flutter frame profiling is #28/#29 scope).

The physical, real-device wall-clock is validated **out-of-band** and recorded
here as evidence — see [`measurement-protocol.md`](./measurement-protocol.md) and
[§ Field measurements](#field-measurements-g5). It is never in the CI gate.

## Reference profile — `3G-STABLE`

A single named profile, chosen **conservatively**:

```
3G-STABLE = { goodput = 750 kbit/s (application-layer), rtt = 150 ms }
```

- **Goodput 750 kbit/s.** Above UMTS R99 (384 kbit/s), well below HSPA peak
  (several Mbit/s). This is *stable* 3G (UMTS/HSPA in good coverage) — a faster,
  steadier link than the **unstable Edge/3G at 100–300 kbit/s** that issue #24
  tuned gzip + exponential-backoff retry against. Two different regimes, on
  purpose: #24 hardens the *degraded* case; #27 gates the *stable-3G* NFR.
  Sources: ITU-R IMT-2000 / 3GPP UMTS-HSPA class figures; to be re-anchored to
  **Ivorian field goodput** during the pilot (#31, see Open Questions).
- **RTT 150 ms.** Representative UMTS/HSPA round-trip in good coverage.

> **Decision status:** these numbers are the agreed working reference for the
> gate. They are revisited against real Ivorian field data before the pilot
> (#31); a change here re-derives `MAX_BLOB_BYTES` and is a documented profile
> change — **never** a reason to weaken crypto (see below).

## Budget decomposition

```
T_total = T_conn_setup + T_transfer(blob) + T_decrypt + T_decompress
          + T_deserialize + T_render                              ≤ 3000 ms

where  T_transfer(blob) = blob_bytes × 8 / goodput
```

We hold back a **600 ms safety reserve**, so the modelled realistic sum targets
**≤ 2400 ms**, and we require that even at every *generous guard ceiling* the sum
stays **≤ 3000 ms**.

| Term | Allowance | Notes |
|---|---|---|
| `T_conn_setup` | **300 ms** | ≈ 2 × RTT (request + first byte, warm connection). |
| `T_transfer(MAX_BLOB)` | **≈ 1398 ms** | `131072 B × 8 / 750 kbit/s`. Bounded by the size ceiling below. |
| `T_decrypt` (guard) | **≤ 100 ms** | Real AES-256-GCM of the worst-case blob. `DECRYPT_BUDGET_MS`. |
| `T_decompress + T_deserialize` (guard) | **≤ 500 ms** | Dart CPU chain. `pipelineCpuBudgetMs`. |
| `T_render` | **400 ms** | Coarse deserialize → widget-ready allowance. |

**Self-consistency (checked in code, `blob_size_budget_test.dart`):**
`300 + 1398 + 100 + 500 + 400 = 2698 ms ≤ 3000 ms` — even at all CPU **guard
ceilings** we clear the cap with ~300 ms of margin. The realistic modelled sum
(observed CPU ≪ the guards, see below) is well under 2400 ms.

### Derived size ceiling — `MAX_BLOB_BYTES = 131 072 B (128 Kio)`

The transferred blob is `AES-256-GCM(gzip(plaintext))` (frozen by #10/#24). With
~1000 ms of non-transfer allowance and the 600 ms reserve, ~1400 ms remains for
transfer; `1400 ms × 750 kbit/s ÷ 8 ≈ 131 250 B`, rounded **down** to a clean
128 Kio. Modelled transfer at the ceiling is `131072 × 8 / 750000 ≈ 1398 ms`.

This ceiling is the **primary, fully-deterministic CI defence** for the network
term: `test/record/blob_size_budget_test.dart` drives a worst-case ~500 Kio
synthetic record through the real `MedicalRecordStore.write` path and asserts the
produced blob (+ the fixed 28-byte AES overhead) ≤ `MAX_BLOB_BYTES`. A schema
bloat (#15) or a lost/broken compression step (#24) blows past it and fails the
build. It **complements** the plaintext ≤ 500 Kio `RecordSizeGuard` (#15): that
bounds decrypt/deserialize *work*; this bounds transfer *time*.

## Measured CPU numbers (deterministic, in-CI)

Generous guards, not tight SLAs — set far above observed timings so they catch
**order-of-magnitude** regressions (an accidental O(n²); the recovery PBKDF2 KDF
— 10⁵–10⁶ iterations, hundreds of ms — wrongly wired onto the decrypt hot path)
without flaking on shared-runner jitter.

| Measurement | Fixture | Guard threshold | Observed (dev, see below) |
|---|---|---|---|
| Rust `decrypt_record` median | worst-case 128 Kio blob | `DECRYPT_BUDGET_MS = 100 ms` | sub-millisecond (AES-NI); run `cargo bench -p crypto-core` to refresh |
| Dart parse→decrypt→decompress→deserialize median | worst-case ~500 Kio record | `pipelineCpuBudgetMs = 500 ms` | tens of ms on dev hardware |
| `MedicalRecordStore.write` blob (compressed+encrypted) | worst-case ~500 Kio synthetic record | `MAX_BLOB_BYTES = 128 Kio` | **~47.9 Kio on-wire** (503 816 B plaintext → 9.5 % gzip ratio), macOS dev, 2026-07-01 |

The Rust p50/p95 are produced by the **reporting bench**
`crypto-core/benches/decrypt_record.rs` (`cargo bench -p crypto-core`); it is
off the required fast path. Refresh these rows when re-running on the CI runner
class or the reference device lab (#29).

## Field measurements (G5)

Real wall-clock under a throttled link / emulator / device, per
[`measurement-protocol.md`](./measurement-protocol.md). **Manual / periodic —
never CI-gated.** Populate before the pilot (#31); this table is evidence for the
ARTCI homologation dossier (#30) that NFR §5 is met.

| Date | Surface | Link profile | p50 | p95 | Notes |
|---|---|---|---|---|---|
| _pending_ | app-patient (Flutter) | `3G-STABLE` (netem 750 kbit/s, 150 ms) | — | — | run the protocol before #31 |
| _pending_ | app-medecin (PWA) | `3G-STABLE` (DevTools throttle) | — | — | **blocked** on #17 WASM decrypt |

## Security & compliance — never weaken crypto to hit the number

This is a **measurement + gate** issue (#27). It changes **no** cryptography: the
AES-256-GCM path, the GCM authentication tag, nonce handling, and the PBKDF2
parameters are untouched. If a measurement ever shows the budget is missed, the
fix is **optimisation elsewhere** (e.g. compressing the QR session blob — see
below) or a **documented profile change** — **never** dropping authentication,
truncating the tag, or lowering KDF cost to "hit the number." Benches/tests use
**synthetic, non-nominative** fixtures and ephemeral in-test keys; they emit
**sizes and timings only** (never record contents, keys, or nonces) and write
nothing to disk. The zero-knowledge boundary and data-residency posture (ARTCI /
loi n°2013-450) are unaffected — measurement is entirely client-side.

## Scope, open questions & follow-ups

- **QR session blob is currently *uncompressed*.** `AccessTokenService`
  (`app-patient/lib/src/qr/access_token.dart`) re-encrypts the record with the
  session key **without** gzip, and `ScanService.fetchAndDecrypt` does not
  decompress. So the doctor's session download is *not* bounded by
  `MAX_BLOB_BYTES` today — only the patient-backup `MedicalRecordStore` path is.
  Compressing the session path is an **optimisation** (out of #27's measure+gate
  scope, per the spec Non-Goals) and should be a follow-up so the doctor
  scan→display transfer is actually inside the modelled budget. The pipeline
  timing test therefore measures the `MedicalRecordStore.read` chain, which is
  the production code path that performs every budgeted CPU stage
  (decrypt → gzip decompress → deserialize).
- **PWA decrypt path does not exist yet.** `app-medecin` has no WASM crypto
  (`session.ts`, `TODO(#17)`). This spec does **not** benchmark it. When #17's
  WASM decrypt lands, add a mirror perf test + a DevTools-throttling row above.
- **CI hardware variance.** Mitigated by generous order-of-magnitude thresholds,
  warm-up + median-of-N, and — primarily — the deterministic size guard.
- **Bench framework.** A std-only harness (no criterion) keeps the supply-chain
  surface (`cargo deny` / osv) and `Cargo.lock` unchanged; criterion is
  deliberately not on the required fast path (ADR 0003).
- **Which surface is the homologation target?** Today the real scan/decrypt is
  Flutter (`app-patient/lib/src/doctor/`); the product doctor UI is the PWA. Likely
  both eventually — Flutter now, PWA after #17-WASM.
