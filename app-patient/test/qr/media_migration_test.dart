// Tests for downloadPendingMedia (issue #152 — local-first media migration).
//
// Verified properties:
//   - url:null descriptor in a consultation is downloaded, written to file://,
//     and returned in toDelete.
//   - url:file:// descriptor is left untouched (idempotent).
//   - url:null in ChronicCondition.documents is migrated.
//   - url:null in PatientDocument.media is migrated.
//   - Network failure (requestAccess throws) keeps url:null; UUID not in toDelete.
//   - Integrity failure (hash mismatch) keeps url:null; UUID not in toDelete.
//   - Ciphertext (not plaintext) is written to the local file — consistent with
//     patient_record_screen.dart.
//   - DELETE must not appear in toDelete until after local file is written.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_patient/src/cloud/media_client.dart';
import 'package:app_patient/src/qr/media_migration.dart';
import 'package:app_patient/src/record/media_cipher.dart';
import 'package:app_patient/src/record/medical_record.dart';
import 'package:app_patient/src/rust/crypto_core_bindings.dart';

// ─── Fakes ────────────────────────────────────────────────────────────────────

class _FakeHandle implements MasterKeyHandle {}

/// XOR 0x5A symmetric fake — encrypt == decrypt, key-agnostic.
class _FakeCrypto implements CryptoCore {
  const _FakeCrypto();
  static const _xor = 0x5A;

  @override
  Future<MasterKeyHandle> generateMasterKey() async => _FakeHandle();
  @override
  Future<Uint8List> exportSealable(MasterKeyHandle h) async => Uint8List(32);
  @override
  Future<MasterKeyHandle> handleFromUnsealed(Uint8List clearBytes) async =>
      _FakeHandle();
  @override
  Future<void> wipe(MasterKeyHandle h) async {}
  @override
  Future<Uint8List> encryptRecord(MasterKeyHandle h, Uint8List p) async =>
      Uint8List.fromList(p.map((b) => b ^ _xor).toList());
  @override
  Future<Uint8List> decryptRecord(MasterKeyHandle h, Uint8List c) async =>
      Uint8List.fromList(c.map((b) => b ^ _xor).toList());
  @override
  Future<Uint8List> sealRecoveryEnvelope(
    Uint8List masterKeyClear,
    Uint8List secret,
    int iterations,
  ) async =>
      Uint8List(0);
  @override
  Future<MasterKeyHandle> openRecoveryEnvelope(
    Uint8List secret,
    Uint8List envelopeBytes,
  ) async =>
      _FakeHandle();
  @override
  Future<Uint8List> normalizeRecoveryAnswers(List<String> answers) async =>
      Uint8List(0);
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

const _fakeCipher = MediaCipher(_FakeCrypto());
const _xor = 0x5A;

/// XOR-encrypts [plaintext] to produce the ciphertext that a server would hold.
Uint8List _encrypt(Uint8List plaintext) =>
    Uint8List.fromList(plaintext.map((b) => b ^ _xor).toList());

/// Builds a url:null [MediaDescriptor] whose ciphertext on the server is the
/// XOR-0x5A encryption of [plaintext] (matches _FakeCrypto).
MediaDescriptor _pendingDescriptor({
  required String uuid,
  required Uint8List plaintext,
  String mime = 'image/jpeg',
}) {
  return MediaDescriptor(
    uuid: uuid,
    contentKey: base64.encode(Uint8List(32)),
    contentHash: sha256.convert(plaintext).toString(),
    mime: mime,
    sizeBytes: plaintext.length,
    addedAt: '2026-07-30T00:00:00Z',
  );
}

/// Builds a url:file:// [MediaDescriptor] (already migrated).
MediaDescriptor _localDescriptor({required String uuid}) {
  return MediaDescriptor(
    uuid: uuid,
    contentKey: base64.encode(Uint8List(32)),
    contentHash: 'abc123',
    mime: 'image/jpeg',
    sizeBytes: 64,
    addedAt: '2026-07-30T00:00:00Z',
    url: 'file:///device/media_$uuid.jpg',
  );
}

const _kPatientId = 'patient-test-uuid';
const _kDate = '2026-07-30T00:00:00Z';

MedicalRecord _emptyRecord() => const MedicalRecord(
      patientId: _kPatientId,
      createdAt: _kDate,
      updatedAt: _kDate,
    );

/// [MockClient] that serves [ciphertexts] keyed by UUID on GET, returns 200
/// on POST /access, and records DELETE UUIDs in [deleted].
MediaClient _makeClient({
  Map<String, Uint8List> ciphertexts = const {},
  List<String>? deleted,
  bool failAccess = false,
}) {
  return MediaClient(
    'http://fake',
    httpClient: MockClient((req) async {
      if (req.method == 'POST' && req.url.path.endsWith('/access')) {
        if (failAccess) return http.Response('unavailable', 503);
        final uuid = req.url.pathSegments[req.url.pathSegments.length - 2];
        return http.Response(
          '{"url":"http://fake/dl/$uuid","expires_at":"2099-01-01T00:00:00Z"}',
          200,
        );
      }
      if (req.method == 'GET') {
        final uuid = req.url.pathSegments.last;
        final body = ciphertexts[uuid] ?? Uint8List(0);
        return http.Response.bytes(body, 200);
      }
      if (req.method == 'DELETE') {
        final uuid = req.url.pathSegments.last;
        deleted?.add(uuid);
        return http.Response('', 204);
      }
      return http.Response('not found', 404);
    }),
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  late Directory tmpDir;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('media_migration_test_');
  });

