// Unit tests for the append-only consultation merge (issue #18 — US-2.2).
//
// Verified properties (the "sans écraser l'historique" invariant):
//   - Exactly one new Consultation is appended; all pre-existing consultations
//     remain present and unchanged (order preserved).
//   - Allergies, conditions, immunizations are untouched.
//   - patientId, createdAt, v, demographics are untouched.
//   - updatedAt is bumped to nowIso.
//   - New consultation fields (id, date, practitionerRef, summary, imageUrls)
//     carry the injected arguments unchanged.
//   - With prescription: medications appended (count correct, fields correct);
//     consultation.prescription == renderText().
//   - Without prescription (null / empty / all-blank): medications unchanged;
//     consultation.prescription is null.
//   - Note-only (empty summary, prescription present): valid consultation.
//   - Prescription-only (non-empty prescription, empty summary): valid.
//   - Empty record (no prior consultations): result has exactly 1 consultation.
//   - Determinism: identical inputs produce identical outputs.
//   - Immutability: the original record is not mutated.

import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/doctor/consultation_merge.dart';
import 'package:app_patient/src/record/medical_record.dart';
import 'package:app_patient/src/record/prescription.dart';

// ─── Fixtures ─────────────────────────────────────────────────────────────────

const _kPatientId = 'patient-fake-uuid-001';
const _kCreatedAt = '2025-01-01T00:00:00Z';
const _kPriorUpdatedAt = '2025-06-01T10:00:00Z';
const _kNowIso = '2026-06-29T08:00:00Z';
const _kDate = '2026-06-29';
const _kConsultId = 'new-consult-fake-uuid-001';
const _kPractRef = 'dr-fake-uuid-001';

const _kDemographics = Demographics(givenName: 'Kofi', bloodType: 'O+');

const _kAllergy = Allergy(
  substance: 'Pénicilline',
  severity: 'severe',
  notedAt: '2024-01-01',
);

const _kCondition = ChronicCondition(name: 'Hypertension', icd10: 'I10');

const _kMedication = Medication(
  name: 'Amlodipine',
  dose: '5 mg',
  frequency: '1×/jour',
  prescribedAt: '2025-01-01',
  prescribedBy: 'dr-prior',
);

const _kImmunization = Immunization(name: 'Hépatite B', date: '2023-06-01');

const _kExistingConsultation = Consultation(
  id: 'existing-consult-uuid-001',
  date: '2025-06-01',
  practitionerRef: 'dr-prior',
  summary: 'Consultation initiale',
);

const _kPrescription = Prescription(lines: [
  PrescriptionLine(
    drug: 'Amoxicilline',
    dose: '500 mg',
    frequency: '3×/jour',
    durationDays: 7,
  ),
  PrescriptionLine(drug: 'Ibuprofène', dose: '400 mg', frequency: '2×/jour'),
]);

MedicalRecord _fullRecord({
  List<Allergy>? allergies,
  List<ChronicCondition>? conditions,
  List<Medication>? medications,
  List<Consultation>? consultations,
  List<Immunization>? immunizations,
}) =>
    MedicalRecord(
      patientId: _kPatientId,
      demographics: _kDemographics,
      allergies: allergies ?? const [_kAllergy],
      chronicConditions: conditions ?? const [_kCondition],
      medications: medications ?? const [_kMedication],
      consultations: consultations ?? const [_kExistingConsultation],
      immunizations: immunizations ?? const [_kImmunization],
      createdAt: _kCreatedAt,
      updatedAt: _kPriorUpdatedAt,
    );

