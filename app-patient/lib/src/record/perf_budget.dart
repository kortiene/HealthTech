// Decryption-pipeline performance budget (issue #27 — NFR §5).
//
// PRD §5 sets a hard non-functional requirement: after a doctor scans a
// patient's QR code, the record must be downloaded, decrypted, and displayed on
// the doctor's screen in ≤ 3 s under STABLE 3G coverage.
//
// This file is the SINGLE SOURCE OF TRUTH for the numeric budget model that
// turns "≤ 3 s" into a set of checkable inequalities. It is documented in full
// (reference-profile citation, derivation, the "never weaken crypto to hit the
// number" rule) in docs/perf/decryption-budget.md — keep the two in sync.
//
// The model DECOMPOSES the 3 s cap into:
//   * a network term modelled analytically from the reference 3G profile, and
//     bounded deterministically by a compressed-blob SIZE ceiling
//     ([maxCompressedBlobBytes], enforced by blob_size_budget_test.dart);
//   * CPU terms bounded by generous, order-of-magnitude guard thresholds
//     ([decryptBudgetMs] in crypto-core, [pipelineCpuBudgetMs] in Dart);
//   * a coarse render allowance.
//
// CI runners cannot reproduce a real 3G radio, so the network term is NOT timed
// in CI — it is proxied by the size ceiling. Real wall-clock is validated
// out-of-band (docs/perf/measurement-protocol.md).

/// Performance-budget constants for the scan → display decryption pipeline.
abstract final class PerfBudget {
  // ── Reference "stable 3G" profile (3G-STABLE) ────────────────────────────
  //
  // A single, documented reference profile the whole gate hangs off. Chosen
  // conservatively: above UMTS R99 (384 kbit/s) and well below HSPA peak
  // (several Mbit/s), and deliberately higher than the 100–300 kbit/s *unstable*
  // Edge/3G that #24 tuned retry/backoff against — "stable 3G" (UMTS/HSPA in
  // good coverage) is a faster, steadier link. See docs/perf/decryption-budget.md
  // for the citation and the rationale.

  /// Application-layer goodput of the reference profile, in bits per second.
  static const int stable3gGoodputBitsPerSec = 750000; // 750 kbit/s

  /// Round-trip time of the reference profile, in milliseconds.
  static const int stable3gRttMs = 150;

  // ── End-to-end budget ────────────────────────────────────────────────────

  /// Hard end-to-end cap: scan → record displayed (PRD §5 NFR).
  static const int totalBudgetMs = 3000;

  /// Safety reserve held back from [totalBudgetMs] for runner/device/link
  /// variance. The modelled stage sum targets `totalBudgetMs - safetyReserveMs`.
  static const int safetyReserveMs = 600;

  // ── Per-stage allowances (modelled) ──────────────────────────────────────

  /// Connection setup + first-byte latency allowance (~2×RTT: request +
  /// first byte, assuming a warm/reused connection after handshake).
  static const int connSetupMs = 2 * stable3gRttMs; // 300 ms

  /// Coarse deserialize → widget-ready render allowance. Deep Flutter frame /
  /// jank profiling is #28/#29 scope and is out of this budget.
  static const int renderAllowanceMs = 400;

  // ── CPU guard thresholds (generous, order-of-magnitude) ──────────────────
  //
  // These are anti-regression GUARDS, not tight SLAs: set far above observed
  // timings so they catch order-of-magnitude regressions (an accidental O(n²),
  // a KDF wrongly on the hot path, a lost compression step) without flaking on
  // shared-runner jitter. The primary, fully-deterministic defence is the
  // blob-size ceiling below.

  /// Guard ceiling (ms) for the real AES-256-GCM decrypt of the worst-case
  /// blob. Enforced by `crypto-core/tests/decrypt_perf_regression.rs`, which
  /// mirrors this value (Rust cannot read Dart — keep them equal).
  static const int decryptBudgetMs = 100;

  /// Guard ceiling (ms) for the in-process Dart CPU chain
  /// (decrypt → decompress → deserialize). Enforced by
  /// `test/perf/decrypt_pipeline_perf_test.dart`. The decrypt in that test is a
  /// fake (real AES decrypt is covered by [decryptBudgetMs] in Rust), so this
  /// effectively bounds gzip-decompress + JSON-deserialize of a worst-case
  /// (~500 Kio plaintext) record.
  static const int pipelineCpuBudgetMs = 500;

  // ── Wire-format overhead ──────────────────────────────────────────────────

  /// Fixed AES-256-GCM wire overhead in bytes: prepended 12-byte nonce +
  /// appended 16-byte tag (crypto-core `OVERHEAD_LEN`, frozen by #10). Counted
  /// against [maxCompressedBlobBytes] because the transferred blob carries it.
  static const int aesGcmOverheadBytes = 28;

  // ── Derived size ceiling (G3) ─────────────────────────────────────────────

  /// Largest transferred (compressed + encrypted) blob, in bytes, whose
  /// modelled transfer time over the reference profile keeps the whole pipeline
  /// within [totalBudgetMs] with the safety reserve intact. This is the
  /// DETERMINISTIC proxy for the network term and the primary CI gate for it.
  /// Enforced by `test/record/blob_size_budget_test.dart`.
  ///
  /// Derivation (see docs/perf/decryption-budget.md): with the modelled
  /// allowances above summing to ~1000 ms of non-transfer time and a 600 ms
  /// reserve, ~1400 ms remains for transfer; `1400 ms × 750 kbit/s ÷ 8 ≈
  /// 131 250 bytes`, rounded down to a clean 128 Kio.
  static const int maxCompressedBlobBytes = 131072; // 128 Kio

  // ── Model helpers ─────────────────────────────────────────────────────────

  /// Modelled transfer time (ms) for a blob of [bytes] over the reference
  /// profile: `bytes × 8 / goodput`.
  static double modelledTransferMs(int bytes) =>
      bytes * 8 * 1000 / stable3gGoodputBitsPerSec;

  /// Modelled end-to-end time (ms) for a blob of [bytes] evaluated at the
  /// GUARD ceilings (worst permitted CPU): connection setup + transfer + real
  /// decrypt budget + Dart CPU-chain budget + render allowance. Used by the
  /// self-consistency test to prove the chosen thresholds still fit under
  /// [totalBudgetMs].
  static double modelledTotalAtCeilingsMs(int bytes) =>
      connSetupMs +
      modelledTransferMs(bytes) +
      decryptBudgetMs +
      pipelineCpuBudgetMs +
      renderAllowanceMs;
}
