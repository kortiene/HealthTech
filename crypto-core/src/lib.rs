//! # crypto-core
//!
//! The **single** place AES-256-GCM / PBKDF2 logic exists for the whole HealthTech
//! platform (ADR 0003). Encryption is client-side and the server only ever holds opaque
//! ciphertext (zero-knowledge). Every client — the Flutter patient app (via
//! `flutter_rust_bridge`), the doctor PWA (via WASM), and the backend test harness —
//! calls only the high-level functions exposed here. Platform crypto (`javax.crypto`,
//! WebCrypto AES, ...) is explicitly forbidden: a second implementation would be a second
//! audit surface and a zero-knowledge risk.
//!
//! ## Stateless, no-I/O
//! This module performs **no I/O and keeps no state**: it never reads/writes disk, never
//! caches keys, never logs. That is what lets the doctor PWA decrypt purely in RAM (#17)
//! and lets a session be wiped on inactivity (#19). It also makes it trivially usable from
//! the offline SQLCipher queue (#21).
//!
//! ## Wire format (stable contract — frozen by #10)
//! [`encrypt_record`] returns:
//!
//! ```text
//! nonce (12 bytes) || ciphertext (= plaintext length) || GCM tag (16 bytes)
//! ```
//!
//! The 96-bit nonce is random per call and **prepended**; [`decrypt_record`] splits it
//! back off. The fixed overhead is **28 bytes** (12 nonce + 16 tag) — the storage budget
//! of #9/#15 (plaintext ≤ 500 KB) must account for it. This layout is a **persistence
//! contract** consumed by #9 (blob store), #14 (cloud backup), #16/#17 (QR / doctor scan)
//! and #21 (offline queue); it does not change without a coordinated migration.
//!
//! ### Format versioning (decision)
//! v1 of the wire format is exactly `nonce || ciphertext || tag` with **no version byte**,
//! to stay consistent with the 28-byte overhead already budgeted by the merged #9 blob
//! store. Future evolution (binding record metadata as AES-GCM associated data in #11, or
//! an algorithm change) is introduced **additively** — via a new function and/or a new,
//! self-describing format — never by silently re-interpreting these bytes. See
//! `docs/security/crypto-core-review.md` for the rationale and the cross-issue agreement.
//!
//! ## Nonce policy (G3)
//! - 96-bit nonce, **freshly random per call** from the OS CSPRNG (`getrandom`).
//! - A nonce is **never reused** under a given key: every new record gets a new nonce.
//!   There is no deterministic/counter nonce in this design.
//! - If the CSPRNG fails, [`encrypt_record`] returns [`CryptoError::Rng`] — it **never**
//!   falls back to a zero/degenerate nonce (which would reuse a nonce and break GCM).
//! - **Usage bound.** A random 96-bit nonce risks a birthday collision only after ≈ 2³²
//!   messages under the same key. HealthTech rewrites a single patient blob per
//!   consultation, so the real volume is many orders of magnitude below that bound — the
//!   random-nonce strategy is safe here without a counter.
//!
//! ## Error model (no oracle)
//! Errors are intentionally **coarse** ([`CryptoError`]): decryption never distinguishes a
//! wrong key from a tampered tag from a malformed blob. This denies an attacker a
//! padding/error oracle on the doctor or server side.
#![forbid(unsafe_code)]
#![deny(warnings)]

use aes_gcm::aead::{Aead, KeyInit, Payload};
use aes_gcm::{Aes256Gcm, Key, Nonce};
use pbkdf2::pbkdf2_hmac;
use sha2::Sha256;
use zeroize::{Zeroize, Zeroizing};

/// AES-256 key length in bytes.
pub const KEY_LEN: usize = 32;
/// AES-GCM nonce length in bytes (96-bit, the recommended GCM nonce size).
pub const NONCE_LEN: usize = 12;
/// AES-GCM authentication tag length in bytes (128-bit, full tag — never truncated).
pub const TAG_LEN: usize = 16;
/// Fixed wire-format overhead in bytes: prepended nonce + appended tag.
pub const OVERHEAD_LEN: usize = NONCE_LEN + TAG_LEN;

/// Errors surfaced across the FFI / WASM boundary. Kept intentionally coarse so no
/// secret-dependent detail leaks to callers (no padding/error oracle).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CryptoError {
    /// The OS CSPRNG (`getrandom`) failed, or the AEAD could not produce a sealed blob.
    /// Either way no ciphertext is returned and no degenerate nonce is ever emitted.
    Rng,
    /// AEAD open failed: wrong key, tampered ciphertext/tag, or a malformed/short blob.
    /// The cause is deliberately indistinguishable.
    Decrypt,
}

impl core::fmt::Display for CryptoError {
    fn fmt(&self, f: &mut core::fmt::Formatter<'_>) -> core::fmt::Result {
        match self {
            CryptoError::Rng => f.write_str("secure RNG / sealing failure"),
            CryptoError::Decrypt => f.write_str("decryption failed (bad key, tag, or blob)"),
        }
    }
}

impl std::error::Error for CryptoError {}

