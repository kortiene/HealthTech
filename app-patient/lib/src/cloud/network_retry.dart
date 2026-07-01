// Retry-with-exponential-backoff for degraded-network resilience (issue #24).
//
// Edge/3G links in Côte d'Ivoire drop packets unpredictably; a single transient
// error should not permanently block the user. NetworkRetry wraps any async
// call with configurable retry up to maxAttempts, with delay doubling on each
// attempt (capped at 8 s). Use baseDelayMs = 0 in tests for instant retries.

import 'dart:math' show min;

/// Exponential-backoff retry policy for HTTP transport (issue #24).
///
/// Inject into [MedicalRecordStore] and [MediaClient] to enable automatic
/// retry on transient [BackendUnavailable] / [MediaBackendUnavailable] errors.
/// Set [baseDelayMs] = 0 in tests to avoid real sleeps.
class NetworkRetry {
  const NetworkRetry({this.maxAttempts = 3, this.baseDelayMs = 500});

  /// Maximum number of attempts (first try + retries). Must be ≥ 1.
  final int maxAttempts;

  /// Base retry delay in milliseconds. Doubles each attempt, capped at 8 s.
  final int baseDelayMs;

  /// Calls [fn] up to [maxAttempts] times with exponential backoff.
  ///
  /// Retries any exception for which [retryIf] returns true (defaults to
  /// retrying all exceptions). On the final attempt, the exception is rethrown
  /// regardless. Non-retryable exceptions propagate immediately.
  Future<T> run<T>(
    Future<T> Function() fn, {
    bool Function(Object)? retryIf,
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await fn();
      } catch (e) {
        final shouldRetry = retryIf != null ? retryIf(e) : true;
        if (!shouldRetry || attempt == maxAttempts) rethrow;
        final delayMs = min(baseDelayMs * (1 << (attempt - 1)), 8000);
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }
    throw StateError('unreachable');
  }
}
