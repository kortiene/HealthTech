//! # crypto-core
//!
//! The **single** place AES/PBKDF2 logic exists for the whole HealthTech platform
//! (ADR 0003). Encryption is client-side and the server only ever holds opaque
//! ciphertext (zero-knowledge). Every client — the Flutter patient app (via
//! `flutter_rust_bridge`), the doctor PWA (via WASM), and the backend test harness
//! — calls only the high-level functions exposed here.
//!
//! Platform crypto (`javax.crypto`, WebCrypto AES, ...) is explicitly forbidden:
//! a second implementation would be a second audit surface and a zero-knowledge risk.
//!
//! ## Wire format of [`encrypt_record`]
//! `nonce (12 bytes) || ciphertext || GCM tag (16 bytes)`. The 96-bit nonce is random
//! per call and prepended; [`decrypt_record`] splits it back off.
//!
//! ## Scope of this scaffold
//! Issue #2 (greenfield structure). The cipher wiring below is REAL and round-trips,
//! but the NIST gating vectors and the PBKDF2 device calibration are deferred — see the
//! `TODO(#10)` / `TODO(#12)` markers in the test module.
#![forbid(unsafe_code)]
#![deny(warnings)]

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use pbkdf2::pbkdf2_hmac;
use sha2::Sha256;
use zeroize::Zeroize;

/// AES-256 key length in bytes.
pub const KEY_LEN: usize = 32;
/// AES-GCM nonce length in bytes (96-bit, the recommended GCM nonce size).
pub const NONCE_LEN: usize = 12;

/// Errors surfaced across the FFI / WASM boundary. Kept intentionally coarse so no
/// secret-dependent detail leaks to callers.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CryptoError {
    /// The OS CSPRNG (`getrandom`) failed to produce randomness.
    Rng,
    /// AEAD open failed: wrong key, tampered ciphertext, or a malformed/short blob.
    Decrypt,
}

impl core::fmt::Display for CryptoError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            CryptoError::Rng => f.write_str("secure RNG failure"),
            CryptoError::Decrypt => f.write_str("decryption failed (bad key, tag, or blob)"),
        }
    }
}

impl std::error::Error for CryptoError {}

/// Generate a fresh random 256-bit master key from the OS CSPRNG.
///
/// Callers are responsible for sealing this with platform key storage
/// (Android Keystore, etc., per ADR 0003 — storage is the only platform-specific code)
/// and for [`wipe`]-ing the copy once sealed.
pub fn generate_master_key() -> [u8; KEY_LEN] {
    let mut key = [0u8; KEY_LEN];
    // Panics only if the OS has no entropy source at all, which is unrecoverable.
    getrandom::getrandom(&mut key).expect("OS CSPRNG unavailable");
    key
}

/// Encrypt a record with AES-256-GCM under `key`.
///
/// A fresh random 96-bit nonce is generated and **prepended** to the output:
/// `nonce || ciphertext || tag`. No associated data is bound in this minimal API;
/// `TODO(#11)` will add an AAD channel for record metadata (record id / version).
pub fn encrypt_record(key: &[u8; KEY_LEN], plaintext: &[u8]) -> Result<Vec<u8>, CryptoError> {
    let mut nonce_bytes = [0u8; NONCE_LEN];
    getrandom::getrandom(&mut nonce_bytes).map_err(|_| CryptoError::Rng)?;

    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));
    let nonce = Nonce::from_slice(&nonce_bytes);
    let ciphertext = cipher
        .encrypt(nonce, Payload { msg: plaintext, aad: &[] })
        // Encryption only errors on absurd input sizes; treat as RNG-class failure.
        .map_err(|_| CryptoError::Rng)?;

    let mut out = Vec::with_capacity(NONCE_LEN + ciphertext.len());
    out.extend_from_slice(&nonce_bytes);
    out.extend_from_slice(&ciphertext);
    Ok(out)
}

