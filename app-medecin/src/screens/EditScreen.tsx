import { useState } from "preact/hooks";
import { AppBar } from "../components/AppBar";
import { Icon } from "../components/Icon";
import type { MedicalRecord } from "../stubs/data";

interface PrescriptionLine {
  id: string;
  medication: string;
  dose: string;
  frequency: string;
  durationDays: string;
}

export interface NewAllergy {
  substance: string;
  severity: "mild" | "moderate" | "severe";
}

export interface NewConsultation {
  summary: string;
  prescription?: string;
  doctorName: string;
  newAllergies: NewAllergy[];
}

function newLine(): PrescriptionLine {
  return {
    id: crypto.randomUUID(),
    medication: "",
    dose: "",
    frequency: "",
    durationDays: "",
  };
}

function buildPrescriptionText(lines: PrescriptionLine[]): string | undefined {
  const filled = lines.filter((l) => l.medication.trim());
  if (!filled.length) return undefined;
  return filled
    .map((l) => {
      let s = l.medication.trim();
      if (l.dose) s += ` ${l.dose.trim()}`;
      if (l.frequency) s += ` — ${l.frequency.trim()}`;
      if (l.durationDays) s += ` (${l.durationDays}j)`;
      return s;
    })
    .join("\n");
}

export interface EditScreenProps {
  record: MedicalRecord;
  onSaved: (consultation: NewConsultation) => Promise<void>;
  onCancel: () => void;
}

