import { useState } from "preact/hooks";
import { AppBar } from "../components/AppBar";
import { Icon } from "../components/Icon";
import type {
  MedicalRecord,
  OrdonnanceJson,
  TreatmentJson,
} from "../stubs/data";

// ── Local types (UI-only, not serialised) ────────────────────────────────────

interface MedLine {
  id: string;
  medication: string;
  dose: string;
  frequency: string;
  durationDays: string;
}

interface LocalOrdonnance {
  id: string;
  label: string;
  lines: MedLine[];
}

export interface NewAllergy {
  substance: string;
  severity: "mild" | "moderate" | "severe";
}

export interface NewCondition {
  name: string;
  icd10?: string;
  since?: string;
}

export interface NewConsultation {
  summary: string;
  doctorName: string;
  newAllergies: NewAllergy[];
  newConditions: NewCondition[];
  /** Ordonnances written at this consultation. */
  ordonnances: OrdonnanceJson[];
  /** Non-null only when the doctor starts a new global treatment at this visit. */
  newTreatment?: TreatmentJson;
  /** Id of an existing active treatment to mark as completed at this consultation. */
  closedTreatmentId?: string;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function newLine(): MedLine {
  return { id: crypto.randomUUID(), medication: "", dose: "", frequency: "", durationDays: "" };
}

function newOrdonnance(): LocalOrdonnance {
  return { id: crypto.randomUUID(), label: "", lines: [newLine()] };
}

function buildOrdonnances(
  local: LocalOrdonnance[],
  treatmentId: string | undefined,
): OrdonnanceJson[] {
  return local
    .map((o) => {
      const filled = o.lines.filter((l) => l.medication.trim());
      if (!filled.length) return null;
      return {
        id: o.id,
        ...(treatmentId ? { treatment_id: treatmentId } : {}),
        ...(o.label.trim() ? { label: o.label.trim() } : {}),
        lines: filled.map((l) => ({
          medication: l.medication.trim(),
          ...(l.dose.trim() ? { dose: l.dose.trim() } : {}),
          ...(l.frequency.trim() ? { frequency: l.frequency.trim() } : {}),
          ...(l.durationDays.trim()
            ? { duration_days: parseInt(l.durationDays, 10) }
            : {}),
        })),
      } satisfies OrdonnanceJson;
    })
    .filter((o): o is OrdonnanceJson => o !== null);
}

// ── Component ─────────────────────────────────────────────────────────────────

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

  // "none" = no treatment / "new" = start a new treatment / existing id = link to it
  const [treatmentMode, setTreatmentMode] = useState<"none" | "new" | string>(
    "none",
  );
  const [newDiagnosis, setNewDiagnosis] = useState("");
  const [closeTreatment, setCloseTreatment] = useState(false);

  const [ordonnances, setOrdonnances] = useState<LocalOrdonnance[]>([
    newOrdonnance(),
  ]);

  const [allergySubstance, setAllergySubstance] = useState("");
  const [allergySeverity, setAllergySeverity] =
    useState<NewAllergy["severity"]>("mild");
  const [newAllergies, setNewAllergies] = useState<NewAllergy[]>([]);
  const [conditionType, setConditionType] = useState<"allergy" | "condition">(
    "allergy",
  );
  const [conditionName, setConditionName] = useState("");
  const [conditionIcd10, setConditionIcd10] = useState("");
  const [conditionSince, setConditionSince] = useState("");
  const [newConditions, setNewConditions] = useState<NewCondition[]>([]);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const activeExistingTreatments = record.treatments.filter(
    (t) => t.status === "active",
  );

  // ── Allergy helpers ──────────────────────────────────────────────────────

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

  function addCondition() {
    const n = conditionName.trim();
    if (!n) return;
    setNewConditions((prev) => [
      ...prev,
      {
        name: n,
        icd10: conditionIcd10.trim() || undefined,
        since: conditionSince.trim() || undefined,
      },
    ]);
    setConditionName("");
    setConditionIcd10("");
    setConditionSince("");
  }

  function removeCondition(i: number) {
    setNewConditions((prev) => prev.filter((_, idx) => idx !== i));
  }

  // ── Ordonnance helpers ───────────────────────────────────────────────────

  function updateLine(
    ordId: string,
    lineId: string,
    field: keyof MedLine,
    value: string,
  ) {
    setOrdonnances((prev) =>
      prev.map((o) =>
        o.id === ordId
          ? {
              ...o,
              lines: o.lines.map((l) =>
                l.id === lineId ? { ...l, [field]: value } : l,
              ),
            }
          : o,
      ),
    );
  }

