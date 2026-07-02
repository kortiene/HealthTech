//! Decrypt performance bench (issue #27, G2) — REPORTING ONLY.
//!
//! Measures the CPU cost of the AES-256-GCM `decrypt_record` step on the doctor
//! scan → display hot path, on two representative fixtures:
//!   * worst-case: a blob at the transferred-size ceiling
//!     (`MAX_BLOB_BYTES` ≈ 128 Kio — the largest compressed+encrypted record the
//!     3G budget model permits, see docs/perf/decryption-budget.md);
//!   * typical: a ~100 Kio compressed blob.
//!
//! It prints p50/p95 wall-clock per decrypt — evidence for the budget doc — and
//! does NOT assert anything. The build-failing, generous-threshold regression
//! assertion lives in `tests/decrypt_perf_regression.rs` (rides
//! `cargo test --workspace`); this bench stays off the required CI fast path
//! (spec §B/§E). Run on demand: `cargo bench -p crypto-core`.
//!
//! std-only harness (`harness = false`, no criterion) so the supply-chain
//! surface and Cargo.lock are unchanged (ADR 0003).
//!
//! SECURITY: fixtures are synthetic, non-nominative filler; keys are ephemeral,
//! generated in-process. Output is SIZES and TIMINGS only — never record
//! contents, keys, or nonces. Nothing is written to disk.

use std::time::Instant;

use crypto_core::{decrypt_record, encrypt_record, KEY_LEN, OVERHEAD_LEN};

/// Transferred-blob size ceiling from the 3G budget model (128 Kio on the wire).
const MAX_BLOB_BYTES: usize = 131072;

/// A "typical" compressed blob size (~100 Kio).
const TYPICAL_BLOB_BYTES: usize = 100 * 1024;

/// Decrypt iterations per fixture (median/p95 over this many samples).
const ITERATIONS: usize = 300;

/// Seal a synthetic filler payload under `key` so the resulting blob is exactly
/// `blob_bytes` on the wire. The bytes are non-nominative filler; their content
/// is irrelevant to GCM decrypt timing (avoids an all-zero page all the same).
fn fixture(key: &[u8; KEY_LEN], blob_bytes: usize) -> Vec<u8> {
    let mut payload = vec![0u8; blob_bytes - OVERHEAD_LEN];
    for (i, b) in payload.iter_mut().enumerate() {
        *b = (i * 31 + 7) as u8;
    }
    encrypt_record(key, &payload).expect("seal fixture")
}

/// Print median and p95 (ms) of decrypting `blob` under `key`, over `ITERATIONS`.
fn measure(label: &str, key: &[u8; KEY_LEN], blob: &[u8]) {
    let mut samples_us = Vec::with_capacity(ITERATIONS);
    for _ in 0..ITERATIONS {
        let start = Instant::now();
        let plaintext = decrypt_record(key, blob).expect("decrypt");
        // Prevent the optimiser from eliding the work; touch one byte.
        std::hint::black_box(plaintext.first().copied().unwrap_or(0));
        samples_us.push(start.elapsed().as_micros());
    }
    samples_us.sort_unstable();
    let p50 = samples_us[samples_us.len() / 2] as f64 / 1000.0;
    let p95 = samples_us[(samples_us.len() * 95) / 100] as f64 / 1000.0;
    println!(
        "{label:<8} blob={:>7} B  iters={ITERATIONS}  p50={p50:.3} ms  p95={p95:.3} ms",
        blob.len(),
    );
}

fn main() {
    println!("crypto-core decrypt_record bench (issue #27, G2) — timings only");

    // A single ephemeral key both fixtures are sealed under and measured with.
    let key = crypto_core::generate_master_key();

    let worst = fixture(&key, MAX_BLOB_BYTES);
    let typical = fixture(&key, TYPICAL_BLOB_BYTES);

    measure("worst", &key, &worst);
    measure("typical", &key, &typical);
}
