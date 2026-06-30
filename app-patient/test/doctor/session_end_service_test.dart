// Unit tests for SessionEndService (issues #19 — US-2.3, and #21 — US-2.4).
//
// Verified properties:
//   - terminate with pendingBlob: issues PUT /blob/{uuid} with the blob bytes.
//   - PUT body carries the exact pending blob bytes.
//   - terminate without pendingBlob: no PUT issued, returns nothingToUpload.
//   - successful PUT returns uploaded and nothing is queued.
//   - session key is zeroed after successful terminate.
//   - pending blob bytes are zeroed in-place after successful terminate.
//   - pendingBlob is null after terminate.
//   - #21 offline: a failed PUT enqueues the blob (queued) instead of throwing.
//   - #21 offline: session key + pending blob bytes are still zeroed.
//   - #21 offline: the queued ciphertext is opaque and survives the wipe.
//   - #21 double-failure: PUT fails AND enqueue throws → OfflineQueueUnavailable
//     propagated; session (key + blob + pendingBlob) still fully wiped.
//   - #21 double-failure: pendingBlob == null with failing queue → nothingToUpload
//     (OfflineQueueUnavailable is never thrown when there is nothing to enqueue).
//   - ZK: terminate never issues GET (write-only cloud operation).
//   - repeated call: second terminate on an already-wiped session → nothingToUpload.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_patient/src/cloud/backend_client.dart';
import 'package:app_patient/src/doctor/consultation_session.dart';
import 'package:app_patient/src/doctor/offline_upload_queue.dart';
import 'package:app_patient/src/doctor/session_end_service.dart';
import 'package:app_patient/src/qr/access_token.dart';
import 'package:app_patient/src/record/medical_record.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

const _uuid = '00000000-0000-4000-8000-000000000001';
const _base = 'http://backend.test';

const _kRecord = MedicalRecord(
  patientId: _uuid,
  createdAt: '2025-01-01T00:00:00Z',
  updatedAt: '2026-06-29T00:00:00Z',
);

QrPayload _payload({Uint8List? key}) => QrPayload(
      uuid: _uuid,
      backendUrl: _base,
      sessionKey: key ?? Uint8List.fromList(List.filled(32, 0x42)),
      expiresAt: DateTime.now().add(const Duration(seconds: 120)),
    );

/// Creates a session, optionally with a [blob] applied via [applyMerge].
ConsultationSession _session({Uint8List? blob, Uint8List? key}) {
  final session = ConsultationSession(
    payload: _payload(key: key),
    record: _kRecord,
  );
  if (blob != null) {
    session.applyMerge(
      _kRecord.copyWith(updatedAt: '2026-06-30T00:00:00Z'),
      blob,
    );
  }
  return session;
}

SessionEndService _svc(http.Client httpClient, {OfflineUploadQueue? queue}) =>
    SessionEndService(
      client: BackendClient(_base, httpClient: httpClient),
      queue: queue ?? InMemoryUploadQueue(),
    );

/// Offline queue that always throws [OfflineQueueUnavailable] on [enqueue] —
/// simulates a Keystore failure or disk-full condition.
class _FailingQueue implements OfflineUploadQueue {
  @override
  Future<void> enqueue(String blobUuid, Uint8List ciphertext) async =>
      throw const OfflineQueueUnavailable('keystore failure (test)');

  @override
  Future<List<PendingUpload>> pending() async => const [];

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

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('SessionEndService.terminate — PUT behaviour', () {
    test('issues PUT /blob/{uuid} when pendingBlob is present', () async {
      final puts = <String>[];
      final blob = Uint8List.fromList([0x01, 0x02, 0x03]);
      final svc = _svc(
        MockClient((req) async {
          if (req.method == 'PUT') puts.add(req.url.path);
          return http.Response('', 200);
        }),
      );
      await svc.terminate(_session(blob: blob));
      expect(puts, hasLength(1));
      expect(puts.first, '/blob/$_uuid');
    });

    test('PUT body carries the exact pending blob bytes', () async {
      final captured = <Uint8List>[];
      // Take a snapshot of the original bytes before wipe zeroes them.
      final blob = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
      final origBlob = Uint8List.fromList(blob);
      final svc = _svc(
        MockClient((req) async {
          // http package copies body bytes into the Request object, so this
          // snapshot is unaffected by the wipe() that follows the PUT.
          captured.add(Uint8List.fromList(req.bodyBytes));
          return http.Response('', 200);
        }),
      );
      await svc.terminate(_session(blob: blob));
      expect(captured, hasLength(1));
      expect(captured.first, equals(origBlob));
    });

    test('does not issue PUT when pendingBlob is null', () async {
      final puts = <String>[];
      final svc = _svc(
        MockClient((req) async {
          if (req.method == 'PUT') puts.add(req.url.path);
          return http.Response('', 200);
        }),
      );
      await svc.terminate(_session());
      expect(puts, isEmpty);
    });
  });

