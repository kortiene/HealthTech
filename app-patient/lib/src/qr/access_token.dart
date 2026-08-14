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
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../cloud/backend_client.dart';
import '../cloud/media_client.dart';
import '../record/medical_record.dart';
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
  Future<QrPayload> generate({
    QrMode mode = QrMode.readWrite,
    Set<String> selectedMediaUuids = const {},
  });
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
  Future<QrPayload> generate({
    QrMode mode = QrMode.readWrite,
    Set<String> selectedMediaUuids = const {},
  }) async {
    final handle = await _masterKey.unsealForUse();
    try {
      final account = await _accountStore.read(handle);
      return await _tokenService.generate(
        account.anonymousUuid,
        handle,
        backendUrl,
        mode: mode,
        selectedMediaUuids: selectedMediaUuids,
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
    MediaClient? mediaClient,
  })  : _crypto = crypto,
        _recordStore = recordStore,
        _client = client,
        _mediaClient = mediaClient;

  final CryptoCore _crypto;
  final MedicalRecordStore _recordStore;
  final BackendClient _client;
  final MediaClient? _mediaClient;

  static final _rng = Random.secure();

  static Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _rng.nextInt(256)));

  /// Generate a [QrPayload] for [anonymousUuid].
  ///
  /// [handle] is the master-key handle from [MasterKeyService.unsealForUse];
  /// the caller owns the handle lifecycle and must wipe it after this returns.
  ///
  /// When [selectedMediaUuids] is non-empty and a [MediaClient] was injected,
  /// only those descriptors (matched by UUID) are uploaded to the backend before
  /// the session blob is generated. Their `url` is set to null in the QR payload —
  /// the doctor fetches them via [MediaClient.requestAccess]. Descriptors whose
  /// UUID is NOT in [selectedMediaUuids] are stripped entirely: the doctor has no
  /// UUID and cannot call requestAccess for the patient's local-only files.
  ///
  /// When [selectedMediaUuids] is empty, all `file://` descriptors are stripped
  /// without uploading — doctor sees the full text record but no attachments.
  ///
  /// Throws [BlobNotFound] when no local or cloud record exists yet.
  /// Throws [BackendUnavailable] when the session blob cannot be uploaded.
  /// Throws [MediaBackendUnavailable] when any selected upload fails.
  Future<QrPayload> generate(
    String anonymousUuid,
    MasterKeyHandle handle,
    String backendUrl, {
    QrMode mode = QrMode.readWrite,
    Set<String> selectedMediaUuids = const {},
  }) async {
    // 1-2. Generate ephemeral session key + write token (OS CSPRNG, never on disk).
    final sessionKey = _randomBytes(_kKeyBytes);
    final writeToken = _randomBytes(_kKeyBytes);

    // 3. Read current record (decrypted in Rust using the master handle).
    final record = await _recordStore.read(handle, anonymousUuid);

    // 4. Flush only the selected local media, then sanitise.
    //    Unselected file:// descriptors are stripped — doctor cannot access them.
    MedicalRecord qrRecord = record;
    if (selectedMediaUuids.isNotEmpty && _mediaClient != null) {
      final pending = _collectPendingMedia(record)
          .where((d) => selectedMediaUuids.contains(d.uuid))
          .toList();
      if (pending.isNotEmpty) {
        await _flushPendingMedia(pending, _mediaClient);
      }
    }
    qrRecord =
        _sanitiseFileUrls(record, selectedMediaUuids: selectedMediaUuids);

    // 5. Re-encrypt sanitised record with session key — doctor will decrypt with this key.
    final plaintext = Uint8List.fromList(qrRecord.toUtf8Bytes());
    final sessionBlob = await _encryptWithSession(sessionKey, plaintext);

    // 6. Upload session blob and register the write token with the backend.
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

  /// Collects all [MediaDescriptor]s with a local `file://` URL across the record.
  List<MediaDescriptor> _collectPendingMedia(MedicalRecord record) {
    final result = <MediaDescriptor>[];
    for (final c in record.consultations) {
      result
          .addAll(c.media.where((d) => d.url?.startsWith('file://') ?? false));
    }
    for (final cc in record.chronicConditions) {
      result.addAll(
        cc.documents.where((d) => d.url?.startsWith('file://') ?? false),
      );
    }
    for (final doc in record.documents) {
      if (doc.media.url?.startsWith('file://') ?? false) {
        result.add(doc.media);
      }
    }
    return result;
  }

  /// Reads each descriptor's on-disk ciphertext and uploads it via [client].
  ///
  /// The bytes at `file://` are already the XOR-encrypted ciphertext written at
  /// attach time — they are passed opaquely to the backend without re-encryption.
  Future<void> _flushPendingMedia(
    List<MediaDescriptor> pending,
    MediaClient client,
  ) async {
    for (final d in pending) {
      final path = d.url!.replaceFirst('file://', '');
      final bytes = await File(path).readAsBytes();
      await client.putMedia(d.uuid, bytes);
    }
  }

  /// Returns a copy of [record] with all `file://` descriptors handled.
  ///
  /// For each `file://` descriptor:
  ///   - UUID in [selectedMediaUuids] → url set to null (bytes were uploaded,
  ///     doctor fetches via requestAccess(uuid)).
  ///   - UUID NOT in [selectedMediaUuids] → descriptor removed entirely
  ///     (doctor has no UUID and cannot call requestAccess).
  ///
  /// When [selectedMediaUuids] is empty, all `file://` descriptors are removed.
  /// Non-file:// descriptors (cloud URLs or null) are always kept unchanged.
  /// Local `file://` paths are never embedded in the QR payload.
  MedicalRecord _sanitiseFileUrls(
    MedicalRecord record, {
    Set<String> selectedMediaUuids = const {},
  }) {
    bool isDirty(MediaDescriptor d) => d.url?.startsWith('file://') ?? false;

    MediaDescriptor nullUrl(MediaDescriptor d) => MediaDescriptor(
          uuid: d.uuid,
          contentKey: d.contentKey,
          contentHash: d.contentHash,
          mime: d.mime,
          sizeBytes: d.sizeBytes,
          addedAt: d.addedAt,
          alg: d.alg,
          durationMs: d.durationMs,
          // url intentionally omitted → null
        );

    // Selected file:// → null url (uploaded). Unselected → strip.
    List<MediaDescriptor> handle(List<MediaDescriptor> media) => media
        .map((d) {
          if (!isDirty(d)) return d;
          if (selectedMediaUuids.contains(d.uuid)) return nullUrl(d);
          return null;
        })
        .whereType<MediaDescriptor>()
        .toList();

    final sanitisedConsultations = record.consultations.map((c) {
      if (!c.media.any(isDirty)) return c;
      return Consultation(
        id: c.id,
        date: c.date,
        practitionerRef: c.practitionerRef,
        summary: c.summary,
        prescription: c.prescription,
        ordonnances: c.ordonnances,
        imageUrls: c.imageUrls,
        media: handle(c.media),
      );
    }).toList();

    final sanitisedConditions = record.chronicConditions.map((cc) {
      if (!cc.documents.any(isDirty)) return cc;
      return ChronicCondition(
        name: cc.name,
        icd10: cc.icd10,
        since: cc.since,
        documents: handle(cc.documents),
        severity: cc.severity,
        addedAt: cc.addedAt,
      );
    }).toList();

    // Admin documents: selected → keep with null url; unselected → strip entry.
    final sanitisedDocuments = record.documents
        .map((doc) {
          if (!isDirty(doc.media)) return doc;
          if (selectedMediaUuids.contains(doc.media.uuid)) {
            return doc.copyWithMedia(nullUrl(doc.media));
          }
          return null;
        })
        .whereType<PatientDocument>()
        .toList();

    return record.copyWith(
      consultations: sanitisedConsultations,
      chronicConditions: sanitisedConditions,
      documents: sanitisedDocuments,
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
