// Unit and integration tests for SyncService, RetryPolicy, ManualSyncTrigger,
// and AppLifecycleSyncTrigger (issue #22 — US-2.4, M3 "Résilience hors-ligne").
//
// All drain tests run host-only: [InMemoryUploadQueue] (no native SQLCipher),
// [MockClient] (no real network), and deterministic injectable clocks. The
// AppLifecycleSyncTrigger group needs the Flutter binding and uses testWidgets.
//
// Verified properties:
//   RetryPolicy.backoffFor:
//     - 0 attempts  → Duration.zero
//     - 1 attempt   → baseBackoff
//     - 2 attempts  → 2 × baseBackoff
//     - large n     → capped at maxBackoff
//     - extreme n   → shift clamped to 30, no integer overflow
//   RetryPolicy.isEligible:
//     - fresh item (attempts=0)  → always eligible
//     - conflict item            → never eligible
//     - attempts == maxAttempts  → not eligible (persistent failure)
//     - attempts > maxAttempts   → not eligible
//     - inside backoff window    → not eligible
//     - exactly at window end    → eligible
//     - after  backoff window    → eligible
//     - null lastAttemptAtIso    → eligible (defensive — never stall)
//     - unparseable timestamp    → eligible (defensive — never stall)
//   SyncService.drain:
//     - empty queue → all counts 0, remaining=0, didRun=true
//     - single PUT success → synced=1, item removed from queue
//     - PUT body carries exact opaque ciphertext (ZK invariant)
//     - PUT is issued to the correct /blob/{uuid} path
//     - two items both succeed → PUT issued in FIFO enqueue order
//     - item is removed ONLY after a confirmed PUT (put-then-remove order)
//     - failed PUT → item kept, attempts incremented, failed=1
//     - drain stops after first BackendUnavailable (break — no further PUTs)
//     - partial drain: first succeeds, second fails → synced=1, failed=1, remaining=1
//     - conflict item → counted in conflicts, never PUT, never removed
//     - persistent-failure (attempts >= max) → counted, never PUT
//     - inside-backoff item → counted in skipped, never PUT
//     - after backoff window elapses → eligible again, PUT issued
//     - remaining field == queue.count() after drain
//     - drain never issues GET (write-only ZK invariant)
//     - failed item carries a non-null, non-empty redacted lastError
//     - long error message truncated to ≤120 chars
//     - multi-line error → first line stored only
//     - queueCount() is a thin pass-through to queue.count()
//   SyncService concurrency:
//     - re-entrant drain call while one is in flight → alreadyRunning (didRun=false)
//   ManualSyncTrigger:
//     - requestSync() emits a void event on the stream
//     - multiple calls emit multiple events
//     - after dispose(), requestSync() is a no-op (no throw, no event)
//   SyncService with trigger:
//     - trigger event drives a drain (PUT is issued)
//     - dispose() cancels subscription → subsequent trigger events are no-ops
//   AppLifecycleSyncTrigger:
//     - fires once at construction when fireOnStart=true
//     - does NOT fire at construction when fireOnStart=false
//     - fires on AppLifecycleState.resumed
//     - does NOT fire on paused / inactive / detached
//     - after dispose(), lifecycle events are no-ops
//   Integration — offline queue → drain on reconnect (AC for #22):
//     - session-end with network down → blob queued, not lost
//     - drain on reconnect → exactly one PUT per UUID (no duplicate)
//     - queue is empty after a successful reconnect drain
//   SyncSummary:
//     - alreadyRunning constant: didRun=false, all counts 0
//     - toString() includes all field names and values

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_patient/src/cloud/backend_client.dart';
import 'package:app_patient/src/doctor/offline_upload_queue.dart';
import 'package:app_patient/src/doctor/session_end_service.dart';
import 'package:app_patient/src/doctor/sync_service.dart';
import 'package:app_patient/src/doctor/sync_trigger.dart';
import 'package:app_patient/src/doctor/consultation_session.dart';
import 'package:app_patient/src/qr/access_token.dart';
import 'package:app_patient/src/record/medical_record.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

const _base = 'http://backend.test';
const _uuid1 = '00000000-0000-4000-8000-000000000001';
const _uuid2 = '00000000-0000-4000-8000-000000000002';
const _uuid3 = '00000000-0000-4000-8000-000000000003';

// Read-only opaque byte fixtures (never plaintext — security invariant).
final _ct1 = Uint8List.fromList([0x01, 0x02, 0x03]);
final _ct2 = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
final _ct3 = Uint8List.fromList([0x11, 0x22, 0x33]);

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Queue with a deterministic id factory so assertions are stable.
InMemoryUploadQueue _queue({DateTime Function()? clock}) {
  var n = 0;
  return InMemoryUploadQueue(
    idFactory: () => 'test-id-${n++}',
    clock: clock ?? (() => DateTime.utc(2026, 6, 30)),
  );
}

