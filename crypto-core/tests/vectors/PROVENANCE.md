# AES-256-GCM known-answer vectors — provenance

These are the canonical **AES-256-GCM** known-answer test (KAT) tuples — 256-bit key,
96-bit IV — used to gate `crypto-core` against the standard (acceptance criterion #1 of
issue #10). They are exercised in two complementary places:

- `crypto-core/src/lib.rs` (`mod tests`) — exact **encrypt** match (`gcmEncryptExtIV256`:
  produced `ciphertext || tag` is byte-for-byte the expected value) and **decrypt**
  PASS/FAIL (`gcmDecrypt256`), including a non-empty-AAD vector. These run against the
  crate-internal deterministic seal/open (fixed nonce), which is the only way to compare
  to a fixed-IV vector — the production API uses a random nonce by design.
- `crypto-core/tests/aes_gcm_nist_vectors.rs` — the same empty-AAD vectors driven through
  the **public** `decrypt_record` to prove the production wire format
  (`nonce || ciphertext || tag`) and public decrypt path conform too.

## Source

Test cases **13–16** of the GCM specification:

> D. McGrew, J. Viega, *The Galois/Counter Mode of Operation (GCM)*, 2005 — Appendix B,
> "AES Test Vectors", cases 13–18 (the 256-bit key cases).

These are the same fixed `(Key, IV, PT, AAD, CT, Tag)` tuples that the **NIST CAVP
GCMVS** suites `gcmEncryptExtIV256.rsp` / `gcmDecrypt256.rsp` enumerate (AES-256, external
96-bit IV), and that every reference implementation reproduces verbatim — RustCrypto
`aes-gcm`, BoringSSL, OpenSSL, Go `crypto/cipher`. They are reproduced here as inline
constants (small, readable, self-contained) rather than committing the multi-megabyte
NIST `.rsp` files.

| Case | Key | IV | PT len | AAD len | Notes |
| ---- | --- | -- | ------ | ------- | ----- |
| 13 | all-zero | all-zero | 0 | 0 | empty PT, empty AAD |
| 14 | all-zero | all-zero | 16 | 0 | single block |
| 15 | `feffe992…` | `cafebabe…` | 64 | 0 | multi-block, empty AAD |
| 16 | `feffe992…` | `cafebabe…` | 60 | 20 | multi-block, **non-empty AAD** (anticipates #11) |

## Extending to the full NIST `.rsp` corpus

If a future hardening pass (or the independent crypto review, #26) wants the full CAVP
corpus, drop the official `gcmEncryptExtIV256.rsp` / `gcmDecrypt256.rsp` files in this
directory and add a small `.rsp` parser to `tests/`. The current subset already gates the
encrypt path, the decrypt PASS path, the decrypt FAIL path, and the AAD channel, which
satisfies issue #10's acceptance criterion.

---

# PBKDF2-HMAC-SHA256 known-answer vectors — provenance

These vectors pin `crypto_core::derive_key` (PBKDF2-HMAC-SHA256, dkLen = 32) against the
published standard, so the KDF is proven against the spec, not merely against itself
(acceptance criterion #1 of issue #12). They are exercised in
`crypto-core/tests/pbkdf2_rfc6070_vectors.rs`.

## Source

> C. Percival, S. Josefsson, *The scrypt Password-Based Key Derivation Function*,
> RFC 7914, August 2016, §11 "Test Vectors for PBKDF2 with HMAC-SHA-256".
> <https://www.rfc-editor.org/rfc/rfc7914#section-11>

The RFC defines two reference vectors with dkLen = 64.  `derive_key` produces dkLen = 32
(= `KEY_LEN`, one AES-256 key), which equals the first PBKDF2 output block T1.  Because
HMAC-SHA256 has hLen = 32, and we request dkLen ≤ hLen, only T1 is ever computed — no
truncation of a multi-block derivation is involved.  The 32-byte expected values used in
the tests are the first 32 bytes of the corresponding RFC 7914 §11 reference outputs,
cross-verified against:

- OpenSSL: `openssl kdf -keylen 32 -kdfopt digest:SHA2-256 -kdfopt pass:<P> \`
  `-kdfopt salt:<S> -kdfopt iter:<c> PBKDF2`
- Go `crypto/pbkdf2`: `pbkdf2.Key([]byte(P), []byte(S), c, 32, sha256.New)`
- Python `hashlib`: `hashlib.pbkdf2_hmac('sha256', P, S, c, dklen=32)`

| # | Passphrase | Salt   | Iterations | Expected T1 (32 bytes hex)                                     |
|---|-----------|--------|-----------|----------------------------------------------------------------|
| 1 | `passwd`  | `salt` | 1         | `55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc` |
| 2 | `Password`| `NaCl` | 80 000    | `4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56` |

## dkLen = 32 truncation rationale

RFC 7914 specifies these vectors at dkLen = 64 (two PBKDF2 output blocks).  Requesting
dkLen = 32 is equivalent to truncating the 64-byte result to its first half, which is
exactly T1 — the output of the first (and only) block-iteration loop.  This is a standard
and lossless operation: T1 is independently computable and does not depend on T2.  The
test vectors above encode T1 directly; no partial-block arithmetic or exotic truncation is
involved.
