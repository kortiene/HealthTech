// Unit tests for ConsultationSession (issue #18 — US-2.2).
//
// Verified properties:
//   - current returns the initial record on construction.
//   - pendingBlob is null on construction.
//   - applyMerge updates current and pendingBlob.
//   - Multiple applyMerge calls update both fields to the latest values.
//   - wipe zeroes out sessionKey bytes in the payload (best-effort RAM scrub).
//   - wipe zeroes out pendingBlob bytes in-place.
//   - wipe sets pendingBlob to null after scrub.
//   - wipe with no pendingBlob is safe (no throw).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/doctor/consultation_session.dart';
import 'package:app_patient/src/qr/access_token.dart';
import 'package:app_patient/src/record/medical_record.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

const _kPatientId = 'patient-fake-uuid-001';
const _kCreatedAt = '2025-01-01T00:00:00Z';
const _kUpdatedAt = '2026-06-29T08:00:00Z';

const _kRecord = MedicalRecord(
  patientId: _kPatientId,
  createdAt: _kCreatedAt,
  updatedAt: _kUpdatedAt,
);

/// Returns a payload with a non-zero session key so wipe() is detectable.
QrPayload _payload() => QrPayload(
      uuid: _kPatientId,
      backendUrl: 'http://backend.test',
      sessionKey: Uint8List.fromList(List.filled(32, 0x42)),
      expiresAt: DateTime.now().add(const Duration(seconds: 120)),
    );

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('ConsultationSession — initial state', () {
    test('current returns the record supplied at construction', () {
      final session =
          ConsultationSession(payload: _payload(), record: _kRecord);
      expect(session.current, equals(_kRecord));
    });

    test('pendingBlob is null at construction', () {
      final session =
          ConsultationSession(payload: _payload(), record: _kRecord);
      expect(session.pendingBlob, isNull);
    });
  });

  group('ConsultationSession.applyMerge', () {
    test('updates current to the merged record', () {
      final session =
          ConsultationSession(payload: _payload(), record: _kRecord);
      final merged = _kRecord.copyWith(updatedAt: '2026-06-30T00:00:00Z');
      session.applyMerge(merged, Uint8List.fromList([1, 2, 3]));
      expect(session.current, equals(merged));
    });

    test('sets pendingBlob to the provided blob', () {
      final session =
          ConsultationSession(payload: _payload(), record: _kRecord);
      final blob = Uint8List.fromList([0x01, 0x02, 0x03]);
      session.applyMerge(_kRecord, blob);
      expect(session.pendingBlob, equals(blob));
    });

    test('second applyMerge overwrites both current and pendingBlob', () {
      final session =
          ConsultationSession(payload: _payload(), record: _kRecord);
      final merged1 = _kRecord.copyWith(updatedAt: '2026-06-30T00:00:00Z');
      final merged2 = _kRecord.copyWith(updatedAt: '2026-07-01T00:00:00Z');
      final blob1 = Uint8List.fromList([1, 2, 3]);
      final blob2 = Uint8List.fromList([4, 5, 6]);
      session.applyMerge(merged1, blob1);
      session.applyMerge(merged2, blob2);
      expect(session.current, equals(merged2));
      expect(session.pendingBlob, equals(blob2));
    });

    test('payload is unchanged by applyMerge', () {
      final payload = _payload();
      final session = ConsultationSession(payload: payload, record: _kRecord);
      final originalKey = Uint8List.fromList(payload.sessionKey);
      session.applyMerge(_kRecord, Uint8List(4));
      expect(session.payload.sessionKey, equals(originalKey));
    });
  });

  group('ConsultationSession.wipe', () {
    test('zeroes out all sessionKey bytes in the payload', () {
      final session =
          ConsultationSession(payload: _payload(), record: _kRecord);
      session.wipe();
      expect(session.payload.sessionKey, everyElement(0));
    });

    test('zeroes out pendingBlob bytes in-place after applyMerge', () {
      final session =
          ConsultationSession(payload: _payload(), record: _kRecord);
      final blob = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
      session.applyMerge(_kRecord, blob);
      session.wipe();
      // The original Uint8List reference should be zeroed.
      expect(blob, everyElement(0));
    });

    test('sets pendingBlob to null after scrub', () {
      final session =
          ConsultationSession(payload: _payload(), record: _kRecord);
      session.applyMerge(_kRecord, Uint8List.fromList([1, 2, 3]));
      session.wipe();
      expect(session.pendingBlob, isNull);
    });

    test('wipe with no pendingBlob does not throw', () {
      final session =
          ConsultationSession(payload: _payload(), record: _kRecord);
      expect(() => session.wipe(), returnsNormally);
    });

    test('second wipe is safe (no throw, sessionKey remains zeroed)', () {
      final session =
          ConsultationSession(payload: _payload(), record: _kRecord);
      session.wipe();
      expect(() => session.wipe(), returnsNormally);
      expect(session.payload.sessionKey, everyElement(0));
    });

    test('current record is unchanged by wipe (record itself is not scrubbed)',
        () {
      final session =
          ConsultationSession(payload: _payload(), record: _kRecord);
      session.wipe();
      // The record is immutable value type — it is unaffected by the session wipe.
      expect(session.current, equals(_kRecord));
    });
  });
}
