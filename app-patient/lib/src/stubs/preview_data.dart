// DEV-ONLY — static preview record for UI development.
// Uses the production MedicalRecord model so screens compile against real types.
// Never referenced from main.dart (production entry point).

import '../record/medical_record.dart';

abstract final class PreviewData {
  static const record = MedicalRecord(
    patientId: 'dev-patient-001',
    demographics: Demographics(
      givenName: 'Awa',
      birthYear: 1998,
      sex: 'F',
      bloodType: 'O+',
    ),
    allergies: [
      Allergy(substance: 'Pénicilline', severity: 'severe', notedAt: '2024-03-10'),
      Allergy(substance: "Piqûre d'abeille", severity: 'severe', notedAt: '2024-01-15'),
      Allergy(substance: 'Arachides', severity: 'moderate', notedAt: '2024-06-01'),
    ],
    chronicConditions: [
      ChronicCondition(name: 'Asthme bronchique', icd10: 'J45'),
    ],
    medications: [
      Medication(
        name: 'Salbutamol',
        dose: '100 µg',
        frequency: '2×/jour si besoin',
        prescribedAt: '2025-11-18',
      ),
      Medication(
        name: 'Prednisolone',
        dose: '5 mg',
        frequency: '1×/jour le matin',
        prescribedAt: '2025-11-18',
      ),
    ],
    consultations: [
      Consultation(
        id: 'c-001',
        date: '2026-06-12',
        practitionerRef: 'Dr. Koné',
        summary:
            'Contrôle de routine. Tension artérielle 120/80. '
            'Bonne tolérance au traitement.',
        prescription: 'Paracétamol 500 mg — 3×/jour, 5 jours',
      ),
      Consultation(
        id: 'c-002',
        date: '2026-03-02',
        practitionerRef: 'Dr. Koné',
        summary: "Crise d'asthme légère. SpO2 96 %. Traitement de fond maintenu.",
      ),
      Consultation(
        id: 'c-003',
        date: '2025-11-18',
        practitionerRef: 'Dr. Diallo',
        summary: 'Premier bilan de santé. Diagnostic asthme bronchique posé.',
        prescription:
            'Salbutamol 100 µg — 2×/jour · Prednisolone 5 mg — 1×/jour',
      ),
    ],
    createdAt: '2025-11-18T10:00:00Z',
    updatedAt: '2026-06-12T14:30:00Z',
  );
}