  tearDown(() {
    tmpDir.deleteSync(recursive: true);
  });

  group('downloadPendingMedia — consultation media', () {
    test('url:null descriptor is downloaded and replaced with file://',
        () async {
      final plaintext = Uint8List.fromList([1, 2, 3, 4]);
      final ciphertext = _encrypt(plaintext);
      const uuid = 'media-uuid-001';
      final desc = _pendingDescriptor(uuid: uuid, plaintext: plaintext);
      final consultation = Consultation(
        id: 'consult-1',
        date: '2026-07-30',
        practitionerRef: 'dr-001',
        summary: 'Check-up',
        media: [desc],
      );
      final record = _emptyRecord().copyWith(consultations: [consultation]);

      final client = _makeClient(ciphertexts: {uuid: ciphertext});
      final (updated, toDelete) = await downloadPendingMedia(
        record,
        client,
        _fakeCipher,
        dir: tmpDir,
      );

      final updatedDesc = updated.consultations.first.media.first;
      expect(updatedDesc.uuid, uuid);
      expect(updatedDesc.url, startsWith('file://'));
      expect(toDelete, contains(uuid));
    });

    test('local file contains ciphertext, not plaintext', () async {
      final plaintext = Uint8List.fromList([10, 20, 30]);
      final ciphertext = _encrypt(plaintext);
      const uuid = 'media-cipher-check';
      final desc = _pendingDescriptor(uuid: uuid, plaintext: plaintext);
      final consultation = Consultation(
        id: 'c2',
        date: '2026-07-30',
        practitionerRef: 'dr-001',
        summary: 'X-ray',
        media: [desc],
      );
      final record = _emptyRecord().copyWith(consultations: [consultation]);
      final client = _makeClient(ciphertexts: {uuid: ciphertext});

      final (updated, _) = await downloadPendingMedia(
        record,
        client,
        _fakeCipher,
        dir: tmpDir,
      );

      final url = updated.consultations.first.media.first.url!;
      final onDisk = await File(url.replaceFirst('file://', '')).readAsBytes();
      // File must hold the ciphertext — not plaintext.
      expect(onDisk, equals(ciphertext));
    });

    test('url:file:// descriptor is left untouched (idempotent)', () async {
      const uuid = 'already-local';
      final desc = _localDescriptor(uuid: uuid);
      final consultation = Consultation(
        id: 'c3',
        date: '2026-07-30',
        practitionerRef: 'dr-001',
        summary: 'Follow-up',
        media: [desc],
      );
      final record = _emptyRecord().copyWith(consultations: [consultation]);
      final client = _makeClient();

      final (updated, toDelete) = await downloadPendingMedia(
        record,
        client,
        _fakeCipher,
        dir: tmpDir,
      );

      expect(
        updated.consultations.first.media.first.url,
        equals('file:///device/media_$uuid.jpg'),
      );
      expect(toDelete, isEmpty);
    });

    test('network failure keeps url:null and UUID not in toDelete', () async {
      const uuid = 'fail-uuid';
      final desc = _pendingDescriptor(
        uuid: uuid,
        plaintext: Uint8List.fromList([5, 6, 7]),
      );
      final consultation = Consultation(
        id: 'c4',
        date: '2026-07-30',
        practitionerRef: 'dr-001',
        summary: 'MRI',
        media: [desc],
      );
      final record = _emptyRecord().copyWith(consultations: [consultation]);
      final client = _makeClient(failAccess: true);

      final (updated, toDelete) = await downloadPendingMedia(
        record,
        client,
        _fakeCipher,
        dir: tmpDir,
      );

      expect(updated.consultations.first.media.first.url, isNull);
      expect(toDelete, isEmpty);
    });

    test(
        'integrity failure (wrong hash) keeps url:null and UUID not in toDelete',
        () async {
      final plaintext = Uint8List.fromList([1, 2, 3]);
      final ciphertext = _encrypt(plaintext);
      const uuid = 'tampered-uuid';
      // Descriptor claims a different hash → MediaIntegrityError.
      final desc = MediaDescriptor(
        uuid: uuid,
        contentKey: base64.encode(Uint8List(32)),
        contentHash: 'wrong_hash_not_sha256',
        mime: 'image/jpeg',
        sizeBytes: plaintext.length,
        addedAt: _kDate,
      );
      final consultation = Consultation(
        id: 'c5',
        date: '2026-07-30',
        practitionerRef: 'dr-001',
        summary: 'CT scan',
        media: [desc],
      );
      final record = _emptyRecord().copyWith(consultations: [consultation]);
      final client = _makeClient(ciphertexts: {uuid: ciphertext});

      final (updated, toDelete) = await downloadPendingMedia(
        record,
        client,
        _fakeCipher,
        dir: tmpDir,
      );

      expect(updated.consultations.first.media.first.url, isNull);
      expect(toDelete, isEmpty);
    });
  });

