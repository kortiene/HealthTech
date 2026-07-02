// Unit tests for TaskTiming (issue #28, Livrable D — instrumentation temps-tâche).
//
// Verified properties:
//   - Disabled by default (production safe): start/stop are no-ops.
//   - Enabled: records per-step durations via an injected clock.
//   - Label whitelist rejects non-canonical strings on start and stop — this is the
//     STRUCTURAL PII FIREWALL: no free-form string (patient name, key, QR payload)
//     can ever enter the instrument.
//   - stop() before start() throws ArgumentError even on a canonical label.
//   - toCsv() produces a two-column, header-first CSV with ONLY canonical labels
//     and non-negative integers (redaction invariant).
//   - toJson() produces an object with ONLY canonical labels + integers + total_ms.
//   - Both exports respect UxBudget.canonicalSteps order, not insertion order.
//   - Partial recording: only recorded steps appear in export.
//   - Non-monotonic clock: elapsed is clamped to 0, never negative.
//   - durationsMs is a defensive, unmodifiable copy.
//   - totalMs == sum of all recorded step durations.
//
// REDACTION INVARIANT: toCsv() and toJson() output are parsed and verified to
// contain ONLY canonical step labels and integers — no free-form string that
// could carry PII, a medical datum, or a key can survive into the export.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/doctor/task_timing.dart';
import 'package:app_patient/src/doctor/ux_budget.dart';

// ── Clock helpers ──────────────────────────────────────────────────────────────

/// Returns a monotonic fake clock that starts at [start] and advances by
/// [delta] ms on every call.
MillisClock _monotonic({int start = 0, int delta = 100}) {
  var t = start;
  return () {
    final now = t;
    t += delta;
    return now;
  };
}

/// A fake clock that goes BACKWARDS — an adversarial, non-monotonic source.
MillisClock _nonMonotonic() {
  var t = 1000;
  return () {
    final now = t;
    t -= 500;
    return now;
  };
}

// ── Tests ──────────────────────────────────────────────────────────────────────

