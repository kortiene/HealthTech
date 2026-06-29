// Doctor-side consultation session (issue #17 — US-2.1).
//
// [ScanService.parseQr] validates the raw QR string and rejects expired tokens.
// [ScanService.fetchAndDecrypt] downloads the session blob from the backend and
// decrypts it entirely in RAM using the Rust crypto core.  No plaintext is ever
// written to disk — the Rust handle is wiped in a finally block immediately after
// the plaintext bytes are deserialized, and the [MedicalRecord] lives only on the
// Dart heap until the caller disposes it.

import 'dart:convert';

import '../cloud/backend_client.dart';
import '../qr/access_token.dart';
import '../record/medical_record.dart';
import '../rust/crypto_core_bindings.dart';

/// Thrown when a scanned QR code's expiry timestamp is in the past.
class ExpiredQrCode implements Exception {
  const ExpiredQrCode();

  @override
  String toString() =>
      'QR expiré — veuillez demander un nouveau code au patient';
}

/// Orchestrates the doctor-side consultation open flow (US-2.1, #17).
///
/// [parseQr] is a static helper that decodes the raw QR string and rejects
/// expired tokens.  [fetchAndDecrypt] downloads the session blob and decrypts
/// it entirely in RAM using the session key embedded in the [QrPayload].
/// No plaintext leaves the method — the Rust handle is wiped in a finally block.
class ScanService {
  ScanService({
    required CryptoCore crypto,
    required BackendClient client,
  })  : _crypto = crypto,
        _client = client;

  final CryptoCore _crypto;
  final BackendClient _client;

  /// Parse [rawValue] from a QR scan result into a [QrPayload].
  ///
  /// Throws [ExpiredQrCode] when [QrPayload.isExpired] is true.
  /// Throws [FormatException] when [rawValue] is not a valid JSON payload.
  static QrPayload parseQr(String rawValue) {
    final payload = QrPayload.fromQrString(rawValue);
    if (payload.isExpired) throw const ExpiredQrCode();
    return payload;
  }

  /// Download and decrypt the session blob for [payload] entirely in RAM.
  ///
  /// 1. GET /blob/{payload.uuid} — fetches the session-encrypted blob.
  /// 2. handleFromUnsealed(payload.sessionKey) — wraps the session key in Rust.
  /// 3. decryptRecord(handle, blob) — AES-256-GCM in Rust; plaintext stays RAM.
  /// 4. wipe(handle) — zeroes the Rust-side key bytes in a finally block.
  /// 5. MedicalRecord.fromJson — deserializes; record lives only on Dart heap.
  ///
  /// Throws [BlobNotFound] if the session blob is gone (server-side expiry).
  /// Throws [BackendUnavailable] on network failure.
  /// Throws [DecryptError] if the session key does not match the blob.
  Future<MedicalRecord> fetchAndDecrypt(QrPayload payload) async {
    final blob = await _client.get(payload.uuid);
    final handle = await _crypto.handleFromUnsealed(payload.sessionKey);
    try {
      final plaintext = await _crypto.decryptRecord(handle, blob);
      final json = jsonDecode(utf8.decode(plaintext)) as Map<String, Object?>;
      return MedicalRecord.fromJson(json);
    } finally {
      await _crypto.wipe(handle);
    }
  }
}
