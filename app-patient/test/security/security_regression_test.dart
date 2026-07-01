// Security regression test suite (issue #25 — Audit de sécurité & test d'intrusion externe).
//
// Each test is named after the invariant it enforces (matching the pentest scenario codes
// in docs/security/pentest-scope.md). Run after any vulnerability fix to confirm the
// invariant holds:
//
//   flutter test test/security/security_regression_test.dart
//
// All tests use deterministic XOR fakes (FakeCryptoCore from the shared harness).
// They do NOT validate real AES-256-GCM — that coverage lives in the crypto-core
// crate (NIST CAVP + RFC 6070 vectors). These tests verify the WIRING: that the
// services correctly handle plaintext only in RAM and never expose it to the network.
//
// Invariant reference:
//   ZK-1  : cloud blob never contains plaintext PII (SC-01)
//   ZK-2  : compression does not break blob opacity (SC-09)
//   QR-REPLAY: expired QR is always rejected (SC-02)
//   QR-WIPE  : session key bytes zeroed after wipe() (SC-03)
//   SESSION-WIPE: key zeroed unconditionally — even on double failure (SC-03)
//   SESSION-IDEMPOTENT: second terminate() returns nothingToUpload safely (SC-03)
//   SCAN-NO-PUT: fetchAndDecrypt never issues a cloud write (SC-08)
//   MEDIA-403: 403 from backend → MediaAccessExpired only, no data returned (SC-05)
//   OFFLINE-OPAQUE: ciphertext in offline queue ≠ plaintext JSON (SC-07)

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_patient/src/cloud/backend_client.dart';
import 'package:app_patient/src/cloud/media_client.dart';
import 'package:app_patient/src/doctor/consultation_session.dart';
import 'package:app_patient/src/doctor/offline_upload_queue.dart';
import 'package:app_patient/src/doctor/scan_service.dart';
import 'package:app_patient/src/doctor/session_end_service.dart';
import 'package:app_patient/src/qr/access_token.dart';
import 'package:app_patient/src/record/medical_record.dart';
import 'package:app_patient/src/record/medical_record_store.dart';
import 'package:app_patient/src/secure/sealed_blob_store.dart';

import '../support/consultation_loop_harness.dart';

// ─── Shared constants ────────────────────────────────────────────────────────

const _uuid = '00000000-0000-4000-8000-000000000099';
const _base = 'http://backend.test';
const _crypto = FakeCryptoCore();
const _handle = FakeMasterKeyHandle();

/// A record with multiple PII markers across the medical fields.
const _piiRecord = MedicalRecord(
  patientId: _uuid,
  demographics: Demographics(bloodType: 'MARKER-BLOOD-TYPE'),
  allergies: [
    Allergy(
      substance: 'MARKER-ALLERGY-PENICILLIN',
      severity: 'severe',
      notedAt: '2025-01-01',
    ),
  ],
  createdAt: '2025-01-01T00:00:00Z',
  updatedAt: '2025-01-01T00:00:00Z',
);

/// PII strings that must never appear verbatim in a cloud blob.
const _piiMarkers = ['MARKER-BLOOD-TYPE', 'MARKER-ALLERGY-PENICILLIN'];

MedicalRecordStore _store({
  int statusCode = 201,
  InMemorySealedBlobStore? local,
  void Function(http.Request)? onRequest,
}) {
  return MedicalRecordStore(
    crypto: _crypto,
    client: BackendClient(
      _base,
      httpClient: MockClient((req) async {
        onRequest?.call(req);
        return http.Response('', statusCode);
      }),
    ),
    localStore: local ?? InMemorySealedBlobStore(),
  );
}

QrPayload _freshPayload({Uint8List? key}) => QrPayload(
      uuid: _uuid,
      backendUrl: _base,
      sessionKey: key ?? Uint8List.fromList(List.filled(32, 0x42)),
      expiresAt: DateTime.now().add(const Duration(seconds: 120)),
    );

/// Creates a [ConsultationSession] with an optional pending blob.
ConsultationSession _session({Uint8List? blob, Uint8List? key}) {
  const record = MedicalRecord(
    patientId: _uuid,
    createdAt: '2025-01-01T00:00:00Z',
    updatedAt: '2025-01-01T00:00:00Z',
  );
  final session = ConsultationSession(
    payload: _freshPayload(key: key),
    record: record,
  );
  if (blob != null) {
    session.applyMerge(
      record.copyWith(updatedAt: '2026-01-01T00:00:00Z'),
      blob,
    );
  }
  return session;
}

