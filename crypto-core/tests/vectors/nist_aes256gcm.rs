//! Canonical AES-256-GCM known-answer vectors (256-bit key, 96-bit IV).
//!
//! Provenance and the full table are documented in `PROVENANCE.md` alongside this file.
//! Source: GCM specification (McGrew & Viega, 2005) test cases 13–16 — the 256-bit cases
//! that NIST CAVP `gcmEncryptExtIV256` / `gcmDecrypt256` also enumerate.
//!
//! Only the **empty-AAD** cases are surfaced here, because they are driven through the
//! public `decrypt_record` API (which binds empty AAD). The non-empty-AAD case and the
//! exact-encrypt match live in the crate's internal `#[cfg(test)]` module, which can use a
//! deterministic, caller-chosen nonce.

/// One AES-256-GCM known-answer vector, hex-encoded.
pub struct Vector {
    pub name: &'static str,
    pub key: &'static str,
    pub iv: &'static str,
    pub plaintext: &'static str,
    pub ciphertext: &'static str,
    pub tag: &'static str,
}

/// Empty-AAD AES-256-GCM vectors (GCM spec test cases 13, 14, 15).
pub const EMPTY_AAD_VECTORS: &[Vector] = &[
    Vector {
        name: "tc13: empty plaintext, empty AAD",
        key: "0000000000000000000000000000000000000000000000000000000000000000",
        iv: "000000000000000000000000",
        plaintext: "",
        ciphertext: "",
        tag: "530f8afbc74536b9a963b4f1c4cb738b",
    },
    Vector {
        name: "tc14: single-block plaintext, empty AAD",
        key: "0000000000000000000000000000000000000000000000000000000000000000",
        iv: "000000000000000000000000",
        plaintext: "00000000000000000000000000000000",
        ciphertext: "cea7403d4d606b6e074ec5d3baf39d18",
        tag: "d0d1c8a799996bf0265b98b5d48ab919",
    },
    Vector {
        name: "tc15: multi-block plaintext, empty AAD",
        key: "feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308",
        iv: "cafebabefacedbaddecaf888",
        plaintext: "d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255",
        ciphertext: "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f6627a890def",
        tag: "b094dac5d93471bdec1a502270e3cc6c",
    },
];