  group('SessionEndService.terminate — wipe behaviour', () {
    test('zeroes session key after successful terminate', () async {
      final key = Uint8List.fromList(List.filled(32, 0x42));
      final session = _session(
        blob: Uint8List.fromList([1, 2, 3]),
        key: key,
      );
      final svc = _svc(MockClient((_) async => http.Response('', 200)));
      await svc.terminate(session);
      expect(key, everyElement(0));
    });

    test('zeroes pending blob bytes in-place after successful terminate',
        () async {
      final blob = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
      final session = _session(blob: blob);
      final svc = _svc(MockClient((_) async => http.Response('', 200)));
      await svc.terminate(session);
      // The original Uint8List reference should be zeroed.
      expect(blob, everyElement(0));
    });

    test('sets pendingBlob to null after terminate', () async {
      final session = _session(blob: Uint8List.fromList([1, 2, 3]));
      final svc = _svc(MockClient((_) async => http.Response('', 200)));
      await svc.terminate(session);
      expect(session.pendingBlob, isNull);
    });

    test('zeroes session key even when PUT fails (offline → queued)', () async {
      final key = Uint8List.fromList(List.filled(32, 0x42));
      final session = _session(
        blob: Uint8List.fromList([1, 2, 3]),
        key: key,
      );
      final svc = _svc(MockClient((_) async => http.Response('error', 503)));
      final outcome = await svc.terminate(session);
      expect(outcome, SessionEndOutcome.queued);
      expect(key, everyElement(0));
    });

    test('zeroes pending blob bytes even when PUT fails (offline → queued)',
        () async {
      final blob = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      final session = _session(blob: blob);
      final svc = _svc(MockClient((_) async => http.Response('error', 503)));
      await svc.terminate(session);
      expect(blob, everyElement(0));
    });
  });

  group('SessionEndService.terminate — #21 offline queue', () {
    test('successful PUT returns uploaded and queues nothing', () async {
      final queue = InMemoryUploadQueue();
      final svc = _svc(
        MockClient((_) async => http.Response('', 200)),
        queue: queue,
      );
      final outcome = await svc.terminate(
        _session(blob: Uint8List.fromList([1, 2, 3])),
      );
      expect(outcome, SessionEndOutcome.uploaded);
      expect(await queue.count(), 0);
    });

    test('failed PUT enqueues the blob and returns queued', () async {
      final queue = InMemoryUploadQueue();
      final session = _session(blob: Uint8List.fromList([1, 2, 3]));
      final svc = _svc(
        MockClient((_) async => http.Response('error', 503)),
        queue: queue,
      );
      final outcome = await svc.terminate(session);
      expect(outcome, SessionEndOutcome.queued);
      expect(await queue.count(), 1);
      final queued = await queue.pending();
      expect(queued.single.blobUuid, _uuid);
    });

    test('queued ciphertext survives the post-enqueue wipe (defensive copy)',
        () async {
      final queue = InMemoryUploadQueue();
      final blob = Uint8List.fromList([0xCA, 0xFE, 0xBA, 0xBE]);
      final session = _session(blob: blob);
      final svc = _svc(
        MockClient((_) async => http.Response('error', 503)),
        queue: queue,
      );
      await svc.terminate(session);
      // The source blob was zeroed by wipe; the stored copy is intact + opaque.
      expect(blob, everyElement(0));
      expect(
        (await queue.pending()).single.ciphertext,
        equals(Uint8List.fromList([0xCA, 0xFE, 0xBA, 0xBE])),
      );
    });

    test('returns nothingToUpload when pendingBlob is null (no PUT, no queue)',
        () async {
      final queue = InMemoryUploadQueue();
      final svc = _svc(
        MockClient((_) async => http.Response('error', 503)),
        queue: queue,
      );
      final outcome = await svc.terminate(_session());
      expect(outcome, SessionEndOutcome.nothingToUpload);
      expect(await queue.count(), 0);
    });
  });

