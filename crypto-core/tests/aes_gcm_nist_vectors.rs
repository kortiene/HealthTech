//! Public-API conformance & robustness tests for `crypto-core` (issue #10).
//!
//! These exercise the **stable public API** (`encrypt_record` / `decrypt_record`) and the
//! frozen `nonce || ciphertext || tag` wire format. They complement the exact-match NIST
//! known-answer tests that live in the crate's internal `#[cfg(test)]` module (those need a
//! deterministic, caller-chosen nonce, which is crate-internal by design).
//!
//! Run by the canonical gate: `cargo test --workspace` (a.k.a. `just test` → `just
//! test-rust`). A failing vector turns the build red.

use crypto_core::{
    decrypt_record, derive_key, encrypt_record, generate_master_key, wipe, CryptoError, KEY_LEN,
    NONCE_LEN, OVERHEAD_LEN, TAG_LEN,
};

// Pull in the shared vector table (see tests/vectors/PROVENANCE.md for provenance).
#[path = "vectors/nist_aes256gcm.rs"]
mod vectors;

fn hexd(s: &str) -> Vec<u8> {
    hex::decode(s).expect("valid hex")
}

fn key32(s: &str) -> [u8; 32] {
    hexd(s).try_into().expect("32-byte key")
}

/// gcmDecrypt256 PASS through the PUBLIC decrypt path: reconstruct the module's wire
/// format `iv || ciphertext || tag` for each empty-AAD NIST vector and assert
/// `decrypt_record` recovers the exact plaintext.
#[test]
fn public_decrypt_matches_nist_empty_aad_vectors() {
    for v in vectors::EMPTY_AAD_VECTORS {
        let key = key32(v.key);

        let mut blob = hexd(v.iv);
        blob.extend_from_slice(&hexd(v.ciphertext));
        blob.extend_from_slice(&hexd(v.tag));

        let recovered = decrypt_record(&key, &blob).expect(v.name);
        assert_eq!(
            recovered,
            hexd(v.plaintext),
            "{}: plaintext mismatch",
            v.name
        );
    }
}

/// gcmDecrypt256 FAIL through the public path: a single flipped tag bit must be rejected
/// with `Decrypt` and never return plaintext.
#[test]
fn public_decrypt_rejects_tampered_nist_vectors() {
    for v in vectors::EMPTY_AAD_VECTORS {
        let key = key32(v.key);

        let mut blob = hexd(v.iv);
        blob.extend_from_slice(&hexd(v.ciphertext));
        blob.extend_from_slice(&hexd(v.tag));
        let last = blob.len() - 1;
        blob[last] ^= 0x01;

        assert_eq!(
            decrypt_record(&key, &blob),
            Err(CryptoError::Decrypt),
            "{}: tampered blob must be rejected",
            v.name
        );
    }
}

/// The output is exactly `nonce (12) || ciphertext (= plaintext len) || tag (16)`, and the
/// detached ciphertext+tag round-trips when re-prefixed with its nonce.
#[test]
fn wire_format_layout_and_overhead() {
    let key = generate_master_key();
    let plaintext = b"dossier patient";
    let blob = encrypt_record(&key, plaintext).expect("encrypt");

    // 28-byte overhead = 12 nonce + 16 tag — the budget #9/#15 must reserve.
    assert_eq!(blob.len(), OVERHEAD_LEN + plaintext.len());

    // Recompose nonce || (ct || tag) and decrypt.
    let (nonce, ct_tag) = blob.split_at(NONCE_LEN);
    let mut recomposed = nonce.to_vec();
    recomposed.extend_from_slice(ct_tag);
    assert_eq!(
        decrypt_record(&key, &recomposed).expect("decrypt"),
        plaintext
    );
}

// --- G6: input robustness -----------------------------------------------------------

