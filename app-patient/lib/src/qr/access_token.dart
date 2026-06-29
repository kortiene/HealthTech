// QR access tokens for consultation sessions (issue #16).
//
// [AccessTokenService] generates a fresh 256-bit session key, re-encrypts the
// patient's medical record with it, uploads the session blob to the backend,
// and embeds the key (base64url) + blob URL + 120 s expiry in a [QrPayload].
// The session key lives ONLY in RAM — never written to any storage layer.
//
// Zero-knowledge invariant: the server receives only an opaque ciphertext keyed
// by the anonymous UUID; the session key is visible only in the QR image and in
// the QrPayload for the 120 s access window.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../cloud/backend_client.dart';
import '../record/medical_record_store.dart';
import '../rust/crypto_core_bindings.dart';
import '../secure/master_key_service.dart';
import '../secure/patient_account.dart';

const int _kTtlSeconds = 120;
const int _kKeyBytes = 32;
const int _kVersion = 1;

/// Payload encoded inside the QR code for a consultation session.
///
/// The [sessionKey] is a 256-bit ephemeral key that lives in RAM only.
/// [toQrString] encodes it as base64url inside a JSON string for QR embedding.
/// Call [wipe] when the session ends to overwrite the key bytes in place.
class QrPayload {
  QrPayload({
    required this.uuid,
    required this.backendUrl,
    required this.sessionKey,
    required this.expiresAt,
  });

  /// Decode a QR payload string produced by [toQrString].
  factory QrPayload.fromQrString(String s) {
    final map = jsonDecode(s) as Map<String, Object?>;
    return QrPayload(
      uuid: map['uuid'] as String,
      backendUrl: map['url'] as String,
      sessionKey: base64Url.decode(map['key'] as String),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (map['exp'] as int) * 1000,
      ),
    );
  }

  final String uuid;
  final String backendUrl;

  /// 32-byte ephemeral session key (AES-256). In RAM only — never on disk.
  final Uint8List sessionKey;

  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// JSON string suitable for embedding in a QR code.
  String toQrString() => jsonEncode({
        'v': _kVersion,
        'uuid': uuid,
        'url': backendUrl,
        'key': base64Url.encode(sessionKey),
        'exp': expiresAt.millisecondsSinceEpoch ~/ 1000,
      });

  /// Overwrite [sessionKey] bytes in place (best-effort RAM scrub on expiry).
  void wipe() => sessionKey.fillRange(0, sessionKey.length, 0);
}

/// Abstract controller used by [QrScreen] — inject [DefaultQrController] in
/// production and a fake in tests.
abstract class QrController {
  Future<QrPayload> generate();
}

/// Production [QrController] that unseals the master key, reads the patient
/// account UUID, re-encrypts the medical record with a session key, uploads the
/// session blob, and returns the [QrPayload] (session key in RAM only).
class DefaultQrController implements QrController {
  DefaultQrController({
    required MasterKeyService masterKey,
    required PatientAccountStore accountStore,
    required AccessTokenService tokenService,
    required this.backendUrl,
  })  : _masterKey = masterKey,
        _accountStore = accountStore,
        _tokenService = tokenService;

  final MasterKeyService _masterKey;
  final PatientAccountStore _accountStore;
  final AccessTokenService _tokenService;
  final String backendUrl;

  @override
  Future<QrPayload> generate() async {
    final handle = await _masterKey.unsealForUse();
    try {
      final account = await _accountStore.read(handle);
      return await _tokenService.generate(
        account.anonymousUuid,
        handle,
        backendUrl,
      );
    } finally {
      await _masterKey.wipeHandle(handle);
    }
  }
}

/// Generates ephemeral QR access tokens for consultation sessions (#16).
///
/// On [generate]:
///   1. Generates a fresh 256-bit session key (OS CSPRNG, never persisted).
///   2. Reads and decrypts the patient record using the caller's [handle].
///   3. Re-encrypts the record with the session key via the Rust crypto core.
///   4. Uploads the session-encrypted blob to the backend.
///   5. Returns a [QrPayload] whose [QrPayload.sessionKey] lives in RAM only.
///
/// The caller must call [QrPayload.wipe] when the QR session ends or expires.
class AccessTokenService {
  AccessTokenService({
    required CryptoCore crypto,
    required MedicalRecordStore recordStore,
    required BackendClient client,
  })  : _crypto = crypto,
        _recordStore = recordStore,
        _client = client;

  final CryptoCore _crypto;
  final MedicalRecordStore _recordStore;
  final BackendClient _client;

  static final _rng = Random.secure();

  /// Generate a [QrPayload] for [anonymousUuid].
  ///
  /// [handle] is the master-key handle from [MasterKeyService.unsealForUse];
  /// the caller owns the handle lifecycle and must wipe it after this returns.
  ///
  /// Throws [BlobNotFound] when no local or cloud record exists yet.
  /// Throws [BackendUnavailable] when the session blob cannot be uploaded.
  Future<QrPayload> generate(
    String anonymousUuid,
    MasterKeyHandle handle,
    String backendUrl,
  ) async {
    // 1. Generate ephemeral session key — OS CSPRNG bytes, never on disk.
    final sessionKey = Uint8List.fromList(
      List.generate(_kKeyBytes, (_) => _rng.nextInt(256)),
    );

    // 2. Read current record (decrypted in Rust using the master handle).
    final record = await _recordStore.read(handle, anonymousUuid);
    final plaintext = Uint8List.fromList(record.toUtf8Bytes());

    // 3. Re-encrypt with session key — doctor will decrypt with this key.
    final sessionBlob = await _encryptWithSession(sessionKey, plaintext);

    // 4. Upload session blob; doctor fetches and decrypts with sessionKey.
    await _client.put(anonymousUuid, sessionBlob);

    return QrPayload(
      uuid: anonymousUuid,
      backendUrl: backendUrl,
      sessionKey: sessionKey,
      expiresAt: DateTime.now().add(const Duration(seconds: _kTtlSeconds)),
    );
  }

  Future<Uint8List> _encryptWithSession(
    Uint8List sessionKey,
    Uint8List plaintext,
  ) async {
    final kHandle = await _crypto.handleFromUnsealed(sessionKey);
    try {
      return await _crypto.encryptRecord(kHandle, plaintext);
    } finally {
      await _crypto.wipe(kHandle);
    }
  }
}
