import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/record/medical_record.dart';

void main() {
  group('MedicalRecord', () {
    const sample = MedicalRecord(
      patientId: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
      demographics: Demographics(
        givenName: 'Awa',
        birthYear: 1996,
        sex: 'F',
        bloodType: 'O+',
      ),
      allergies: [
        Allergy(
          substance: 'Pénicilline',
          severity: 'severe',
          notedAt: '2024-01-15',
        ),
      ],
      chronicConditions: [
        ChronicCondition(name: 'Diabète type 2', icd10: 'E11', since: '2020'),
      ],
      medications: [
        Medication(
          name: 'Metformine',
          dose: '500 mg',
          frequency: '2x/jour',
          prescribedAt: '2024-01-15',
        ),
      ],
      consultations: [
        Consultation(
          id: 'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
          date: '2024-01-15',
          practitionerRef: 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22',
          summary: 'Contrôle glycémie, résultats normaux.',
          prescription: 'Continuer Metformine.',
          imageUrls: ['https://cdn.healthtech.ci/img/abc?token=xyz'],
        ),
      ],
      immunizations: [
        Immunization(name: 'Hépatite B', date: '2010-03-01', dose: 1),
      ],
      createdAt: '2024-01-01T00:00:00Z',
      updatedAt: '2024-01-15T10:30:00Z',
    );

    test('toJson includes v: 1', () {
      expect(sample.toJson()['v'], equals(1));
    });

    test('JSON round-trip preserves all fields', () {
      final restored = MedicalRecord.fromJson(sample.toJson());
      expect(restored, equals(sample));
    });

    test('fromJson rejects unknown schema version', () {
      final json = sample.toJson()..['v'] = 99;
      expect(() => MedicalRecord.fromJson(json), throwsUnsupportedError);
    });

    test('toUtf8Bytes returns valid UTF-8 JSON', () {
      final bytes = sample.toUtf8Bytes();
      expect(bytes, isNotEmpty);
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, Object?>;
      expect(decoded['v'], equals(1));
    });

    test('no binary data: image_urls are strings', () {
      final json = sample.toJson();
      final consultations = json['consultations'] as List<Object?>;
      final firstConsultation = consultations.first as Map<String, Object?>;
      final imageUrls = firstConsultation['image_urls'] as List<Object?>;
      for (final url in imageUrls) {
        expect(url, isA<String>());
      }
    });

    test('copyWith updates consultations and updatedAt', () {
      const newConsultation = Consultation(
        id: 'c0eebc99-9c0b-4ef8-bb6d-6bb9bd380a33',
        date: '2024-02-01',
        practitionerRef: 'b0eebc99-9c0b-4ef8-bb6d-6bb9bd380a22',
        summary: 'Suivi annuel.',
      );
      final updated = sample.copyWith(
        consultations: [...sample.consultations, newConsultation],
        updatedAt: '2024-02-01T09:00:00Z',
      );
      expect(updated.consultations.length, equals(2));
      expect(updated.updatedAt, equals('2024-02-01T09:00:00Z'));
      expect(updated.createdAt, equals(sample.createdAt));
    });

    test('empty optional fields round-trip correctly', () {
      const minimal = MedicalRecord(
        patientId: 'aaaaaaaa-0000-4000-8000-000000000001',
        createdAt: '2024-01-01T00:00:00Z',
        updatedAt: '2024-01-01T00:00:00Z',
      );
      final restored = MedicalRecord.fromJson(minimal.toJson());
      expect(restored, equals(minimal));
    });

    group('MediaDescriptor', () {
      const desc = MediaDescriptor(
        uuid: 'aaaabbbb-0000-4000-8000-111111111111',
        contentKey: 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=',
        contentHash:
            'abc123abc123abc123abc123abc123abc123abc123abc123abc123abc123abcd',
        mime: 'image/jpeg',
        sizeBytes: 102400,
        addedAt: '2099-06-01T00:00:00Z',
      );

      test('toJson / fromJson round-trip', () {
        expect(MediaDescriptor.fromJson(desc.toJson()), equals(desc));
      });

      test('toJson includes all required fields', () {
        final json = desc.toJson();
        expect(json['uuid'], desc.uuid);
        expect(json['content_key'], desc.contentKey);
        expect(json['content_hash'], desc.contentHash);
        expect(json['mime'], desc.mime);
        expect(json['size_bytes'], desc.sizeBytes);
        expect(json['added_at'], desc.addedAt);
        expect(json['alg'], 'A256GCM');
      });

      test('alg defaults to A256GCM when absent from JSON (backward compat)',
          () {
        final json = desc.toJson()..remove('alg');
        final restored = MediaDescriptor.fromJson(json);
        expect(restored.alg, 'A256GCM');
      });

      test('Consultation with media round-trips through MedicalRecord JSON',
          () {
        const consultation = Consultation(
          id: 'a1eebc99-9c0b-4ef8-bb6d-6bb9bd380a00',
          date: '2099-06-01',
          practitionerRef: 'doc-ref-1',
          summary: 'Test with media.',
          media: [desc],
        );
        const record = MedicalRecord(
          patientId: 'eeeeeeee-0000-4000-8000-000000000099',
          createdAt: '2099-06-01T00:00:00Z',
          updatedAt: '2099-06-01T00:00:00Z',
          consultations: [consultation],
        );
        final restored = MedicalRecord.fromJson(record.toJson());
        expect(restored.consultations.first.media.first, equals(desc));
      });

      test('Consultation without media: media field absent from JSON', () {
        const consultation = Consultation(
          id: 'a2eebc99-0000-4000-8000-000000000001',
          date: '2099-06-01',
          practitionerRef: 'doc-ref-1',
          summary: 'No media.',
        );
        final json = consultation.toJson();
        expect(json.containsKey('media'), isFalse,
            reason:
                'empty media list must be omitted (G3: no binary in record)');
      });

      test('content_key field contains no image bytes (G3)', () {
        final json = desc.toJson();
        // content_key is base64 of key bytes — must be a string, not binary
        expect(json['content_key'], isA<String>());
        // size_bytes is an int, not the actual bytes
        expect(json['size_bytes'], isA<int>());
      });
    });

    group('Demographics', () {
      test('null fields are omitted from JSON', () {
        const demo = Demographics(givenName: 'Koné');
        final json = demo.toJson();
        expect(json.containsKey('birth_year'), isFalse);
        expect(json.containsKey('sex'), isFalse);
      });

      test('round-trip with all fields', () {
        const demo = Demographics(
          givenName: 'Awa',
          birthYear: 1996,
          sex: 'F',
          bloodType: 'O+',
        );
        expect(Demographics.fromJson(demo.toJson()), equals(demo));
      });
    });
  });
}