#[test]
fn empty_plaintext_round_trips() {
    let key = generate_master_key();
    let blob = encrypt_record(&key, b"").expect("encrypt empty");
    // No ciphertext bytes — just nonce + tag.
    assert_eq!(blob.len(), OVERHEAD_LEN);
    assert!(decrypt_record(&key, &blob)
        .expect("decrypt empty")
        .is_empty());
}

#[test]
fn blob_of_exactly_overhead_is_legal_empty_record() {
    // A blob of nonce+tag length with no ciphertext is the valid empty-plaintext case.
    let key = generate_master_key();
    let blob = encrypt_record(&key, b"").expect("encrypt");
    assert_eq!(blob.len(), OVERHEAD_LEN);
    assert!(decrypt_record(&key, &blob).is_ok());
}

#[test]
fn wrong_key_is_rejected() {
    let key = generate_master_key();
    let other = generate_master_key();
    let blob = encrypt_record(&key, b"secret record").expect("encrypt");
    assert_eq!(decrypt_record(&other, &blob), Err(CryptoError::Decrypt));
}

#[test]
fn truncated_ciphertext_is_rejected() {
    let key = generate_master_key();
    let blob = encrypt_record(&key, b"some longer plaintext payload").expect("encrypt");
    let truncated = &blob[..blob.len() - 1];
    assert_eq!(decrypt_record(&key, truncated), Err(CryptoError::Decrypt));
}

#[test]
fn extended_ciphertext_is_rejected() {
    let key = generate_master_key();
    let mut blob = encrypt_record(&key, b"some longer plaintext payload").expect("encrypt");
    blob.push(0x00); // append a stray byte
    assert_eq!(decrypt_record(&key, &blob), Err(CryptoError::Decrypt));
}

#[test]
fn blob_shorter_than_nonce_is_rejected() {
    let key = generate_master_key();
    for len in 0..NONCE_LEN {
        let short = vec![0u8; len];
        assert_eq!(decrypt_record(&key, &short), Err(CryptoError::Decrypt));
    }
}

#[test]
fn record_at_500kb_budget_round_trips() {
    // The PRD caps a plaintext record at ≤ 500 KB; prove the module handles the boundary.
    let key = generate_master_key();
    let plaintext = vec![0x5Au8; 500 * 1024];
    let blob = encrypt_record(&key, &plaintext).expect("encrypt 500 KB");
    assert_eq!(blob.len(), OVERHEAD_LEN + plaintext.len());
    assert_eq!(
        decrypt_record(&key, &blob).expect("decrypt 500 KB"),
        plaintext
    );
}

/// Blobs in [NONCE_LEN, OVERHEAD_LEN) carry a nonce but no complete GCM tag.
/// Every such length must be rejected with Decrypt — not succeed or panic.
///
/// `blob_shorter_than_nonce_is_rejected` covers 0..NONCE_LEN; the empty-plaintext
/// round-trip covers exactly OVERHEAD_LEN (28). This closes the gap for 12–27.
#[test]
fn blob_between_nonce_len_and_overhead_len_is_rejected() {
    let key = generate_master_key();
    for len in NONCE_LEN..OVERHEAD_LEN {
        let short = vec![0u8; len];
        assert_eq!(
            decrypt_record(&key, &short),
            Err(CryptoError::Decrypt),
            "len {len}: blob with nonce but incomplete/absent tag must be rejected"
        );
    }
}

/// Flipping a byte inside the ciphertext body (indices NONCE_LEN..blob.len()-TAG_LEN)
/// must cause authentication failure. This proves the GCM tag covers the ciphertext
/// itself — not only the 16 tag bytes at the end.
#[test]
fn tampered_ciphertext_body_is_rejected() {
    let key = generate_master_key();
    // Encrypt enough plaintext to have at least one ciphertext byte to tamper.
    let plaintext = b"dossier: groupe O-negatif, allergie penicilline";
    let mut blob = encrypt_record(&key, plaintext).expect("encrypt");
    // Wire layout: nonce[0..NONCE_LEN] || ct[NONCE_LEN..blob.len()-TAG_LEN] || tag[..]
    let ct_start = NONCE_LEN;
    let ct_end = blob.len() - TAG_LEN;
    assert!(
        ct_end > ct_start,
        "test requires at least one ciphertext byte"
    );
    blob[ct_start] ^= 0xFF; // flip bits in the first ciphertext byte
    assert_eq!(decrypt_record(&key, &blob), Err(CryptoError::Decrypt));
}

