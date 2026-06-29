// Prescription template model (issue #18 — US-2.2, "modèle d'ordonnance").
//
// A small, pure, dependency-free model the doctor fills in during a
// consultation. It is NOT a new persisted schema: the canonical persisted form
// stays the existing [Consultation.prescription] text field plus appended
// [Medication] entries (see medical_record.dart). [renderText] produces the
// legible ordonnance string; [toMedications] keeps the structured medication
// list in sync. No `MedicalRecord` schema change (recordSchemaVersion stays 1).
//
// English identifiers, French UI strings (handled in the edit screen).

import 'medical_record.dart';

/// A single drug line of a structured prescription (ordonnance).
///
/// All fields are free UTF-8 text except [durationDays]. Nothing here is logged
/// or persisted in plaintext outside the in-RAM record (PRD §4, zero-knowledge).
class PrescriptionLine {
  const PrescriptionLine({
    required this.drug,
    required this.dose,
    required this.frequency,
    this.durationDays,
    this.instructions,
  });

  /// Drug name, e.g. `"Amoxicilline"`.
  final String drug;

  /// Dose per intake, e.g. `"500 mg"`.
  final String dose;

  /// Intake frequency, e.g. `"3×/jour"`.
  final String frequency;

  /// Treatment duration in days, e.g. `7`. Null when not specified.
  final int? durationDays;

  /// Optional free-text guidance, e.g. `"après les repas"`.
  final String? instructions;

  /// True when the line carries no usable content (used to drop blank rows).
  bool get isBlank =>
      drug.trim().isEmpty &&
      dose.trim().isEmpty &&
      frequency.trim().isEmpty &&
      (instructions == null || instructions!.trim().isEmpty);

  @override
  bool operator ==(Object other) =>
      other is PrescriptionLine &&
      other.drug == drug &&
      other.dose == dose &&
      other.frequency == frequency &&
      other.durationDays == durationDays &&
      other.instructions == instructions;

  @override
  int get hashCode =>
      Object.hash(drug, dose, frequency, durationDays, instructions);
}

/// A structured ordonnance: an ordered list of [PrescriptionLine]s.
///
/// Deterministic: [renderText] and [toMedications] never read the clock or
/// generate ids — the caller injects `prescribedAt`/`prescribedBy`.
class Prescription {
  const Prescription({this.lines = const []});

  final List<PrescriptionLine> lines;

  /// True when there is nothing to prescribe (no lines or all blank).
  bool get isEmpty => lines.every((l) => l.isBlank);

  /// Render a deterministic, human-legible multi-line ordonnance string.
  ///
  /// One line per drug, e.g. `"Amoxicilline — 500 mg — 3×/jour — 7 j"`.
  /// Blank lines are skipped. Returns the empty string when [isEmpty].
  String renderText() {
    final buffer = <String>[];
    for (final line in lines) {
      if (line.isBlank) continue;
      final parts = <String>[
        line.drug.trim(),
        line.dose.trim(),
        line.frequency.trim(),
      ].where((p) => p.isNotEmpty).toList();
      if (line.durationDays != null) parts.add('${line.durationDays} j');
      var rendered = parts.join(' — ');
      final notes = line.instructions?.trim();
      if (notes != null && notes.isNotEmpty) rendered = '$rendered ($notes)';
      buffer.add(rendered);
    }
    return buffer.join('\n');
  }

  /// Map each non-blank line to a [Medication] so the patient's structured
  /// medication list stays in sync with the rendered ordonnance.
  ///
  /// [prescribedAt] is an ISO-8601 date string; [prescribedBy] is the opaque
  /// practitioner reference. Neither is generated here (testability).
  List<Medication> toMedications(String prescribedAt, String prescribedBy) {
    return [
      for (final line in lines)
        if (!line.isBlank)
          Medication(
            name: line.drug.trim(),
            dose: line.dose.trim(),
            frequency: line.frequency.trim(),
            prescribedAt: prescribedAt,
            prescribedBy: prescribedBy,
          ),
    ];
  }
}