/// AES-256-GCM seal of `plaintext` under `key`/`nonce`, binding `aad`. Returns
/// `ciphertext || tag`. Private: the production API ([`encrypt_record`]) owns nonce
/// generation so a caller can never choose (and thus reuse) a nonce.
fn seal(
    key: &[u8; KEY_LEN],
    nonce: &[u8],
    aad: &[u8],
    plaintext: &[u8],
) -> Result<Vec<u8>, CryptoError> {
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));
    cipher
        .encrypt(
            Nonce::from_slice(nonce),
            Payload {
                msg: plaintext,
                aad,
            },
        )
        // GCM only errors when plaintext exceeds its ~64 GiB limit — unreachable for a
        // ≤ 500 KB record. Surfaced coarsely as an internal sealing failure, no oracle.
        .map_err(|_| CryptoError::Rng)
}

/// AES-256-GCM authenticated decrypt of `ciphertext_and_tag` under `key`/`nonce`, binding
/// `aad`. Returns [`CryptoError::Decrypt`] on any authentication failure — the single,
/// undifferentiated error variant (no oracle).
fn open(
    key: &[u8; KEY_LEN],
    nonce: &[u8],
    aad: &[u8],
    ciphertext_and_tag: &[u8],
) -> Result<Vec<u8>, CryptoError> {
    let cipher = Aes256Gcm::new(Key::<Aes256Gcm>::from_slice(key));
    cipher
        .decrypt(
            Nonce::from_slice(nonce),
            Payload {
                msg: ciphertext_and_tag,
                aad,
            },
        )
        .map_err(|_| CryptoError::Decrypt)
}

/// Generate a fresh random 256-bit master key from the OS CSPRNG.
///
/// Callers are responsible for sealing this with platform key storage
/// (Android Keystore, etc., per ADR 0003 — storage is the only platform-specific code)
/// and for [`wipe`]-ing the in-RAM copy once sealed.
pub fn generate_master_key() -> [u8; KEY_LEN] {
    let mut key = [0u8; KEY_LEN];
    // Panics only if the OS has no entropy source at all, which is unrecoverable.
    getrandom::getrandom(&mut key).expect("OS CSPRNG unavailable");
    key
}

/// In-RAM owner of the patient master key (root DEK), kept inside the Rust core (#11).
///
/// This is the opaque *handle* the FFI / `flutter_rust_bridge` surface hands to Dart
/// (ADR 0003 / ADR 0006). The 256-bit key it wraps is generated on-device by the OS
/// CSPRNG and **never leaves the device in clear** — it exists in clear only in RAM, only
/// for as long as this handle is alive.
///
/// ## Why a handle, not raw bytes (G8)
/// The clear key crossing the FFI boundary is a leak surface. By exposing a handle, Dart
/// holds only an opaque reference; the clear bytes cross the boundary exactly once, through
/// the explicitly named [`MasterKeyHandle::export_sealable`], whose only caller is the
/// immediate hardware-sealing step (Android Keystore StrongBox/TEE). The
/// [`zeroize::Zeroizing`] inner buffer is overwritten on `Drop`, so an abandoned handle
/// does not leave the key in freed memory (acceptance criterion #2 — no persistent leak).
///
/// The seal/unseal of the *clear* bytes by hardware is platform code (Kotlin/Swift); this
/// type is the device-agnostic Rust anchor for the key's lifetime. The hardware-sealed blob
/// is a separate, device-internal format and is **not** the [`encrypt_record`] wire format.
pub struct MasterKeyHandle {
    key: Zeroizing<[u8; KEY_LEN]>,
}

impl MasterKeyHandle {
    /// Generate a fresh master key from the OS CSPRNG, owned by this handle (G1).
    ///
    /// The key is produced inside the Rust core — never in Dart/Kotlin/Swift — and is held
    /// in a self-zeroizing buffer from the moment it exists.
    pub fn generate() -> Self {
        let mut key = [0u8; KEY_LEN];
        // Panics only if the OS has no entropy source at all, which is unrecoverable.
        getrandom::getrandom(&mut key).expect("OS CSPRNG unavailable");
        let handle = Self {
            key: Zeroizing::new(key),
        };
        // Wipe the transient stack copy; only the handle retains the key.
        key.zeroize();
        handle
    }

    /// Re-wrap clear bytes that hardware has just **unsealed** back into a handle (#14).
    ///
    /// The unseal path hands the Keystore-decrypted bytes straight back to the Rust core as
    /// a handle, used, then dropped (which zeroizes). Keeping the unsealed key inside a
    /// handle, not a loose buffer, bounds the post-unseal exposure window.
    pub fn from_unsealed(bytes: [u8; KEY_LEN]) -> Self {
        let mut bytes = bytes;
        let handle = Self {
            key: Zeroizing::new(bytes),
        };
        bytes.zeroize();
        handle
    }

    /// Export the clear key **for immediate hardware sealing only** (G8).
    ///
    /// This is the single sanctioned point where the clear master key crosses the FFI
    /// boundary. The caller (the Kotlin/Swift Keystore shim) must seal the returned bytes at
    /// once and drop them; the returned buffer is itself [`zeroize::Zeroizing`], so a dropped
    /// copy is overwritten. Do **not** persist, log, or transmit these bytes — by
    /// construction only the hardware-sealed blob is ever written to disk (G4).
    pub fn export_sealable(&self) -> Zeroizing<[u8; KEY_LEN]> {
        Zeroizing::new(*self.key)
    }