/// Flipping a byte in the nonce portion (indices 0..NONCE_LEN) of a well-formed blob
/// must cause authentication failure. GCM's GHASH and CTR counter are both seeded from
/// the nonce, so a wrong nonce produces a wholly different keystream and GHASH result.
#[test]
fn tampered_nonce_is_rejected() {
    let key = generate_master_key();
    let mut blob = encrypt_record(&key, b"patient dossier").expect("encrypt");
    blob[0] ^= 0x01; // flip one bit in the first nonce byte
    assert_eq!(decrypt_record(&key, &blob), Err(CryptoError::Decrypt));
}

// --- generate_master_key -----------------------------------------------------------

/// Two consecutive calls must return distinct 32-byte arrays (CSPRNG freshness guard).
/// The probability that two independent 256-bit random values collide is 2^-256 — if this
/// test ever fails, the OS CSPRNG is broken, not the code.
#[test]
fn generate_master_key_produces_distinct_outputs() {
    let k1 = generate_master_key();
    let k2 = generate_master_key();
    assert_ne!(k1, k2, "two consecutive master keys must differ");
    assert_eq!(k1.len(), KEY_LEN);
    assert_eq!(k2.len(), KEY_LEN);
}

// --- derive_key sensitivity --------------------------------------------------------

/// Different salts under the same passphrase and iteration count must yield different keys.
/// Proves the salt is actually mixed into PBKDF2 (regression guard for #12).
#[test]
fn derive_key_is_sensitive_to_salt() {
    let key_a = derive_key(b"passphrase", b"salt-A", 1000);
    let key_b = derive_key(b"passphrase", b"salt-B", 1000);
    assert_ne!(
        key_a, key_b,
        "different salts must yield different derived keys"
    );
}

/// Different passphrases under the same salt and iteration count must yield different keys.
#[test]
fn derive_key_is_sensitive_to_passphrase() {
    let key_a = derive_key(b"correct horse battery staple", b"salt", 1000);
    let key_b = derive_key(b"incorrect horse battery staple", b"salt", 1000);
    assert_ne!(
        key_a, key_b,
        "different passphrases must yield different derived keys"
    );
}

/// An empty passphrase is a valid (if weak) PBKDF2 input — must not panic.
#[test]
fn derive_key_accepts_empty_passphrase() {
    let key = derive_key(b"", b"some-salt", 1000);
    assert_eq!(key.len(), KEY_LEN);
}

/// An empty salt is a valid (if discouraged) PBKDF2 input — must not panic.
#[test]
fn derive_key_accepts_empty_salt() {
    let key = derive_key(b"passphrase", b"", 1000);
    assert_eq!(key.len(), KEY_LEN);
}

// --- wipe edge cases ---------------------------------------------------------------

/// Wiping an empty slice must be a no-op and must not panic.
#[test]
fn wipe_empty_slice_is_noop() {
    let mut empty: Vec<u8> = Vec::new();
    wipe(&mut empty); // must not panic
}

/// Wiping a buffer that is not KEY_LEN (e.g. an AAD or nonce buffer) must zero it fully.
#[test]
fn wipe_arbitrary_length_buffer() {
    let mut buf = vec![0xDEu8; 37]; // arbitrary non-KEY_LEN length
    wipe(&mut buf);
    assert!(
        buf.iter().all(|&b| b == 0),
        "wipe must zero every byte regardless of length"
    );
}

// --- CryptoError surface -----------------------------------------------------------

