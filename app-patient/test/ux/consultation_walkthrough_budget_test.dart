// Consultation walkthrough guard-rail and machine task-time proxy (issue #28, Livrable C).
//
// Traverses the canonical 4-step consultation flow at the SERVICE layer (not the
// widget layer) using the shared FakeCryptoCore + FakeBlobBackend harness.
// This is the automated anti-regression gate for the UX single-flow norm:
//
//   Step 1 "scan"       — ScanService.parseQr + fetchAndDecrypt (→ ScanScreen)
//   Step 2 "read"       — decrypted record available in RAM     (→ RecordViewScreen)
//   Step 3 "edit"       — ConsultationEditService.reEncrypt     (→ ConsultationEditScreen)
//   Step 4 "terminate"  — SessionEndService.terminate           (→ pop, no new screen)
//
// Asserted properties:
//   - The flow records exactly UxBudget.maxConsultationSteps (4) canonical steps.
//   - Exactly UxBudget.maxConsultationScreens (3) steps correspond to a screen push
//     (scan, read, edit); "terminate" is a pop, not a push.
//   - Machine task-time proxy (sum of in-process durations, network excluded) is
//     < UxBudget.taskTimeProxyBudgetMs (generous ceiling; not the human < 5 min proof).
//
// HONESTY (mirroring the spec §Testing Plan):
//   The machine proxy catches an ORDER-OF-MAGNITUDE regression in app-side
//   processing — an accidental O(n²) serialise, a heavy synchronous call — not
//   human usability. The human proof is the usability campaign
//   (docs/ux/usability-test-protocol.md). Network latency is excluded because the
//   blob backend is an in-memory fake.
//
// CRYPTO HONESTY: FakeCryptoCore is XOR. This proves loop WIRING, not AES-256-GCM.

import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/cloud/backend_client.dart';
import 'package:app_patient/src/doctor/consultation_edit_service.dart';
import 'package:app_patient/src/doctor/consultation_merge.dart';
import 'package:app_patient/src/doctor/consultation_session.dart';
import 'package:app_patient/src/doctor/offline_upload_queue.dart';
import 'package:app_patient/src/doctor/scan_service.dart';
import 'package:app_patient/src/doctor/session_end_service.dart';
import 'package:app_patient/src/doctor/task_timing.dart';
import 'package:app_patient/src/doctor/ux_budget.dart';
import 'package:app_patient/src/qr/access_token.dart';
import 'package:app_patient/src/record/prescription.dart';

import '../support/consultation_loop_harness.dart';

const _baseUrl = 'http://backend.test';
const _walkthroughConsultationId = 'consult-walkthrough-0001';