    /// Explicitly wipe and consume the handle (G5).
    ///
    /// Dropping the handle already zeroizes the inner buffer; this consuming method makes
    /// the "sealed → wipe the clear copy" step explicit and self-documenting at call sites
    /// and across the FFI surface.
    pub fn wipe(self) {
        // `self` is dropped here; `Zeroizing` overwrites the key in place.
    }

    /// Borrow the clear key for an in-RAM operation (test-only for now; #14 will expose the
    /// production borrow that wraps the SQLCipher DB key). The borrow stays within the
    /// handle's lifetime, so the key is never copied out.
    #[cfg(test)]
    fn expose_for_test(&self) -> &[u8; KEY_LEN] {
        &self.key
    }
}

/// Encrypt a record with AES-256-GCM under `key`.
///
/// A fresh random 96-bit nonce is generated and **prepended** to the output:
/// `nonce || ciphertext || tag` (see the module-level wire-format contract). No associated
/// data is bound in this minimal API; `TODO(#11)` will add an AAD channel for record
/// metadata (record id / version) as an **additive** function so this signature stays
/// stable.
///
/// Returns [`CryptoError::Rng`] if the OS CSPRNG fails — never a degenerate nonce.
///
/// ```
/// use crypto_core::{generate_master_key, encrypt_record, decrypt_record};
/// let key = generate_master_key();
/// let blob = encrypt_record(&key, b"blood type O-, allergy: penicillin").unwrap();
/// assert_eq!(decrypt_record(&key, &blob).unwrap(), b"blood type O-, allergy: penicillin".to_vec());
/// ```
pub fn encrypt_record(key: &[u8; KEY_LEN], plaintext: &[u8]) -> Result<Vec<u8>, CryptoError> {
    // 1) Fresh 96-bit nonce from the OS CSPRNG. A failure here MUST abort: we never fall
    //    back to a zero/degenerate nonce, which would reuse a nonce under the same key and
    //    destroy GCM's confidentiality guarantee.
    let mut nonce_bytes = [0u8; NONCE_LEN];
    getrandom::getrandom(&mut nonce_bytes).map_err(|_| CryptoError::Rng)?;

    // 2) AEAD seal (distinct, clearly-separated failure path from the RNG above).
    let ciphertext = seal(key, &nonce_bytes, &[], plaintext)?;

    let mut out = Vec::with_capacity(NONCE_LEN + ciphertext.len());
    out.extend_from_slice(&nonce_bytes);
    out.extend_from_slice(&ciphertext);
    Ok(out)
}

/// Decrypt a `nonce || ciphertext || tag` blob produced by [`encrypt_record`].
///
/// Returns [`CryptoError::Decrypt`] for any blob shorter than the nonce, a wrong key,
/// or a failed authentication tag — without distinguishing the cases (no oracle).
/// No plaintext is ever returned on authentication failure.
pub fn decrypt_record(key: &[u8; KEY_LEN], blob: &[u8]) -> Result<Vec<u8>, CryptoError> {
    if blob.len() < NONCE_LEN {
        return Err(CryptoError::Decrypt);
    }
    let (nonce_bytes, ciphertext) = blob.split_at(NONCE_LEN);
    open(key, nonce_bytes, &[], ciphertext)
}

/// Derive a 256-bit key from a memorable secret via PBKDF2-HMAC-SHA256 (#12).
///
/// This is the low-level KDF primitive behind the recovery envelope. Policy (frozen by
/// #12, ADR 0003 / ADR 0006):
///
/// - `salt` is **public by design**, mandatory, and stored alongside the envelope. It MUST
///   be random and at least [`RECOVERY_SALT_LEN`] bytes for production use (anti
///   rainbow-table, per-patient). PBKDF2 itself tolerates any salt — the length policy is
///   enforced by [`seal_recovery_envelope`], the only sanctioned producer.
/// - `iterations` is stored with the envelope (never guessed) so it is **forward-tunable**:
///   the count can be raised over time, and a future KDF migration is carried by the
///   envelope's version/kdf bytes (G4). The calibrated default is
///   [`RECOVERY_PBKDF2_DEFAULT_ITERS`] with a hard floor of [`RECOVERY_PBKDF2_MIN_ITERS`].
/// - The secret is **never** persisted, logged, or transmitted; the derived key is held in
///   [`Zeroizing`] by callers (G8).
///
/// The exact byte output of this function is pinned by the **gating** RFC 6070 / NIST
/// PBKDF2-HMAC-SHA256 known-answer vectors in `tests/pbkdf2_rfc6070_vectors.rs` (ADR 0003):
/// `derive_key` is proven against the spec, not merely against itself.
///
/// Brute-force note (acceptance criterion #2): PBKDF2-HMAC-SHA256 is **not memory-hard**.
/// A low-entropy secret (culturally-adapted answers) is defended by the high iteration
/// count + the per-patient salt; a higher-entropy passphrase is strongly recommended. A
/// memory-hard KDF (Argon2id) would raise the bar further and is *prepared* by the version
/// byte but not adopted while the PRD mandates "PBKDF2" (see ADR 0003).
pub fn derive_key(passphrase: &[u8], salt: &[u8], iterations: u32) -> [u8; KEY_LEN] {
    let mut key = [0u8; KEY_LEN];
    pbkdf2_hmac::<Sha256>(passphrase, salt, iterations, &mut key);
    key
}

