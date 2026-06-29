// Unit tests for the prescription template model (issue #18 — US-2.2).
//
// Verified properties:
//   - PrescriptionLine.isBlank: all-empty / whitespace-only → true; any field
//     filled (including non-empty instructions) → false.
//   - PrescriptionLine equality via == / hashCode.
//   - Prescription.isEmpty: no lines or all-blank lines → true.
//   - Prescription.renderText: deterministic; one line per drug; duration appended;
//     instructions in parentheses; blank lines skipped; whitespace trimmed;
//     empty prescription → empty string.
//   - Prescription.toMedications: one Medication per non-blank line with correct
//     fields; blank lines excluded; empty prescription → empty list; fields trimmed.

import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/record/medical_record.dart';
import 'package:app_patient/src/record/prescription.dart';

const _date = '2026-06-29';
const _ref = 'dr-fake-uuid-001';

void main() {
  group('PrescriptionLine.isBlank', () {
    test('all empty fields → blank', () {
      const line = PrescriptionLine(drug: '', dose: '', frequency: '');
      expect(line.isBlank, isTrue);
    });

    test('whitespace-only fields → blank', () {
      const line = PrescriptionLine(drug: '  ', dose: '\t', frequency: ' ');
      expect(line.isBlank, isTrue);
    });

    test('null instructions counts as blank for that field', () {
      const line = PrescriptionLine(drug: '', dose: '', frequency: '');
      expect(line.isBlank, isTrue);
    });

    test('empty instructions counts as blank for that field', () {
      const line = PrescriptionLine(
        drug: '',
        dose: '',
        frequency: '',
        instructions: '',
      );
      expect(line.isBlank, isTrue);
    });

    test('non-empty instructions alone makes line non-blank', () {
      // instructions is a content field: a non-empty note with no drug info is
      // still non-blank (caller should decide whether to accept it).
      const line = PrescriptionLine(
        drug: '',
        dose: '',
        frequency: '',
        instructions: 'après les repas',
      );
      expect(line.isBlank, isFalse);
    });

    test('drug filled → not blank', () {
      const line = PrescriptionLine(
        drug: 'Amoxicilline',
        dose: '',
        frequency: '',
      );
      expect(line.isBlank, isFalse);
    });

    test('dose filled → not blank', () {
      const line = PrescriptionLine(drug: '', dose: '500 mg', frequency: '');
      expect(line.isBlank, isFalse);
    });

    test('frequency filled → not blank', () {
      const line = PrescriptionLine(drug: '', dose: '', frequency: '3×/jour');
      expect(line.isBlank, isFalse);
    });
  });

  group('PrescriptionLine equality', () {
    test('identical lines are equal', () {
      const a = PrescriptionLine(
        drug: 'Amoxicilline',
        dose: '500 mg',
        frequency: '3×/jour',
        durationDays: 7,
        instructions: 'après repas',
      );
      const b = PrescriptionLine(
        drug: 'Amoxicilline',
        dose: '500 mg',
        frequency: '3×/jour',
        durationDays: 7,
        instructions: 'après repas',
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('different drug → not equal', () {
      const a = PrescriptionLine(
        drug: 'Amoxicilline',
        dose: '500 mg',
        frequency: '3×/jour',
      );
      const b = PrescriptionLine(
        drug: 'Paracétamol',
        dose: '500 mg',
        frequency: '3×/jour',
      );
      expect(a, isNot(equals(b)));
    });

    test('different durationDays → not equal', () {
      const a = PrescriptionLine(
        drug: 'Drug',
        dose: '10 mg',
        frequency: '1×/jour',
        durationDays: 7,
      );
      const b = PrescriptionLine(
        drug: 'Drug',
        dose: '10 mg',
        frequency: '1×/jour',
        durationDays: 14,
      );
      expect(a, isNot(equals(b)));
    });
  });

  group('Prescription.isEmpty', () {
    test('no lines → empty', () {
      const p = Prescription();
      expect(p.isEmpty, isTrue);
    });

    test('single blank line → empty', () {
      const p = Prescription(lines: [
        PrescriptionLine(drug: '', dose: '', frequency: ''),
      ]);
      expect(p.isEmpty, isTrue);
    });

    test('multiple blank lines → empty', () {
      const p = Prescription(lines: [
        PrescriptionLine(drug: '', dose: '', frequency: ''),
        PrescriptionLine(drug: '  ', dose: '  ', frequency: '  '),
      ]);
      expect(p.isEmpty, isTrue);
    });

    test('one non-blank line → not empty', () {
      const p = Prescription(lines: [
        PrescriptionLine(
            drug: 'Amoxicilline', dose: '500 mg', frequency: '3×/jour'),
      ]);
      expect(p.isEmpty, isFalse);
    });

    test('mix of blank and non-blank lines → not empty', () {
      const p = Prescription(lines: [
        PrescriptionLine(drug: '', dose: '', frequency: ''),
        PrescriptionLine(drug: 'Drug A', dose: '10 mg', frequency: '1×/jour'),
      ]);
      expect(p.isEmpty, isFalse);
    });
  });

  group('Prescription.renderText', () {
    test('empty prescription → empty string', () {
      const p = Prescription();
      expect(p.renderText(), isEmpty);
    });

    test('all-blank lines → empty string', () {
      const p = Prescription(lines: [
        PrescriptionLine(drug: '', dose: '', frequency: ''),
      ]);
      expect(p.renderText(), isEmpty);
    });

    test('single line with all fields including duration', () {
      const p = Prescription(lines: [
        PrescriptionLine(
          drug: 'Amoxicilline',
          dose: '500 mg',
          frequency: '3×/jour',
          durationDays: 7,
        ),
      ]);
      expect(p.renderText(), 'Amoxicilline — 500 mg — 3×/jour — 7 j');
    });

    test('duration absent → no duration segment', () {
      const p = Prescription(lines: [
        PrescriptionLine(
          drug: 'Paracétamol',
          dose: '500 mg',
          frequency: 'si besoin',
        ),
      ]);
      expect(p.renderText(), 'Paracétamol — 500 mg — si besoin');
    });

    test('instructions appended in parentheses', () {
      const p = Prescription(lines: [
        PrescriptionLine(
          drug: 'Ibuprofène',
          dose: '400 mg',
          frequency: '2×/jour',
          instructions: 'après les repas',
        ),
      ]);
      expect(
        p.renderText(),
        'Ibuprofène — 400 mg — 2×/jour (après les repas)',
      );
    });

    test('instructions + duration both present', () {
      const p = Prescription(lines: [
        PrescriptionLine(
          drug: 'Drug X',
          dose: '5 mg',
          frequency: '1×/jour',
          durationDays: 3,
          instructions: 'le soir',
        ),
      ]);
      expect(
        p.renderText(),
        'Drug X — 5 mg — 1×/jour — 3 j (le soir)',
      );
    });

    test('multi-line: one rendered line per non-blank drug line', () {
      const p = Prescription(lines: [
        PrescriptionLine(drug: 'Drug A', dose: '10 mg', frequency: '1×/jour'),
        PrescriptionLine(drug: 'Drug B', dose: '20 mg', frequency: '2×/jour'),
      ]);
      final lines = p.renderText().split('\n');
      expect(lines, hasLength(2));
    });

    test('blank lines are skipped in output', () {
      const p = Prescription(lines: [
        PrescriptionLine(drug: 'Drug A', dose: '10 mg', frequency: '1×/jour'),
        PrescriptionLine(drug: '', dose: '', frequency: ''), // blank
        PrescriptionLine(drug: 'Drug B', dose: '20 mg', frequency: '2×/jour'),
      ]);
      final lines = p.renderText().split('\n');
      expect(lines, hasLength(2));
    });

    test('whitespace is trimmed from drug, dose, frequency', () {
      const p = Prescription(lines: [
        PrescriptionLine(
          drug: '  Amoxicilline  ',
          dose: '  500 mg  ',
          frequency: '  3×/jour  ',
        ),
      ]);
      expect(p.renderText(), 'Amoxicilline — 500 mg — 3×/jour');
    });

    test('renderText is deterministic: same output on repeated calls', () {
      const p = Prescription(lines: [
        PrescriptionLine(
          drug: 'Amoxicilline',
          dose: '500 mg',
          frequency: '3×/jour',
          durationDays: 7,
        ),
      ]);
      expect(p.renderText(), p.renderText());
    });

    test('instructions with surrounding whitespace are trimmed in output', () {
      const p = Prescription(lines: [
        PrescriptionLine(
          drug: 'Drug X',
          dose: '5 mg',
          frequency: '1×/jour',
          instructions: '  après les repas  ',
        ),
      ]);
      expect(p.renderText(), 'Drug X — 5 mg — 1×/jour (après les repas)');
    });
  });

  group('Prescription.toMedications', () {
    test('maps each non-blank line to a Medication', () {
      const p = Prescription(lines: [
        PrescriptionLine(drug: 'Drug A', dose: '10 mg', frequency: '1×/jour'),
        PrescriptionLine(drug: 'Drug B', dose: '20 mg', frequency: '2×/jour'),
      ]);
      final meds = p.toMedications(_date, _ref);
      expect(meds, hasLength(2));
    });

    test('medication fields match the prescription line', () {
      const p = Prescription(lines: [
        PrescriptionLine(
          drug: 'Amoxicilline',
          dose: '500 mg',
          frequency: '3×/jour',
        ),
      ]);
      final med = p.toMedications(_date, _ref).first;
      expect(med.name, 'Amoxicilline');
      expect(med.dose, '500 mg');
      expect(med.frequency, '3×/jour');
      expect(med.prescribedAt, _date);
      expect(med.prescribedBy, _ref);
    });

    test('blank lines are excluded from the medication list', () {
      const p = Prescription(lines: [
        PrescriptionLine(drug: 'Drug A', dose: '10 mg', frequency: '1×/jour'),
        PrescriptionLine(drug: '', dose: '', frequency: ''), // blank
      ]);
      expect(p.toMedications(_date, _ref), hasLength(1));
    });

    test('empty prescription → empty list', () {
      const p = Prescription();
      expect(p.toMedications(_date, _ref), isEmpty);
    });

    test('drug, dose, frequency are trimmed in resulting Medication', () {
      const p = Prescription(lines: [
        PrescriptionLine(
          drug: '  Drug A  ',
          dose: '  10 mg  ',
          frequency: '  1×/jour  ',
        ),
      ]);
      final med = p.toMedications(_date, _ref).first;
      expect(med.name, 'Drug A');
      expect(med.dose, '10 mg');
      expect(med.frequency, '1×/jour');
    });

    test('each result element is a Medication', () {
      const p = Prescription(lines: [
        PrescriptionLine(drug: 'Drug A', dose: '10 mg', frequency: '1×/jour'),
      ]);
      expect(p.toMedications(_date, _ref).first, isA<Medication>());
    });

    test('prescribedAt and prescribedBy are set from injected arguments', () {
      const p = Prescription(lines: [
        PrescriptionLine(drug: 'Drug A', dose: '5 mg', frequency: '1×/jour'),
      ]);
      const otherDate = '2025-03-15';
      const otherRef = 'another-practitioner';
      final med = p.toMedications(otherDate, otherRef).first;
      expect(med.prescribedAt, otherDate);
      expect(med.prescribedBy, otherRef);
    });
  });
}
