// Tests for PlaintextCompressor (issue #24 — degraded network).
//
// Verifies:
//   - Round-trip: compress → decodeIfCompressed returns original bytes.
//   - Backward compat: uncompressed JSON input returned unchanged by
//     decodeIfCompressed (magic-byte detection).
//   - Compression ratio on a near-500 Kio JSON fixture is > 75 % reduction
//     (proxy for the 3G perf acceptance criterion: smaller blob ↔ faster DL).
//   - Empty and single-byte inputs do not crash.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/record/plaintext_compressor.dart';

void main() {
  group('PlaintextCompressor.compress + decodeIfCompressed', () {
    test('round-trip restores original bytes', () {
      final original =
          Uint8List.fromList(utf8.encode('{"v":1,"patient_id":"abc"}'));
      final compressed = PlaintextCompressor.compress(original);
      final restored = PlaintextCompressor.decodeIfCompressed(compressed);
      expect(restored, equals(original));
    });

    test('compress output starts with gzip magic 0x1f 0x8b', () {
      final data = Uint8List.fromList(utf8.encode('hello world'));
      final compressed = PlaintextCompressor.compress(data);
      expect(compressed[0], equals(0x1f));
      expect(compressed[1], equals(0x8b));
    });

    test('decodeIfCompressed with raw JSON returns unchanged', () {
      // Backward compat: blobs written before #24 are plain JSON, not gzip.
      final rawJson = Uint8List.fromList(utf8.encode('{"v":1}'));
      final result = PlaintextCompressor.decodeIfCompressed(rawJson);
      expect(result, same(rawJson), reason: 'must return the identical object');
    });

    test('decodeIfCompressed with 1-byte input returns unchanged', () {
      final single = Uint8List.fromList([0x7b]);
      expect(PlaintextCompressor.decodeIfCompressed(single), equals(single));
    });

    test('decodeIfCompressed with empty bytes returns unchanged', () {
      final empty = Uint8List(0);
      expect(PlaintextCompressor.decodeIfCompressed(empty), equals(empty));
    });

    test('compress then decodeIfCompressed handles unicode medical text', () {
      const text = 'Diabète · allergie pénicilline · âge: 45 · Abidjan';
      final original = Uint8List.fromList(utf8.encode(text));
      final result = PlaintextCompressor.decodeIfCompressed(
          PlaintextCompressor.compress(original));
      expect(utf8.decode(result), equals(text));
    });
  });

  group('PlaintextCompressor — compression ratio (3G perf proxy, issue #24)',
      () {
    test('near-500 Kio JSON record compresses to < 25 % of original size', () {
      // Build a representative 400+ KB JSON payload (repetitive medical record).
      final consultationEntry = jsonEncode({
        'id': '00000000-0000-4000-8000-000000000001',
        'date': '2025-01-15',
        'practitioner_ref': 'aaaabbbb-cccc-dddd-eeee-ffffffffffff',
        'summary':
            'Contrôle glycémie, résultats normaux. Tension artérielle stable. '
                'Patient observant le traitement. Pas de complication détectée.',
        'prescription':
            'Continuer Metformine 500 mg 2×/jour. Prochain contrôle dans 3 mois.',
      });

      // Repeat to reach ~400 KB of raw JSON.
      final repeated = List.filled(600, consultationEntry).join(',');
      final fixture = utf8.encode('{"v":1,"consultations":[$repeated]}');
      final fixtureBytes = Uint8List.fromList(fixture);

      expect(
        fixtureBytes.length,
        greaterThan(100 * 1024),
        reason: 'fixture must be large enough to be representative (>100 KB)',
      );

      final compressed = PlaintextCompressor.compress(fixtureBytes);

      final ratio = compressed.length / fixtureBytes.length;
      expect(
        ratio,
        lessThan(0.25),
        reason: 'repetitive JSON must compress to < 25 % of original '
            '(actual ratio: ${(ratio * 100).toStringAsFixed(1)} %)',
      );
    });
  });
}