// ─── Recovery envelope (#12, US-1.4) ─────────────────────────────────────────────────
//
// A hardware-sealed master key (#11) is NOT recoverable on its own — there is nothing to
// re-derive if the phone (and its non-exportable Keystore KEK) is lost. #12 adds a SECOND
// way to decrypt the same master key, from a memorable secret, independent of hardware:
//
//   recovery_key = PBKDF2-HMAC-SHA256(secret, salt, iterations)   // 256-bit, Zeroizing
//   recovery_blob = encrypt_record(recovery_key, master_key)      // #10 wire format
//
// Only the (encrypted) envelope ever leaves the device; the secret and the clear master
// key never do (zero-knowledge, G2/G8). On a new device the patient re-enters the secret,
// the envelope is re-derived + decrypted, and the master key is re-sealed into the new
// device's hardware (#11). The server, holding only opaque envelope bytes, can neither
// derive the secret nor decrypt anything.

/// Recovery-envelope schema version (leading byte). Bump only for an incompatible layout
/// change; readers MUST reject unknown versions (no silent re-interpretation).
pub const RECOVERY_ENVELOPE_VERSION: u8 = 1;

/// KDF identifier stored in the envelope: PBKDF2-HMAC-SHA256. A future memory-hard KDF
/// (Argon2id) would take a new id, carried additively by this byte (G4).
pub const RECOVERY_KDF_PBKDF2_HMAC_SHA256: u8 = 1;

/// Random salt length, in bytes, minted for each recovery envelope (256-bit — matches
/// threat-model control CTRL-04 and exceeds the ≥16-byte floor). Public, per-patient,
/// anti rainbow-table.
pub const RECOVERY_SALT_LEN: usize = 32;

/// Calibrated default PBKDF2-HMAC-SHA256 iteration count for recovery-key derivation.
///
/// Set to the OWASP 2023 recommendation for PBKDF2-HMAC-SHA256 (600 000). The value is
/// **stored with each envelope**, so it can be re-tuned per device class without breaking
/// existing envelopes (G4). It MUST be re-benchmarked on the entry-level Android device
/// lab (#29): targeting a ≤ ~1–2 s derivation on an Infinix-class SoC. Tuning DOWN for UX
/// is permitted only above [`RECOVERY_PBKDF2_MIN_ITERS`]; going below the floor requires a
/// documented security re-review (ADR 0003).
pub const RECOVERY_PBKDF2_DEFAULT_ITERS: u32 = 600_000;

/// Hard floor on the iteration count. [`seal_recovery_envelope`] raises any lower request
/// up to this value, and [`open_recovery_envelope`] rejects envelopes that claim fewer —
/// an anti-regression guard so a calibration mistake can never silently weaken brute-force
/// resistance (acceptance criterion #2).
pub const RECOVERY_PBKDF2_MIN_ITERS: u32 = 210_000;

/// Byte placed between normalized answers when concatenating them into a single secret.
/// It is an ASCII control character (Unit Separator, U+001F) that [`normalize_recovery_answers`]
/// strips from the answers themselves, so it cannot be forged by user input.
const ANSWER_SEPARATOR: char = '\u{1f}';

/// Fixed envelope header length: version(1) + kdf_id(1) + iterations(4, big-endian) +
/// salt_len(1).
const RECOVERY_HEADER_LEN: usize = 1 + 1 + 4 + 1;

/// Fold a single (already-lowercased) character to its unaccented Latin base, so that
/// re-typing an answer with or without diacritics derives the same key (G6).
///
/// Deliberately conservative and dependency-free: it covers the Latin-1 / French diacritics
/// relevant to the Ivorian (francophone) context. Characters outside this set pass through
/// unchanged, so non-Latin scripts keep their entropy. Full Unicode NFD folding is a future
/// option if local-language question sets need it.
fn fold_diacritic(c: char) -> char {
    match c {
        'à' | 'á' | 'â' | 'ã' | 'ä' | 'å' => 'a',
        'ç' => 'c',
        'è' | 'é' | 'ê' | 'ë' => 'e',
        'ì' | 'í' | 'î' | 'ï' => 'i',
        'ñ' => 'n',
        'ò' | 'ó' | 'ô' | 'õ' | 'ö' => 'o',
        'ù' | 'ú' | 'û' | 'ü' => 'u',
        'ý' | 'ÿ' => 'y',
        other => other,
    }
}

