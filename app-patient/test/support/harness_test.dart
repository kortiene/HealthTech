// Tests for the consultation-loop test harness (issue #20).
//
// The harness (consultation_loop_harness.dart) is shared infrastructure relied
// on by the e2e test.  Testing it in isolation ensures that the e2e test's
// assertions are trustworthy:
//
//   - FakeBlobBackend stores a DEEP COPY of PUT bytes (zeroing the caller's
//     buffer after the PUT must not corrupt the stored blob — a prerequisite for
//     the e2e wipe assertions in consultation_loop_e2e_test.dart).
//   - FakeBlobBackend returns the stored bytes on GET and 404 when absent.
//   - FakeBlobBackend failPut=true returns 503 and stores nothing.
//   - FakeBlobBackend putCount/getCount track calls faithfully.
//   - referenceRecord() satisfies the 500 Kio plaintext budget (PRD §4 /
//     maxPlaintextBytes) so it is a valid test fixture.
//   - fakeXor is self-inverse (the XOR round-trip property the e2e relies on).
//   - seededRecordStore returns the exact seed record on read, with no network
//     GET (local-first path).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/cloud/backend_client.dart';
import 'package:app_patient/src/record/medical_record_store.dart';
import 'package:app_patient/src/record/record_size_guard.dart';

import 'consultation_loop_harness.dart';

const _baseUrl = 'http://backend.test';

BackendClient _clientFor(FakeBlobBackend backend) =>
    BackendClient(_baseUrl, httpClient: backend.client);