/// Offline queue that always throws [OfflineQueueUnavailable] on [enqueue] —
/// simulates Keystore failure or disk-full condition.
class _FailingQueue implements OfflineUploadQueue {
  @override
  Future<void> enqueue(String blobUuid, Uint8List ciphertext) async =>
      throw const OfflineQueueUnavailable('disk full (test)');
  @override
  Future<List<PendingUpload>> pending() async => [];
  @override
  Future<void> remove(String id) async {}
  @override
  Future<int> count() async => 0;
  @override
  Future<void> markAttempt(String id, {required String redactedError}) async {}
  @override
  Future<void> markConflict(
    String id, {
    required String redactedReason,
  }) async {}
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── ZK-1-MULTI : Cloud blob sans PII multichamp ────────────────────────────
  //
  // SC-01: a server-level MITM must not be able to read plaintext medical data
  // from the intercepted blob — regardless of how many fields carry PII.

  group('[ZK-1-MULTI] Cloud blob never contains PII across all record fields',
      () {
    test('none of the PII markers appear verbatim in the uploaded blob',
        () async {
      Uint8List? captured;
      final store = _store(
        onRequest: (req) {
          if (req.method == 'PUT') captured = req.bodyBytes;
        },
      );

      await store.write(_piiRecord, _handle, _uuid);

      expect(captured, isNotNull, reason: 'PUT must have been issued');
      final blobText = utf8.decode(captured!, allowMalformed: true);
      for (final marker in _piiMarkers) {
        expect(
          blobText,
          isNot(contains(marker)),
          reason: 'PII marker "$marker" must not appear in cloud blob',
        );
      }
    });
  });

  // ── ZK-2-COMPRESS : Compression préserve l'opacité ────────────────────────
  //
  // SC-09: gzip before AES-256-GCM must not produce JSON-decodable output.
  // The oracle-of-compression concern requires an adaptive real-time channel
  // to exploit (unavailable here — the patient controls all writes), so the
  // test confirms blob opacity at the wire level only.

  group('[ZK-2-COMPRESS] Blob remains opaque after compress+encrypt', () {
    test('uploaded blob is not JSON-decodable', () async {
      Uint8List? captured;
      final store = _store(
        onRequest: (req) {
          if (req.method == 'PUT') captured = req.bodyBytes;
        },
      );

      await store.write(_piiRecord, _handle, _uuid);

      expect(captured, isNotNull);
      Object? parsed;
      try {
        parsed = jsonDecode(utf8.decode(captured!, allowMalformed: false));
      } catch (_) {
        parsed = null;
      }
      expect(
        parsed,
        isNot(isA<Map<String, Object?>>()),
        reason: 'blob must not be a parseable JSON object',
      );
    });

    test('uploaded blob is strictly smaller than raw plaintext JSON', () async {
      final plaintext = Uint8List.fromList(
        jsonEncode(_piiRecord.toJson()).codeUnits,
      );
      Uint8List? captured;
      final store = _store(
        onRequest: (req) {
          if (req.method == 'PUT') captured = req.bodyBytes;
        },
      );

      await store.write(_piiRecord, _handle, _uuid);

      expect(captured, isNotNull);
      expect(
        captured!.length,
        lessThan(plaintext.length),
        reason: 'compress+encrypt must reduce blob below raw plaintext',
      );
    });
  });

  // ── QR-REPLAY : QR expiré rejeté immédiatement ────────────────────────────
  //
  // SC-02: a QR that expired even 1 second ago must be rejected — no replay.