/// Both error variants must produce a non-empty human-readable Display string.
/// Tests the `impl Display for CryptoError` without coupling to exact wording.
#[test]
fn crypto_error_display_is_non_empty() {
    let rng_msg = format!("{}", CryptoError::Rng);
    let dec_msg = format!("{}", CryptoError::Decrypt);
    assert!(
        !rng_msg.is_empty(),
        "CryptoError::Rng Display must be non-empty"
    );
    assert!(
        !dec_msg.is_empty(),
        "CryptoError::Decrypt Display must be non-empty"
    );
    // The messages must differ so a caller can at least log distinct failure modes.
    assert_ne!(rng_msg, dec_msg);
}

// --- No-oracle property ------------------------------------------------------------

/// Wrong key, tampered tag, and truncated blob must all return the SAME error variant
/// (`CryptoError::Decrypt`). A caller must never be able to distinguish the failure cause —
/// this closes the padding/error-oracle attack surface (G2 / threat model #6).
#[test]
fn all_auth_failures_return_same_indistinguishable_error() {
    let key = generate_master_key();
    let other_key = generate_master_key();
    let blob = encrypt_record(&key, b"dossier medical confidentiel").expect("encrypt");

    // Wrong key
    let e_wrong_key = decrypt_record(&other_key, &blob).unwrap_err();
    // Tampered GCM tag (last byte)
    let mut tampered_tag = blob.clone();
    *tampered_tag.last_mut().unwrap() ^= 0xFF;
    let e_tampered_tag = decrypt_record(&key, &tampered_tag).unwrap_err();
    // Truncated blob (removes the last tag byte)
    let truncated = &blob[..blob.len() - 1];
    let e_truncated = decrypt_record(&key, truncated).unwrap_err();

    assert_eq!(
        e_wrong_key,
        CryptoError::Decrypt,
        "wrong key must give Decrypt"
    );
    assert_eq!(
        e_tampered_tag,
        CryptoError::Decrypt,
        "tampered tag must give Decrypt"
    );
    assert_eq!(
        e_truncated,
        CryptoError::Decrypt,
        "truncated blob must give Decrypt"
    );
    // All three are the same variant — no differentiation possible for the caller.
    assert_eq!(e_wrong_key, e_tampered_tag);
    assert_eq!(e_wrong_key, e_truncated);
}

// --- Plaintext edge cases ----------------------------------------------------------

/// A single-byte plaintext must round-trip correctly and produce the expected wire layout.
#[test]
fn single_byte_plaintext_round_trips() {
    let key = generate_master_key();
    let plaintext = b"\x42";
    let blob = encrypt_record(&key, plaintext).expect("encrypt 1 byte");
    assert_eq!(
        blob.len(),
        OVERHEAD_LEN + 1,
        "1-byte plaintext blob must be OVERHEAD_LEN + 1"
    );
    assert_eq!(
        decrypt_record(&key, &blob).expect("decrypt 1 byte"),
        plaintext
    );
}

/// An all-zero plaintext round-trips correctly. GCM operates as a stream cipher and
/// produces non-zero ciphertext even for zero-filled input (cipher independence guard).
#[test]
fn all_zero_plaintext_round_trips() {
    let key = generate_master_key();
    let plaintext = vec![0u8; 64];
    let blob = encrypt_record(&key, &plaintext).expect("encrypt all-zero");
    assert_eq!(blob.len(), OVERHEAD_LEN + 64);

    let recovered = decrypt_record(&key, &blob).expect("decrypt all-zero");
    assert_eq!(recovered, plaintext);

    // The ciphertext region (blob[NONCE_LEN..blob.len()-TAG_LEN]) must not be all-zero:
    // if it were, the keystream would be trivially recoverable.
    let ct_region = &blob[NONCE_LEN..blob.len() - TAG_LEN];
    assert!(
        ct_region.iter().any(|&b| b != 0),
        "AES-GCM ciphertext of all-zero plaintext must not itself be all-zero"
    );
}
