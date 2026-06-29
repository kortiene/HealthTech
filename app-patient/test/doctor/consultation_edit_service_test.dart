// Unit tests for ConsultationEditService (issue #18 — US-2.2).
//
// Verified properties:
//   - reEncrypt round-trips: the produced blob decrypts back to the merged record.
//   - Handle is wiped after successful encryption (finally honoured).
//   - Handle is wiped even when encryptRecord throws (finally honoured on error).
//   - Uses handleFromUnsealed(payload.sessionKey): the session key, never master.
//   - ZK: no BackendClient; no PUT is possible — structural guarantee.
//   - Size guard (happy path): a merged record that exceeds 500 Kio is truncated;
//     the newly added consultation survives (it is the newest by date).
//   - Size guard (new is oldest): when the new consultation's date pre-dates all
//     existing ones, truncation drops it first → RecordFullException.
//   - Size guard (fixed sections overflow): when the record's non-consultation
//     sections alone exceed the budget → RecordFullException.
//   - RecordFullException.toString() contains no record plaintext or key material.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/doctor/consultation_edit_service.dart';
import 'package:app_patient/src/qr/access_token.dart';
import 'package:app_patient/src/record/medical_record.dart';
import 'package:app_patient/src/rust/crypto_core_bindings.dart';

// ─── Fakes ────────────────────────────────────────────────────────────────────

class _FakeMasterKeyHandle implements MasterKeyHandle {
  const _FakeMasterKeyHandle();
}

/// XOR-based fake matching the pattern from scan_service_test.dart.
/// encrypt == decrypt == XOR 0x5A, invertible and deterministic.
class _FakeCryptoCore implements CryptoCore {
  const _FakeCryptoCore();
  static const _xor = 0x5A;

  Uint8List _xorBytes(Uint8List data) =>
      Uint8List.fromList(data.map((b) => b ^ _xor).toList());

  @override
  Future<MasterKeyHandle> generateMasterKey() async =>
      const _FakeMasterKeyHandle();

  @override
  Future<Uint8List> exportSealable(MasterKeyHandle handle) async =>
      Uint8List(32);

  @override
  Future<MasterKeyHandle> handleFromUnsealed(Uint8List clearBytes) async =>
      const _FakeMasterKeyHandle();

  @override
  Future<void> wipe(MasterKeyHandle handle) async {}

  @override
  Future<Uint8List> encryptRecord(
    MasterKeyHandle handle,
    Uint8List plaintext,
  ) async =>
      _xorBytes(plaintext);

  @override
  Future<Uint8List> decryptRecord(
    MasterKeyHandle handle,
    Uint8List ciphertext,
  ) async =>
      _xorBytes(ciphertext);

  @override
  Future<Uint8List> sealRecoveryEnvelope(
    Uint8List masterKeyClear,
    Uint8List secret,
    int iterations,
  ) async =>
      Uint8List(32);

  @override
  Future<MasterKeyHandle> openRecoveryEnvelope(
    Uint8List secret,
    Uint8List envelopeBytes,
  ) async =>
      const _FakeMasterKeyHandle();

  @override
  Future<Uint8List> normalizeRecoveryAnswers(List<String> answers) async =>
      Uint8List.fromList(answers.join('\x1f').codeUnits);
}

/// Counts wipe calls; optionally throws on encryptRecord.
class _TrackingCryptoCore implements CryptoCore {
  _TrackingCryptoCore({this.failEncrypt = false});

  final bool failEncrypt;
  var wipeCount = 0;
  Uint8List? lastKeyPassedToHandleFromUnsealed;

  static const _xor = 0x5A;

  Uint8List _xorBytes(Uint8List data) =>
      Uint8List.fromList(data.map((b) => b ^ _xor).toList());

  @override
  Future<MasterKeyHandle> generateMasterKey() async =>
      const _FakeMasterKeyHandle();

  @override
  Future<Uint8List> exportSealable(MasterKeyHandle handle) async =>
      Uint8List(32);

  @override
  Future<MasterKeyHandle> handleFromUnsealed(Uint8List clearBytes) async {
    lastKeyPassedToHandleFromUnsealed = clearBytes;
    return const _FakeMasterKeyHandle();
  }

  @override
  Future<void> wipe(MasterKeyHandle handle) async => wipeCount++;

  @override
  Future<Uint8List> encryptRecord(
    MasterKeyHandle handle,
    Uint8List plaintext,
  ) async {
    if (failEncrypt) {
      throw const DecryptError(); // reuse as a generic crypto error
    }
    return _xorBytes(plaintext);
  }

  @override
  Future<Uint8List> decryptRecord(
    MasterKeyHandle handle,
    Uint8List ciphertext,
  ) async =>
      _xorBytes(ciphertext);

  @override
  Future<Uint8List> sealRecoveryEnvelope(
    Uint8List masterKeyClear,
    Uint8List secret,
    int iterations,
  ) async =>
      Uint8List(32);