  group('SessionEndService ZK', () {
    test('terminate never issues GET (write-only cloud operation)', () async {
      final gets = <String>[];
      final session = _session(blob: Uint8List.fromList([1, 2, 3]));
      final svc = _svc(
        MockClient((req) async {
          if (req.method == 'GET') gets.add(req.url.path);
          return http.Response('', 200);
        }),
      );
      await svc.terminate(session);
      expect(gets, isEmpty);
    });
  });

  group('SessionEndService.terminate — double-failure (queue unavailable)', () {
    // PUT fails (503) AND the offline queue itself throws OfflineQueueUnavailable.
    // This is the only remaining path where data can be lost — the spec mandates
    // that the session is STILL fully wiped and the exception is propagated so
    // the UI can alert the doctor.

    test(
        'propagates OfflineQueueUnavailable when both PUT fails and enqueue throws',
        () async {
      final session = _session(blob: Uint8List.fromList([1, 2, 3]));
      final svc = SessionEndService(
        client: BackendClient(
          _base,
          httpClient:
              MockClient((_) async => http.Response('unavailable', 503)),
        ),
        queue: _FailingQueue(),
      );
      await expectLater(
        () => svc.terminate(session),
        throwsA(isA<OfflineQueueUnavailable>()),
      );
    });

    test('wipes session key even when OfflineQueueUnavailable is thrown',
        () async {
      final key = Uint8List.fromList(List.filled(32, 0x42));
      final session = _session(
        blob: Uint8List.fromList([1, 2, 3]),
        key: key,
      );
      final svc = SessionEndService(
        client: BackendClient(
          _base,
          httpClient:
              MockClient((_) async => http.Response('unavailable', 503)),
        ),
        queue: _FailingQueue(),
      );
      try {
        await svc.terminate(session);
      } on OfflineQueueUnavailable {
        // expected — verify wipe happened despite the exception
      }
      expect(key, everyElement(0));
    });

    test('wipes pending blob bytes even when OfflineQueueUnavailable is thrown',
        () async {
      final blob = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      final session = _session(blob: blob);
      final svc = SessionEndService(
        client: BackendClient(
          _base,
          httpClient:
              MockClient((_) async => http.Response('unavailable', 503)),
        ),
        queue: _FailingQueue(),
      );
      try {
        await svc.terminate(session);
      } on OfflineQueueUnavailable {
        // expected
      }
      expect(blob, everyElement(0));
      expect(session.pendingBlob, isNull);
    });

    test(
        'pendingBlob == null with a failing queue returns nothingToUpload — '
        'OfflineQueueUnavailable is NOT thrown when there is nothing to enqueue',
        () async {
      // The double-failure path is only reachable when a blob exists. A null
      // pendingBlob must short-circuit before any PUT or enqueue attempt, even
      // with a queue that would always throw.
      final svc = SessionEndService(
        client: BackendClient(
          _base,
          httpClient:
              MockClient((_) async => http.Response('unavailable', 503)),
        ),
        queue: _FailingQueue(),
      );
      final outcome = await svc.terminate(_session());
      expect(outcome, SessionEndOutcome.nothingToUpload);
    });
  });

  group('SessionEndService.terminate — repeated calls', () {
    test(
        'second terminate on the same session returns nothingToUpload — '
        'pendingBlob was already wiped by the first call', () async {
      final queue = InMemoryUploadQueue();
      final svc = _svc(
        MockClient((_) async => http.Response('', 200)),
        queue: queue,
      );
      final session = _session(blob: Uint8List.fromList([1, 2, 3]));
      final first = await svc.terminate(session);
      expect(first, SessionEndOutcome.uploaded);
      // Second call: session was wiped — pendingBlob is null.
      final second = await svc.terminate(session);
      expect(second, SessionEndOutcome.nothingToUpload);
      expect(await queue.count(), 0);
    });
  });
}
