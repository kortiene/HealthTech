// Append-only consultation merge (issue #18 — US-2.2).
//
// The heart of "fusion sans écraser l'historique": a PURE function (no I/O, no
// crypto, no clock, no id generation) that takes the in-RAM decrypted
// [MedicalRecord] plus the doctor's note/prescription and returns a NEW record
// with one [Consultation] (and, when prescribed, [Medication] entries)
// APPENDED. It never mutates or removes any existing entry; createdAt /
// patientId / v / demographics are untouched. Determinism is preserved by
// injecting [newConsultationId] and [nowIso] from the edge (cf. access_token).

import '../record/medical_record.dart';
import '../record/prescription.dart';

/// Append a doctor's consultation note and/or prescription to [existing],
/// returning a new [MedicalRecord]. Existing history is never overwritten.
///
/// - A single new [Consultation] is appended to [MedicalRecord.consultations].
/// - When [prescription] is non-null and non-empty, its lines are appended to
///   [MedicalRecord.medications] and rendered into the consultation's
///   `prescription` text field.
/// - [MedicalRecord.updatedAt] is bumped to [nowIso]; every other section
///   (allergies, conditions, immunizations, demographics, createdAt, patientId,
///   schema version) is carried over unchanged.
///
/// [date] is the consultation's ISO `yyyy-MM-dd`; [summary] is the clinical
/// note (may be empty for a prescription-only visit). [newConsultationId] and
/// [nowIso] are injected by the caller (OS CSPRNG UUID + `DateTime.now()` in
/// production) so this function stays deterministic and unit-testable.
MedicalRecord mergeConsultation(
  MedicalRecord existing, {
  required String practitionerRef,
  required String date,
  required String summary,
  Prescription? prescription,
  required String newConsultationId,
  required String nowIso,
}) {
  final hasPrescription = prescription != null && !prescription.isEmpty;

  final newConsultation = Consultation(
    id: newConsultationId,
    date: date,
    practitionerRef: practitionerRef,
    summary: summary,
    prescription: hasPrescription ? prescription.renderText() : null,
    imageUrls: const [],
  );

  return existing.copyWith(
    // Append only — pre-existing consultations stay in place and order.
    consultations: [...existing.consultations, newConsultation],
    // Append only — never drop or rewrite prior medications.
    medications: hasPrescription
        ? [
            ...existing.medications,
            ...prescription.toMedications(date, practitionerRef),
          ]
        : existing.medications,
    updatedAt: nowIso,
  );
}
