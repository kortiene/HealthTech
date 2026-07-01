# Optimisation réseau dégradé Edge/3G (issue #24)

## Problem Statement

The patient record (≤ 500 Kio plaintext JSON) is uploaded and downloaded as an
AES-256-GCM encrypted blob. On an Edge/3G connection (typical ~100–300 kbps
real throughput in Côte d'Ivoire), a raw 500 KB blob takes 13–40 seconds to
transfer — far above the 3 s UX target (PRD NFR §5). Two independent
improvements close the gap: (1) compress the plaintext before encryption so
the blob is 4–6× smaller, and (2) retry transiently-failed transfers with
exponential backoff so an unstable link does not permanently block the user.

## Goals

1. **G1 Compression** — Gzip the record plaintext *before* AES-256-GCM
   encryption on the write path; reverse on the read path.  The 500 Kio budget
   remains measured on the *uncompressed* plaintext (RecordSizeGuard
   unchanged).
2. **G2 Backward compat** — Blobs written before #24 (uncompressed plaintext
   inside the AES envelope) must remain readable without migration.
3. **G3 Retry** — Transient network errors on PUT/GET blob are automatically
   retried with exponential backoff (configurable, injectable for tests).
4. **G4 Verifiability** — A deterministic test confirms the compressed blob
   size is significantly smaller than the raw plaintext (proxy for 3G perf),
   and retry logic is covered without real network calls.

## Non-Goals

- HTTP-level `Content-Encoding: gzip` (requires backend changes — server must
  stay zero-knowledge/opaque).
