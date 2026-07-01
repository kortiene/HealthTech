// Encrypted local-first medical record store with cloud sync (issue #14).
//
// Write path (US-1.3):
//   RecordSizeGuard.truncate → gzip compress (#24) → AES-256-GCM encrypt →
//   local persist → PUT blob (with optional retry, #24)
//   Local write happens first; a cloud failure leaves a valid local copy so
//   the offline-sync queue (#21) can retry without data loss.
//
// Read path:
//   local cache first → cloud GET fallback (with optional retry, #24) →
//   AES-256-GCM decrypt → gzip decompress if compressed (#24) → JSON parse.
//   The decompress step is backward-compatible: uncompressed blobs (pre-#24)
//   are detected by the absence of the gzip magic header and returned as-is.
//
// Zero-knowledge invariant: plaintext never leaves this service.
//   The server receives only the opaque ciphertext keyed by anonymousUuid;
//   it has no key and no decrypt path (ADR 0004).

import 'dart:convert';
import 'dart:typed_data';

import '../cloud/backend_client.dart';
import '../cloud/network_retry.dart';
import '../rust/crypto_core_bindings.dart';
import '../secure/sealed_blob_store.dart';
import 'medical_record.dart';
import 'plaintext_compressor.dart';
import 'record_size_guard.dart';

/// Orchestrates AES-256-GCM encryption and local + cloud persistence of the
/// patient medical record (issue #14, US-1.3).
///
/// Optionally accepts a [NetworkRetry] for automatic retry of transient cloud
/// failures on degraded Edge/3G links (issue #24). Pass [retry] = null to
/// disable retries (default; existing tests are unaffected).
///
/// The [handle] passed to [write] and [read] is owned by the caller and must
/// be wiped after each call via [MasterKeyService.wipeHandle].
class MedicalRecordStore {
  MedicalRecordStore({
    required CryptoCore crypto,
    required BackendClient client,
    required SealedBlobStore localStore,
    NetworkRetry? retry,
  })  : _crypto = crypto,
        _client = client,
        _localStore = localStore,
        _retry = retry;

  final CryptoCore _crypto;
  final BackendClient _client;
  final SealedBlobStore _localStore;
  final NetworkRetry? _retry;

  /// Encrypt [record], save locally, then upload to the cloud (US-1.3).
  ///
  /// Applies [RecordSizeGuard.truncate] to stay within the 500 Kio limit
  /// (oldest consultations dropped first), then gzip-compresses the plaintext
  /// before AES-256-GCM encryption (issue #24 — reduces blob size 75–85 %
  /// for faster Edge/3G transfer). The local write is performed before the
  /// cloud PUT so that a network failure does not lose the record.
  ///
  /// Throws [RecordTooLargeException] if the record cannot be made to fit.
  /// Throws [BackendUnavailable] when the cloud PUT fails; the local copy is
  /// already persisted and can be retried by the offline queue (#21).
  Future<void> write(
    MedicalRecord record,
    MasterKeyHandle handle,
    String anonymousUuid,
  ) async {
    final safe = RecordSizeGuard.truncate(record);
    final plaintext = Uint8List.fromList(safe.toUtf8Bytes());
    final compressed = PlaintextCompressor.compress(plaintext);
    final blob = await _crypto.encryptRecord(handle, compressed);
    await _localStore.write(blob);
    Future<void> doPut() => _client.put(anonymousUuid, blob);
    if (_retry != null) {
      await _retry.run(doPut, retryIf: (e) => e is BackendUnavailable);
    } else {
      await doPut();
    }
  }

  /// Decrypt and return the medical record.
  ///
  /// Reads from the local cache first. If no local copy exists, fetches from
  /// the cloud (first open on a new device after key recovery, issue #12)
  /// and caches the result locally before decrypting. Cloud GET is wrapped
  /// with retry on transient failures when a [NetworkRetry] was provided
  /// (issue #24).
  ///
  /// After decryption, applies [PlaintextCompressor.decodeIfCompressed] so
  /// that blobs written before #24 (uncompressed plaintext) are still readable
  /// alongside newer gzip-compressed blobs (backward compat).
  ///
  /// Throws [BlobNotFound] if neither local nor cloud has a copy.
  /// Throws [DecryptError] on a bad key or corrupted blob.
  Future<MedicalRecord> read(
    MasterKeyHandle handle,
    String anonymousUuid,
  ) async {
    Uint8List blob;
    final cached = await _localStore.read();
    if (cached != null) {
      blob = cached;
    } else {
      Future<Uint8List> doGet() => _client.get(anonymousUuid);
      blob = _retry != null
          ? await _retry.run(doGet, retryIf: (e) => e is BackendUnavailable)
          : await doGet();
      await _localStore.write(blob);
    }
    final decrypted = await _crypto.decryptRecord(handle, blob);
    final plaintext = PlaintextCompressor.decodeIfCompressed(decrypted);
    final json = jsonDecode(utf8.decode(plaintext)) as Map<String, Object?>;
    return MedicalRecord.fromJson(json);
  }

  /// Whether a local record blob exists on this device.
  Future<bool> exists() => _localStore.exists();
}