  function removeLine(ordId: string, lineId: string) {
    setOrdonnances((prev) =>
      prev.map((o) =>
        o.id === ordId
          ? {
              ...o,
              lines: o.lines.length > 1 ? o.lines.filter((l) => l.id !== lineId) : o.lines,
            }
          : o,
      ),
    );
  }

  function addLine(ordId: string) {
    setOrdonnances((prev) =>
      prev.map((o) =>
        o.id === ordId ? { ...o, lines: [...o.lines, newLine()] } : o,
      ),
    );
  }

  function updateLabel(ordId: string, label: string) {
    setOrdonnances((prev) =>
      prev.map((o) => (o.id === ordId ? { ...o, label } : o)),
    );
  }

  function removeOrdonnance(ordId: string) {
    setOrdonnances((prev) =>
      prev.length > 1 ? prev.filter((o) => o.id !== ordId) : prev,
    );
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  async function handleSave() {
    if (!note.trim()) {
      setError("La note de consultation est requise.");
      return;
    }

    const pendingSubstance = allergySubstance.trim();
    const finalAllergies: typeof newAllergies = pendingSubstance
      ? [...newAllergies, { substance: pendingSubstance, severity: allergySeverity }]
      : newAllergies;

    const pendingConditionName = conditionName.trim();
    const finalConditions: typeof newConditions = pendingConditionName
      ? [
          ...newConditions,
          {
            name: pendingConditionName,
            icd10: conditionIcd10.trim() || undefined,
            since: conditionSince.trim() || undefined,
          },
        ]
      : newConditions;

    const headerParts: string[] = [];
    if (hospital.trim()) headerParts.push(`Hôpital / Clinique : ${hospital.trim()}`);
    if (contact.trim()) headerParts.push(`Contact : ${contact.trim()}`);
    const summary = headerParts.length
      ? `${headerParts.join("\n")}\n\n${note.trim()}`
      : note.trim();

    let newTreatment: TreatmentJson | undefined;
    let resolvedTreatmentId: string | undefined;

    if (treatmentMode === "new" && newDiagnosis.trim()) {
      const newId = crypto.randomUUID();
      newTreatment = {
        id: newId,
        diagnosis: newDiagnosis.trim(),
        started_at: new Date().toISOString().slice(0, 10),
        ...(doctorName.trim() ? { doctor_ref: doctorName.trim() } : {}),
        status: "active",
      };
      resolvedTreatmentId = newId;
    } else if (treatmentMode !== "none" && treatmentMode !== "new") {
      resolvedTreatmentId = treatmentMode; // existing treatment id
    }

    const builtOrdonnances = buildOrdonnances(ordonnances, resolvedTreatmentId);

    const closedTreatmentId =
      treatmentMode !== "none" && treatmentMode !== "new" && closeTreatment
        ? treatmentMode
        : undefined;

    setIsSaving(true);
    setError(null);
    try {
      await onSaved({
        summary,
        doctorName: doctorName.trim(),
        newAllergies: finalAllergies,
        newConditions: finalConditions,
        ordonnances: builtOrdonnances,
        newTreatment,
        closedTreatmentId,
      });
    } catch (e) {
      setIsSaving(false);
      setError(
        e instanceof Error
          ? e.message
          : "Échec de l'enregistrement — réessayez.",
      );
    }
  }

  // ── Render ────────────────────────────────────────────────────────────────

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
        {/* Médecin + Établissement + Contact */}
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
              <span style={{ fontWeight: 400, color: "var(--color-neutral-400)" }}>
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
              <Icon name="edit_note" size={16} color="var(--color-primary-700)" />
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

        {/* Traitement */}
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
              <Icon name="medical_services" size={16} color="var(--color-primary-700)" />
            </span>
            <h2 className="text-title-sm" style={{ margin: 0 }}>
              Traitement
            </h2>
          </div>

          {/* Treatment mode tabs */}
          <div
            style={{
              display: "flex",
              gap: "var(--space-xs)",
              marginBottom: "var(--space-sm)",
              flexWrap: "wrap",
            }}
          >
            <button
              type="button"
              onClick={() => { setTreatmentMode("none"); setCloseTreatment(false); }}
              className={treatmentMode === "none" ? "btn btn-filled" : "btn btn-outline"}
              style={{ fontSize: 13 }}
            >
              Aucun traitement
            </button>
            <button
              type="button"
              onClick={() => { setTreatmentMode("new"); setCloseTreatment(false); }}
              className={treatmentMode === "new" ? "btn btn-filled" : "btn btn-outline"}
              style={{ fontSize: 13 }}
            >
              <Icon name="add" size={16} color={treatmentMode === "new" ? "var(--color-white)" : "var(--color-primary-700)"} />
              Nouveau traitement
            </button>
            {activeExistingTreatments.map((t) => (
              <button
                key={t.id}
                type="button"
                onClick={() => { setTreatmentMode(t.id); setCloseTreatment(false); }}
                className={treatmentMode === t.id ? "btn btn-filled" : "btn btn-outline"}
                style={{ fontSize: 13 }}
              >
                {t.diagnosis}
                {t.doctor_ref && (
                  <span style={{ opacity: 0.7, fontWeight: 400, marginLeft: 6 }}>
                    · {t.doctor_ref}
                  </span>
                )}
              </button>
            ))}
          </div>

          {/* Diagnosis input for new treatment */}
          {treatmentMode === "new" && (
            <div style={{ marginBottom: "var(--space-sm)" }}>
              <label
                className="text-title-sm field-label"
                style={{ display: "block", marginBottom: "var(--space-xs)" }}
              >
                Diagnostic *
              </label>
              <input
                className="field-input"
                placeholder="Ex. Paludisme simple, Asthme bronchique…"
                value={newDiagnosis}
                onInput={(e) =>
                  setNewDiagnosis((e.target as HTMLInputElement).value)
                }
              />
            </div>
          )}

          {/* Clore un traitement existant */}
          {treatmentMode !== "none" && treatmentMode !== "new" && (
            <label
              style={{
                display: "flex",
                alignItems: "center",
                gap: "var(--space-sm)",
                cursor: "pointer",
                padding: "var(--space-sm) var(--space-md)",
                background: closeTreatment
                  ? "rgba(220,38,38,0.06)"
                  : "var(--color-neutral-50)",
                border: `1px solid ${closeTreatment ? "rgba(220,38,38,0.3)" : "var(--color-neutral-200)"}`,
                borderRadius: "var(--radius-sm)",
              }}
            >
              <input
                type="checkbox"
                checked={closeTreatment}
                onChange={(e) =>
                  setCloseTreatment((e.target as HTMLInputElement).checked)
                }
              />
              <span className="text-body">
                Clore ce traitement à cette consultation
              </span>
            </label>
          )}
        </div>

        {/* Ordonnances */}
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
              <Icon name="medication" size={16} color="var(--color-primary-700)" />
            </span>
            <h2 className="text-title-sm" style={{ margin: 0 }}>
              Ordonnance{ordonnances.length > 1 ? "s" : ""}
            </h2>
          </div>

          <div
            style={{
              display: "flex",
              flexDirection: "column",
              gap: "var(--space-md)",
            }}
          >
            {ordonnances.map((ord, ordIdx) => (
              <div
                key={ord.id}
                style={{
                  background: "var(--color-white)",
                  border: "1px solid var(--color-neutral-200)",
                  borderRadius: "var(--radius-md)",
                  padding: "var(--space-sm)",
                }}
              >
                {/* Ordonnance header */}
                <div
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: "var(--space-sm)",
                    marginBottom: "var(--space-sm)",
                  }}
                >
                  {ordonnances.length > 1 && (
                    <span
                      style={{
                        fontSize: 12,
                        fontWeight: 600,
                        color: "var(--color-primary-700)",
                        flexShrink: 0,
                      }}
                    >
                      #{ordIdx + 1}
                    </span>
                  )}
                  <input
                    className="field-input"
                    placeholder="Libellé (optionnel) — ex. Médicaments, Examens bio…"
                    value={ord.label}
                    onInput={(e) =>
                      updateLabel(ord.id, (e.target as HTMLInputElement).value)
                    }
                    style={{ flex: 1, fontSize: 13 }}
                  />
                  {ordonnances.length > 1 && (
                    <button
                      type="button"
                      className="btn-icon"
                      onClick={() => removeOrdonnance(ord.id)}
                      aria-label="Supprimer cette ordonnance"
                      style={{ color: "var(--color-neutral-500)", flexShrink: 0 }}
                    >
                      <Icon name="delete" size={18} />
                    </button>
                  )}
                </div>

                {/* Medication lines */}
                <div
                  style={{
                    display: "flex",
                    flexDirection: "column",
                    gap: "var(--space-xs)",
                  }}
                >
                  {ord.lines.map((line) => (
                    <div
                      key={line.id}
                      style={{
                        background: "var(--color-neutral-50)",
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
                              ord.id,
                              line.id,
                              "medication",
                              (e.target as HTMLInputElement).value,
                            )
                          }
                        />
                        {ord.lines.length > 1 && (
                          <button
                            type="button"
                            className="btn-icon"
                            onClick={() => removeLine(ord.id, line.id)}
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
                              ord.id,
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
                              ord.id,
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
                              ord.id,
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
                  style={{ marginTop: "var(--space-sm)", gap: "var(--space-xs)", fontSize: 13 }}
                  onClick={() => addLine(ord.id)}
                >
                  <Icon name="add" size={16} color="var(--color-primary-700)" />
                  Ajouter un médicament
                </button>
              </div>
            ))}
          </div>

          <button
            type="button"
            className="btn btn-outline"
            style={{ marginTop: "var(--space-sm)", gap: "var(--space-xs)" }}
            onClick={() =>
              setOrdonnances((prev) => [...prev, newOrdonnance()])
            }
          >
            <Icon name="add" size={18} color="var(--color-primary-700)" />
            Ajouter une ordonnance
          </button>
        </div>

        {/* Conditions médicales (allergies + antécédents) */}
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
              <Icon name="monitor_heart" size={16} color="var(--color-allergy)" />
            </span>
            <h2 className="text-title-sm" style={{ margin: 0 }}>
              Conditions médicales
            </h2>
          </div>

          {(newAllergies.length > 0 || newConditions.length > 0) && (
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
                  key={`allergy-${i}`}
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
                      className="text-label"
                      style={{ color: "var(--color-neutral-600)", marginRight: "var(--space-xs)" }}
                    >
                      Allergie
                    </span>
                    <span
                      className="text-body"
                      style={{ fontWeight: 600, color: "var(--color-neutral-900)" }}
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
              {newConditions.map((c, i) => (
                <div
                  key={`cond-${i}`}
                  style={{
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "space-between",
                    padding: "var(--space-sm) var(--space-md)",
                    background: "var(--color-primary-50)",
                    borderRadius: "var(--radius-sm)",
                    border: "1px solid var(--color-primary-200)",
                  }}
                >
                  <div>
                    <span
                      className="text-label"
                      style={{ color: "var(--color-neutral-600)", marginRight: "var(--space-xs)" }}
                    >
                      Antécédent
                    </span>
                    <span
                      className="text-body"
                      style={{ fontWeight: 600, color: "var(--color-neutral-900)" }}
                    >
                      {c.name}
                    </span>
                    {c.icd10 && (
                      <span
                        className="text-label"
                        style={{ marginLeft: "var(--space-sm)", color: "var(--color-neutral-600)" }}
                      >
                        {c.icd10}
                      </span>
                    )}
                  </div>
                  <button
                    type="button"
                    className="btn-icon"
                    onClick={() => removeCondition(i)}
                    aria-label={`Retirer ${c.name}`}
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
            {/* Type toggle */}
            <div style={{ display: "flex", gap: "var(--space-xs)" }}>
              <button
                type="button"
                className={conditionType === "allergy" ? "btn btn-filled" : "btn btn-outline"}
                style={{ flex: 1 }}
                onClick={() => setConditionType("allergy")}
              >
                Allergie
              </button>
              <button
                type="button"
                className={conditionType === "condition" ? "btn btn-filled" : "btn btn-outline"}
                style={{ flex: 1 }}
                onClick={() => setConditionType("condition")}
              >
                Antécédent
              </button>
            </div>

            {conditionType === "allergy" ? (
              <>
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
                <div style={{ display: "flex", gap: "var(--space-sm)", alignItems: "center" }}>
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
              </>
            ) : (
              <>
                <input
                  className="field-input"
                  placeholder="Nom de la pathologie"
                  value={conditionName}
                  onInput={(e) =>
                    setConditionName((e.target as HTMLInputElement).value)
                  }
                  onKeyDown={(e) => {
                    if (e.key === "Enter") {
                      e.preventDefault();
                      addCondition();
                    }
                  }}
                />
                <input
                  className="field-input"
                  placeholder="Code ICD-10 (optionnel)"
                  value={conditionIcd10}
                  onInput={(e) =>
                    setConditionIcd10((e.target as HTMLInputElement).value)
                  }
                />
                <input
                  className="field-input"
                  placeholder="Depuis (ex : 2020, optionnel)"
                  value={conditionSince}
                  onInput={(e) =>
                    setConditionSince((e.target as HTMLInputElement).value)
                  }
                />
                <button
                  type="button"
                  className="btn btn-outline"
                  style={{ gap: "var(--space-xs)", alignSelf: "flex-end" }}
                  onClick={addCondition}
                >
                  <Icon name="add" size={18} color="var(--color-primary-700)" />
                  Ajouter
                </button>
              </>
            )}
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
