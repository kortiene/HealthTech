import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/legal/consent_model.dart';

void main() {
  group('ConsentRecord', () {
    const record = ConsentRecord(
      version: '1.0',
      acceptedAt: '2024-01-15T10:30:00Z',
    );

    test('JSON round-trip preserves all fields', () {
      final restored = ConsentRecord.fromJson(record.toJson());
      expect(restored, equals(record));
    });

    test('toJson uses snake_case keys', () {
      final json = record.toJson();
      expect(json['version'], equals('1.0'));
      expect(json['accepted_at'], equals('2024-01-15T10:30:00Z'));
      expect(json.length, equals(2));
    });

    test('fromJson rejects missing version', () {
      expect(
        () => ConsentRecord.fromJson({'accepted_at': '2024-01-15T10:30:00Z'}),
        throwsA(isA<TypeError>()),
      );
    });

    test('fromJson rejects missing accepted_at', () {
      expect(
        () => ConsentRecord.fromJson({'version': '1.0'}),
        throwsA(isA<TypeError>()),
      );
    });

    test('equality is value-based', () {
      const a = ConsentRecord(
        version: '1.0',
        acceptedAt: '2024-01-15T10:30:00Z',
      );
      const b = ConsentRecord(
        version: '1.0',
        acceptedAt: '2024-01-15T10:30:00Z',
      );
      const c = ConsentRecord(
        version: '2.0',
        acceptedAt: '2024-01-15T10:30:00Z',
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('hashCode is consistent with equality', () {
      const a = ConsentRecord(
        version: '1.0',
        acceptedAt: '2024-01-15T10:30:00Z',
      );
      const b = ConsentRecord(
        version: '1.0',
        acceptedAt: '2024-01-15T10:30:00Z',
      );
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('consentBundleVersion', () {
    test('current bundle version is 1.0', () {
      expect(consentBundleVersion, equals('1.0'));
    });

    test('ConsentRecord can be created with current bundle version', () {
      const r = ConsentRecord(
        version: consentBundleVersion,
        acceptedAt: '2024-01-15T10:30:00Z',
      );
      expect(r.version, equals('1.0'));
    });
  });
}