  group('downloadPendingMedia — chronicCondition documents', () {
    test('url:null document in ChronicCondition is migrated', () async {
      final plaintext = Uint8List.fromList([0xAB, 0xCD]);
      final ciphertext = _encrypt(plaintext);
      const uuid = 'cc-doc-uuid';
      final desc = _pendingDescriptor(uuid: uuid, plaintext: plaintext);
      final condition = ChronicCondition(
        name: 'Diabète type 2',
        documents: [desc],
      );
      final record = _emptyRecord().copyWith(chronicConditions: [condition]);
      final client = _makeClient(ciphertexts: {uuid: ciphertext});

      final (updated, toDelete) = await downloadPendingMedia(
        record,
        client,
        _fakeCipher,
        dir: tmpDir,
      );

      final updatedDoc = updated.chronicConditions.first.documents.first;
      expect(updatedDoc.url, startsWith('file://'));
      expect(toDelete, contains(uuid));
    });
  });

  group('downloadPendingMedia — PatientDocument media', () {
    test('url:null PatientDocument media is migrated', () async {
      final plaintext = Uint8List.fromList([0x11, 0x22, 0x33]);
      final ciphertext = _encrypt(plaintext);
      const uuid = 'patient-doc-uuid';
      final desc = _pendingDescriptor(
        uuid: uuid,
        plaintext: plaintext,
        mime: 'application/pdf',
      );
      final doc = PatientDocument(
        id: 'doc-1',
        type: DocumentType.other,
        label: 'Carte CMU',
        media: desc,
        addedAt: _kDate,
      );
      final record = _emptyRecord().copyWith(documents: [doc]);
      final client = _makeClient(ciphertexts: {uuid: ciphertext});

      final (updated, toDelete) = await downloadPendingMedia(
        record,
        client,
        _fakeCipher,
        dir: tmpDir,
      );

      final updatedMedia = updated.documents.first.media;
      expect(updatedMedia.url, startsWith('file://'));
      expect(updatedMedia.url, endsWith('.pdf'));
      expect(toDelete, contains(uuid));
    });
  });

  group('downloadPendingMedia — no-op when nothing pending', () {
    test('record with no url:null descriptors returns same record object',
        () async {
      final record = _emptyRecord();
      final client = _makeClient();

      final (updated, toDelete) = await downloadPendingMedia(
        record,
        client,
        _fakeCipher,
        dir: tmpDir,
      );

      expect(identical(updated, record), isTrue);
      expect(toDelete, isEmpty);
    });
  });

  group('downloadPendingMedia — file extension from MIME', () {
    for (final entry in {
      'image/jpeg': '.jpg',
      'image/png': '.png',
      'audio/mpeg': '.mp3',
      'application/pdf': '.pdf',
      'video/mp4': '.mp4',
      'application/octet-stream': '.bin',
    }.entries) {
      test('${entry.key} → ${entry.value}', () async {
        final plaintext = Uint8List.fromList([0x01]);
        final ciphertext = _encrypt(plaintext);
        const uuid = 'ext-test-uuid';
        final desc = _pendingDescriptor(
          uuid: uuid,
          plaintext: plaintext,
          mime: entry.key,
        );
        final consultation = Consultation(
          id: 'cExt',
          date: '2026-07-30',
          practitionerRef: 'dr-001',
          summary: 'Ext test',
          media: [desc],
        );
        final record = _emptyRecord().copyWith(consultations: [consultation]);
        final client = _makeClient(ciphertexts: {uuid: ciphertext});

        final (updated, _) = await downloadPendingMedia(
          record,
          client,
          _fakeCipher,
          dir: tmpDir,
        );

        final url = updated.consultations.first.media.first.url!;
        expect(url, endsWith(entry.value));
      });
    }
  });
}