  @override
  Future<MasterKeyHandle> openRecoveryEnvelope(
    Uint8List secret,
    Uint8List envelopeBytes,
  ) async =>
      const _FakeMasterKeyHandle();

  @override
  Future<Uint8List> normalizeRecoveryAnswers(List<String> answers) async =>
      Uint8List.fromList(answers.join('\x1f').codeUnits);
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

const _kPatientId = 'patient-fake-uuid-001';
const _kCreatedAt = '2025-01-01T00:00:00Z';
const _kUpdatedAt = '2026-06-29T08:00:00Z';
const _kNewId = 'new-consult-fake-uuid-001';

/// Byte size chosen to put 6 consultations with this summary well over 512 000 B
/// (≈ 6 × 91 KiB ≈ 546 KiB) while 5 consultations fit (≈ 455 KiB < 500 KiB).
const _kPadSize = 90000;

QrPayload _fakePayload() => QrPayload(
      uuid: _kPatientId,
      backendUrl: 'http://backend.test',
      sessionKey: Uint8List.fromList(List.filled(32, 0x42)),
      expiresAt: DateTime.now().add(const Duration(seconds: 120)),
    );

ConsultationEditService _svc(CryptoCore crypto) =>
    ConsultationEditService(crypto: crypto);

/// Smallest useful merged record: one consultation, well under the 500 KiB limit.
MedicalRecord _smallMergedRecord() => const MedicalRecord(
      patientId: _kPatientId,
      consultations: [
        Consultation(
          id: _kNewId,
          date: '2026-06-29',
          practitionerRef: 'dr-fake',
          summary: 'Bilan annuel',
        ),
      ],
      createdAt: _kCreatedAt,
      updatedAt: _kUpdatedAt,
    );

/// Merged record with 5 existing + 1 new consultation, each padded to ~90 KiB
/// summary. Total exceeds 500 KiB; new consultation (newest date) is last.
MedicalRecord _oversizedMergedRecord({required String newDate}) {
  final pad = 'x' * _kPadSize;
  final existing = [
    for (var i = 0; i < 5; i++)
      Consultation(
        id: 'existing-$i',
        date: '2025-0${i + 1}-01',
        practitionerRef: 'dr-fake',
        summary: pad,
      ),
  ];
  final merged = [
    ...existing,
    Consultation(
      id: _kNewId,
      date: newDate,
      practitionerRef: 'dr-fake',
      summary: pad,
    ),
  ];
  return MedicalRecord(
    patientId: _kPatientId,
    consultations: merged,
    createdAt: _kCreatedAt,
    updatedAt: _kUpdatedAt,
  );
}

/// Merges the result of XOR-decoding [blob] back into a MedicalRecord.
MedicalRecord _xorDecodeRecord(Uint8List blob) {
  final plain = Uint8List.fromList(blob.map((b) => b ^ 0x5A).toList());
  final map = jsonDecode(utf8.decode(plain)) as Map<String, Object?>;
  return MedicalRecord.fromJson(map);
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('ConsultationEditService.reEncrypt — round-trip', () {
    test('produced blob decrypts back to the merged record', () async {
      final svc = _svc(const _FakeCryptoCore());
      final merged = _smallMergedRecord();
      final blob = await svc.reEncrypt(
        merged,
        _fakePayload(),
        newConsultationId: _kNewId,
      );
      final recovered = _xorDecodeRecord(blob);
      expect(recovered, equals(merged));
    });

    test('result is non-empty bytes', () async {
      final svc = _svc(const _FakeCryptoCore());
      final blob = await svc.reEncrypt(
        _smallMergedRecord(),
        _fakePayload(),
        newConsultationId: _kNewId,
      );
      expect(blob, isNotEmpty);
    });
  });

  group('ConsultationEditService.reEncrypt — handle lifecycle', () {
    test('wipes the Rust handle exactly once after success', () async {
      final crypto = _TrackingCryptoCore();
      await _svc(crypto).reEncrypt(
        _smallMergedRecord(),
        _fakePayload(),
        newConsultationId: _kNewId,
      );
      expect(crypto.wipeCount, 1);
    });

    test('wipes the Rust handle even when encryptRecord throws', () async {
      final crypto = _TrackingCryptoCore(failEncrypt: true);
      await expectLater(
        _svc(crypto).reEncrypt(
          _smallMergedRecord(),
          _fakePayload(),
          newConsultationId: _kNewId,
        ),
        throwsA(isA<DecryptError>()),
      );
      expect(crypto.wipeCount, 1);
    });

    test('passes payload.sessionKey to handleFromUnsealed', () async {
      final crypto = _TrackingCryptoCore();
      final payload = _fakePayload();
      await _svc(crypto).reEncrypt(
        _smallMergedRecord(),
        payload,
        newConsultationId: _kNewId,
      );
      expect(
        crypto.lastKeyPassedToHandleFromUnsealed,
        equals(payload.sessionKey),
      );
    });

    test(
        'RecordFullException from guard throws before handle creation: '
        'wipe is never called', () async {
      // _guardKeepingNewest throws BEFORE handleFromUnsealed is called.
      // No handle was ever created, so wipeCount must remain 0.
      final crypto = _TrackingCryptoCore();
      await expectLater(
        _svc(crypto).reEncrypt(
          _oversizedMergedRecord(newDate: '2000-01-01'),
          _fakePayload(),
          newConsultationId: _kNewId,
        ),
        throwsA(isA<RecordFullException>()),
      );
      expect(crypto.wipeCount, 0);
    });
  });

  group('ConsultationEditService — ZK / no-PUT guarantee', () {
    test('ConsultationEditService constructor takes no BackendClient', () {
      // Structural test: the service's public interface accepts only CryptoCore.
      // A BackendClient cannot be injected → no accidental cloud PUT is possible.
      final svc = ConsultationEditService(crypto: const _FakeCryptoCore());
      expect(svc, isNotNull);
    });
  });

  group('ConsultationEditService.reEncrypt — size guard', () {
    test(
        'oversized record: new (newest) consultation is retained after truncation',
        () async {
      // 6 consultations × ~90 KiB ≈ 540 KiB > 512 KiB → truncation needed.
      // New consultation has date '2026-06-29' (newest) → truncation drops one
      // of the 2025 consultations, keeping the new one.
      final merged = _oversizedMergedRecord(newDate: '2026-06-29');
      final svc = _svc(const _FakeCryptoCore());
      final blob = await svc.reEncrypt(
        merged,
        _fakePayload(),
        newConsultationId: _kNewId,
      );
      final recovered = _xorDecodeRecord(blob);
      expect(
        recovered.consultations.any((c) => c.id == _kNewId),
        isTrue,
        reason: 'New consultation must survive truncation',
      );
    });

    test(
        'oversized record: at least one old consultation is dropped to make it fit',
        () async {
      final merged = _oversizedMergedRecord(newDate: '2026-06-29');
      final svc = _svc(const _FakeCryptoCore());
      final blob = await svc.reEncrypt(
        merged,
        _fakePayload(),
        newConsultationId: _kNewId,
      );
      final recovered = _xorDecodeRecord(blob);
      // 6 consultations in, must be fewer after truncation.
      expect(recovered.consultations.length, lessThan(6));
    });

    test(
        'RecordFullException when new consultation is oldest and gets truncated',
        () async {
      // New consultation has date '2000-01-01' (oldest) → truncation drops it
      // before any 2025 entry → new consultation id absent → RecordFullException.
      final merged = _oversizedMergedRecord(newDate: '2000-01-01');
      await expectLater(
        _svc(const _FakeCryptoCore()).reEncrypt(
          merged,
          _fakePayload(),
          newConsultationId: _kNewId,
        ),
        throwsA(isA<RecordFullException>()),
      );
    });

    test(
        'RecordFullException when fixed sections alone exceed the 500 KiB budget',
        () async {
      // Allergy substance fills > 512 000 bytes; no consultations to drop.
      final overflowRecord = MedicalRecord(
        patientId: _kPatientId,
        allergies: [
          Allergy(
            substance: 'x' * 512001,
            severity: 'mild',
            notedAt: '2025-01-01',
          ),
        ],
        consultations: const [
          Consultation(
            id: _kNewId,
            date: '2026-06-29',
            practitionerRef: 'dr-fake',
            summary: 'Note',
          ),
        ],
        createdAt: _kCreatedAt,
        updatedAt: _kUpdatedAt,
      );
      await expectLater(
        _svc(const _FakeCryptoCore()).reEncrypt(
          overflowRecord,
          _fakePayload(),
          newConsultationId: _kNewId,
        ),
        throwsA(isA<RecordFullException>()),
      );
    });

    test(
        'throws RecordFullException when newConsultationId is absent from '
        'a within-budget record', () async {
      // The guard verifies the id is present even when no truncation occurs.
      // Passing an id that does not match any consultation in the record is
      // rejected defensively — protects against caller bugs.
      final svc = _svc(const _FakeCryptoCore());
      await expectLater(
        svc.reEncrypt(
          _smallMergedRecord(), // contains _kNewId; a different id is passed
          _fakePayload(),
          newConsultationId: 'id-not-present-in-record',
        ),
        throwsA(isA<RecordFullException>()),
      );
    });
  });

  group('RecordFullException', () {
    test('toString does not expose plaintext record data or key material', () {
      const e = RecordFullException();
      final msg = e.toString();
      // Must not contain sensitive terms; must be a generic informational message.
      expect(msg, isNotEmpty);
      expect(msg.toLowerCase(), isNot(contains('key')));
      expect(msg.toLowerCase(), isNot(contains('session')));
      expect(msg.toLowerCase(), isNot(contains('plaintext')));
    });

    test('toString contains user-facing hint about dossier plein', () {
      const e = RecordFullException();
      expect(e.toString(), contains('dossier'));
    });
  });
}
