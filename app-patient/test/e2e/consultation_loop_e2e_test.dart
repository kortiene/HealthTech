// End-to-end consultation loop (issue #20 — M2 "premier end-to-end").
//
// Wires the REAL services from #16–#19 together — no re-implemented logic — to
// prove the four links chain correctly, an invariant no single unit test can
// see:  patient generates QR  →  doctor scans, decrypts in RAM, appends a note +
// ordonnance, re-encrypts with the session key, terminates (cloud PUT + wipe)
// →  the update is observable by re-decrypting the server blob.
//
// Verified properties (flow-level, beyond the per-service unit suites):
//   - the session key the patient embeds in the QR is the one that decrypts the
//     blob doctor-side (round-trip through `toQrString`/`parseQr`);
//   - the doctor's appended consultation survives re-encryption + cloud PUT and
//     is visible on a fresh decrypt (consultations 1 → 2, "Paludisme" present);
//   - append-only: prior history / createdAt / patientId / allergies untouched;
//   - the server only ever holds OPAQUE bytes (≠ plaintext), keyed by anon UUID;
//   - the doctor's session key and pending blob are zeroed after `terminate`;
//   - variant: an expired QR is rejected (`ExpiredQrCode`);
//   - variant: a 5xx at session end propagates `BackendUnavailable` AND the RAM
//     (session key + pending blob) is still wiped.
//
// CRYPTO HONESTY: the [FakeCryptoCore] is XOR (see consultation_loop_harness.dart).
// This test proves the loop's WIRING, NOT the cryptography — AES-256-GCM, the
// `nonce||ct||tag` format, GCM auth and "wrong key" rejection are covered by the
// crypto-core NIST vectors (#10) and, later, a device-backed e2e (follow-up).
//
// NOTE (open follow-up, see spec §"Risks"): "the patient sees the update" is
// shown here via a session-key re-decrypt within the 120 s window — faithful to
// the current code. Re-importing the doctor's update into the patient's
// master-key backup (#14) is not covered by any issue yet; this test does NOT
// pretend that mechanism exists.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/cloud/backend_client.dart';
import 'package:app_patient/src/doctor/consultation_edit_service.dart';
import 'package:app_patient/src/doctor/consultation_merge.dart';
import 'package:app_patient/src/doctor/consultation_session.dart';
import 'package:app_patient/src/doctor/scan_service.dart';
import 'package:app_patient/src/doctor/session_end_service.dart';
import 'package:app_patient/src/qr/access_token.dart';
import 'package:app_patient/src/record/medical_record.dart';
import 'package:app_patient/src/record/prescription.dart';

import '../support/consultation_loop_harness.dart';

const _baseUrl = 'http://backend.test';
const _newConsultationId = 'consult-paludisme-0002';

/// The doctor's note + ordonnance for the visit.
const _prescription = Prescription(
  lines: [
    PrescriptionLine(
      drug: 'Artéméther-luméfantrine',
      dose: '20/120 mg',
      frequency: '2×/jour',
      durationDays: 3,
    ),
  ],
);

ScanService _scanService(FakeBlobBackend backend) => ScanService(
      crypto: const FakeCryptoCore(),
      client: BackendClient(_baseUrl, httpClient: backend.client),
    );

AccessTokenService _tokenService(FakeBlobBackend backend, MedicalRecord seed) =>
    AccessTokenService(
      crypto: const FakeCryptoCore(),
      recordStore: seededRecordStore(
        backend: backend,
        seed: seed,
        baseUrl: _baseUrl,
      ),
      client: BackendClient(_baseUrl, httpClient: backend.client),
    );

/// Merge the doctor's note + ordonnance into [seen] (append-only).
MedicalRecord _mergeVisit(MedicalRecord seen) => mergeConsultation(
      seen,
      practitionerRef: 'practitioner-unverified',
      date: '2026-06-29',
      summary: 'Paludisme — repos et hydratation',
      prescription: _prescription,
      newConsultationId: _newConsultationId,
      nowIso: '2026-06-29T10:00:00Z',
    );