void main() {
  group('TaskTiming — disabled by default', () {
    test('enabled is false by default', () {
      expect(TaskTiming().enabled, isFalse);
    });

    test('start/stop are no-ops when disabled', () {
      final t = TaskTiming(clock: _monotonic());
      t.start('scan');
      t.stop('scan');
      expect(t.durationsMs, isEmpty);
      expect(t.totalMs, 0);
    });

    test('toCsv() returns header-only when disabled', () {
      final t = TaskTiming(clock: _monotonic());
      t.start('scan');
      t.stop('scan');
      expect(t.toCsv(), 'step,duration_ms');
    });

    test('toJson() returns {"total_ms":0} when disabled', () {
      final t = TaskTiming(clock: _monotonic());
      t.start('scan');
      t.stop('scan');
      final json = jsonDecode(t.toJson()) as Map<String, dynamic>;
      expect(json, <String, int>{'total_ms': 0});
    });
  });

  group('TaskTiming — enabled: recording', () {
    test('records a single step duration with the injected clock', () {
      // _monotonic(delta: 200): start('scan') reads t=0; stop('scan') reads t=200.
      // elapsed = 200 - 0 = 200.
      final t = TaskTiming(enabled: true, clock: _monotonic(delta: 200));
      t.start('scan');
      t.stop('scan');
      expect(t.durationsMs['scan'], 200);
    });

    test('records all canonical steps independently', () {
      // delta=100: each start/stop pair: start reads t=N, stop reads t=N+100 → 100 ms.
      final t = TaskTiming(enabled: true, clock: _monotonic(delta: 100));
      for (final step in UxBudget.canonicalSteps) {
        t.start(step);
        t.stop(step);
      }
      for (final step in UxBudget.canonicalSteps) {
        expect(t.durationsMs[step], 100, reason: 'step $step');
      }
    });

    test('totalMs is the sum of all recorded durations', () {
      final t = TaskTiming(enabled: true, clock: _monotonic(delta: 100));
      for (final step in UxBudget.canonicalSteps) {
        t.start(step);
        t.stop(step);
      }
      // 4 steps × 100 ms = 400 ms.
      expect(t.totalMs, UxBudget.canonicalSteps.length * 100);
    });

    test('partial recording: unrecorded steps absent from durationsMs', () {
      final t = TaskTiming(enabled: true, clock: _monotonic(delta: 100));
      t.start('scan');
      t.stop('scan');
      expect(t.durationsMs.keys.toList(), ['scan']);
      expect(t.durationsMs.containsKey('read'), isFalse);
    });

    test('non-monotonic clock: elapsed clamped to 0, never negative', () {
      // _nonMonotonic(): start reads 1000, stop reads 500 → elapsed = -500 → 0.
      final t = TaskTiming(enabled: true, clock: _nonMonotonic());
      t.start('scan');
      t.stop('scan');
      expect(t.durationsMs['scan'], 0);
    });

    test('durationsMs is an unmodifiable defensive copy', () {
      final t = TaskTiming(enabled: true, clock: _monotonic(delta: 100));
      t.start('scan');
      t.stop('scan');
      final copy = t.durationsMs;
      expect(() => copy['scan'] = 9999, throwsA(isA<UnsupportedError>()));
    });
  });

  group('TaskTiming — label whitelist (PII firewall)', () {
    test('start() rejects a non-canonical label — even a plausible one', () {
      final t = TaskTiming(enabled: true, clock: _monotonic());
      expect(
        () => t.start('patient_name'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('start() rejects a label containing medical data', () {
      final t = TaskTiming(enabled: true, clock: _monotonic());
      expect(
        () => t.start('Allergie: Pénicilline — sévère'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('stop() rejects a non-canonical label', () {
      final t = TaskTiming(enabled: true, clock: _monotonic());
      expect(
        () => t.stop('secretKey=abc123'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('ArgumentError fires even when disabled — whitelist is unconditional',
        () {
      // _requireCanonical is called before the enabled guard; the label check
      // is the structural contract, not an opt-in.
      final t = TaskTiming(clock: _monotonic());
      expect(
        () => t.start('pii_bearing_label'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('stop() before start() throws ArgumentError on a canonical label', () {
      final t = TaskTiming(enabled: true, clock: _monotonic());
      expect(
        () => t.stop('scan'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('all canonical labels are accepted without error', () {
      final t = TaskTiming(enabled: true, clock: _monotonic(delta: 50));
      expect(
        () {
          for (final step in UxBudget.canonicalSteps) {
            t.start(step);
            t.stop(step);
          }
        },
        returnsNormally,
      );
    });
  });

  group('TaskTiming — CSV export (redaction invariant)', () {
    test('header is exactly "step,duration_ms"', () {
      final t = TaskTiming(enabled: true, clock: _monotonic(delta: 100));
      t.start('scan');
      t.stop('scan');
      expect(t.toCsv().split('\n').first, 'step,duration_ms');
    });

    test(
        'each data row is exactly 2 columns: canonical label + non-negative integer',
        () {
      final t = TaskTiming(enabled: true, clock: _monotonic(delta: 100));
      for (final step in UxBudget.canonicalSteps) {
        t.start(step);
        t.stop(step);
      }
      final rows = t.toCsv().split('\n').skip(1);
      for (final row in rows) {
        final parts = row.split(',');
        expect(parts, hasLength(2), reason: 'row must be 2 columns: "$row"');
        expect(UxBudget.canonicalSteps, contains(parts[0]),
            reason: 'first column must be a canonical label');
        final ms = int.tryParse(parts[1]);
        expect(ms, isNotNull, reason: 'second column must be an integer');
        expect(ms, greaterThanOrEqualTo(0));
      }
    });

    test(
        'rows are in UxBudget.canonicalSteps order, regardless of recording order',
        () {
      // Record in REVERSE order — export must still follow canonical order.
      final t = TaskTiming(enabled: true, clock: _monotonic(delta: 100));
      for (final step in UxBudget.canonicalSteps.reversed) {
        t.start(step);
        t.stop(step);
      }
      final exportedSteps = t
          .toCsv()
          .split('\n')
          .skip(1)
          .map((row) => row.split(',').first)
          .toList();
      expect(exportedSteps, UxBudget.canonicalSteps);
    });

    test('unrecorded steps are absent from the CSV', () {
      final t = TaskTiming(enabled: true, clock: _monotonic(delta: 100));
      t.start('scan');
      t.stop('scan');
      final csv = t.toCsv();
      expect(csv, contains('scan'));
      expect(csv, isNot(contains('read')));
      expect(csv, isNot(contains('edit')));
      expect(csv, isNot(contains('terminate')));
    });

    test('CSV contains no free-form string that could carry PII (redaction)',
        () {
      final t = TaskTiming(enabled: true, clock: _monotonic(delta: 150));
      t.start('scan');
      t.stop('scan');
      // Every label in the data rows must be a known canonical step.
      for (final line in t.toCsv().split('\n').skip(1)) {
        final label = line.split(',').first;
        expect(
          UxBudget.canonicalSteps.contains(label),
          isTrue,
          reason: 'non-canonical string in CSV: "$label"',
        );
      }
    });
  });

  group('TaskTiming — JSON export (redaction invariant)', () {
    test('toJson() for a full run contains only canonical keys + total_ms', () {
      final t = TaskTiming(enabled: true, clock: _monotonic(delta: 100));
      for (final step in UxBudget.canonicalSteps) {
        t.start(step);
        t.stop(step);
      }
      final json = jsonDecode(t.toJson()) as Map<String, dynamic>;
      final allowed = {...UxBudget.canonicalSteps, 'total_ms'};
      for (final key in json.keys) {
        expect(allowed, contains(key),
            reason: 'non-canonical JSON key: "$key"');
      }
      for (final val in json.values) {
        expect(val, isA<int>(), reason: 'all JSON values must be integers');
      }
    });

    test('toJson() total_ms equals totalMs', () {
      final t = TaskTiming(enabled: true, clock: _monotonic(delta: 100));
      for (final step in UxBudget.canonicalSteps) {
        t.start(step);
        t.stop(step);
      }
      final json = jsonDecode(t.toJson()) as Map<String, dynamic>;
      expect(json['total_ms'], t.totalMs);
    });

    test('toJson() partial recording — only recorded steps + total_ms appear',
        () {
      final t = TaskTiming(enabled: true, clock: _monotonic(delta: 100));
      t.start('scan');
      t.stop('scan');
      final json = jsonDecode(t.toJson()) as Map<String, dynamic>;
      expect(json.keys.toSet(), {'scan', 'total_ms'});
    });

    test('toJson() when disabled returns {"total_ms":0}', () {
      final t = TaskTiming(clock: _monotonic());
      final json = jsonDecode(t.toJson()) as Map<String, dynamic>;
      expect(json, <String, int>{'total_ms': 0});
    });
  });
}