/// A [BackendClient] whose [MockClient] always returns HTTP 201.
BackendClient _successClient() => BackendClient(
      _base,
      httpClient: MockClient((_) async => http.Response('', 201)),
    );

/// A [BackendClient] whose [MockClient] always returns [statusCode].
BackendClient _failClient([int statusCode = 503]) => BackendClient(
      _base,
      httpClient: MockClient((_) async => http.Response('err', statusCode)),
    );

/// A [PendingUpload] fixture with sane defaults.
PendingUpload _item({
  String id = 'item-1',
  String blobUuid = _uuid1,
  int attempts = 0,
  String? lastAttemptAtIso,
  UploadState state = UploadState.pending,
}) =>
    PendingUpload(
      id: id,
      blobUuid: blobUuid,
      ciphertext: _ct1,
      enqueuedAtIso: '2026-06-30T00:00:00Z',
      attempts: attempts,
      lastAttemptAtIso: lastAttemptAtIso,
      state: state,
    );

// ─── _FakeBlobBackend ─────────────────────────────────────────────────────────

/// In-memory fake blob backend with a mutable [failPut] toggle.
///
/// [failPut] can be flipped mid-test to simulate the network returning —
/// the MockClient holds a reference to the method, so mutations are reflected
/// in subsequent requests.
///
/// [blobs] tracks ONLY successfully stored payloads (failPut=false).
/// [putsByUuid] counts every PUT attempt (successful or not) per UUID.
class _FakeBlobBackend {
  _FakeBlobBackend({this.failPut = false});

  bool failPut;

  /// Opaque ciphertext stored by successful PUTs — keyed by anonymous UUID.
  /// Never inspected: server is zero-knowledge.
  final Map<String, Uint8List> blobs = {};

  /// Total PUT attempts per UUID (including failed ones).
  final Map<String, int> putsByUuid = {};

  /// All HTTP methods seen by this backend.
  final List<String> methods = [];

  late final http.Client client = MockClient(_handle);

  Future<http.Response> _handle(http.Request req) async {
    methods.add(req.method);
    if (req.method == 'PUT') {
      final uuid = req.url.pathSegments.last;
      putsByUuid.update(uuid, (n) => n + 1, ifAbsent: () => 1);
      if (failPut) return http.Response('unavailable', 503);
      blobs[uuid] = Uint8List.fromList(req.bodyBytes);
      return http.Response('', 201);
    }
    return http.Response('not found', 404);
  }
}

// ─── _BlockingQueue ───────────────────────────────────────────────────────────

/// [OfflineUploadQueue] whose [pending] blocks until [_gate] completes.
/// Used by the mutex test to keep the first drain alive long enough for the
/// second call to observe `isDraining == true`.
class _BlockingQueue implements OfflineUploadQueue {
  _BlockingQueue(this._gate);
  final Future<void> _gate;

  @override
  Future<void> enqueue(String blobUuid, Uint8List ciphertext) async {}

  @override
  Future<List<PendingUpload>> pending() async {
    await _gate;
    return const [];
  }

  @override
  Future<void> remove(String id) async {}

  @override
  Future<int> count() async => 0;

  @override
  Future<void> markAttempt(String id, {required String redactedError}) async {}

  @override
  Future<void> markConflict(String id,
      {required String redactedReason}) async {}
}

// ─── Integration helper — ConsultationSession ────────────────────────────────

const _kRecord = MedicalRecord(
  patientId: _uuid1,
  createdAt: '2025-01-01T00:00:00Z',
  updatedAt: '2026-06-29T00:00:00Z',
);

QrPayload _payload({Uint8List? key}) => QrPayload(
      uuid: _uuid1,
      backendUrl: _base,
      sessionKey: key ?? Uint8List.fromList(List.filled(32, 0x42)),
      expiresAt: DateTime.now().add(const Duration(seconds: 120)),
    );

ConsultationSession _session({Uint8List? blob, Uint8List? key}) {
  final s = ConsultationSession(payload: _payload(key: key), record: _kRecord);
  if (blob != null) {
    s.applyMerge(_kRecord.copyWith(updatedAt: '2026-06-30T00:00:00Z'), blob);
  }
  return s;
}

// ═════════════════════════════════════════════════════════════════════════════
// Tests
// ═════════════════════════════════════════════════════════════════════════════

