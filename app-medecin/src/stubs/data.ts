export interface Allergy {
  substance: string;
  severity: string;
}

export interface ChronicCondition {
  name: string;
  icd10: string;
}

export interface Medication {
  name: string;
  dose: string;
  frequency: string;
}

export interface Consultation {
  date: string; // ISO
  doctorName?: string;
  summary: string;
  prescription?: string;
}

export interface MedicalRecord {
  givenName: string;
  birthYear: number;
  sex: string;
  bloodType: string;
  heightCm?: number;
  weightKg?: number;
  cmuNumber?: string;
  phone?: string;
  allergies: Allergy[];
  chronicConditions: ChronicCondition[];
  medications: Medication[];
  consultations: Consultation[];
}

/**
 * Données de démonstration — à remplacer par le dossier réel déchiffré
 * après un scan (voir `session.ts`, non modifié par cette refonte UI).
 */
export const previewRecord: MedicalRecord = {
  givenName: "Awa",
  birthYear: 1998,
  sex: "Féminin",
  bloodType: "O+",
  heightCm: 165,
  weightKg: 58,
  cmuNumber: "CMU-2025-A78341",
  phone: "+225 07 58 23 14",
  allergies: [
    { substance: "Pénicilline", severity: "sévère" },
    { substance: "Piqûre d'abeille", severity: "sévère" },
    { substance: "Arachides", severity: "modérée" },
  ],
  chronicConditions: [{ name: "Asthme bronchique", icd10: "J45" }],
  medications: [
    { name: "Salbutamol", dose: "100 µg", frequency: "2×/jour si besoin" },
    { name: "Prednisolone", dose: "5 mg", frequency: "1×/jour le matin" },
  ],
  consultations: [
    {
      date: "2026-06-12",
      doctorName: "Dr. Koné",
      summary: "Contrôle de routine. Tension artérielle 120/80. Bonne tolérance au traitement.",
      prescription: "Paracétamol 500 mg — 3×/jour, 5 jours",
    },
    {
      date: "2026-03-02",
      doctorName: "Dr. Koné",
      summary: "Crise d'asthme légère. SpO2 96 %. Traitement de fond maintenu.",
    },
    {
      date: "2025-11-18",
      doctorName: "Dr. Diallo",
      summary: "Premier bilan de santé. Diagnostic asthme bronchique posé.",
      prescription: "Salbutamol 100 µg — 2×/jour · Prednisolone 5 mg — 1×/jour",
    },
  ],
};

const moisFr = [
  "janvier", "février", "mars", "avril", "mai", "juin",
  "juillet", "août", "septembre", "octobre", "novembre", "décembre",
];

export function formatDateFr(iso: string): string {
  const d = new Date(iso);
  return `${d.getDate()} ${moisFr[d.getMonth()]} ${d.getFullYear()}`;
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function parseFlutterRecord(raw: any): MedicalRecord {
  const d = raw.demographics ?? {};

  function sexLabel(s: string | null | undefined): string {
    if (!s) return "Inconnu";
    if (s === "M") return "Masculin";
    if (s === "F") return "Féminin";
    return "Autre";
  }

  function severityLabel(s: string): string {
    if (s === "severe") return "sévère";
    if (s === "moderate") return "modérée";
    if (s === "mild") return "légère";
    return s;
  }

  return {
    givenName: d.given_name ?? d.givenName ?? "Patient",
    birthYear: d.birth_year ?? d.birthYear ?? new Date().getFullYear() - 30,
    sex: sexLabel(d.sex),
    bloodType: d.blood_type ?? d.bloodType ?? "—",
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    allergies: (raw.allergies ?? []).map((a: any) => ({
      substance: a.substance,
      severity: severityLabel(a.severity),
    })),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    chronicConditions: (raw.chronic_conditions ?? raw.chronicConditions ?? []).map((c: any) => ({
      name: c.name,
      icd10: c.icd10 ?? "",
    })),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    medications: (raw.medications ?? []).map((m: any) => ({
      name: m.name,
      dose: m.dose ?? "",
      frequency: m.frequency ?? "",
    })),
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    consultations: (raw.consultations ?? []).map((c: any) => ({
      date: c.date,
      doctorName: c.practitioner_ref ?? c.practitionerRef ?? c.doctor_name ?? c.doctorName,
      summary: c.summary,
      prescription: c.prescription,
    })),
  };
}