/// Deterministically normalize one security-question answer (G6).
///
/// Stable and reproducible across the old and new device so the derivation is reliable
/// despite typing variation: lowercase (Unicode), fold Latin diacritics, drop punctuation,
/// and collapse any run of whitespace to a single space (with leading/trailing space
/// removed). Entropy-preserving where it matters — it never destroys the actual answer
/// tokens, only the cosmetic variation around them.
fn normalize_one_answer(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut pending_space = false;
    // `to_lowercase` is locale-independent and may expand a char to several; flatten it.
    for ch in s.chars().flat_map(char::to_lowercase) {
        if ch.is_whitespace() {
            // Only a separator between real tokens; never leading/trailing.
            pending_space = !out.is_empty();
            continue;
        }
        let folded = fold_diacritic(ch);
        if folded.is_alphanumeric() {
            if pending_space {
                out.push(' ');
                pending_space = false;
            }
            out.push(folded);
        }
        // Punctuation and the like are dropped (they reduce re-typing reliability).
    }
    out
}

/// Normalize and concatenate a set of security-question answers into the secret bytes fed
/// to PBKDF2 (G6/G7).
///
/// Each answer is normalized independently by [`normalize_one_answer`], then joined with an
/// in-band separator the normalization strips, so `["Abidjan", "Yopougon"]` cannot collide
/// with `["AbidjanYopougon"]`. The result is UTF-8 bytes suitable for [`derive_key`] /
/// [`MasterKeyHandle::seal_recovery_envelope`]. Passphrases take the higher-entropy path
/// and are NOT folded — pass their raw UTF-8 bytes directly instead of going through here.
pub fn normalize_recovery_answers(answers: &[&str]) -> Vec<u8> {
    let mut joined = String::new();
    for (i, a) in answers.iter().enumerate() {
        if i > 0 {
            joined.push(ANSWER_SEPARATOR);
        }
        joined.push_str(&normalize_one_answer(a));
    }
    joined.into_bytes()
}

/// Build a recovery envelope wrapping `master_key` under a key derived from `secret` (G2).
///
/// Layout (self-describing, so a new device can re-derive without out-of-band parameters):
///
/// ```text
/// version(1) || kdf_id(1) || iterations(4, big-endian) || salt_len(1) || salt || recovery_blob
/// ```
///
/// where `recovery_blob = encrypt_record(recovery_key, master_key)` is the #10 wire format
/// (`nonce || ciphertext || tag`, 60 bytes for a 32-byte key). A fresh
/// [`RECOVERY_SALT_LEN`]-byte salt is minted per call from the OS CSPRNG; `iterations` is
/// raised to [`RECOVERY_PBKDF2_MIN_ITERS`] if a lower value is requested.
///
/// The derived recovery key is held in [`Zeroizing`] and wiped on return; the secret and
/// the clear master key are never persisted, logged, or transmitted (G8). Returns
/// [`CryptoError::Rng`] if the CSPRNG fails.
pub fn seal_recovery_envelope(
    master_key: &[u8; KEY_LEN],
    secret: &[u8],
    iterations: u32,
) -> Result<Vec<u8>, CryptoError> {
    let iterations = iterations.max(RECOVERY_PBKDF2_MIN_ITERS);

    let mut salt = [0u8; RECOVERY_SALT_LEN];
    getrandom::getrandom(&mut salt).map_err(|_| CryptoError::Rng)?;

    let recovery_key = Zeroizing::new(derive_key(secret, &salt, iterations));
    // The master key is the "plaintext" sealed under the recovery key (#10 format).
    let recovery_blob = encrypt_record(&recovery_key, master_key)?;

    let mut out = Vec::with_capacity(RECOVERY_HEADER_LEN + RECOVERY_SALT_LEN + recovery_blob.len());
    out.push(RECOVERY_ENVELOPE_VERSION);
    out.push(RECOVERY_KDF_PBKDF2_HMAC_SHA256);
    out.extend_from_slice(&iterations.to_be_bytes());
    out.push(RECOVERY_SALT_LEN as u8);
    out.extend_from_slice(&salt);
    out.extend_from_slice(&recovery_blob);
    Ok(out)
}

