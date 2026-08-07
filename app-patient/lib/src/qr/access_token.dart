// QR access tokens for consultation sessions (issue #16 / #118).
//
// [AccessTokenService] generates a fresh 256-bit session key, re-encrypts the
// patient's medical record with it, uploads the session blob to the backend
// (with an ephemeral write token), and embeds the key + blob URL + 120 s expiry
// in a [QrPayload].
//
// Write-token enforcement (#118):
//   - In [QrMode.readWrite]: a 32-byte CSPRNG write token is generated, registered
//     on the backend via X-Write-Token, and embedded in the QR (`wt` field).
//     The doctor's PWA presents it as `Authorization: Bearer {wt}` on PUT.
//   - In [QrMode.readOnly]: the write token is still generated and registered so
//     the backend enforces the restriction, but it is NOT included in the QR.
//     The doctor's PWA cannot write back (backend returns 403).
//
// Zero-knowledge invariant: the server receives only opaque ciphertext keyed by
// the anonymous UUID; session key and write token are visible only in the QR
// image / QrPayload for the 120 s access window.

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

/// Whether the doctor may write back a note during this session.
enum QrMode { readOnly, readWrite }

/// Payload encoded inside the QR code for a consultation session.
///
/// The [sessionKey] is a 256-bit ephemeral key (in RAM only).
/// In [QrMode.readWrite] sessions the [writeToken] is also present — the doctor
/// presents it as `Authorization: Bearer` to write back to the backend.
/// Both [sessionKey] and [writeToken] are scrubbed by [wipe].
class QrPayload {
  QrPayload({
    required this.uuid,
    required this.backendUrl,
    required this.sessionKey,
    required this.expiresAt,
    this.writeToken,
  });

  /// Decode a QR payload string produced by [toQrString].
  factory QrPayload.fromQrString(String s) {
    final map = jsonDecode(s) as Map<String, Object?>;
    Uint8List? wt;
    if (map['wt'] != null) {
      wt = base64Url.decode(map['wt'] as String);
    }
    return QrPayload(
      uuid: map['uuid'] as String,
      backendUrl: map['url'] as String,
      sessionKey: base64Url.decode(map['key'] as String),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (map['exp'] as int) * 1000,
      ),
      writeToken: wt,
    );
  }

  final String uuid;
  final String backendUrl;

  /// 32-byte ephemeral session key (AES-256). In RAM only — never on disk.
  final Uint8List sessionKey;

  final DateTime expiresAt;

  /// 32-byte write token. Present only in [QrMode.readWrite] sessions.
  /// In RAM only — wiped by [wipe]. Never logged or stored to disk.
  final Uint8List? writeToken;

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// True when the doctor may not write back (no write token in QR).
  bool get isReadOnly => writeToken == null;

  /// JSON string suitable for embedding in a QR code.
  String toQrString() => jsonEncode({
        'v': _kVersion,
        'uuid': uuid,
        'url': backendUrl,
        'key': base64Url.encode(sessionKey),
        'exp': expiresAt.millisecondsSinceEpoch ~/ 1000,
        if (writeToken != null) 'wt': base64Url.encode(writeToken!),
      });

  /// Overwrite [sessionKey] and [writeToken] bytes in place (best-effort RAM
  /// scrub on expiry / screen dispose).
  void wipe() {
    sessionKey.fillRange(0, sessionKey.length, 0);
    writeToken?.fillRange(0, writeToken!.length, 0);
  }
}

/// Abstract controller used by [QrScreen] — inject [DefaultQrController] in
/// production and a fake in tests.
abstract class QrController {
  Future<QrPayload> generate({QrMode mode = QrMode.readWrite});
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
  Future<QrPayload> generate({QrMode mode = QrMode.readWrite}) async {
    final handle = await _masterKey.unsealForUse();
    try {
      final account = await _accountStore.read(handle);
      return await _tokenService.generate(
        account.anonymousUuid,
        handle,
        backendUrl,
        mode: mode,
      );
    } finally {
      await _masterKey.wipeHandle(handle);
    }
  }
}

/// Generates ephemeral QR access tokens for consultation sessions (#16 / #118).
///
/// On [generate]:
///   1. Generates a fresh 256-bit session key (OS CSPRNG, never persisted).
///   2. Generates a fresh 256-bit write token (OS CSPRNG, never persisted).
///   3. Reads and decrypts the patient record using the caller's [handle].
///   4. Re-encrypts the record with the session key via the Rust crypto core.
///   5. Uploads the session-encrypted blob to the backend with
///      `X-Write-Token: {writeToken}` — the backend registers the token.
///   6. Returns a [QrPayload] embedding the write token only in [QrMode.readWrite].
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

  static Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _rng.nextInt(256)));

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
    String backendUrl, {
    QrMode mode = QrMode.readWrite,
  }) async {
    // 1-2. Generate ephemeral session key + write token (OS CSPRNG, never on disk).
    final sessionKey = _randomBytes(_kKeyBytes);
    final writeToken = _randomBytes(_kKeyBytes);

    // 3. Read current record (decrypted in Rust using the master handle).
    final record = await _recordStore.read(handle, anonymousUuid);
    final plaintext = Uint8List.fromList(record.toUtf8Bytes());

    // 4. Re-encrypt with session key — doctor will decrypt with this key.
    final sessionBlob = await _encryptWithSession(sessionKey, plaintext);

    // 5. Upload session blob and register the write token with the backend.
    //    The backend stores the token for this UUID (TTL = 120 s).
    await _client.put(anonymousUuid, sessionBlob, writeToken: writeToken);

    return QrPayload(
      uuid: anonymousUuid,
      backendUrl: backendUrl,
      sessionKey: sessionKey,
      expiresAt: DateTime.now().add(const Duration(seconds: _kTtlSeconds)),
      // In read-only mode the write token is NOT embedded in the QR — the doctor
      // cannot write back because they never see it.
      writeToken: mode == QrMode.readWrite ? writeToken : null,
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
