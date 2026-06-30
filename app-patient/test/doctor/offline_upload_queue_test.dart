// Unit tests for OfflineUploadQueue — InMemoryUploadQueue and related types
// (issue #21 — US-2.4, M3 "Résilience hors-ligne").
//
// All tests run host-only against [InMemoryUploadQueue]. The SQLCipher production
// implementation ([SqlCipherUploadQueue]) shares the same contract; its native
// binding is validated by a device-backed integration test (follow-up, depends on
// #1 + emulator).
//
// Verified properties:
//   - count is 0 on an empty queue.
//   - pending() returns empty list on an empty queue.
//   - enqueue adds items; count tracks accurately.
//   - pending lists without removing.
//   - pending returns items in insertion (FIFO) order.
//   - remove deletes the targeted item only.
//   - remove with an unknown id is a no-op.
//   - count decrements after remove.
//   - after remove, re-enqueuing the same item is allowed (idempotence is per-contents).
//   - FIFO order preserved after remove-middle and re-enqueue.
//   - pending() returns an unmodifiable list (add throws UnsupportedError).
//   - idempotence: re-enqueuing identical (blobUuid, ciphertext) → no duplicate.
//   - idempotence: same blobUuid but different ciphertext → separate entry.
//   - idempotence: byte-for-byte copy is still recognised as a duplicate.
//   - defensive copy at enqueue: zeroing the source leaves the stored copy intact.
//   - defensive copy at pending: mutating a returned item leaves the queue intact.
//   - PendingUpload constructor: copies bytes defensively.
//   - PendingUpload.attempts defaults to 0.
//   - generateUploadId: produces valid RFC-4122 v4 format; successive calls unique.
//   - Injected idFactory/clock produce deterministic ids and timestamps.
//   - OfflineQueueUnavailable.toString() includes the message and class label.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/doctor/offline_upload_queue.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

const _uuid1 = '00000000-0000-4000-8000-000000000001';
const _uuid2 = '00000000-0000-4000-8000-000000000002';

// These are used READ-ONLY as inputs to enqueue (InMemoryUploadQueue copies them
// defensively). The defensive-copy tests use separate local variables so these
// module-level arrays are never mutated.
final _ct1 = Uint8List.fromList([0x01, 0x02, 0x03]);
final _ct2 = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
final _ct1b =
    Uint8List.fromList([0x01, 0x02, 0x04]); // same uuid, different bytes