export function EditScreen({ record, onSaved, onCancel }: EditScreenProps) {
  const [note, setNote] = useState("");
  const [doctorName, setDoctorName] = useState("");
  const [hospital, setHospital] = useState("");
  const [contact, setContact] = useState("");
  const [lines, setLines] = useState<PrescriptionLine[]>([newLine()]);
  const [allergySubstance, setAllergySubstance] = useState("");
  const [allergySeverity, setAllergySeverity] =
    useState<NewAllergy["severity"]>("mild");
  const [newAllergies, setNewAllergies] = useState<NewAllergy[]>([]);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  function addAllergy() {
    const s = allergySubstance.trim();
    if (!s) return;
    setNewAllergies((prev) => [
      ...prev,
      { substance: s, severity: allergySeverity },
    ]);
    setAllergySubstance("");
    setAllergySeverity("mild");
  }

  function removeAllergy(i: number) {
    setNewAllergies((prev) => prev.filter((_, idx) => idx !== i));
  }

  function updateLine(
    id: string,
    field: keyof PrescriptionLine,
    value: string,
  ) {
    setLines((prev) =>
      prev.map((l) => (l.id === id ? { ...l, [field]: value } : l)),
    );
  }

  function removeLine(id: string) {
    setLines((prev) =>
      prev.length > 1 ? prev.filter((l) => l.id !== id) : prev,
    );
  }

  async function handleSave() {
    if (!note.trim()) {
      setError("La note de consultation est requise.");
      return;
    }
    // Auto-confirm any substance still in the input field — the doctor may have
    // typed an allergy without pressing "Ajouter" before hitting "Enregistrer".
    const pendingSubstance = allergySubstance.trim();
    const finalAllergies: typeof newAllergies = pendingSubstance
      ? [
          ...newAllergies,
          { substance: pendingSubstance, severity: allergySeverity },
        ]
      : newAllergies;
    // Prepend hospital / contact header to the note when provided.
    const headerParts: string[] = [];
    if (hospital.trim())
      headerParts.push(`Hôpital / Clinique : ${hospital.trim()}`);
    if (contact.trim()) headerParts.push(`Contact : ${contact.trim()}`);
    const summary = headerParts.length
      ? `${headerParts.join("\n")}\n\n${note.trim()}`
      : note.trim();
    setIsSaving(true);
    setError(null);
    try {
      await onSaved({
        summary,
        prescription: buildPrescriptionText(lines),
        doctorName: doctorName.trim(),
        newAllergies: finalAllergies,
      });
      // app.tsx navigates away on success — no need to reset state
    } catch (e) {
      setIsSaving(false);
      setError(
        e instanceof Error
          ? e.message
          : "Échec de l'enregistrement — réessayez.",
      );
    }
  }

  return (
    <div style={{ minHeight: "100%", paddingBottom: "var(--space-xl)" }}>
      <AppBar title="Note de consultation">
        <button
          type="button"
          className="btn-icon"
          onClick={onCancel}
          aria-label="Annuler et revenir au dossier"
        >
          <Icon name="close" size={22} />
        </button>
      </AppBar>

      {/* Patient context banner */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: "var(--space-sm)",
          padding: "var(--space-sm) var(--space-md)",
          background: "var(--color-primary-50)",
          borderBottom: "1px solid var(--color-neutral-200)",
        }}
      >
        <div
          style={{
            width: 28,
            height: 28,
            borderRadius: "50%",
            background: "var(--color-primary-100)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: 12,
            fontWeight: 700,
            color: "var(--color-primary-700)",
            flexShrink: 0,
          }}
        >
          {record.givenName[0]?.toUpperCase()}
        </div>
        <p className="text-label" style={{ color: "var(--color-neutral-700)" }}>
          Consultation pour{" "}
          <strong style={{ color: "var(--color-neutral-900)" }}>
            {record.givenName}
          </strong>
          {record.birthYear
            ? ` — ${new Date().getFullYear() - record.birthYear} ans · ${record.sex}`
            : ""}
        </p>
      </div>

      <main
        style={{
          padding: "var(--space-md)",
          display: "flex",
          flexDirection: "column",
          gap: "var(--space-lg)",
        }}
      >
        {/* Médecin + Établissement sur la même ligne */}
        <div style={{ display: "flex", gap: "var(--space-md)" }}>
          <div style={{ flex: 1 }}>
            <label
              className="text-title-sm field-label"
              htmlFor="doctor-name"
              style={{ display: "block", marginBottom: "var(--space-sm)" }}
            >
              Médecin
            </label>
            <input
              id="doctor-name"
              className="field-input"
              placeholder="Dr. Nom Prénom"
              value={doctorName}
              onInput={(e) =>
                setDoctorName((e.target as HTMLInputElement).value)
              }
            />
          </div>

          <div style={{ flex: 1 }}>
            <label
              className="text-title-sm field-label"
              style={{ display: "block", marginBottom: "var(--space-sm)" }}
            >
              Établissement{" "}
              <span
                style={{ fontWeight: 400, color: "var(--color-neutral-400)" }}
              >
                (optionnel)
              </span>
            </label>
            <input
              className="field-input"
              placeholder="Hôpital / Clinique"
              value={hospital}
              onInput={(e) => setHospital((e.target as HTMLInputElement).value)}
            />
          </div>

          <div style={{ flex: 1 }}>
            <label
              className="text-title-sm field-label"
              style={{ display: "block", marginBottom: "var(--space-sm)" }}
            >
              Contact
            </label>
            <input
              className="field-input"
              placeholder="Tél. ou e-mail"
              value={contact}
              onInput={(e) => setContact((e.target as HTMLInputElement).value)}
            />
          </div>
        </div>

        {/* Note */}
        <div>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: "var(--space-sm)",
              marginBottom: "var(--space-sm)",
            }}
          >
            <span
              className="icon-badge"
              style={{
                background: "var(--color-primary-100)",
                width: 32,
                height: 32,
              }}
            >
              <Icon
                name="edit_note"
                size={16}
                color="var(--color-primary-700)"
              />
            </span>
            <label
              className="text-title-sm field-label"
              htmlFor="note"
              style={{ margin: 0 }}
            >
              Note de consultation
            </label>
          </div>
          <textarea
            id="note"
            className="field-textarea"
            placeholder="Observations, diagnostic, évolution…"
            value={note}
            onInput={(e) => setNote((e.target as HTMLTextAreaElement).value)}
          />
        </div>

        {/* Ordonnance */}
        <div>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: "var(--space-sm)",
              marginBottom: "var(--space-sm)",
            }}
          >
            <span
              className="icon-badge"
              style={{
                background: "var(--color-primary-100)",
                width: 32,
                height: 32,
              }}
            >
              <Icon
                name="medication"
                size={16}
                color="var(--color-primary-700)"
              />
            </span>
            <h2 className="text-title-sm" style={{ margin: 0 }}>
              Ordonnance
            </h2>
          </div>

          <div
            style={{
              display: "flex",
              flexDirection: "column",
              gap: "var(--space-xs)",
            }}
          >
            {lines.map((line) => (
              <div
                key={line.id}
                style={{
                  background: "var(--color-white)",
                  border: "1px solid var(--color-neutral-200)",
                  borderRadius: "var(--radius-sm)",
                  padding: "var(--space-sm)",
                }}
              >
                <div
                  style={{
                    display: "flex",
                    gap: "var(--space-sm)",
                    alignItems: "center",
                    marginBottom: "var(--space-sm)",
                  }}
                >
                  <input
                    className="field-input"
                    placeholder="Médicament"
                    value={line.medication}
                    onInput={(e) =>
                      updateLine(
                        line.id,
                        "medication",
                        (e.target as HTMLInputElement).value,
                      )
                    }
                  />
                  {lines.length > 1 && (
                    <button
                      type="button"
                      className="btn-icon"
                      onClick={() => removeLine(line.id)}
                      aria-label="Retirer ce médicament"
                      style={{
                        flexShrink: 0,
                        color: "var(--color-neutral-500)",
                      }}
                    >
                      <Icon name="close" size={18} />
                    </button>
                  )}
                </div>
                <div
                  style={{
                    display: "grid",
                    gridTemplateColumns: "1fr 1fr 72px",
                    gap: "var(--space-sm)",
                  }}
                >
                  <input
                    className="field-input"
                    placeholder="Dose"
                    value={line.dose}
                    onInput={(e) =>
                      updateLine(
                        line.id,
                        "dose",
                        (e.target as HTMLInputElement).value,
                      )
                    }
                  />
                  <input
                    className="field-input"
                    placeholder="Fréquence"
                    value={line.frequency}
                    onInput={(e) =>
                      updateLine(
                        line.id,
                        "frequency",
                        (e.target as HTMLInputElement).value,
                      )
                    }
                  />
                  <input
                    className="field-input"
                    type="number"
                    placeholder="Jours"
                    value={line.durationDays}
                    onInput={(e) =>
                      updateLine(
                        line.id,
                        "durationDays",
                        (e.target as HTMLInputElement).value,
                      )
                    }
                  />
                </div>
              </div>
            ))}
          </div>

          <button
            type="button"
            className="btn btn-outline"
            style={{ marginTop: "var(--space-sm)", gap: "var(--space-xs)" }}
            onClick={() => setLines((prev) => [...prev, newLine()])}
          >
            <Icon name="add" size={18} color="var(--color-primary-700)" />
            Ajouter un médicament
          </button>
        </div>

        {/* Allergies */}
        <div>
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: "var(--space-sm)",
              marginBottom: "var(--space-sm)",
            }}
          >
            <span
              className="icon-badge"
              style={{
                background: "var(--color-allergy-bg)",
                width: 32,
                height: 32,
              }}
            >
              <Icon name="warning" size={16} color="var(--color-allergy)" />
            </span>
            <h2 className="text-title-sm" style={{ margin: 0 }}>
              Allergies à noter
            </h2>
          </div>

          {newAllergies.length > 0 && (
            <div
              style={{
                display: "flex",
                flexDirection: "column",
                gap: "var(--space-xs)",
                marginBottom: "var(--space-sm)",
              }}
            >
              {newAllergies.map((a, i) => (
                <div
                  key={i}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    padding: "var(--space-sm) var(--space-md)",
                    background: "var(--color-allergy-bg)",
                    borderRadius: "var(--radius-sm)",
                    border: "1px solid var(--color-allergy)",
                  }}
                >
                  <div>
                    <span
                      className="text-body"
                      style={{
                        fontWeight: 600,
                        color: "var(--color-neutral-900)",
                      }}
                    >
                      {a.substance}
                    </span>
                    <span
                      className="text-label"
                      style={{
                        marginLeft: "var(--space-sm)",
                        color:
                          a.severity === "severe"
                            ? "var(--color-error)"
                            : a.severity === "moderate"
                              ? "var(--color-allergy)"
                              : "var(--color-neutral-700)",
                      }}
                    >
                      {a.severity === "severe"
                        ? "Sévère"
                        : a.severity === "moderate"
                          ? "Modérée"
                          : "Légère"}
                    </span>
                  </div>
                  <button
                    type="button"
                    className="btn-icon"
                    onClick={() => removeAllergy(i)}
                    aria-label={`Retirer ${a.substance}`}
                    style={{ color: "var(--color-neutral-500)" }}
                  >
                    <Icon name="close" size={18} />
                  </button>
                </div>
              ))}
            </div>
          )}

          <div
            style={{
              background: "var(--color-white)",
              border: "1px solid var(--color-neutral-200)",
              borderRadius: "var(--radius-sm)",
              padding: "var(--space-sm)",
              display: "flex",
              flexDirection: "column",
              gap: "var(--space-sm)",
            }}
          >
            <input
              className="field-input"
              placeholder="Substance ou allergène"
              value={allergySubstance}
              onInput={(e) =>
                setAllergySubstance((e.target as HTMLInputElement).value)
              }
              onKeyDown={(e) => {
                if (e.key === "Enter") {
                  e.preventDefault();
                  addAllergy();
                }
              }}
            />
            <div
              style={{
                display: "flex",
                gap: "var(--space-sm)",
                alignItems: "center",
              }}
            >
              <select
                className="field-input"
                value={allergySeverity}
                onChange={(e) =>
                  setAllergySeverity(
                    (e.target as HTMLSelectElement)
                      .value as NewAllergy["severity"],
                  )
                }
                style={{ flex: 1 }}
              >
                <option value="mild">Légère</option>
                <option value="moderate">Modérée</option>
                <option value="severe">Sévère</option>
              </select>
              <button
                type="button"
                className="btn btn-outline"
                style={{ gap: "var(--space-xs)", flexShrink: 0 }}
                onClick={addAllergy}
              >
                <Icon name="add" size={18} color="var(--color-primary-700)" />
                Ajouter
              </button>
            </div>
          </div>
        </div>

        {error && (
          <div
            role="alert"
            style={{
              display: "flex",
              alignItems: "center",
              gap: "var(--space-sm)",
              padding: "var(--space-sm) var(--space-md)",
              background: "var(--color-error-bg)",
              borderRadius: "var(--radius-sm)",
              border: "1px solid rgba(220,38,38,0.2)",
            }}
          >
            <Icon name="error" size={20} color="var(--color-error)" />
            <p
              className="text-body"
              style={{ color: "var(--color-error)", margin: 0 }}
            >
              {error}
            </p>
          </div>
        )}

        <button
          type="button"
          className="btn btn-filled btn-block"
          disabled={isSaving}
          onClick={handleSave}
        >
          {isSaving ? "Enregistrement…" : "Enregistrer la consultation"}
        </button>
      </main>
    </div>
  );
}
