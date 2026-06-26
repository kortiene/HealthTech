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