void main() {
  group('FakeBlobBackend — PUT/GET contract', () {
    test('GET returns exactly the bytes stored by PUT', () async {
      final backend = FakeBlobBackend();
      final bytes = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      await _clientFor(backend).put(kPatientUuid, bytes);
      final result = await _clientFor(backend).get(kPatientUuid);
      expect(result, equals(bytes));
    });

    test('GET throws BlobNotFound when no PUT was made for that UUID',
        () async {
      final backend = FakeBlobBackend();
      await expectLater(
        _clientFor(backend).get(kPatientUuid),
        throwsA(isA<BlobNotFound>()),
      );
    });

    test(
        'PUT stores a deep copy — zeroing the caller buffer after PUT does not '
        'corrupt the stored blob', () async {
      final backend = FakeBlobBackend();
      final original = Uint8List.fromList([0x01, 0x02, 0x03]);
      final snapshot = Uint8List.fromList(original);
      await _clientFor(backend).put(kPatientUuid, original);

      // Simulate the caller wiping the buffer after PUT (mirrors wipe() calls).
      original.fillRange(0, original.length, 0);

      expect(backend.blobs[kPatientUuid], equals(snapshot));
    });

    test('failPut: PUT throws BackendUnavailable', () async {
      final backend = FakeBlobBackend(failPut: true);
      await expectLater(
        _clientFor(backend).put(kPatientUuid, Uint8List(4)),
        throwsA(isA<BackendUnavailable>()),
      );
    });

    test('failPut: nothing is stored when PUT is refused', () async {
      final backend = FakeBlobBackend(failPut: true);
      try {
        await _clientFor(backend).put(kPatientUuid, Uint8List(4));
      } on BackendUnavailable {
        // expected
      }
      expect(backend.blobs, isEmpty);
    });

    test('unsupported HTTP method returns 405 without modifying blobs',
        () async {
      // BackendClient only exposes PUT and GET; use the raw MockClient to
      // exercise the 405 default branch in FakeBlobBackend._handle.
      final backend = FakeBlobBackend();
      final response =
          await backend.client.patch(Uri.parse('$_baseUrl/blob/$kPatientUuid'));
      expect(response.statusCode, 405);
      expect(backend.blobs, isEmpty);
    });
  });

  group('FakeBlobBackend — counter tracking', () {
    test('putCount starts at zero and increments on each PUT', () async {
      final backend = FakeBlobBackend();
      expect(backend.putCount, 0);
      await _clientFor(backend).put(kPatientUuid, Uint8List(4));
      expect(backend.putCount, 1);
      await _clientFor(backend).put(kPatientUuid, Uint8List(4));
      expect(backend.putCount, 2);
    });

    test('getCount starts at zero and increments on each GET', () async {
      final backend = FakeBlobBackend();
      await _clientFor(backend).put(kPatientUuid, Uint8List(4));
      expect(backend.getCount, 0);
      await _clientFor(backend).get(kPatientUuid);
      expect(backend.getCount, 1);
      await _clientFor(backend).get(kPatientUuid);
      expect(backend.getCount, 2);
    });

    test('failPut: putCount increments even when PUT is refused', () async {
      final backend = FakeBlobBackend(failPut: true);
      expect(backend.putCount, 0);
      try {
        await _clientFor(backend).put(kPatientUuid, Uint8List(4));
      } on BackendUnavailable {
        // expected
      }
      expect(backend.putCount, 1);
    });

    test('getCount increments even when GET returns 404 (no stored blob)',
        () async {
      final backend = FakeBlobBackend();
      expect(backend.getCount, 0);
      try {
        await _clientFor(backend).get(kPatientUuid);
      } on BlobNotFound {
        // expected — blob was never PUT
      }
      expect(backend.getCount, 1);
    });
  });

  group('referenceRecord', () {
    test('plaintext is under maxPlaintextBytes (512 000 B / 500 Kio)', () {
      final size = RecordSizeGuard.measure(referenceRecord());
      expect(size, lessThan(maxPlaintextBytes));
    });

    test('has exactly 1 consultation', () {
      expect(referenceRecord().consultations, hasLength(1));
    });

    test('patientId equals kPatientUuid', () {
      expect(referenceRecord().patientId, kPatientUuid);
    });

    test('createdAt and updatedAt are non-empty', () {
      final r = referenceRecord();
      expect(r.createdAt, isNotEmpty);
      expect(r.updatedAt, isNotEmpty);
    });

    test('has exactly 1 allergy', () {
      expect(referenceRecord().allergies, hasLength(1));
    });

    test('allergy substance is Pénicilline with severity severe', () {
      final allergy = referenceRecord().allergies.first;
      expect(allergy.substance, 'Pénicilline');
      expect(allergy.severity, 'severe');
    });

    test('demographics is non-null (PRD "Awa" persona)', () {
      expect(referenceRecord().demographics, isNotNull);
    });

    test('demographics givenName is Awa', () {
      expect(referenceRecord().demographics.givenName, 'Awa');
    });

    test('demographics birthYear is 1990', () {
      expect(referenceRecord().demographics.birthYear, 1990);
    });

    test('demographics sex is F', () {
      expect(referenceRecord().demographics.sex, 'F');
    });
  });

  group('fakeXor', () {
    test('is self-inverse: fakeXor(fakeXor(x)) == x', () {
      final bytes = Uint8List.fromList(List.generate(32, (i) => i));
      expect(fakeXor(fakeXor(bytes)), equals(bytes));
    });

    test('transforms non-zero bytes (output differs from input)', () {
      final bytes = Uint8List.fromList([0xFF, 0x01, 0xA5]);
      expect(fakeXor(bytes), isNot(equals(bytes)));
    });

    test('maps 0x00 to kFakeXor and kFakeXor to 0x00', () {
      expect(fakeXor(Uint8List.fromList([0x00])), equals([kFakeXor]));
      expect(fakeXor(Uint8List.fromList([kFakeXor])), equals([0x00]));
    });
  });

  group('seededRecordStore', () {
    test('read returns the exact seed record (local-first, no network)',
        () async {
      final backend = FakeBlobBackend();
      final seed = referenceRecord();
      final MedicalRecordStore store = seededRecordStore(
        backend: backend,
        seed: seed,
        baseUrl: _baseUrl,
      );
      final result =
          await store.read(const FakeMasterKeyHandle(), kPatientUuid);
      expect(result, equals(seed));
    });

    test('read does not issue a network GET (local record is pre-seeded)',
        () async {
      final backend = FakeBlobBackend();
      final MedicalRecordStore store = seededRecordStore(
        backend: backend,
        seed: referenceRecord(),
        baseUrl: _baseUrl,
      );
      await store.read(const FakeMasterKeyHandle(), kPatientUuid);
      expect(backend.getCount, 0);
    });
  });
}