MedicalRecord _doMerge({
  MedicalRecord? existing,
  String summary = 'Bilan annuel',
  Prescription? prescription,
}) =>
    mergeConsultation(
      existing ?? _fullRecord(),
      practitionerRef: _kPractRef,
      date: _kDate,
      summary: summary,
      prescription: prescription,
      newConsultationId: _kConsultId,
      nowIso: _kNowIso,
    );

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group("mergeConsultation — append invariant (sans écraser l'historique)", () {
    test('appends exactly one new Consultation', () {
      final result = _doMerge();
      expect(result.consultations, hasLength(2));
    });

    test('new consultation is the last element', () {
      final result = _doMerge();
      expect(result.consultations.last.id, _kConsultId);
    });

    test('all pre-existing consultations are still present and unchanged', () {
      final result = _doMerge();
      expect(result.consultations.first, equals(_kExistingConsultation));
    });

    test('pre-existing consultation appears before the new one', () {
      final existing = _fullRecord(consultations: [
        const Consultation(
          id: 'c1',
          date: '2025-01-01',
          practitionerRef: 'dr-a',
          summary: 'S1',
        ),
        const Consultation(
          id: 'c2',
          date: '2025-06-01',
          practitionerRef: 'dr-b',
          summary: 'S2',
        ),
      ]);
      final result = _doMerge(existing: existing);
      expect(result.consultations[0].id, 'c1');
      expect(result.consultations[1].id, 'c2');
      expect(result.consultations[2].id, _kConsultId);
    });

    test('allergies are unchanged', () {
      final result = _doMerge();
      expect(result.allergies, equals(const [_kAllergy]));
    });

    test('chronic conditions are unchanged', () {
      final result = _doMerge();
      expect(result.chronicConditions, equals(const [_kCondition]));
    });

    test('immunizations are unchanged', () {
      final result = _doMerge();
      expect(result.immunizations, equals(const [_kImmunization]));
    });

    test('patientId is unchanged', () {
      expect(_doMerge().patientId, _kPatientId);
    });

    test('createdAt is unchanged', () {
      expect(_doMerge().createdAt, _kCreatedAt);
    });

    test('schema version v is unchanged', () {
      final existing = _fullRecord();
      expect(_doMerge(existing: existing).v, existing.v);
    });

    test('demographics are unchanged', () {
      expect(_doMerge().demographics, _kDemographics);
    });

    test('updatedAt is bumped to nowIso', () {
      expect(_doMerge().updatedAt, _kNowIso);
    });
  });

  group('mergeConsultation — new consultation fields', () {
    test('id matches injected newConsultationId', () {
      expect(_doMerge().consultations.last.id, _kConsultId);
    });

    test('date matches injected date', () {
      expect(_doMerge().consultations.last.date, _kDate);
    });

    test('practitionerRef matches injected value', () {
      expect(_doMerge().consultations.last.practitionerRef, _kPractRef);
    });

    test('summary matches injected value', () {
      expect(_doMerge().consultations.last.summary, 'Bilan annuel');
    });

    test('imageUrls is always empty (no images in #18)', () {
      expect(_doMerge().consultations.last.imageUrls, isEmpty);
    });

    test('prescription field is null when no prescription given', () {
      final result = _doMerge();
      expect(result.consultations.last.prescription, isNull);
    });

    test('prescription field equals renderText() when prescription given', () {
      final result = _doMerge(prescription: _kPrescription);
      expect(
        result.consultations.last.prescription,
        _kPrescription.renderText(),
      );
    });
  });

  group('mergeConsultation — medications handling', () {
    test('with prescription: medications list grows by the number of lines',
        () {
      final result = _doMerge(prescription: _kPrescription);
      // 1 existing + 2 prescription lines = 3 total
      expect(result.medications, hasLength(3));
    });

    test('with prescription: pre-existing medication is still first', () {
      final result = _doMerge(prescription: _kPrescription);
      expect(result.medications.first, equals(_kMedication));
    });

    test('with prescription: new medication fields are correct', () {
      final result = _doMerge(prescription: _kPrescription);
      final newMed = result.medications[1];
      expect(newMed.name, 'Amoxicilline');
      expect(newMed.dose, '500 mg');
      expect(newMed.frequency, '3×/jour');
      expect(newMed.prescribedAt, _kDate);
      expect(newMed.prescribedBy, _kPractRef);
    });

    test('without prescription (null): medications list unchanged', () {
      final result = _doMerge();
      expect(result.medications, equals(const [_kMedication]));
    });

    test('empty Prescription (isEmpty == true): treated as absent', () {
      final result = _doMerge(prescription: const Prescription());
      expect(result.medications, equals(const [_kMedication]));
    });

    test('all-blank Prescription lines: treated as absent', () {
      final result = _doMerge(
        prescription: const Prescription(lines: [
          PrescriptionLine(drug: '', dose: '', frequency: ''),
        ]),
      );
      expect(result.medications, equals(const [_kMedication]));
      expect(result.consultations.last.prescription, isNull);
    });

    test('mixed blank/non-blank lines: only non-blank appended to medications',
        () {
      final result = _doMerge(
        prescription: const Prescription(lines: [
          PrescriptionLine(
            drug: 'Amoxicilline',
            dose: '500 mg',
            frequency: '3×/jour',
          ),
          PrescriptionLine(
              drug: '', dose: '', frequency: ''), // blank — skipped
        ]),
      );
      // 1 pre-existing medication + 1 non-blank prescription line = 2
      expect(result.medications, hasLength(2));
      expect(result.medications.last.name, 'Amoxicilline');
    });
  });

  group('mergeConsultation — input edge cases', () {
    test('note-only (empty summary) + prescription: valid consultation', () {
      final result = _doMerge(
        existing: _fullRecord(consultations: const []),
        summary: '',
        prescription: _kPrescription,
      );
      expect(result.consultations, hasLength(1));
      expect(result.consultations.first.summary, '');
      expect(result.consultations.first.prescription, isNotNull);
    });

    test('prescription-only (non-empty prescription, empty summary): valid',
        () {
      final result = _doMerge(
        summary: '',
        prescription: _kPrescription,
      );
      expect(result.consultations.last.summary, '');
      expect(result.consultations.last.prescription, isNotNull);
    });

    test('starts from record with no prior consultations', () {
      final result = _doMerge(existing: _fullRecord(consultations: const []));
      expect(result.consultations, hasLength(1));
      expect(result.consultations.first.id, _kConsultId);
    });

    test('starts from completely empty record (no history in any list)', () {
      const empty = MedicalRecord(
        patientId: _kPatientId,
        createdAt: _kCreatedAt,
        updatedAt: _kPriorUpdatedAt,
      );
      final result = mergeConsultation(
        empty,
        practitionerRef: _kPractRef,
        date: _kDate,
        summary: 'First visit',
        newConsultationId: _kConsultId,
        nowIso: _kNowIso,
      );
      expect(result.consultations, hasLength(1));
      expect(result.allergies, isEmpty);
      expect(result.medications, isEmpty);
    });

    test('is deterministic: identical inputs produce identical outputs', () {
      final existing = _fullRecord();
      final r1 = mergeConsultation(
        existing,
        practitionerRef: _kPractRef,
        date: _kDate,
        summary: 'Test déterminisme',
        prescription: _kPrescription,
        newConsultationId: _kConsultId,
        nowIso: _kNowIso,
      );
      final r2 = mergeConsultation(
        existing,
        practitionerRef: _kPractRef,
        date: _kDate,
        summary: 'Test déterminisme',
        prescription: _kPrescription,
        newConsultationId: _kConsultId,
        nowIso: _kNowIso,
      );
      expect(r1, equals(r2));
    });

    test('does not mutate the original record', () {
      final existing = _fullRecord();
      final originalCount = existing.consultations.length;
      _doMerge(existing: existing);
      expect(existing.consultations, hasLength(originalCount));
    });

    test('unique consultation ids produce distinct consultations', () {
      final existing = _fullRecord();
      final r1 = mergeConsultation(
        existing,
        practitionerRef: _kPractRef,
        date: _kDate,
        summary: 'Visit 1',
        newConsultationId: 'id-visit-1',
        nowIso: _kNowIso,
      );
      final r2 = mergeConsultation(
        r1,
        practitionerRef: _kPractRef,
        date: _kDate,
        summary: 'Visit 2',
        newConsultationId: 'id-visit-2',
        nowIso: _kNowIso,
      );
      expect(r2.consultations, hasLength(3));
      expect(r2.consultations.map((c) => c.id), contains('id-visit-1'));
      expect(r2.consultations.map((c) => c.id), contains('id-visit-2'));
    });
  });
}
