// Tests for NetworkRetry (issue #24 — degraded network).
//
// Uses baseDelayMs = 0 throughout so tests run instantly.
//
// Verifies:
//   - Eventual success after N-1 failures.
//   - Gives up and rethrows on the maxAttempts-th consecutive failure.
//   - retryIf predicate prevents retry of non-retryable errors.
//   - Single-attempt policy (maxAttempts=1) never retries.
//   - Return value is forwarded correctly.

import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/cloud/network_retry.dart';

class _Transient implements Exception {
  const _Transient();
}

class _Permanent implements Exception {
  const _Permanent();
}

void main() {
  const fast = NetworkRetry(maxAttempts: 3, baseDelayMs: 0);

  group('NetworkRetry.run — success paths', () {
    test('succeeds immediately (no failures)', () async {
      final result = await fast.run(() async => 42);
      expect(result, equals(42));
    });

    test('succeeds after 1 failure', () async {
      var calls = 0;
      final result = await fast.run(() async {
        calls++;
        if (calls < 2) throw const _Transient();
        return 'ok';
      });
      expect(result, equals('ok'));
      expect(calls, equals(2));
    });

    test('succeeds after 2 failures (maxAttempts=3)', () async {
      var calls = 0;
      final result = await fast.run(() async {
        calls++;
        if (calls < 3) throw const _Transient();
        return 'done';
      });
      expect(result, equals('done'));
      expect(calls, equals(3));
    });
  });

  group('NetworkRetry.run — failure paths', () {
    test('rethrows after maxAttempts failures', () async {
      var calls = 0;
      await expectLater(
        fast.run(() async {
          calls++;
          throw const _Transient();
        }),
        throwsA(isA<_Transient>()),
      );
      expect(calls, equals(3),
          reason: 'should attempt exactly maxAttempts times');
    });

    test('maxAttempts=1 never retries', () async {
      const once = NetworkRetry(maxAttempts: 1, baseDelayMs: 0);
      var calls = 0;
      await expectLater(
        once.run(() async {
          calls++;
          throw const _Transient();
        }),
        throwsA(isA<_Transient>()),
      );
      expect(calls, equals(1));
    });
  });

  group('NetworkRetry.run — retryIf predicate', () {
    test('non-retryable exception propagates immediately', () async {
      var calls = 0;
      await expectLater(
        fast.run(
          () async {
            calls++;
            throw const _Permanent();
          },
          retryIf: (e) => e is _Transient,
        ),
        throwsA(isA<_Permanent>()),
      );
      expect(calls, equals(1), reason: 'non-retryable must not trigger retry');
    });

    test('retryable exception is retried, permanent propagates', () async {
      var calls = 0;
      await expectLater(
        fast.run(
          () async {
            calls++;
            // First call: transient (retried); second: permanent (not retried).
            if (calls == 1) throw const _Transient();
            throw const _Permanent();
          },
          retryIf: (e) => e is _Transient,
        ),
        throwsA(isA<_Permanent>()),
      );
      expect(calls, equals(2));
    });
  });

  group('NetworkRetry.run — return value', () {
    test('forwards Future<void> without error', () async {
      await expectLater(
        fast.run(() async {}),
        completes,
      );
    });

    test('forwards typed return value', () async {
      final bytes = [1, 2, 3];
      final result = await fast.run(() async => bytes);
      expect(result, same(bytes));
    });
  });
}
