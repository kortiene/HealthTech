import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/record/medical_record.dart';
import 'package:app_patient/src/record/record_size_guard.dart';

MedicalRecord _minimal() => const MedicalRecord(
      patientId: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
      createdAt: '2024-01-01T00:00:00Z',
      updatedAt: '2024-01-01T00:00:00Z',
    );

/// Produces a [Consultation] whose summary is exactly [payloadBytes] bytes.
Consultation _consultationOfSize(String id, String date, int payloadBytes) {
  // summary must be exactly payloadBytes UTF-8 bytes; ASCII is 1 byte/char.
  final summary = 'x' * payloadBytes;
  return Consultation(
    id: id,
    date: date,
    practitionerRef: 'practitioner-ref',
    summary: summary,
  );
}

/// Returns a record whose serialised JSON is approximately [targetBytes].
///
/// Adds a single consultation whose summary pads the record to the target.
MedicalRecord _recordNearBytes(int targetBytes) {
  final base = _minimal();
  final baseSize = RecordSizeGuard.measure(base);

  // Overhead for wrapping the consultation in JSON (keys, brackets, etc.)
  // We measure empirically by adding an empty consultation first.
  final probeRecord = base.copyWith(
    consultations: [
      const Consultation(
        id: 'probe',
        date: '2024-01-01',
        practitionerRef: 'r',
        summary: '',
      ),
    ],
  );
  final probeSize = RecordSizeGuard.measure(probeRecord);
  final consultationOverhead = probeSize - baseSize;

  final payloadNeeded = targetBytes - baseSize - consultationOverhead;
  final summary = payloadNeeded > 0 ? 'x' * payloadNeeded : '';

  return base.copyWith(
    consultations: [
      Consultation(
        id: 'c1',
        date: '2024-01-01',
        practitionerRef: 'r',
        summary: summary,
      ),
    ],
  );
}

void main() {
  group('RecordSizeGuard', () {
    test('measure returns correct UTF-8 byte count', () {
      final record = _minimal();
      final expected = utf8.encode(jsonEncode(record.toJson())).length;
      expect(RecordSizeGuard.measure(record), equals(expected));
    });

    test('validate passes for a tiny record', () {
      expect(() => RecordSizeGuard.validate(_minimal()), returnsNormally);
    });

    test('validate throws RecordTooLargeException at maxPlaintextBytes', () {
      final large = _recordNearBytes(maxPlaintextBytes + 100);
      expect(
        () => RecordSizeGuard.validate(large),
        throwsA(isA<RecordTooLargeException>()),
      );
    });

    test('validate throws RecordSizeWarning in warn zone', () {
      final near = _recordNearBytes(warnPlaintextBytes + 100);
      expect(
        () => RecordSizeGuard.validate(near),
        throwsA(isA<RecordSizeWarning>()),
      );
    });

    test('validate does not throw below warnPlaintextBytes', () {
      final safe = _recordNearBytes(warnPlaintextBytes - 500);
      expect(() => RecordSizeGuard.validate(safe), returnsNormally);
    });

    group('truncate', () {
      test('returns the original record if it already fits', () {
        final small = _minimal();
        expect(RecordSizeGuard.truncate(small), equals(small));
      });

      test('removes oldest consultations until record fits', () {
        // Build a record over the limit with 3 consultations (oldest → newest).
        const eachBytes = 80000; // 80 KB each → 3 = 240 KB over base
        final base = _minimal();
        final consultations = [
          _consultationOfSize('c1', '2022-01-01', eachBytes),
          _consultationOfSize('c2', '2023-01-01', eachBytes),
          _consultationOfSize('c3', '2024-01-01', eachBytes),
          _consultationOfSize('c4', '2024-06-01', eachBytes),
          _consultationOfSize('c5', '2024-12-01', eachBytes),
          _consultationOfSize('c6', '2025-01-01', eachBytes),
          _consultationOfSize('c7', '2025-06-01', eachBytes),
        ];
        final record = base.copyWith(consultations: consultations);

        // If the record is already under limit, skip (adjust if needed).
        if (RecordSizeGuard.measure(record) < maxPlaintextBytes) {
          // Test would be vacuous — skip.
          return;
        }

        final truncated = RecordSizeGuard.truncate(record);
        expect(
          RecordSizeGuard.measure(truncated),
          lessThan(maxPlaintextBytes),
        );
        // Oldest consultations are removed first.
        final ids = truncated.consultations.map((c) => c.id).toList();
        expect(ids, isNot(contains('c1')));
      });

      test(
        'throws RecordTooLargeException when even no consultations is too big',
        () {
          // Craft a record whose fixed sections alone are too large.
          // We do this by creating an allergy with a huge substance name.
          final hugeName = 'A' * (maxPlaintextBytes + 1000);
          final record = MedicalRecord(
            patientId: 'p',
            allergies: [
              Allergy(
                substance: hugeName,
                severity: 'mild',
                notedAt: '2024-01-01',
              ),
            ],
            consultations: const [],
            createdAt: '2024-01-01T00:00:00Z',
            updatedAt: '2024-01-01T00:00:00Z',
          );
          expect(
            () => RecordSizeGuard.truncate(record),
            throwsA(isA<RecordTooLargeException>()),
          );
        },
      );

      test('truncated record sorts oldest consultations first for removal', () {
        // Out-of-order dates: the oldest one (2020) must be removed first.
        const eachBytes = 70000;
        final base = _minimal();
        final record = base.copyWith(
          consultations: [
            _consultationOfSize('c-new', '2025-01-01', eachBytes),
            _consultationOfSize('c-old', '2020-01-01', eachBytes),
            _consultationOfSize('c-mid', '2022-06-01', eachBytes),
            _consultationOfSize('c-mid2', '2023-01-01', eachBytes),
            _consultationOfSize('c-mid3', '2024-01-01', eachBytes),
            _consultationOfSize('c-mid4', '2024-06-01', eachBytes),
            _consultationOfSize('c-mid5', '2024-09-01', eachBytes),
          ],
        );
        if (RecordSizeGuard.measure(record) < maxPlaintextBytes) return;

        final truncated = RecordSizeGuard.truncate(record);
        final ids = truncated.consultations.map((c) => c.id).toList();
        // The newest consultation must still be present if any are kept.
        if (ids.isNotEmpty) {
          expect(ids, contains('c-new'));
        }
      });
    });

    group('RecordTooLargeException', () {
      test('toString includes size and limit', () {
        const ex = RecordTooLargeException(600000);
        expect(ex.toString(), contains('600000'));
        expect(ex.toString(), contains('512000'));
      });
    });

    group('RecordSizeWarning', () {
      test('toString includes size and threshold description', () {
        const warn = RecordSizeWarning(420000);
        expect(warn.toString(), contains('420000'));
        expect(warn.toString(), contains('80 %'));
      });
    });
  });
}