/// Re-derive and unwrap a recovery envelope produced by [`seal_recovery_envelope`] (G1).
///
/// Parses the self-describing header, re-derives the recovery key from `secret` + the
/// stored salt/iterations, and authenticated-decrypts the wrapped master key. On success
/// the recovered master key is returned **inside a [`MasterKeyHandle`]** — it never crosses
/// the FFI as raw bytes; the caller re-seals it into the new device's hardware (#11) via the
/// single sanctioned [`MasterKeyHandle::export_sealable`] crossing.
///
/// Every failure mode — wrong secret, tampered/truncated envelope, unknown version/KDF,
/// or an iteration count below the floor — collapses to the single coarse
/// [`CryptoError::Decrypt`] (no oracle distinguishing "wrong secret" from "bad blob",
/// threat model THR-05). "Envelope not found" is a *lookup* concern handled above this
/// layer (typed separately in Dart), never here.
pub fn open_recovery_envelope(
    secret: &[u8],
    envelope: &[u8],
) -> Result<MasterKeyHandle, CryptoError> {
    if envelope.len() < RECOVERY_HEADER_LEN {
        return Err(CryptoError::Decrypt);
    }
    if envelope[0] != RECOVERY_ENVELOPE_VERSION || envelope[1] != RECOVERY_KDF_PBKDF2_HMAC_SHA256 {
        return Err(CryptoError::Decrypt);
    }
    let iterations = u32::from_be_bytes([envelope[2], envelope[3], envelope[4], envelope[5]]);
    if iterations < RECOVERY_PBKDF2_MIN_ITERS {
        return Err(CryptoError::Decrypt);
    }
    let salt_len = envelope[6] as usize;
    let salt_start = RECOVERY_HEADER_LEN;
    let blob_start = salt_start + salt_len;
    // Salt must meet the ≥16-byte floor and fit, leaving room for the recovery blob.
    if salt_len < 16 || envelope.len() <= blob_start {
        return Err(CryptoError::Decrypt);
    }
    let salt = &envelope[salt_start..blob_start];
    let recovery_blob = &envelope[blob_start..];

    let recovery_key = Zeroizing::new(derive_key(secret, salt, iterations));
    let mut master = decrypt_record(&recovery_key, recovery_blob)?;
    // A correct secret must yield exactly a 32-byte master key; anything else is treated as
    // a (coarse) decrypt failure rather than handing back an ill-sized key.
    if master.len() != KEY_LEN {
        master.zeroize();
        return Err(CryptoError::Decrypt);
    }
    let mut key = [0u8; KEY_LEN];
    key.copy_from_slice(&master);
    master.zeroize();
    let handle = MasterKeyHandle::from_unsealed(key);
    key.zeroize();
    Ok(handle)
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

    /// Deterministic AES-256-GCM seal with a **caller-chosen** nonce, returning
    /// `ciphertext || tag`. Test-only (`#[cfg(test)]`): it exists solely to compare against
    /// fixed known-answer vectors and is deliberately NOT part of the production API, where
    /// a caller-chosen nonce could be reused and break GCM.
    fn encrypt_with_nonce(
        key: &[u8; KEY_LEN],
        nonce: &[u8; NONCE_LEN],
        aad: &[u8],
        plaintext: &[u8],
    ) -> Result<Vec<u8>, CryptoError> {
        seal(key, nonce, aad, plaintext)
    }

    /// Deterministic AES-256-GCM open with a caller-chosen nonce (test-only counterpart to
    /// `encrypt_with_nonce`).
    fn decrypt_with_nonce(
        key: &[u8; KEY_LEN],
        nonce: &[u8; NONCE_LEN],
        aad: &[u8],
        ciphertext_and_tag: &[u8],
    ) -> Result<Vec<u8>, CryptoError> {
        open(key, nonce, aad, ciphertext_and_tag)
    }

    fn arr<const N: usize>(hex_str: &str) -> [u8; N] {
        let v = hex::decode(hex_str).expect("valid hex");
        v.try_into().expect("hex length matches array")
    }

    // ---------------------------------------------------------------------------------
    // Official AES-256-GCM known-answer vectors (KAT) — GATING (acceptance criterion #1).
    //
    // Provenance: the canonical AES-256-GCM test cases (key = 256-bit, IV = 96-bit) from
    // the GCM specification (McGrew & Viega, "The Galois/Counter Mode of Operation (GCM)",
    // 2005), test cases 13–16 — the same fixed (Key, IV, PT, AAD, CT, Tag) tuples that NIST
    // CAVP `gcmEncryptExtIV256` / `gcmDecrypt256` exercise and that every reference
    // implementation (RustCrypto `aes-gcm`, BoringSSL, Go `crypto/cipher`) reproduces.
    // Full provenance / extension note: crypto-core/tests/vectors/PROVENANCE.md.
    //
    // Coverage: empty PT + empty AAD (13), single-block PT + empty AAD (14), multi-block
    // PT + empty AAD (15), multi-block PT + NON-empty AAD (16, anticipating #11).
    // ---------------------------------------------------------------------------------

    struct Kat {
        key: &'static str,
        iv: &'static str,
        aad: &'static str,
        pt: &'static str,
        ct: &'static str,
        tag: &'static str,
    }

    const VECTORS: &[Kat] = &[
        // Test case 13
        Kat {
            key: "0000000000000000000000000000000000000000000000000000000000000000",
            iv: "000000000000000000000000",
            aad: "",
            pt: "",
            ct: "",
            tag: "530f8afbc74536b9a963b4f1c4cb738b",
        },
        // Test case 14
        Kat {
            key: "0000000000000000000000000000000000000000000000000000000000000000",
            iv: "000000000000000000000000",
            aad: "",
            pt: "00000000000000000000000000000000",
            ct: "cea7403d4d606b6e074ec5d3baf39d18",
            tag: "d0d1c8a799996bf0265b98b5d48ab919",
        },
        // Test case 15 (empty AAD, 60-byte PT — GCM spec §B, McGrew & Viega 2005)
        Kat {
            key: "feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308",
            iv: "cafebabefacedbaddecaf888",
            aad: "",
            pt: "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39",
            ct: "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662",
            tag: "eb9f796c8d356fc31a8433884b696f4f",
        },
        // Test case 16 (NON-empty AAD, 60-byte PT — anticipates the #11 AAD channel)
        Kat {
            key: "feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308",
            iv: "cafebabefacedbaddecaf888",
            aad: "feedfacedeadbeeffeedfacedeadbeefabaddad2",
            pt: "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39",
            ct: "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662",
            tag: "76fc6ece0f4e1768cddf8853bb2d551b",
        },
    ];

    #[test]
    fn nist_kat_encrypt_exact_ciphertext_and_tag() {
        // gcmEncryptExtIV256: for fixed (Key, IV, PT, AAD) the produced CT *and* Tag must
        // be byte-for-byte the standard's expected values.
        for (i, v) in VECTORS.iter().enumerate() {
            let key: [u8; KEY_LEN] = arr(v.key);
            let nonce: [u8; NONCE_LEN] = arr(v.iv);
            let aad = hex::decode(v.aad).unwrap();
            let pt = hex::decode(v.pt).unwrap();

            let out = encrypt_with_nonce(&key, &nonce, &aad, &pt).expect("seal");

            let mut expected = hex::decode(v.ct).unwrap();
            expected.extend_from_slice(&hex::decode(v.tag).unwrap());
            assert_eq!(out, expected, "vector {i}: ciphertext||tag mismatch");
        }
    }

    #[test]
    fn nist_kat_decrypt_recovers_plaintext() {
        // gcmDecrypt256 PASS: authentic CT||Tag must decrypt back to the exact plaintext.
        for (i, v) in VECTORS.iter().enumerate() {
            let key: [u8; KEY_LEN] = arr(v.key);
            let nonce: [u8; NONCE_LEN] = arr(v.iv);
            let aad = hex::decode(v.aad).unwrap();
            let pt = hex::decode(v.pt).unwrap();

            let mut ct_tag = hex::decode(v.ct).unwrap();
            ct_tag.extend_from_slice(&hex::decode(v.tag).unwrap());

            let recovered = decrypt_with_nonce(&key, &nonce, &aad, &ct_tag).expect("open");
            assert_eq!(recovered, pt, "vector {i}: plaintext mismatch");
        }
    }

    #[test]
    fn nist_kat_decrypt_fails_on_tampered_tag() {
        // gcmDecrypt256 FAIL: a single flipped tag bit must yield Decrypt and NO plaintext.
        for (i, v) in VECTORS.iter().enumerate() {
            let key: [u8; KEY_LEN] = arr(v.key);
            let nonce: [u8; NONCE_LEN] = arr(v.iv);
            let aad = hex::decode(v.aad).unwrap();

            let mut ct_tag = hex::decode(v.ct).unwrap();
            ct_tag.extend_from_slice(&hex::decode(v.tag).unwrap());
            let last = ct_tag.len() - 1;
            ct_tag[last] ^= 0x01;

            assert_eq!(
                decrypt_with_nonce(&key, &nonce, &aad, &ct_tag),
                Err(CryptoError::Decrypt),
                "vector {i}: tampered tag must be rejected"
            );
        }
    }

    #[test]
    fn nist_kat_decrypt_fails_on_wrong_aad() {
        // The non-empty-AAD vector must fail to authenticate under empty AAD: proves AAD is
        // actually bound, so #11 can rely on it without an API break.
        let v = &VECTORS[3];
        let key: [u8; KEY_LEN] = arr(v.key);
        let nonce: [u8; NONCE_LEN] = arr(v.iv);
        let mut ct_tag = hex::decode(v.ct).unwrap();
        ct_tag.extend_from_slice(&hex::decode(v.tag).unwrap());

        assert_eq!(
            decrypt_with_nonce(&key, &nonce, b"", &ct_tag),
            Err(CryptoError::Decrypt),
            "wrong AAD must be rejected"
        );
    }

    #[test]
    fn encrypt_decrypt_round_trip() {
        let key = generate_master_key();
        let plaintext = b"patient record: blood type O-, allergy: penicillin";

        let blob = encrypt_record(&key, plaintext).expect("encrypt");
        // Output is exactly nonce + plaintext + tag.
        assert_eq!(blob.len(), OVERHEAD_LEN + plaintext.len());

        let recovered = decrypt_record(&key, &blob).expect("decrypt");
        assert_eq!(recovered, plaintext);
    }

    #[test]
    fn fresh_nonce_makes_outputs_differ() {
        // Two encryptions of the SAME plaintext under the SAME key must differ, proving a
        // fresh random nonce per call (G3 anti-regression guard).
        let key = generate_master_key();
        let a = encrypt_record(&key, b"same plaintext").expect("encrypt");
        let b = encrypt_record(&key, b"same plaintext").expect("encrypt");
        assert_ne!(a, b);
        // Differ specifically in the prepended nonce.
        assert_ne!(a[..NONCE_LEN], b[..NONCE_LEN]);
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
        // Same inputs => same key; this is a smoke test, NOT a gating vector (see #12).
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

    #[test]
    fn master_key_handle_generates_full_length_nonzero_key() {
        let handle = MasterKeyHandle::generate();
        // 256-bit key, and not the all-zero buffer (basic entropy sanity).
        assert_eq!(handle.expose_for_test().len(), KEY_LEN);
        assert_ne!(handle.expose_for_test(), &[0u8; KEY_LEN]);
    }

    #[test]
    fn master_key_handles_differ_between_generations() {
        // Two independent generations must not collide (CSPRNG entropy).
        let a = MasterKeyHandle::generate();
        let b = MasterKeyHandle::generate();
        assert_ne!(a.expose_for_test(), b.expose_for_test());
    }

    #[test]
    fn export_sealable_matches_handle_key() {
        // The exported bytes (which go straight to hardware sealing) equal the handle's key.
        let handle = MasterKeyHandle::generate();
        let sealable = handle.export_sealable();
        assert_eq!(&*sealable, handle.expose_for_test());
    }

    #[test]
    fn from_unsealed_round_trips_clear_bytes() {
        // Mirrors the unseal path: hardware returns clear bytes, Rust re-wraps them.
        let original = MasterKeyHandle::generate();
        let sealable = original.export_sealable();
        let rewrapped = MasterKeyHandle::from_unsealed(*sealable);
        assert_eq!(rewrapped.expose_for_test(), original.expose_for_test());
    }

    // ── MasterKeyHandle / generate_master_key gap coverage (#11) ─────────────

    #[test]
    fn generate_master_key_returns_32_nonzero_bytes() {
        // Directly exercises the raw function (distinct from the handle-based tests).
        let key = generate_master_key();
        assert_eq!(key.len(), KEY_LEN);
        assert_ne!(key, [0u8; KEY_LEN]);
    }

    #[test]
    fn generate_master_key_twice_differs() {
        // CSPRNG entropy: two raw calls must not collide.
        let a = generate_master_key();
        let b = generate_master_key();
        assert_ne!(a, b);
    }

    #[test]
    fn handle_wipe_consumes_without_panic() {
        // Calling wipe() explicitly must consume the handle cleanly.
        let handle = MasterKeyHandle::generate();
        handle.wipe(); // moves and drops; Zeroizing overwrites the key
    }

    #[test]
    fn export_sealable_is_independent_copy() {
        // Mutating the exported Zeroizing buffer must NOT affect the handle's own key
        // (they are separate allocations — Zeroizing::new(*self.key) copies the array).
        let handle = MasterKeyHandle::generate();
        let original = *handle.expose_for_test();
        let mut exported = handle.export_sealable();
        exported.iter_mut().for_each(|b| *b ^= 0xFF);
        assert_eq!(
            handle.expose_for_test(),
            &original,
            "export_sealable must return an independent copy, not an alias"
        );
    }

    #[test]
    fn from_unsealed_zeroed_input_wraps_without_panic() {
        // An all-zero byte array is degenerate but must not crash from_unsealed.
        let handle = MasterKeyHandle::from_unsealed([0u8; KEY_LEN]);
        assert_eq!(handle.expose_for_test(), &[0u8; KEY_LEN]);
    }

    // ── Decrypt security regressions (#11) ───────────────────────────────────

    #[test]
    fn decrypt_rejects_wrong_key() {
        // A ciphertext produced under key_a must NOT be openable under key_b.
        // Guards against accidental key-bypass in future refactors.
        let key_a = generate_master_key();
        let key_b = generate_master_key();
        let blob = encrypt_record(&key_a, b"patient data").expect("encrypt");
        assert_eq!(
            decrypt_record(&key_b, &blob),
            Err(CryptoError::Decrypt),
            "wrong key must yield Decrypt, not garbage plaintext"
        );
    }

    #[test]
    fn decrypt_rejects_nonce_only_blob() {
        // A blob of exactly NONCE_LEN bytes has no ciphertext payload and no tag;
        // the GCM open call must reject it (not return empty plaintext).
        let key = generate_master_key();
        let nonce_only = vec![0u8; NONCE_LEN];
        assert_eq!(
            decrypt_record(&key, &nonce_only),
            Err(CryptoError::Decrypt),
            "a nonce-only blob (no tag) must be rejected"
        );
    }

    // ── CryptoError contract (#11) ────────────────────────────────────────────

    #[test]
    fn crypto_error_display_is_non_empty() {
        // Display must be non-empty so log / UI message is always informative.
        assert!(!CryptoError::Rng.to_string().is_empty());
        assert!(!CryptoError::Decrypt.to_string().is_empty());
    }

    #[test]
    fn crypto_error_variants_are_distinct() {
        assert_ne!(CryptoError::Rng, CryptoError::Decrypt);
        assert_eq!(CryptoError::Rng, CryptoError::Rng);
        assert_eq!(CryptoError::Decrypt, CryptoError::Decrypt);
    }

    // TODO(#11): bind record metadata (id / version) as AES-GCM associated data via an
    //            ADDITIVE function (e.g. `encrypt_record_aad`) so this stable signature is
    //            preserved. The non-empty-AAD KAT above already proves the AAD path.
    // TODO(#12): add the RFC 6070 / NIST PBKDF2-HMAC-SHA256 known-answer vectors as GATING
    //            CI tests so `derive_key` is proven against the spec, not just
    //            self-consistent. Per ADR 0003 these vectors gate the build.
}