  group('[QR-REPLAY] Expired QR is always rejected — no replay attacks', () {
    test('parseQr throws ExpiredQrCode for a QR that expired 1 second ago', () {
      final expired = QrPayload(
        uuid: _uuid,
        backendUrl: _base,
        sessionKey: Uint8List(32),
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(
        () => ScanService.parseQr(expired.toQrString()),
        throwsA(isA<ExpiredQrCode>()),
        reason: 'expired QR must never be accepted',
      );
    });

    test('parseQr accepts a QR that expires in the future', () {
      expect(
        () => ScanService.parseQr(_freshPayload().toQrString()),
        returnsNormally,
      );
    });

    test('isExpired is true for epoch-0 timestamp', () {
      final expired = QrPayload(
        uuid: _uuid,
        backendUrl: _base,
        sessionKey: Uint8List(32),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      expect(expired.isExpired, isTrue);
    });
  });

  // ── QR-WIPE : Session key zéroïsée après QrPayload.wipe() ─────────────────
  //
  // SC-03: a memory dump after wipe() must not reveal the session key.

  group('[QR-WIPE] Session key bytes are zeroed after QrPayload.wipe()', () {
    test('all session key bytes are 0x00 after wipe()', () {
      final key = Uint8List.fromList(List.filled(32, 0xAB));
      final payload = QrPayload(
        uuid: _uuid,
        backendUrl: _base,
        sessionKey: key,
        expiresAt: DateTime.now().add(const Duration(seconds: 120)),
      );
      payload.wipe();
      expect(key, everyElement(0x00), reason: 'session key must be zeroed');
    });
  });

  // ── SESSION-WIPE : Wipe garanti sur tous les chemins ──────────────────────
  //
  // SC-03: session key must be zeroed even on error paths.

  group('[SESSION-WIPE] Session memory zeroed unconditionally', () {
    test('session key zeroed after successful terminate()', () async {
      final key = Uint8List.fromList(List.filled(32, 0x42));
      final svc = SessionEndService(
        client: BackendClient(
          _base,
          httpClient: MockClient((_) async => http.Response('', 200)),
        ),
        queue: InMemoryUploadQueue(),
      );
      await svc.terminate(
        _session(blob: Uint8List.fromList([1, 2, 3]), key: key),
      );
      expect(key, everyElement(0x00), reason: 'key must be zeroed on success');
    });

    test('session key zeroed when PUT fails (offline queue path)', () async {
      final key = Uint8List.fromList(List.filled(32, 0x42));
      final svc = SessionEndService(
        client: BackendClient(
          _base,
          httpClient: MockClient((_) async => http.Response('', 503)),
        ),
        queue: InMemoryUploadQueue(),
      );
      await svc.terminate(
        _session(blob: Uint8List.fromList([1, 2, 3]), key: key),
      );
      expect(key, everyElement(0x00),
          reason: 'key must be zeroed even on PUT failure');
    });

    test(
        '[SESSION-WIPE-DOUBLE] session key zeroed when both PUT and queue fail',
        () async {
      // Worst case: double failure. The session MUST still be wiped (SC-03).
      final key = Uint8List.fromList(List.filled(32, 0x42));
      final svc = SessionEndService(
        client: BackendClient(
          _base,
          httpClient: MockClient((_) async => http.Response('', 503)),
        ),
        queue: _FailingQueue(),
      );
      try {
        await svc.terminate(
          _session(blob: Uint8List.fromList([1, 2, 3]), key: key),
        );
      } on OfflineQueueUnavailable {
        // expected — double failure propagates this exception
      }
      expect(key, everyElement(0x00),
          reason: 'key must be zeroed even on OfflineQueueUnavailable');
    });
  });

  // ── SESSION-IDEMPOTENT : Deuxième terminate() safe ────────────────────────
  //
  // SC-03: calling terminate() on an already-wiped session must not throw and
  // must not issue a spurious PUT.

  group('[SESSION-IDEMPOTENT] Second terminate() is safe and idempotent', () {
    test('second terminate() returns nothingToUpload without issuing PUT',
        () async {
      final puts = <String>[];
      final svc = SessionEndService(
        client: BackendClient(
          _base,
          httpClient: MockClient((req) async {
            if (req.method == 'PUT') puts.add(req.url.path);
            return http.Response('', 200);
          }),
        ),
        queue: InMemoryUploadQueue(),
      );
      final session = _session(blob: Uint8List.fromList([1, 2, 3]));

      final first = await svc.terminate(session);
      expect(first, SessionEndOutcome.uploaded);
      expect(puts, hasLength(1));

      final second = await svc.terminate(session);
      expect(second, SessionEndOutcome.nothingToUpload,
          reason: 'second terminate must not issue duplicate PUT');
      expect(puts, hasLength(1), reason: 'no additional PUT on second call');
    });
  });

  // ── SCAN-NO-PUT : fetchAndDecrypt n'émet pas de PUT ───────────────────────
  //
  // SC-08: doctor-side decrypt must never write to the backend.

  group('[SCAN-NO-PUT] ScanService.fetchAndDecrypt is strictly read-only', () {
    test('fetchAndDecrypt issues only GET — no PUT or POST', () async {
      final methods = <String>[];
      final payload = QrPayload(
        uuid: _uuid,
        backendUrl: _base,
        sessionKey: Uint8List.fromList(List.filled(32, kFakeXor)),
        expiresAt: DateTime.now().add(const Duration(seconds: 120)),
      );

      // Build a fake session blob: xor(plaintext) — what the server holds.
      const record = MedicalRecord(
        patientId: _uuid,
        createdAt: '2025-01-01T00:00:00Z',
        updatedAt: '2025-01-01T00:00:00Z',
      );
      final blob = fakeXor(
        Uint8List.fromList(jsonEncode(record.toJson()).codeUnits),
      );

      final svc = ScanService(
        crypto: _crypto,
        client: BackendClient(
          _base,
          httpClient: MockClient((req) async {
            methods.add(req.method);
            if (req.method == 'GET') {
              return http.Response.bytes(blob, 200);
            }
            return http.Response('', 405);
          }),
        ),
      );

      await svc.fetchAndDecrypt(payload);

      expect(methods, isNot(contains('PUT')),
          reason: 'fetchAndDecrypt must never issue PUT');
      expect(methods, isNot(contains('POST')),
          reason: 'fetchAndDecrypt must never issue POST');
      expect(methods, contains('GET'));
    });
  });

  // ── MEDIA-403 : 403 → MediaAccessExpired uniquement ──────────────────────
  //
  // SC-05: an expired/tampered capability URL returns 403; the client must
  // raise MediaAccessExpired and never return any response body data.

  group('[MEDIA-403] MediaClient maps 403 to MediaAccessExpired only', () {
    test('fetchCiphertext throws MediaAccessExpired on 403', () async {
      final client = MediaClient(
        _base,
        httpClient: MockClient((_) async => http.Response('confidential', 403)),
      );

      Object? thrown;
      try {
        await client.fetchCiphertext('$_base/media/$_uuid?exp=0&sig=dead');
      } catch (e) {
        thrown = e;
      }

      expect(thrown, isA<MediaAccessExpired>(),
          reason: '403 must map to MediaAccessExpired');
      expect(
        thrown.toString(),
        isNot(contains('confidential')),
        reason: 'exception message must not carry the response body',
      );
    });
  });

  // ── OFFLINE-OPAQUE : Ciphertext dans la queue ≠ plaintext JSON ────────────
  //
  // SC-07: if a session blob is queued offline (PUT failed), the stored bytes
  // must be ciphertext, not the plaintext medical record.

  group('[OFFLINE-OPAQUE] Ciphertext enqueued in offline queue is opaque', () {
    test('queued ciphertext does not contain plaintext PII markers', () async {
      const record = MedicalRecord(
        patientId: _uuid,
        demographics: Demographics(bloodType: 'OFFLINE-PII-MARKER'),
        createdAt: '2025-01-01T00:00:00Z',
        updatedAt: '2025-01-01T00:00:00Z',
      );

      // Build a fake encrypted blob: xor(plaintext) — the fake crypto output.
      final plaintext = Uint8List.fromList(
        jsonEncode(record.toJson()).codeUnits,
      );
      final ciphertext = fakeXor(plaintext);

      final session = ConsultationSession(
        payload: _freshPayload(),
        record: record,
      );
      session.applyMerge(
        record.copyWith(updatedAt: '2026-01-01T00:00:00Z'),
        ciphertext,
      );

      final queue = InMemoryUploadQueue();
      final svc = SessionEndService(
        client: BackendClient(
          _base,
          httpClient: MockClient((_) async => http.Response('', 503)),
        ),
        queue: queue,
      );
      await svc.terminate(session);

      expect(await queue.count(), 1,
          reason: 'blob must have been queued after PUT failure');
      final queued = (await queue.pending()).single;
      final queuedText = utf8.decode(queued.ciphertext, allowMalformed: true);

      expect(
        queuedText,
        isNot(contains('OFFLINE-PII-MARKER')),
        reason: 'queued bytes must not contain plaintext PII',
      );
    });
  });
}
