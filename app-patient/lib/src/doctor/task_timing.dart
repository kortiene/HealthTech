// Privacy-preserving task-time instrumentation for usability tests (issue #28).
//
// A light utility to time the canonical consultation steps DURING usability-test
// sessions (docs/ux/usability-test-protocol.md, §5). It exists to feed the
// campaign's report with anonymous per-step durations — nothing more.
//
// SECURITY CONTRACT (hard invariant, guide UX §9 — proven by task_timing_test.dart):
//   * It accepts ONLY the canonical step labels ([UxBudget.canonicalSteps]) and
//     produces ONLY durations in milliseconds. An unknown label is rejected.
//   * It NEVER stores, logs, or exports medical data, keys, QR payloads, or PII —
//     structurally, its API has no channel to receive any of that.
//   * It is DISABLED BY DEFAULT (`enabled == false`); when disabled, start/stop
//     are no-ops. Enable it explicitly only in a test/measurement build.
//   * Its CSV/JSON export contains only step labels + integers.
//
// This introduces NO crypto, protocol, blob-format or data-model change, and no
// persistent session storage.

import 'dart:convert';

import 'ux_budget.dart';

/// Monotonic millisecond clock. Injectable for deterministic tests.
typedef MillisClock = int Function();

/// Times the canonical consultation steps and exports anonymous durations.
///
/// Usage (measurement/test build only):
/// ```dart
/// final t = TaskTiming(enabled: true);
/// t.start('scan');  /* ...doctor scans... */  t.stop('scan');
/// t.start('read');  /* ...reads dossier... */ t.stop('read');
/// final csv = t.toCsv(); // "step,duration_ms\nscan,1200\nread,3400"
/// ```
class TaskTiming {
  /// Create an instrument. When [enabled] is false (the default, i.e. production),
  /// [start]/[stop] are no-ops and the instrument records nothing.
  ///
  /// [clock] returns a monotonic time in milliseconds; defaults to a wall clock.
  /// Inject a fake clock in tests for deterministic durations.
  TaskTiming({this.enabled = false, MillisClock? clock})
      : _clock = clock ?? _defaultClock;

  /// Whether the instrument records. Disabled by default (production safety).
  final bool enabled;

  final MillisClock _clock;

  final Map<String, int> _startedAt = <String, int>{};
  final Map<String, int> _durationsMs = <String, int>{};

  static int _defaultClock() => DateTime.now().millisecondsSinceEpoch;

  /// Mark the start of a canonical [step]. No-op when [enabled] is false.
  ///
  /// Throws [ArgumentError] if [step] is not one of [UxBudget.canonicalSteps] —
  /// the label whitelist is the structural guarantee that no free-form (and thus
  /// potentially PII-bearing) string can ever enter the instrument.
  void start(String step) {
    _requireCanonical(step);
    if (!enabled) return;
    _startedAt[step] = _clock();
  }

  /// Mark the end of a canonical [step] and record its duration (ms). No-op when
  /// [enabled] is false. Throws [ArgumentError] on a non-canonical label or if
  /// [stop] is called for a step that was never [start]ed.
  void stop(String step) {
    _requireCanonical(step);
    if (!enabled) return;
    final started = _startedAt.remove(step);
    if (started == null) {
      throw ArgumentError.value(step, 'step', 'stop() called before start()');
    }
    final elapsed = _clock() - started;
    // Clamp to >= 0 to stay robust against a non-monotonic injected clock.
    _durationsMs[step] = elapsed < 0 ? 0 : elapsed;
  }

  /// Aggregated recorded durations (ms) keyed by canonical step label. A defensive
  /// copy — callers cannot mutate the internal map.
  Map<String, int> get durationsMs =>
      Map<String, int>.unmodifiable(_durationsMs);

  /// Total recorded task time (ms): the sum of all recorded step durations.
  int get totalMs => _durationsMs.values.fold(0, (a, b) => a + b);

  /// Anonymous CSV export: `step,duration_ms` header + one row per recorded step,
  /// in canonical order. Contains only step labels + integers — never PII.
  String toCsv() {
    final buffer = StringBuffer('step,duration_ms');
    for (final step in UxBudget.canonicalSteps) {
      final ms = _durationsMs[step];
      if (ms != null) buffer.write('\n$step,$ms');
    }
    return buffer.toString();
  }

  /// Anonymous JSON export: `{"scan":1200,"read":3400,...,"total_ms":...}`.
  /// Contains only canonical step labels + integer durations.
  String toJson() {
    final ordered = <String, int>{};
    for (final step in UxBudget.canonicalSteps) {
      final ms = _durationsMs[step];
      if (ms != null) ordered[step] = ms;
    }
    ordered['total_ms'] = totalMs;
    return jsonEncode(ordered);
  }

  void _requireCanonical(String step) {
    if (!UxBudget.canonicalSteps.contains(step)) {
      throw ArgumentError.value(
        step,
        'step',
        'not a canonical consultation step ${UxBudget.canonicalSteps}',
      );
    }
  }
}