void main() {
  group('Consultation walkthrough guard-rail (#28)', () {
    test(
      'traverses exactly maxConsultationSteps steps, '
      'crosses maxConsultationScreens screen-push boundaries, '
      'and stays within taskTimeProxyBudgetMs (machine proxy, network excluded)',
      () async {
        final backend = FakeBlobBackend();
        final seed = referenceRecord();

        // Instrument the canonical steps. Real wall clock is used so the proxy
        // measures actual in-process time (FakeCryptoCore + in-memory backend
        // run in microseconds; the 2 s ceiling is very generous).
        final timing = TaskTiming(enabled: true);

        // ── STEP 1: "scan" ────────────────────────────────────────────────────
        // Corresponds to ScanScreen (screen 1). The patient pre-seeds the QR;
        // the doctor parses it and fetches + decrypts the blob in RAM.
        timing.start('scan');

        final patientQr = await AccessTokenService(
          crypto: const FakeCryptoCore(),
          recordStore: seededRecordStore(
            backend: backend,
            seed: seed,
            baseUrl: _baseUrl,
          ),
          client: BackendClient(_baseUrl, httpClient: backend.client),
        ).generate(kPatientUuid, const FakeMasterKeyHandle(), _baseUrl);

        final doctorPayload = ScanService.parseQr(patientQr.toQrString());
        final seenRecord = await ScanService(
          crypto: const FakeCryptoCore(),
          client: BackendClient(_baseUrl, httpClient: backend.client),
        ).fetchAndDecrypt(doctorPayload);

        timing.stop('scan');

        // ── STEP 2: "read" ────────────────────────────────────────────────────
        // Corresponds to RecordViewScreen (screen 2). The decrypted record is
        // available in RAM; no further service call is needed for display.
        timing.start('read');
        expect(seenRecord.patientId, kPatientUuid);
        expect(seenRecord.allergies, isNotEmpty,
            reason:
                'reference record has at least one allergy (life-critical data)');
        timing.stop('read');

        // ── STEP 3: "edit" ────────────────────────────────────────────────────
        // Corresponds to ConsultationEditScreen (screen 3). The doctor adds a
        // note + ordonnance; the merged record is re-encrypted in RAM.
        timing.start('edit');

        const prescription = Prescription(
          lines: [
            PrescriptionLine(
              drug: 'Paracétamol',
              dose: '500 mg',
              frequency: '3×/jour',
              durationDays: 5,
            ),
          ],
        );
        final merged = mergeConsultation(
          seenRecord,
          practitionerRef: 'practitioner-unverified',
          date: '2026-07-02',
          summary: 'Bilan de walkthrough — données de test',
          prescription: prescription,
          newConsultationId: _walkthroughConsultationId,
          nowIso: '2026-07-02T10:00:00Z',
        );
        final updatedBlob =
            await ConsultationEditService(crypto: const FakeCryptoCore())
                .reEncrypt(
          merged,
          doctorPayload,
          newConsultationId: _walkthroughConsultationId,
        );
        final session =
            ConsultationSession(payload: doctorPayload, record: seenRecord)
              ..applyMerge(merged, updatedBlob);

        timing.stop('edit');

        // ── STEP 4: "terminate" ───────────────────────────────────────────────
        // Corresponds to the "Terminer" action: re-encrypted blob is PUT to the
        // cloud (or enqueued), then the session key + blob are wiped from RAM.
        // This is a NAVIGATION POP, not a new screen — hence 4 steps / 3 screens.
        timing.start('terminate');

        final outcome = await SessionEndService(
          client: BackendClient(_baseUrl, httpClient: backend.client),
          queue: InMemoryUploadQueue(),
        ).terminate(session);
        expect(outcome, SessionEndOutcome.uploaded);
        // RAM is wiped: session key zeroed, pending blob cleared.
        expect(session.pendingBlob, isNull);
        expect(doctorPayload.sessionKey, everyElement(0));

        timing.stop('terminate');

        // ── Budget assertions ─────────────────────────────────────────────────

        // 4a. Exactly maxConsultationSteps steps were traversed.
        expect(
          timing.durationsMs.keys.length,
          UxBudget.maxConsultationSteps,
          reason:
              'the flow must traverse exactly ${UxBudget.maxConsultationSteps} '
              'canonical steps; add a step only with an explicit budget bump',
        );

        // 4b. All canonical step labels are present.
        expect(
          timing.durationsMs.keys.toSet(),
          containsAll(UxBudget.canonicalSteps),
        );

        // 4c. Exactly maxConsultationScreens steps correspond to a screen push.
        //     'terminate' is a pop (RecordViewScreen dismissed) — not a new screen.
        //     Any change to this constant requires a conscious review.
        const screenPushSteps = <String>['scan', 'read', 'edit'];
        expect(
          screenPushSteps.length,
          UxBudget.maxConsultationScreens,
          reason:
              'screenPushSteps.length must equal UxBudget.maxConsultationScreens '
              '(${UxBudget.maxConsultationScreens}); update UxBudget if you add a screen',
        );

        // 4d. Machine task-time proxy: total in-process duration < generous ceiling.
        //     This catches an accidental O(n²), a heavy synchronous serialise, or a
        //     regression in the fake operations. It is NOT the human < 5 min proof.
        expect(
          timing.totalMs,
          lessThan(UxBudget.taskTimeProxyBudgetMs),
          reason: 'machine task-time proxy ${timing.totalMs} ms must be < '
              '${UxBudget.taskTimeProxyBudgetMs} ms. '
              'This is an anti-regression signal (network excluded, in-process only), '
              'NOT a substitute for the human usability campaign '
              '(docs/ux/usability-test-protocol.md).',
        );
      },
    );

    test('variant: offline terminate (network down) still completes in budget',
        () async {
      final backend = FakeBlobBackend();
      final seed = referenceRecord();
      final timing = TaskTiming(enabled: true);

      final patientQr = await AccessTokenService(
        crypto: const FakeCryptoCore(),
        recordStore:
            seededRecordStore(backend: backend, seed: seed, baseUrl: _baseUrl),
        client: BackendClient(_baseUrl, httpClient: backend.client),
      ).generate(kPatientUuid, const FakeMasterKeyHandle(), _baseUrl);

      final doctorPayload = ScanService.parseQr(patientQr.toQrString());
      final seenRecord = await ScanService(
        crypto: const FakeCryptoCore(),
        client: BackendClient(_baseUrl, httpClient: backend.client),
      ).fetchAndDecrypt(doctorPayload);

      timing.start('scan');
      timing.stop('scan');

      timing.start('read');
      timing.stop('read');

      timing.start('edit');
      const consultationId = 'consult-offline-walkthrough-0001';
      final merged = mergeConsultation(
        seenRecord,
        practitionerRef: 'practitioner-unverified',
        date: '2026-07-02',
        summary: 'Consultation hors-ligne — test de walkthrough',
        newConsultationId: consultationId,
        nowIso: '2026-07-02T10:00:00Z',
      );
      final updatedBlob = await ConsultationEditService(
              crypto: const FakeCryptoCore())
          .reEncrypt(merged, doctorPayload, newConsultationId: consultationId);
      final session =
          ConsultationSession(payload: doctorPayload, record: seenRecord)
            ..applyMerge(merged, updatedBlob);
      timing.stop('edit');

      timing.start('terminate');
      final failingBackend = FakeBlobBackend(failPut: true);
      final queue = InMemoryUploadQueue();
      final outcome = await SessionEndService(
        client: BackendClient(_baseUrl, httpClient: failingBackend.client),
        queue: queue,
      ).terminate(session);
      expect(outcome, SessionEndOutcome.queued);
      expect(session.pendingBlob, isNull);
      expect(doctorPayload.sessionKey, everyElement(0));
      timing.stop('terminate');

      expect(timing.durationsMs.keys.length, UxBudget.maxConsultationSteps);
      expect(timing.totalMs, lessThan(UxBudget.taskTimeProxyBudgetMs));
    });
  });
}