void main() {
  // ─── RetryPolicy.backoffFor ─────────────────────────────────────────────────

  group('RetryPolicy.backoffFor', () {
    const policy = RetryPolicy(
      maxAttempts: 5,
      baseBackoff: Duration(seconds: 30),
      maxBackoff: Duration(minutes: 30),
    );

    test('0 attempts → Duration.zero', () {
      expect(policy.backoffFor(0), Duration.zero);
    });

    test('negative attempts → Duration.zero', () {
      expect(policy.backoffFor(-1), Duration.zero);
    });

    test('1 attempt → baseBackoff (30 s)', () {
      expect(policy.backoffFor(1), const Duration(seconds: 30));
    });

    test('2 attempts → 2 × baseBackoff (60 s)', () {
      expect(policy.backoffFor(2), const Duration(seconds: 60));
    });

    test('3 attempts → 4 × baseBackoff (120 s)', () {
      expect(policy.backoffFor(3), const Duration(seconds: 120));
    });

    test('7 attempts → capped at maxBackoff (30 min)', () {
      // 30 s * 2^6 = 1920 s > 30 min → clamped.
      expect(policy.backoffFor(7), const Duration(minutes: 30));
    });

    test('very large attempt count does not overflow (shift clamped to 30)',
        () {
      expect(policy.backoffFor(1000), const Duration(minutes: 30));
    });
  });

  // ─── RetryPolicy.isEligible ─────────────────────────────────────────────────

  group('RetryPolicy.isEligible', () {
    final now = DateTime.utc(2026, 6, 30, 12, 0, 0);
    const policy = RetryPolicy(
      maxAttempts: 3,
      baseBackoff: Duration(minutes: 1),
      maxBackoff: Duration(minutes: 30),
    );

    test('fresh item (attempts=0, no timestamp) is always eligible', () {
      expect(policy.isEligible(_item(attempts: 0), now), isTrue);
    });

    test('conflict item is never eligible', () {
      expect(
        policy.isEligible(_item(state: UploadState.conflict), now),
        isFalse,
      );
    });

    test('attempts == maxAttempts → not eligible (persistent failure)', () {
      expect(policy.isEligible(_item(attempts: 3), now), isFalse);
    });

    test('attempts > maxAttempts → also not eligible', () {
      expect(policy.isEligible(_item(attempts: 99), now), isFalse);
    });

    test('inside backoff window → not eligible', () {
      // attempts=1, backoff=1 min; lastAttempt was only 30 s ago.
      final last = now.subtract(const Duration(seconds: 30)).toIso8601String();
      expect(
        policy.isEligible(_item(attempts: 1, lastAttemptAtIso: last), now),
        isFalse,
      );
    });

    test('exactly at backoff boundary → eligible', () {
      // attempts=1, backoff=1 min; lastAttempt was exactly 60 s ago.
      final last = now.subtract(const Duration(minutes: 1)).toIso8601String();
      expect(
        policy.isEligible(_item(attempts: 1, lastAttemptAtIso: last), now),
        isTrue,
      );
    });

    test('after backoff window → eligible', () {
      final last = now.subtract(const Duration(minutes: 5)).toIso8601String();
      expect(
        policy.isEligible(_item(attempts: 1, lastAttemptAtIso: last), now),
        isTrue,
      );
    });

    test('null lastAttemptAtIso → eligible (attempts > 0 but no stamp)', () {
      expect(
        policy.isEligible(_item(attempts: 1, lastAttemptAtIso: null), now),
        isTrue,
      );
    });

    test('unparseable lastAttemptAtIso → eligible (defensive, never stall)',
        () {
      expect(
        policy.isEligible(
          _item(attempts: 1, lastAttemptAtIso: 'not-a-date'),
          now,
        ),
        isTrue,
      );
    });
  });

  // ─── SyncService.drain — empty queue ────────────────────────────────────────

  group('SyncService.drain — empty queue', () {
    test('returns all-zero summary with didRun=true', () async {
      final q = _queue();
      final svc = SyncService(client: _successClient(), queue: q);
      final s = await svc.drain();
      expect(s.didRun, isTrue);
      expect(s.synced, 0);
      expect(s.failed, 0);
      expect(s.conflicts, 0);
      expect(s.skipped, 0);
      expect(s.persistentFailures, 0);
      expect(s.remaining, 0);
    });
  });

  // ─── SyncService.drain — successful PUT ─────────────────────────────────────

  group('SyncService.drain — successful PUT', () {
    test('single item: synced=1, queue empty after drain', () async {
      final q = _queue();
      await q.enqueue(_uuid1, _ct1);
      final svc = SyncService(client: _successClient(), queue: q);
      final s = await svc.drain();
      expect(s.synced, 1);
      expect(s.remaining, 0);
      expect(await q.count(), 0);
    });

    test('PUT body carries the exact opaque ciphertext bytes (ZK invariant)',
        () async {
      final q = _queue();
      final originalBytes = Uint8List.fromList([0xCA, 0xFE, 0xBA, 0xBE]);
      await q.enqueue(_uuid1, Uint8List.fromList(originalBytes));
      final capturedBodies = <Uint8List>[];
      final svc = SyncService(
        client: BackendClient(
          _base,
          httpClient: MockClient((req) async {
            if (req.method == 'PUT') {
              capturedBodies.add(Uint8List.fromList(req.bodyBytes));
            }
            return http.Response('', 201);
          }),
        ),
        queue: q,
      );
      await svc.drain();
      expect(capturedBodies, hasLength(1));
      expect(capturedBodies.first, equals(originalBytes));
    });

    test('PUT is issued to the correct /blob/{uuid} path', () async {
      final q = _queue();
      await q.enqueue(_uuid1, _ct1);
      final paths = <String>[];
      final svc = SyncService(
        client: BackendClient(
          _base,
          httpClient: MockClient((req) async {
            if (req.method == 'PUT') paths.add(req.url.path);
            return http.Response('', 201);
          }),
        ),
        queue: q,
      );
      await svc.drain();
      expect(paths, hasLength(1));
      expect(paths.first, '/blob/$_uuid1');
    });

    test('two items both succeed: PUT issued in FIFO enqueue order', () async {
      final q = _queue();
      await q.enqueue(_uuid1, _ct1);
      await q.enqueue(_uuid2, _ct2);
      final uuidOrder = <String>[];
      final svc = SyncService(
        client: BackendClient(
          _base,
          httpClient: MockClient((req) async {
            if (req.method == 'PUT') {
              uuidOrder.add(req.url.pathSegments.last);
            }
            return http.Response('', 201);
          }),
        ),
        queue: q,
      );
      final s = await svc.drain();
      expect(s.synced, 2);
      expect(uuidOrder, equals([_uuid1, _uuid2]));
      expect(await q.count(), 0);
    });

    test(
        'item is removed ONLY after a confirmed PUT (put-then-remove semantics)',
        () async {
      // Verify via the successful case: after drain, queue is empty.
      // The failed-PUT case (item stays in queue) is the complementary proof.
      final q = _queue();
      await q.enqueue(_uuid1, _ct1);
      final svc = SyncService(client: _successClient(), queue: q);
      await svc.drain();
      expect(await q.count(), 0);
    });
  });

  // ─── SyncService.drain — PUT failure ────────────────────────────────────────

  group('SyncService.drain — PUT failure', () {
    test('failed PUT keeps item in queue', () async {
      final q = _queue();
      await q.enqueue(_uuid1, _ct1);
      final svc = SyncService(client: _failClient(), queue: q);
      await svc.drain();
      expect(await q.count(), 1);
    });

    test('failed PUT increments item attempts via markAttempt', () async {
      final q = _queue();
      await q.enqueue(_uuid1, _ct1);
      final svc = SyncService(client: _failClient(), queue: q);
      final s = await svc.drain();
      expect(s.failed, 1);
      final item = (await q.pending()).single;
      expect(item.attempts, 1);
      expect(item.lastAttemptAtIso, isNotNull);
    });

    test(
        'drain stops after first BackendUnavailable — subsequent items not PUT',
        () async {
      final q = _queue();
      await q.enqueue(_uuid1, _ct1);
      await q.enqueue(_uuid2, _ct2);
      await q.enqueue(_uuid3, _ct3);
      var putCount = 0;
      final svc = SyncService(
        client: BackendClient(
          _base,
          httpClient: MockClient((req) async {
            if (req.method == 'PUT') putCount++;
            return http.Response('unavailable', 503);
          }),
        ),
        queue: q,
      );
      final s = await svc.drain();
      // The break exits after the first failure — only item 1 was attempted.
      expect(putCount, 1);
      expect(s.failed, 1);
      expect(s.synced, 0);
      expect(s.remaining, 3);
    });

    test('partial drain: first succeeds, second fails → synced=1 failed=1',
        () async {
      final q = _queue();
      await q.enqueue(_uuid1, _ct1);
      await q.enqueue(_uuid2, _ct2);
      var putCount = 0;
      final svc = SyncService(
        client: BackendClient(
          _base,
          httpClient: MockClient((req) async {
            if (req.method == 'PUT') {
              putCount++;
              if (putCount >= 2) return http.Response('err', 503);
            }
            return http.Response('', 201);
          }),
        ),
        queue: q,
      );
      final s = await svc.drain();
      expect(s.synced, 1);
      expect(s.failed, 1);
      expect(s.remaining, 1);
      // Item 1 removed; item 2 still present with attempts=1.
      final remaining = await q.pending();
      expect(remaining.single.blobUuid, _uuid2);
      expect(remaining.single.attempts, 1);
    });

    test('failed item carries a non-null, non-empty redacted lastError',
        () async {
      final q = _queue();
      await q.enqueue(_uuid1, _ct1);
      final svc = SyncService(client: _failClient(503), queue: q);
      await svc.drain();
      expect((await q.pending()).single.lastError, isNotEmpty);
    });

    test('long error message stored as at most 120 chars (truncation)',
        () async {
      // MockClient throws an exception whose toString() is very long.
      // BackendClient wraps it: BackendUnavailable('PUT /blob/uuid: $e').
      // SyncService._redact must clamp lastError to ≤ 120 chars.
      final q = _queue();
      await q.enqueue(_uuid1, _ct1);
      final longMsg = 'E' * 300;
      final svc = SyncService(
        client: BackendClient(
          _base,
          httpClient: MockClient((_) async => throw Exception(longMsg)),
        ),
        queue: q,
      );
      await svc.drain();
      expect(
          (await q.pending()).single.lastError!.length, lessThanOrEqualTo(120));
    });

    test('multi-line error → only the first line stored (no PII leak path)',
        () async {
      final q = _queue();
      await q.enqueue(_uuid1, _ct1);
      final svc = SyncService(
        client: BackendClient(
          _base,
          httpClient: MockClient(
            (_) async => throw Exception('first line\nsecond line\nthird'),
          ),
        ),
        queue: q,
      );
      await svc.drain();
      final lastError = (await q.pending()).single.lastError!;
      expect(lastError.contains('\n'), isFalse);
      expect(lastError.contains('second line'), isFalse);
    });
  });

  // ─── SyncService.drain — special item states ─────────────────────────────────

  group('SyncService.drain — special item states', () {
    test('conflict item: counted in conflicts, never PUT, never removed',
        () async {
      final q = _queue();
      await q.enqueue(_uuid1, _ct1);
      await q.markConflict(
        (await q.pending()).single.id,
        redactedReason: '412 precondition',
      );
      final puts = <String>[];
      final svc = SyncService(
        client: BackendClient(
          _base,
          httpClient: MockClient((req) async {
            if (req.method == 'PUT') puts.add(req.url.path);
            return http.Response('', 201);
          }),
        ),
        queue: q,
      );
      final s = await svc.drain();
      expect(puts, isEmpty);
      expect(s.conflicts, 1);
      expect(s.synced, 0);
      expect(await q.count(), 1);
    });

    test('persistent-failure item (attempts >= maxAttempts): not PUT',
        () async {
      const policy = RetryPolicy(maxAttempts: 3);
      final q = _queue();
      await q.enqueue(_uuid1, _ct1);
      final id = (await q.pending()).single.id;
      // Exhaust the retry budget.
      for (var i = 0; i < 3; i++) {
        await q.markAttempt(id, redactedError: 'test-error');
      }
      final puts = <String>[];
      final svc = SyncService(
        client: BackendClient(
          _base,
          httpClient: MockClient((req) async {
            if (req.method == 'PUT') puts.add(req.url.path);
            return http.Response('', 201);
          }),
        ),
        queue: q,
        retry: policy,
      );
      final s = await svc.drain();
      expect(puts, isEmpty);
      expect(s.persistentFailures, 1);
      expect(s.synced, 0);
    });

    test('inside-backoff item: counted in skipped, not PUT', () async {
      final now = DateTime.utc(2026, 6, 30, 12, 0, 0);
      const policy = RetryPolicy(
        maxAttempts: 5,
        baseBackoff: Duration(minutes: 10),
        maxBackoff: Duration(hours: 1),
      );
      final q = _queue(clock: () => now);
      await q.enqueue(_uuid1, _ct1);
      // One attempt at `now` → item is inside the 10-min backoff.
      await q.markAttempt(
        (await q.pending()).single.id,
        redactedError: 'err',
      );
      final puts = <String>[];
      final svc = SyncService(
        client: BackendClient(
          _base,
          httpClient: MockClient((req) async {
            if (req.method == 'PUT') puts.add(req.url.path);
            return http.Response('', 201);
          }),
        ),
        queue: q,
        retry: policy,
        clock: () => now, // drain clock == queue clock → still inside window
      );
      final s = await svc.drain();
      expect(puts, isEmpty);
      expect(s.skipped, 1);
    });

    test('item becomes eligible again after the backoff window elapses',
        () async {
      var now = DateTime.utc(2026, 6, 30, 12, 0, 0);
      const policy = RetryPolicy(
        maxAttempts: 5,
        baseBackoff: Duration(minutes: 1),
        maxBackoff: Duration(hours: 1),
      );
      final q = _queue(clock: () => now);
      await q.enqueue(_uuid1, _ct1);
      await q.markAttempt(
        (await q.pending()).single.id,
        redactedError: 'err',
      );
      var putCount = 0;
      final svc = SyncService(
        client: BackendClient(
          _base,
          httpClient: MockClient((req) async {
            if (req.method == 'PUT') putCount++;
            return http.Response('', 201);
          }),
        ),
        queue: q,
        retry: policy,
        clock: () => now,
      );

      // Drain while inside the 1-min backoff window → skipped.
      final s1 = await svc.drain();
      expect(s1.skipped, 1);
      expect(putCount, 0);

      // Advance clock past the backoff window.
      now = now.add(const Duration(minutes: 2));
      final s2 = await svc.drain();
      expect(s2.synced, 1);
      expect(putCount, 1);
    });
  });

  // ─── SyncService.drain — invariants ─────────────────────────────────────────

  group('SyncService.drain — ZK and summary invariants', () {
    test('drain never issues GET (write-only ZK invariant)', () async {
      final q = _queue();
      await q.enqueue(_uuid1, _ct1);
      final methods = <String>[];
      final svc = SyncService(
        client: BackendClient(
          _base,
          httpClient: MockClient((req) async {
            methods.add(req.method);
            return http.Response('', 201);
          }),
        ),
        queue: q,
      );
      await svc.drain();
      expect(methods, everyElement('PUT'));
      expect(methods.where((m) => m == 'GET'), isEmpty);
    });

    test('remaining field equals queue.count() after drain', () async {
      final q = _queue();
      await q.enqueue(_uuid1, _ct1);
      await q.enqueue(_uuid2, _ct2);
      final svc = SyncService(client: _failClient(), queue: q);
      final s = await svc.drain();
      expect(s.remaining, await q.count());
    });

    test('queueCount() is a pass-through to queue.count()', () async {
      final q = _queue();
      await q.enqueue(_uuid1, _ct1);
      await q.enqueue(_uuid2, _ct2);
      final svc = SyncService(client: _successClient(), queue: q);
      expect(await svc.queueCount(), 2);
    });
  });

  // ─── SyncService concurrency (mutex) ────────────────────────────────────────

  group('SyncService.drain — re-entrancy mutex', () {
    test('re-entrant call while a drain is in flight → alreadyRunning',
        () async {
      // _BlockingQueue.pending() blocks until the gate completer fires.
      // This keeps the first drain alive long enough for the second call to
      // observe `_draining == true` (set synchronously before the first await).
      final gate = Completer<void>();
      final q = _BlockingQueue(gate.future);
      final svc = SyncService(client: _successClient(), queue: q);

      final firstFuture = svc.drain(); // starts, sets _draining=true, blocks
      final secondFuture = svc.drain(); // immediately sees _draining=true

      final second = await secondFuture;
      expect(second.didRun, isFalse);
      expect(second.synced, 0);
      expect(second.remaining, 0);

      gate.complete(); // release first drain
      await firstFuture;
    });
  });

  // ─── ManualSyncTrigger ───────────────────────────────────────────────────────

  group('ManualSyncTrigger', () {
    test('requestSync() emits a void event', () async {
      final trigger = ManualSyncTrigger();
      final events = <void>[];
      final sub = trigger.events.listen((_) => events.add(null));
      trigger.requestSync();
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      await sub.cancel();
      await trigger.dispose();
    });

    test('multiple calls each emit one event', () async {
      final trigger = ManualSyncTrigger();
      final events = <void>[];
      final sub = trigger.events.listen((_) => events.add(null));
      trigger.requestSync();
      trigger.requestSync();
      trigger.requestSync();
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(3));
      await sub.cancel();
      await trigger.dispose();
    });

    test('requestSync() after dispose() is a no-op (isClosed guard)', () async {
      final trigger = ManualSyncTrigger();
      final events = <void>[];
      final sub = trigger.events.listen((_) => events.add(null));
      await trigger.dispose();
      expect(() => trigger.requestSync(), returnsNormally); // must not throw
      await Future<void>.delayed(Duration.zero);
      expect(events, isEmpty);
      await sub.cancel();
    });
  });

  // ─── SyncService ↔ ManualSyncTrigger wiring ─────────────────────────────────

  group('SyncService with ManualSyncTrigger', () {
    test('trigger event drives a drain — PUT is issued', () async {
      final q = _queue();
      await q.enqueue(_uuid1, _ct1);

      // Use a Completer to reliably detect when the PUT fires — more robust
      // than a fixed-delay Future.
      final putFired = Completer<void>();
      final trigger = ManualSyncTrigger();
      final svc = SyncService(
        client: BackendClient(
          _base,
          httpClient: MockClient((req) async {
            if (req.method == 'PUT' && !putFired.isCompleted) {
              putFired.complete();
            }
            return http.Response('', 201);
          }),
        ),
        queue: q,
        trigger: trigger,
      );

      trigger.requestSync();
      await putFired.future; // blocks until the drain issues the PUT

      await svc.dispose();
      await trigger.dispose();
    });

    test('dispose() cancels subscription — subsequent trigger events no-op',
        () async {
      final q = _queue();
      await q.enqueue(_uuid1, _ct1);
      final trigger = ManualSyncTrigger();
      final svc = SyncService(
        client: _successClient(),
        queue: q,
        trigger: trigger,
      );

      await svc.dispose(); // subscription cancelled BEFORE any event

      trigger.requestSync();
      // 50 ms is an eternity for async ops; no drain should have run.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(await q.count(), 1,
          reason: 'drain must not have run after dispose');

      await trigger.dispose();
    });
  });

  // ─── AppLifecycleSyncTrigger ─────────────────────────────────────────────────

  group('AppLifecycleSyncTrigger', () {
    testWidgets('fires once at construction when fireOnStart=true',
        (tester) async {
      final trigger = AppLifecycleSyncTrigger(fireOnStart: true);
      final events = <void>[];
      final sub = trigger.events.listen((_) => events.add(null));
      // tester.pump() drives the Flutter event loop and drains the
      // scheduleMicrotask from the constructor before the assertion.
      await tester.pump();
      expect(events, hasLength(1));
      // Do not await cleanup in testWidgets — broadcast-stream close() needs a
      // pump to complete, so awaiting sub.cancel() or dispose() hangs the test.
      unawaited(sub.cancel());
      unawaited(trigger.dispose());
    });

    testWidgets('does NOT fire at construction when fireOnStart=false',
        (tester) async {
      final trigger = AppLifecycleSyncTrigger(fireOnStart: false);
      final events = <void>[];
      final sub = trigger.events.listen((_) => events.add(null));
      await tester.pump();
      expect(events, isEmpty);
      unawaited(sub.cancel());
      unawaited(trigger.dispose());
    });

    testWidgets('fires on AppLifecycleState.resumed', (tester) async {
      final trigger = AppLifecycleSyncTrigger(fireOnStart: false);
      final events = <void>[];
      final sub = trigger.events.listen((_) => events.add(null));
      trigger.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(events, hasLength(1));
      unawaited(sub.cancel());
      unawaited(trigger.dispose());
    });

    testWidgets('does NOT fire on AppLifecycleState.paused', (tester) async {
      final trigger = AppLifecycleSyncTrigger(fireOnStart: false);
      final events = <void>[];
      final sub = trigger.events.listen((_) => events.add(null));
      trigger.didChangeAppLifecycleState(AppLifecycleState.paused);
      await tester.pump();
      expect(events, isEmpty);
      unawaited(sub.cancel());
      unawaited(trigger.dispose());
    });

    testWidgets('does NOT fire on AppLifecycleState.inactive', (tester) async {
      final trigger = AppLifecycleSyncTrigger(fireOnStart: false);
      final events = <void>[];
      final sub = trigger.events.listen((_) => events.add(null));
      trigger.didChangeAppLifecycleState(AppLifecycleState.inactive);
      await tester.pump();
      expect(events, isEmpty);
      unawaited(sub.cancel());
      unawaited(trigger.dispose());
    });

    testWidgets('does NOT fire on AppLifecycleState.detached', (tester) async {
      final trigger = AppLifecycleSyncTrigger(fireOnStart: false);
      final events = <void>[];
      final sub = trigger.events.listen((_) => events.add(null));
      trigger.didChangeAppLifecycleState(AppLifecycleState.detached);
      await tester.pump();
      expect(events, isEmpty);
      unawaited(sub.cancel());
      unawaited(trigger.dispose());
    });

    testWidgets('resumed event is a no-op after dispose (isClosed guard)',
        (tester) async {
      final trigger = AppLifecycleSyncTrigger(fireOnStart: false);
      final events = <void>[];
      final sub = trigger.events.listen((_) => events.add(null));
      // dispose() sets _controller.isClosed synchronously; don't await to
      // avoid hanging (close() completion needs a pump in testWidgets).
      unawaited(trigger.dispose());
      trigger.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(events, isEmpty);
      unawaited(sub.cancel());
    });
  });

  // ─── Integration: offline queue → drain on reconnect ────────────────────────
  // Covers the main AC of issue #22: "Aucune perte ni doublon après
  // reconnexion" (no loss or duplicate after network return).

  group('Integration — offline queue → drain on reconnect', () {
    test(
        'blob queued during network outage is PUT exactly once on reconnect — '
        'no data loss, no duplicate (idempotent PUT at same UUID)', () async {
      final backend = _FakeBlobBackend(failPut: true); // start offline
      final queue = InMemoryUploadQueue();
      final client = BackendClient(_base, httpClient: backend.client);

      // Phase 1: session end while offline → blob queued, not lost.
      // Pass blob directly (no copy) so session.wipe() zeroes it in-place,
      // proving the original reference was wiped while the queue's defensive
      // copy remains intact.
      final blob = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      final session = _session(blob: blob);
      final svc = SessionEndService(client: client, queue: queue);
      final outcome = await svc.terminate(session);
      expect(outcome, SessionEndOutcome.queued);
      expect(await queue.count(), 1);
      // The blob bytes were zeroed by wipe() — but the stored copy is intact.
      expect(blob, everyElement(0));

      // Phase 2: network returns — drain the queue.
      backend.failPut = false;
      final syncSvc = SyncService(client: client, queue: queue);
      final summary = await syncSvc.drain();
      expect(summary.synced, 1);
      expect(summary.failed, 0);

      // Phase 3: verify no loss, no duplicate.
      expect(await queue.count(), 0, reason: 'queue must be empty after drain');
      // The blob must have reached the server (no data loss).
      expect(
        backend.blobs.containsKey(_uuid1),
        isTrue,
        reason: 'blob must be stored on the server after drain',
      );
      // Exactly one UUID stored — the idempotent PUT produced one server record.
      expect(backend.blobs.length, 1);
      // PUT attempts: phase-1 failed (503, no storage), phase-2 succeeded.
      expect(
        backend.putsByUuid[_uuid1],
        2,
        reason:
            '1 failed PUT (offline) + 1 successful PUT (drain) = 2 attempts',
      );
      // No GET was ever issued (write-only ZK drain).
      expect(backend.methods.where((m) => m == 'GET'), isEmpty);
    });

    test('no data loss when drain partially fails then retries after reconnect',
        () async {
      final backend = _FakeBlobBackend(failPut: false);
      final queue = InMemoryUploadQueue();
      final client = BackendClient(_base, httpClient: backend.client);
      final syncSvc = SyncService(
        client: client,
        queue: queue,
        retry: const RetryPolicy(
          maxAttempts: 5,
          baseBackoff: Duration.zero, // zero backoff for deterministic tests
        ),
      );

      // Enqueue two blobs.
      await queue.enqueue(_uuid1, _ct1);
      await queue.enqueue(_uuid2, _ct2);

      // Fail the second PUT on the first drain.
      var putCount = 0;
      final partialClient = BackendClient(
        _base,
        httpClient: MockClient((req) async {
          if (req.method == 'PUT') {
            putCount++;
            if (putCount == 2) return http.Response('err', 503);
          }
          return http.Response('', 201);
        }),
      );
      final partialSvc = SyncService(client: partialClient, queue: queue);
      final s1 = await partialSvc.drain();
      expect(s1.synced, 1);
      expect(s1.failed, 1);
      expect(await queue.count(), 1); // blob 2 still queued

      // Second drain with network back → remaining item drained successfully.
      final s2 = await syncSvc.drain();
      expect(s2.synced, 1);
      expect(await queue.count(), 0); // no loss
    });

    test('conflict item is preserved across drain attempts — never overwritten',
        () async {
      final queue = InMemoryUploadQueue();
      await queue.enqueue(_uuid1, _ct1);
      final id = (await queue.pending()).single.id;
      await queue.markConflict(id, redactedReason: '412 precondition');

      final backend = _FakeBlobBackend();
      final syncSvc = SyncService(
        client: BackendClient(_base, httpClient: backend.client),
        queue: queue,
      );
      final s = await syncSvc.drain();
      expect(s.conflicts, 1);
      expect(s.synced, 0);
      // Conflict item was never PUT (server blob preserved).
      expect(backend.putsByUuid, isEmpty);
      // Item stays in queue for patient-side reconciliation.
      expect(await queue.count(), 1);
    });
  });

  // ─── SyncSummary ─────────────────────────────────────────────────────────────

  group('SyncSummary', () {
    test('alreadyRunning constant: didRun=false, all counts 0', () {
      const s = SyncSummary.alreadyRunning;
      expect(s.didRun, isFalse);
      expect(s.synced, 0);
      expect(s.failed, 0);
      expect(s.conflicts, 0);
      expect(s.skipped, 0);
      expect(s.persistentFailures, 0);
      expect(s.remaining, 0);
    });

    test('toString() includes all field names and values', () {
      const s = SyncSummary(
        synced: 3,
        failed: 1,
        conflicts: 2,
        skipped: 4,
        persistentFailures: 5,
        remaining: 6,
        didRun: true,
      );
      final str = s.toString();
      expect(str, contains('synced'));
      expect(str, contains('3'));
      expect(str, contains('failed'));
      expect(str, contains('1'));
      expect(str, contains('conflicts'));
      expect(str, contains('2'));
      expect(str, contains('skipped'));
      expect(str, contains('4'));
      expect(str, contains('persistentFailures'));
      expect(str, contains('5'));
      expect(str, contains('remaining'));
      expect(str, contains('6'));
      expect(str, contains('didRun'));
    });
  });
}