- Range/partial download (requires durable backend storage, tracked via #8).
- Compressing media ciphertext (binary image data is already compressed by the
  image codec; gzip would enlarge it).
- Actual on-device 3G simulation (device-farm testing, post-M4).

## Relevant Repository Context

- **Stack**: Flutter/Dart 3.x, Rust `crypto-core` via FRB (ADR 0001/0003).
  `dart:io` (including `GZipCodec`) is available on all native targets
  (Android, iOS, desktop) and in host-side unit tests.
- **Record pipeline**: `RecordSizeGuard.truncate` → `CryptoCore.encryptRecord`
  → `SealedBlobStore.write` (local) → `BackendClient.put` (cloud).
  Compression slots in between `truncate` and `encryptRecord`.
- **`MedicalRecordStore`** (`lib/src/record/medical_record_store.dart`) owns
  the write/read pipeline and is the sole integration point.
- **`BackendClient`** (`lib/src/cloud/backend_client.dart`) — injected into
  `MedicalRecordStore`; MockClient-based tests rely on exact constructor
  signature.
- **`MediaClient`** (`lib/src/cloud/media_client.dart`) — media download also
  benefits from retry (large ciphertext on unstable links).
- **Existing tests** seed the local store with `xor(plaintext_json)` (no
  compression); `decodeIfCompressed` with magic-byte detection preserves these
  tests without modification.

## Proposed Implementation

### A — `PlaintextCompressor` (`lib/src/record/plaintext_compressor.dart`)

Pure utility. `dart:io.GZipCodec`:
- `compress(Uint8List) → Uint8List` — always produces a gzip frame.
- `decodeIfCompressed(Uint8List) → Uint8List` — checks magic bytes `0x1f 0x8b`
  (gzip); if absent, returns the input unchanged (valid JSON always starts with
  `0x7b = '{'`, so the two cases are unambiguous).

### B — `NetworkRetry` (`lib/src/cloud/network_retry.dart`)

Configurable retry-with-backoff:
- `maxAttempts` (default 3), `baseDelayMs` (default 500, set to 0 in tests).
- `run<T>(Future<T> Function() fn, {bool Function(Object)? retryIf})` —
  retries on any exception (or only when `retryIf` returns true), with delay
  `baseDelayMs × 2^(attempt-1)` capped at 8 s.

### C — Update `MedicalRecordStore`

- Add optional `NetworkRetry? retry` constructor param (default `null` = no
  retry, preserves existing test behaviour).
- `write`: insert `PlaintextCompressor.compress(plaintext)` before
  `encryptRecord`; wrap `_client.put` with `_retry?.run(...)`.
- `read`: after `decryptRecord`, apply `PlaintextCompressor.decodeIfCompressed`
  before JSON parsing; wrap `_client.get` with `_retry?.run(...)`.

### D — Update `MediaClient`

Add optional `NetworkRetry? retry` param; wrap `putMedia` and `fetchCiphertext`
calls. Media content is not compressed (binary image data).

## Affected Files / Packages / Modules

| File | Action |
|---|---|
| `lib/src/record/plaintext_compressor.dart` | **create** |
| `lib/src/cloud/network_retry.dart` | **create** |
| `lib/src/record/medical_record_store.dart` | **modify** |
| `lib/src/cloud/media_client.dart` | **modify** (retry param) |
| `test/record/plaintext_compressor_test.dart` | **create** |
| `test/cloud/network_retry_test.dart` | **create** |
| `test/record/medical_record_store_test.dart` | **extend** (compressed-write + backward-compat read tests) |

## API / Interface Changes

- `MedicalRecordStore` constructor gains optional `NetworkRetry? retry` —
  fully backward compatible (defaults to `null`).
- `MediaClient` constructor gains optional `NetworkRetry? retry` — backward
  compatible.
- No backend API changes.

## Data Model / Protocol Changes

The blob format after #24 is `AES-256-GCM(gzip(plaintext))` instead of
`AES-256-GCM(plaintext)`. Detection of old vs new format is via gzip magic
bytes after decryption — no schema version bump needed because:
- `PlaintextCompressor.decodeIfCompressed` handles both transparently.
- The server never interprets the blob; format change is invisible to it.

## Security & Compliance Considerations

- **Zero-knowledge boundary unchanged**: compression is client-side, inside the
  encrypt step. The server receives a smaller opaque ciphertext — it still has
  no key and no decrypt path.
- **No plaintext leakage**: gzip header/trailer does not expose plaintext
  content; it is then AES-256-GCM encrypted before transmission.
- **No crypto weakening**: compressing before encrypting is standard practice
  (TLS does this). The GCM authentication tag still covers the compressed
  ciphertext, so tampering is detected.
- **Data residency unaffected**: in-country server stores a smaller opaque blob.

## Testing Plan

1. `PlaintextCompressor` unit tests: compress→decompress round-trip; backward
   compat (uncompressed input returned unchanged); compression ratio on a 400 KB
   JSON fixture is > 75 % reduction (proxy for 3G perf criterion).
2. `NetworkRetry` unit tests: eventual success after 1–2 failures; gives up
   after `maxAttempts`; non-retryable predicate short-circuits; `baseDelayMs=0`
   for fast tests.
3. `MedicalRecordStore` new tests: write produces a compressed blob (smaller
   than plaintext); read handles both old (uncompressed) and new (compressed)
   blobs.
4. All existing `MedicalRecordStore` tests pass unchanged (backward compat).
5. E2E decision: not added — compression/retry are transparent to the
   consultation loop; existing e2e test remains green.

## Risks and Open Questions

- **Compression size regression**: a fully-encrypted blob cannot be further
  compressed (random bytes). If someone passes AES ciphertext as "plaintext"
  to the compressor, output may be larger. Mitigation: `compress` is only
  called on record plaintext (not on blobs).
- **`dart:io` on web**: GZipCodec is not available on web targets. Not a
  concern now (Android-first, backlog #1 did not choose web), but if a web
  patient portal is ever added, use `package:archive` instead.

## Implementation Checklist

- [x] Create `PlaintextCompressor` with `compress` + `decodeIfCompressed`
- [x] Create `NetworkRetry` with exponential backoff + `retryIf` predicate
- [x] Update `MedicalRecordStore.write` to compress before encrypt, retry PUT
- [x] Update `MedicalRecordStore.read` to decompress after decrypt, retry GET
- [x] Update `MediaClient` to accept and use optional `NetworkRetry`
- [x] Write `plaintext_compressor_test.dart`
- [x] Write `network_retry_test.dart`
- [x] Extend `medical_record_store_test.dart` with compressed-write +
      backward-compat read
- [x] Run `flutter test` + `dart format` + `flutter analyze`
