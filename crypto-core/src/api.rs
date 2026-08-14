// FRB 2.x public API surface for the crypto-core crate (#102, ADR 0003).
//
// This module is the ONLY thing exposed across the flutter_rust_bridge FFI.
// All crypto logic remains in lib.rs (AES-256-GCM / PBKDF2 / CSPRNG).
//
// Naming convention: Rust snake_case → Dart camelCase (FRB auto-converts).
//   - CryptoHandle methods → handle.methodName() in Dart
//   - Free functions → topLevelFunction() in Dart
//
// Error surface: Result<T, String> — FRB throws an Exception with the message.
// The message is deliberately coarse (mirrors CryptoError — no oracle, #10).

use crate::{
    decrypt_record as rust_decrypt, encrypt_record as rust_encrypt,
    normalize_recovery_answers as rust_normalize, open_recovery_envelope,
    seal_recovery_envelope, MasterKeyHandle, KEY_LEN,
};

// ── Opaque handle ─────────────────────────────────────────────────────────────

/// Opaque Rust-side master-key handle.
///
/// Dart holds only a pointer; the 256-bit AES key lives in Rust RAM and is
/// zeroized by Zeroizing<> on Drop. The clear key crosses the FFI boundary
/// exactly once — through [export_sealable] — for immediate hardware sealing.
///
/// FRB 2.x treats this as opaque automatically because it holds a non-serializable
/// type (Zeroizing<[u8; 32]>). No `#[frb(opaque)]` annotation is needed.
pub struct CryptoHandle {
    inner: MasterKeyHandle,
}

impl CryptoHandle {
    /// Generate a fresh 256-bit master key from the OS CSPRNG.
    ///
    /// Panics only if the OS has no entropy source (unrecoverable).
    pub fn generate() -> CryptoHandle {
        CryptoHandle {
            inner: MasterKeyHandle::generate(),
        }
    }

    /// Re-wrap hardware-unsealed clear bytes back into a handle.
    ///
    /// Returns Err if `bytes` is not exactly [KEY_LEN] bytes.
    /// The caller must wipe `bytes` after this call.
    pub fn from_clear_bytes(bytes: Vec<u8>) -> Result<CryptoHandle, String> {
        if bytes.len() != KEY_LEN {
            return Err(format!(
                "expected {} key bytes, got {}",
                KEY_LEN,
                bytes.len()
            ));
        }
        let mut arr = [0u8; KEY_LEN];
        arr.copy_from_slice(&bytes);
        Ok(CryptoHandle {
            inner: MasterKeyHandle::from_unsealed(arr),
        })
    }

    /// Export the clear key bytes for immediate hardware sealing (G8).
    ///
    /// This is the one sanctioned point where the clear key crosses the FFI.
    /// The caller must pass the result straight to the Keystore shim and never
    /// persist, log, or transmit it.
    pub fn export_sealable(&self) -> Vec<u8> {
        self.inner.export_sealable().to_vec()
    }

    /// Encrypt [plaintext] with AES-256-GCM. Returns `nonce(12) || ct || tag(16)`.
    pub fn encrypt_record(&self, plaintext: Vec<u8>) -> Result<Vec<u8>, String> {
        rust_encrypt(self.inner.key_ref(), &plaintext).map_err(|e| e.to_string())
    }

    /// Decrypt a blob produced by [encrypt_record].
    ///
    /// Returns Err on a bad key, wrong tag, or corrupted blob — coarse, no oracle.
    pub fn decrypt_record(&self, blob: Vec<u8>) -> Result<Vec<u8>, String> {
        rust_decrypt(self.inner.key_ref(), &blob).map_err(|e| e.to_string())
    }

    /// Zeroize the master key inside this handle (G5). Consumes the handle.
    ///
    /// Drop already calls Zeroizing's destructor; this consuming method makes the
    /// "use then wipe" contract explicit at every call site.
    pub fn wipe(self) {
        // `self` is moved and dropped; Zeroizing<> overwrites the key in place.
        drop(self);
    }
}

// ── Recovery envelope ─────────────────────────────────────────────────────────

/// Seal [master_key_clear] under a PBKDF2-derived recovery key (#12, G2).
///
/// [master_key_clear] must be exactly [KEY_LEN] bytes (the clear master key).
/// [secret] is the passphrase or output of [normalize_answers].
/// [iterations] is clamped to the minimum floor internally.
/// Returns the self-describing envelope bytes.
pub fn seal_recovery(
    master_key_clear: Vec<u8>,
    secret: Vec<u8>,
    iterations: u32,
) -> Result<Vec<u8>, String> {
    if master_key_clear.len() != KEY_LEN {
        return Err(format!(
            "master key must be {} bytes, got {}",
            KEY_LEN,
            master_key_clear.len()
        ));
    }
    let mut arr = [0u8; KEY_LEN];
    arr.copy_from_slice(&master_key_clear);
    seal_recovery_envelope(&arr, &secret, iterations).map_err(|e| e.to_string())
}

/// Open a recovery envelope and return the master key handle (#12, G1).
///
/// Throws on wrong secret, corrupted envelope, or unknown version/KDF
/// — coarse error, no oracle (THR-05).
pub fn open_recovery(
    secret: Vec<u8>,
    envelope: Vec<u8>,
) -> Result<CryptoHandle, String> {
    open_recovery_envelope(&secret, &envelope)
        .map(|inner| CryptoHandle { inner })
        .map_err(|e| e.to_string())
}

/// Normalize and concatenate security-question answers for PBKDF2 (G6).
///
/// Delegates to the Rust normalize_recovery_answers function: lowercase,
/// diacritic-fold, drop punctuation, join with Unit Separator. Deterministic.
pub fn normalize_answers(answers: Vec<String>) -> Vec<u8> {
    let refs: Vec<&str> = answers.iter().map(|s| s.as_str()).collect();
    rust_normalize(&refs)
}