void main() {
  group('Consultation loop e2e (#16→#19)', () {
    test('patient → doctor → patient: the appended consultation is observable',
        () async {
      final backend = FakeBlobBackend();
      final seed = referenceRecord();

      // 1. PATIENT — generate the QR (session blob PUT to the backend).
      final patientQr = await _tokenService(backend, seed).generate(
        kPatientUuid,
        const FakeMasterKeyHandle(),
        _baseUrl,
      );
      final raw = patientQr.toQrString();

      // The server holds exactly one OPAQUE blob (≠ plaintext) for the anon UUID.
      expect(backend.blobs.keys.toList(), [kPatientUuid]);
      final blobAfterGenerate = backend.blobs[kPatientUuid]!;
      expect(blobAfterGenerate, isNot(equals(seed.toUtf8Bytes())));

      // 2. DOCTOR — parse the QR into a DISTINCT payload, decrypt in RAM.
      final doctorPayload = ScanService.parseQr(raw);
      final scanService = _scanService(backend);
      final seenByDoctor = await scanService.fetchAndDecrypt(doctorPayload);
      expect(seenByDoctor.patientId, kPatientUuid);
      expect(seenByDoctor.consultations, hasLength(1));

      // 3. DOCTOR — append note + ordonnance, re-encrypt with the session key.
      final merged = _mergeVisit(seenByDoctor);
      final editService =
          ConsultationEditService(crypto: const FakeCryptoCore());
      final updatedBlob = await editService.reEncrypt(
        merged,
        doctorPayload,
        newConsultationId: _newConsultationId,
      );
      final session = ConsultationSession(
        payload: doctorPayload,
        record: seenByDoctor,
      )..applyMerge(merged, updatedBlob);

      // 4. DOCTOR — terminate: cloud PUT of the updated blob, then RAM wipe.
      await SessionEndService(
        client: BackendClient(_baseUrl, httpClient: backend.client),
      ).terminate(session);
      expect(session.pendingBlob, isNull);
      expect(doctorPayload.sessionKey, everyElement(0));

      // The server blob was replaced by the updated (still opaque) ciphertext.
      final blobAfterTerminate = backend.blobs[kPatientUuid]!;
      expect(blobAfterTerminate, isNot(equals(blobAfterGenerate)));

      // 5. OBSERVABLE — the patient still holds the session key (120 s window).
      final patientView = await scanService.fetchAndDecrypt(patientQr);
      expect(patientView.consultations, hasLength(2));
      expect(patientView.consultations.last.summary, contains('Paludisme'));
      expect(
        patientView.consultations.last.prescription,
        contains('Artéméther-luméfantrine'),
      );

      // Append-only: prior history and fixed sections are intact.
      expect(
        patientView.consultations.first,
        seed.consultations.first,
      );
      expect(patientView.patientId, seed.patientId);
      expect(patientView.createdAt, seed.createdAt);
      expect(patientView.allergies, seed.allergies);
      expect(patientView.medications, hasLength(1));

      // Zero-knowledge: no server blob ever equals the plaintext record.
      for (final blob in backend.blobs.values) {
        expect(blob, isNot(equals(seed.toUtf8Bytes())));
        expect(blob, isNot(equals(patientView.toUtf8Bytes())));
      }
    });

    test('variant: an expired QR is rejected with ExpiredQrCode', () {
      final expired = QrPayload(
        uuid: kPatientUuid,
        backendUrl: _baseUrl,
        sessionKey: Uint8List(32),
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(
        () => ScanService.parseQr(expired.toQrString()),
        throwsA(isA<ExpiredQrCode>()),
      );
    });

    test(
        'variant: 5xx at session end propagates BackendUnavailable but wipes RAM',
        () async {
      final backend = FakeBlobBackend();
      final seed = referenceRecord();

      final patientQr = await _tokenService(backend, seed).generate(
        kPatientUuid,
        const FakeMasterKeyHandle(),
        _baseUrl,
      );
      final doctorPayload = ScanService.parseQr(patientQr.toQrString());
      final seenByDoctor =
          await _scanService(backend).fetchAndDecrypt(doctorPayload);

      final merged = _mergeVisit(seenByDoctor);
      final updatedBlob =
          await ConsultationEditService(crypto: const FakeCryptoCore())
              .reEncrypt(
        merged,
        doctorPayload,
        newConsultationId: _newConsultationId,
      );
      final session = ConsultationSession(
        payload: doctorPayload,
        record: seenByDoctor,
      )..applyMerge(merged, updatedBlob);

      // The cloud PUT fails at session end.
      final failingEnd = SessionEndService(
        client: BackendClient(
          _baseUrl,
          httpClient: FakeBlobBackend(failPut: true).client,
        ),
      );
      await expectLater(
        failingEnd.terminate(session),
        throwsA(isA<BackendUnavailable>()),
      );

      // RAM is wiped regardless of the sync failure.
      expect(session.pendingBlob, isNull);
      expect(doctorPayload.sessionKey, everyElement(0));
      expect(updatedBlob, everyElement(0));
    });
  });
}
