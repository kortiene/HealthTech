//! Decrypt performance REGRESSION gate (issue #27, G2/G4).
//!
//! This is the build-failing half of the crypto-core perf gate: it rides
//! `cargo test --workspace` (the `rust` CI job) so a regression on the
//! AES-256-GCM decrypt hot path blocks merge ("régression bloquée en CI").
//!
//! It is deliberately a GENEROUS, order-of-magnitude guard, NOT a tight SLA:
//! the threshold ([`DECRYPT_BUDGET_MS`]) is set far above the observed decrypt
//! time (see the reporting bench, `benches/decrypt_record.rs`, and the measured
//! numbers in docs/perf/decryption-budget.md), so it catches structural
//! regressions — an accidental O(n²), or the recovery KDF (PBKDF2, ~10⁵–10⁶
//! iterations ⇒ hundreds of ms) wrongly wired onto the decrypt path — without
//! flaking on shared-runner jitter. The precise, stable defence for the network
//! term is the deterministic blob-size guard on the Dart side.
//!
//! [`DECRYPT_BUDGET_MS`] MIRRORS `PerfBudget.decryptBudgetMs`
//! (app-patient/lib/src/record/perf_budget.dart). Rust cannot read Dart — keep
//! the two equal; the single source of truth is docs/perf/decryption-budget.md.
//!
//! SECURITY: synthetic filler payload, ephemeral in-test key, no disk writes;
//! this asserts on timing only and never inspects or logs plaintext/keys.

use std::time::Instant;

use crypto_core::{
    decrypt_record, encrypt_record, generate_master_key, NONCE_LEN, OVERHEAD_LEN, TAG_LEN,
};

/// Generous median-decrypt ceiling (ms) for the worst-case blob. Mirrors
/// `PerfBudget.decryptBudgetMs`. See the module docs for why it is generous.
const DECRYPT_BUDGET_MS: u128 = 100;

/// Transferred-blob size ceiling from the 3G budget model (128 Kio on the wire),
/// mirroring `PerfBudget.maxCompressedBlobBytes`. The worst-case decrypt input.
const MAX_BLOB_BYTES: usize = 131072;

// ── Compile-time cross-language sync guards ────────────────────────────────────
// Rust cannot read Dart. These `const` assertions are the CI-checkable enforcement
// of the mirror obligation documented in the module-level doc comment. A compile
// error here means: update the matching constant in
// app-patient/lib/src/record/perf_budget.dart (or vice-versa) so both sides agree.

const _: () = assert!(
    OVERHEAD_LEN == 28,
    "OVERHEAD_LEN changed — update PerfBudget.aesGcmOverheadBytes in perf_budget.dart",
);
const _: () = assert!(
    MAX_BLOB_BYTES == 131_072,
    "MAX_BLOB_BYTES changed — update PerfBudget.maxCompressedBlobBytes in perf_budget.dart",
);
const _: () = assert!(
    DECRYPT_BUDGET_MS == 100,
    "DECRYPT_BUDGET_MS changed — update PerfBudget.decryptBudgetMs in perf_budget.dart",
);

/// Median-of-N so a single scheduling hiccup on a shared runner cannot fail the
/// build; N is odd so the median is a real sample.
const ITERATIONS: usize = 51;

/// Warm-up runs (not measured) to prime caches/branch predictors.
const WARMUP: usize = 5;

#[test]
fn worst_case_decrypt_median_is_within_budget() {
    // Build a worst-case blob (128 Kio on the wire) of synthetic filler.
    let key = generate_master_key();
    let mut payload = vec![0u8; MAX_BLOB_BYTES - OVERHEAD_LEN];
    for (i, b) in payload.iter_mut().enumerate() {
        *b = (i * 31 + 7) as u8;
    }
    let blob = encrypt_record(&key, &payload).expect("seal worst-case fixture");
    assert_eq!(
        blob.len(),
        MAX_BLOB_BYTES,
        "fixture blob must be exactly the size ceiling"
    );

    for _ in 0..WARMUP {
        decrypt_record(&key, &blob).expect("warm-up decrypt");
    }

    let mut samples_us = Vec::with_capacity(ITERATIONS);
    for _ in 0..ITERATIONS {
        let start = Instant::now();
        let plaintext = decrypt_record(&key, &blob).expect("decrypt");
        std::hint::black_box(plaintext.first().copied().unwrap_or(0));
        samples_us.push(start.elapsed().as_micros());
    }
    samples_us.sort_unstable();
    let median_us = samples_us[samples_us.len() / 2];
    let median_ms = median_us / 1000;

    assert!(
        median_us < DECRYPT_BUDGET_MS * 1000,
        "worst-case AES-256-GCM decrypt median {median_us} µs (~{median_ms} ms) \
         exceeds the {DECRYPT_BUDGET_MS} ms budget. This is an order-of-magnitude \
         regression on the scan→display hot path (e.g. a KDF wrongly on the \
         decrypt path, or an accidental O(n²)) — see \
         docs/perf/decryption-budget.md.",
    );
}

/// Sanity: a round-trip on the worst-case fixture still returns the exact bytes.
/// Guards against a "fast but wrong" regression that trades correctness for speed.
#[test]
fn worst_case_decrypt_round_trips() {
    let key = generate_master_key();
    let payload: Vec<u8> = (0..(MAX_BLOB_BYTES - OVERHEAD_LEN))
        .map(|i| (i * 31 + 7) as u8)
        .collect();
    let blob = encrypt_record(&key, &payload).expect("seal");
    let recovered = decrypt_record(&key, &blob).expect("decrypt");
    assert_eq!(
        recovered, payload,
        "decrypt must recover the exact plaintext"
    );
    // Recovered payload must be non-empty (guards against a "succeed but return nothing" path).
    assert!(!recovered.is_empty(), "decrypted result must be non-empty");
}

/// Cross-language constant sync (Rust ↔ Dart): assert numeric values match the
/// Dart mirrors documented in the module comment. A test failure means the two
/// sides have drifted and both must be updated together.
///
/// Tests here are redundant with the `const _: ()` compile-time assertions above
/// for compile-time-checkable values, but are included as `#[test]` items so
/// failures surface as named test failures in CI output (easier to diagnose).
#[test]
fn cross_language_constants_match_dart_perf_budget() {
    // OVERHEAD_LEN = NONCE_LEN + TAG_LEN, wire-format frozen by #10.
    // Mirrors PerfBudget.aesGcmOverheadBytes in perf_budget.dart.
    assert_eq!(
        NONCE_LEN + TAG_LEN,
        OVERHEAD_LEN,
        "OVERHEAD_LEN must equal NONCE_LEN + TAG_LEN (wire-format contract frozen by #10)",
    );
    assert_eq!(
        OVERHEAD_LEN, 28,
        "OVERHEAD_LEN changed — update PerfBudget.aesGcmOverheadBytes in perf_budget.dart",
    );

    // MAX_BLOB_BYTES mirrors PerfBudget.maxCompressedBlobBytes.
    assert_eq!(
        MAX_BLOB_BYTES, 131_072,
        "MAX_BLOB_BYTES changed — update PerfBudget.maxCompressedBlobBytes in perf_budget.dart",
    );

    // DECRYPT_BUDGET_MS mirrors PerfBudget.decryptBudgetMs.
    assert_eq!(
        DECRYPT_BUDGET_MS, 100,
        "DECRYPT_BUDGET_MS changed — update PerfBudget.decryptBudgetMs in perf_budget.dart",
    );
}