/// Queue with deterministic id and a fixed clock — keeps assertions stable.
InMemoryUploadQueue _deterministicQueue() {
  var n = 0;
  return InMemoryUploadQueue(
    idFactory: () => 'test-id-${n++}',
    clock: () => DateTime.utc(2026, 6, 30),
  );
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('InMemoryUploadQueue — basic CRUD', () {
    test('count is 0 on an empty queue', () async {
      expect(await _deterministicQueue().count(), 0);
    });

    test('enqueue increments count', () async {
      final q = _deterministicQueue();
      await q.enqueue(_uuid1, _ct1);
      expect(await q.count(), 1);
    });

    test('pending does not remove items (idempotent read)', () async {
      final q = _deterministicQueue();
      await q.enqueue(_uuid1, _ct1);
      await q.pending();
      expect(await q.count(), 1);
    });

    test('pending returns the enqueued item with correct blobUuid', () async {
      final q = _deterministicQueue();
      await q.enqueue(_uuid1, _ct1);
      final items = await q.pending();
      expect(items, hasLength(1));
      expect(items.single.blobUuid, _uuid1);
    });

    test('pending returns the stored ciphertext bytes', () async {
      final q = _deterministicQueue();
      await q.enqueue(_uuid1, _ct1);
      expect((await q.pending()).single.ciphertext, equals(_ct1));
    });

    test('remove deletes the targeted item', () async {
      final q = _deterministicQueue();
      await q.enqueue(_uuid1, _ct1);
      final id = (await q.pending()).single.id;
      await q.remove(id);
      expect(await q.count(), 0);
    });

    test('remove with unknown id is a no-op', () async {
      final q = _deterministicQueue();
      await q.enqueue(_uuid1, _ct1);
      await q.remove('does-not-exist');
      expect(await q.count(), 1);
    });

    test('remove deletes only the targeted item when multiple are present',
        () async {
      final q = _deterministicQueue();
      await q.enqueue(_uuid1, _ct1);
      await q.enqueue(_uuid2, _ct2);
      final items = await q.pending();
      await q.remove(items.first.id);
      final remaining = await q.pending();
      expect(remaining, hasLength(1));
      expect(remaining.single.blobUuid, _uuid2);
    });

    test('pending returns items in FIFO (insertion) order', () async {
      final q = _deterministicQueue();
      await q.enqueue(_uuid1, _ct1);
      await q.enqueue(_uuid2, _ct2);
      final items = await q.pending();
      expect(items, hasLength(2));
      expect(items[0].blobUuid, _uuid1);
      expect(items[1].blobUuid, _uuid2);
    });

    test('count tracks multiple items correctly', () async {
      final q = _deterministicQueue();
      await q.enqueue(_uuid1, _ct1);
      await q.enqueue(_uuid2, _ct2);
      expect(await q.count(), 2);
    });
  });

  group('InMemoryUploadQueue — idempotence', () {
    test('re-enqueuing identical (blobUuid, ciphertext) adds no duplicate',
        () async {
      final q = _deterministicQueue();
      await q.enqueue(_uuid1, _ct1);
      await q.enqueue(_uuid1, _ct1); // exact same instance
      expect(await q.count(), 1);
    });

    test('re-enqueuing a byte-for-byte copy is still idempotent', () async {
      final q = _deterministicQueue();
      final copy = Uint8List.fromList(_ct1); // distinct list, same bytes
      await q.enqueue(_uuid1, _ct1);
      await q.enqueue(_uuid1, copy);
      expect(await q.count(), 1);
    });

    test('same blobUuid with different ciphertext is a distinct entry',
        () async {
      var n = 0;
      final q = InMemoryUploadQueue(idFactory: () => 'id-${n++}');
      await q.enqueue(_uuid1, _ct1);
      await q.enqueue(_uuid1, _ct1b); // same uuid, different payload
      expect(await q.count(), 2);
    });

    test('different blobUuids with identical ciphertext are distinct entries',
        () async {
      var n = 0;
      final q = InMemoryUploadQueue(idFactory: () => 'id-${n++}');
      await q.enqueue(_uuid1, _ct1);
      await q.enqueue(_uuid2, _ct1); // same bytes, different uuid
      expect(await q.count(), 2);
    });
  });

  group('InMemoryUploadQueue — defensive copy at enqueue', () {
    test(
        'zeroing the source Uint8List after enqueue does not corrupt the stored ciphertext',
        () async {
      final q = _deterministicQueue();
      final source = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      final snapshot = Uint8List.fromList(source);
      await q.enqueue(_uuid1, source);
      // Simulate what ConsultationSession.wipe() does to the pending blob.
      source.fillRange(0, source.length, 0);
      expect((await q.pending()).single.ciphertext, equals(snapshot));
    });

    test(
        'mutating a Uint8List returned from pending() does not alter the stored copy',
        () async {
      final q = _deterministicQueue();
      final original = Uint8List.fromList([0x01, 0x02, 0x03]);
      await q.enqueue(_uuid1, Uint8List.fromList(original));
      // Tamper with the returned copy.
      final returned = (await q.pending()).single;
      returned.ciphertext.fillRange(0, returned.ciphertext.length, 0xFF);
      // The queue's internal copy must be intact.
      expect(
        (await q.pending()).single.ciphertext,
        equals(original),
      );
    });
  });

  group('PendingUpload', () {
    test('constructor copies ciphertext bytes defensively', () {
      final source = Uint8List.fromList([0x11, 0x22, 0x33]);
      final pu = PendingUpload(
        id: 'id-1',
        blobUuid: _uuid1,
        ciphertext: source,
        enqueuedAtIso: '2026-06-30T00:00:00Z',
      );
      source.fillRange(0, source.length, 0);
      expect(pu.ciphertext, equals(Uint8List.fromList([0x11, 0x22, 0x33])));
    });

    test('attempts defaults to 0', () {
      final pu = PendingUpload(
        id: 'id-1',
        blobUuid: _uuid1,
        ciphertext: Uint8List.fromList([0x01]),
        enqueuedAtIso: '2026-06-30T00:00:00Z',
      );
      expect(pu.attempts, 0);
    });

    test('ciphertext holds opaque bytes — not plaintext (security invariant)',
        () {
      // Any byte sequence is acceptable — the invariant is that the queue
      // NEVER stores or compares the decrypted plaintext. This test pins the
      // contract: ciphertext is stored as-is (opaque), without transformation.
      final ct = Uint8List.fromList([0xCA, 0xFE, 0xBA, 0xBE]);
      final pu = PendingUpload(
        id: 'id-1',
        blobUuid: _uuid1,
        ciphertext: ct,
        enqueuedAtIso: '2026-06-30T00:00:00Z',
      );
      expect(pu.ciphertext, equals(ct));
    });
  });

  group('generateUploadId', () {
    test('produces a valid RFC-4122 v4 UUID', () {
      final id = generateUploadId();
      // v4 UUID: version nibble = 4, variant nibble in [8,9,a,b].
      final v4Pattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(id, matches(v4Pattern));
    });

    test('successive calls produce unique ids', () {
      final ids = {for (var i = 0; i < 20; i++) generateUploadId()};
      expect(ids.length, 20);
    });
  });

  group('InMemoryUploadQueue — deterministic injection', () {
    test('uses injected idFactory for PendingUpload.id', () async {
      var n = 0;
      final q = InMemoryUploadQueue(idFactory: () => 'fixed-${n++}');
      await q.enqueue(_uuid1, _ct1);
      expect((await q.pending()).single.id, 'fixed-0');
    });

    test('uses injected clock for PendingUpload.enqueuedAtIso', () async {
      final q = InMemoryUploadQueue(
        clock: () => DateTime.utc(2026, 6, 30, 12, 0, 0),
      );
      await q.enqueue(_uuid1, _ct1);
      expect(
        (await q.pending()).single.enqueuedAtIso,
        '2026-06-30T12:00:00.000Z',
      );
    });
  });

  group('InMemoryUploadQueue — empty queue', () {
    test('pending() returns an empty list on a fresh queue', () async {
      expect(await _deterministicQueue().pending(), isEmpty);
    });
  });

  group('InMemoryUploadQueue — remove and re-enqueue', () {
    test('count decrements after remove', () async {
      final q = _deterministicQueue();
      await q.enqueue(_uuid1, _ct1);
      await q.enqueue(_uuid2, _ct2);
      final id = (await q.pending()).first.id;
      await q.remove(id);
      expect(await q.count(), 1);
    });

    test(
        'after remove, re-enqueuing the same (blobUuid, ciphertext) is allowed — '
        'idempotence applies only to items currently in the queue', () async {
      final q = _deterministicQueue();
      await q.enqueue(_uuid1, _ct1);
      final id = (await q.pending()).single.id;
      await q.remove(id);
      // Item is gone — the idempotence guard no longer blocks re-enqueue.
      await q.enqueue(_uuid1, _ct1);
      expect(await q.count(), 1);
    });

    test('FIFO order is preserved after remove-middle and re-enqueue',
        () async {
      var n = 0;
      final q = InMemoryUploadQueue(idFactory: () => 'id-${n++}');
      const uuidC = '00000000-0000-4000-8000-000000000003';
      final ctC = Uint8List.fromList([0xCC]);
      await q.enqueue(_uuid1, _ct1); // slot A
      await q.enqueue(_uuid2, _ct2); // slot B
      final first = (await q.pending()).first;
      await q.remove(first.id); // remove A
      await q.enqueue(uuidC, ctC); // slot C (appended after B)
      final remaining = await q.pending();
      expect(remaining, hasLength(2));
      expect(remaining[0].blobUuid, _uuid2); // B is now first
      expect(remaining[1].blobUuid, uuidC); // C is last
    });
  });

  group('InMemoryUploadQueue — returned list contract', () {
    test('pending() returns an unmodifiable list', () async {
      final q = _deterministicQueue();
      await q.enqueue(_uuid1, _ct1);
      final items = await q.pending();
      // List.unmodifiable(...) makes the list grow-/shrink-proof.
      final dummy = PendingUpload(
        id: 'x',
        blobUuid: _uuid1,
        ciphertext: _ct1,
        enqueuedAtIso: '2026-06-30T00:00:00Z',
      );
      expect(() => items.add(dummy), throwsUnsupportedError);
    });
  });

  group('OfflineQueueUnavailable', () {
    test('toString() includes the error message and the class label', () {
      const err = OfflineQueueUnavailable('keystore missing');
      expect(err.toString(), contains('keystore missing'));
      expect(err.toString(), contains('offline queue unavailable'));
    });
  });
}
