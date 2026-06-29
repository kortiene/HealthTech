// Encrypted local-first medical record store with cloud sync (issue #14).
//
// Write path (US-1.3):
//   RecordSizeGuard.truncate → AES-256-GCM encrypt → local persist → PUT blob
//   Local write happens first; a cloud failure leaves a valid local copy so
//   the offline-sync queue (#21) can retry without data loss.
//
// Read path:
//   local cache first → cloud GET fallback (first open after device recovery).
//
// Zero-knowledge invariant: plaintext never leaves this service.
//   The server receives only the opaque ciphertext keyed by anonymousUuid;
//   it has no key and no decrypt path (ADR 0004).

import 'dart:convert';
import 'dart:typed_data';

import '../cloud/backend_client.dart';
import '../rust/crypto_core_bindings.dart';
import '../secure/sealed_blob_store.dart';
import 'medical_record.dart';
import 'record_size_guard.dart';

/// Orchestrates AES-256-GCM encryption and local + cloud persistence of the
/// patient medical record (issue #14, US-1.3).
///
/// The [handle] passed to [write] and [read] is owned by the caller and must
/// be wiped after each call via [MasterKeyService.wipeHandle].
class MedicalRecordStore {
  MedicalRecordStore({
    required CryptoCore crypto,
    required BackendClient client,
    required SealedBlobStore localStore,
  })  : _crypto = crypto,
        _client = client,
        _localStore = localStore;

  final CryptoCore _crypto;
  final BackendClient _client;
  final SealedBlobStore _localStore;

  /// Encrypt [record], save locally, then upload to the cloud (US-1.3).
  ///
  /// Applies [RecordSizeGuard.truncate] to stay within the 500 Kio limit
  /// (oldest consultations dropped first). The local write is performed
  /// before the cloud PUT so that a network failure does not lose the record.
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
    final blob = await _crypto.encryptRecord(handle, plaintext);
    await _localStore.write(blob);
    await _client.put(anonymousUuid, blob);
  }

  /// Decrypt and return the medical record.
  ///
  /// Reads from the local cache first. If no local copy exists, fetches from
  /// the cloud (first open on a new device after key recovery, issue #12)
  /// and caches the result locally before decrypting.
  ///
  /// Throws [BlobNotFound] if neither local nor cloud has a copy.
  /// Throws [DecryptError] on a bad key or corrupted blob.
  Future<MedicalRecord> read(
    MasterKeyHandle handle,
    String anonymousUuid,
  ) async {
    var blob = await _localStore.read();
    if (blob == null) {
      blob = await _client.get(anonymousUuid);
      await _localStore.write(blob);
    }
    final plaintext = await _crypto.decryptRecord(handle, blob);
    final json =
        jsonDecode(utf8.decode(plaintext)) as Map<String, Object?>;
    return MedicalRecord.fromJson(json);
  }

  /// Whether a local record blob exists on this device.
  Future<bool> exists() => _localStore.exists();
}