/// Decrypt a `nonce || ciphertext || tag` blob produced by [`encrypt_record`].
///
/// Returns [`CryptoError::Decrypt`] for any blob shorter than the nonce, a wrong key,
/// or a failed authentication tag — without distinguishing the cases (no oracle).
pub fn decrypt_record(key: &[u8; KEY_LEN], blob: &[u8]) -> Result<Vec<u8>, CryptoError> {
    if blob.len() < NONCE_LEN {
        return Err(CryptoError::Decrypt);
    }
    let (nonce_bytes, ciphertext) = blob.split_at(NONCE_LEN);

    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));
    let nonce = Nonce::from_slice(nonce_bytes);
    cipher
        .decrypt(nonce, Payload { msg: ciphertext, aad: &[] })
        .map_err(|_| CryptoError::Decrypt)
}

/// Derive a 256-bit key from a passphrase via PBKDF2-HMAC-SHA256.
///
/// `salt` is public by design and stored alongside the record; `iterations` is
/// benchmarked per device class and stored too, so it is forward-tunable (ADR 0003).
///
/// `TODO(#12)`: calibrate the default iteration count on entry-level Android (Infinix
/// SoC class) and evaluate Argon2id if the PRD's "PBKDF2" wording is relaxed.
pub fn derive_key(passphrase: &[u8], salt: &[u8], iterations: u32) -> [u8; KEY_LEN] {
    let mut key = [0u8; KEY_LEN];
    pbkdf2_hmac::<Sha256>(passphrase, salt, iterations, &mut key);
    key
}

/// Overwrite a secret buffer in place so it cannot be recovered from freed memory.
///
/// Uses `zeroize` to defeat the compiler's dead-store elimination.
pub fn wipe(secret: &mut [u8]) {
    secret.zeroize();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encrypt_decrypt_round_trip() {
        let key = generate_master_key();
        let plaintext = b"patient record: blood type O-, allergy: penicillin";

        let blob = encrypt_record(&key, plaintext).expect("encrypt");
        // Nonce must be prepended, so the blob is strictly longer than the plaintext.
        assert!(blob.len() > NONCE_LEN + plaintext.len() - 1);

        let recovered = decrypt_record(&key, &blob).expect("decrypt");
        assert_eq!(recovered, plaintext);
    }

    #[test]
    fn decrypt_rejects_tampered_blob() {
        let key = generate_master_key();
        let mut blob = encrypt_record(&key, b"sensitive").expect("encrypt");
        let last = blob.len() - 1;
        blob[last] ^= 0x01; // flip a bit in the GCM tag
        assert_eq!(decrypt_record(&key, &blob), Err(CryptoError::Decrypt));
    }

    #[test]
    fn decrypt_rejects_short_blob() {
        let key = generate_master_key();
        assert_eq!(decrypt_record(&key, &[0u8; 4]), Err(CryptoError::Decrypt));
    }

    #[test]
    fn derive_key_is_deterministic() {
        // Same inputs => same key; this is a smoke test, NOT a gating vector.
        let a = derive_key(b"correct horse", b"salt-1234", 1000);
        let b = derive_key(b"correct horse", b"salt-1234", 1000);
        assert_eq!(a, b);
        let c = derive_key(b"correct horse", b"salt-1234", 1001);
        assert_ne!(a, c);
    }

    #[test]
    fn wipe_zeroes_buffer() {
        let mut secret = [0xABu8; KEY_LEN];
        wipe(&mut secret);
        assert_eq!(secret, [0u8; KEY_LEN]);
    }

    // TODO(#10): Add the official NIST AES-GCM (CAVP gcmEncryptExtIV / gcmDecrypt)
    //            known-answer vectors as GATING CI tests — decode them with the `hex`
    //            dev-dependency and assert exact ciphertext + tag for fixed key/nonce.
    // TODO(#12): Add the RFC 6070 / NIST PBKDF2-HMAC-SHA256 known-answer vectors as
    //            GATING CI tests so `derive_key` is proven against the spec, not just
    //            self-consistent. Per ADR 0003 these vectors gate the build.
}
