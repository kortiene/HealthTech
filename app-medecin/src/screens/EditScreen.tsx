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

export interface NewConsultation {
  summary: string;
  doctorName: string;
  newAllergies: NewAllergy[];
  /** Ordonnances written at this consultation. */
  ordonnances: OrdonnanceJson[];
  /** Non-null only when the doctor starts a new global treatment at this visit. */
  newTreatment?: TreatmentJson;
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

  const [ordonnances, setOrdonnances] = useState<LocalOrdonnance[]>([
    newOrdonnance(),
  ]);

  const [allergySubstance, setAllergySubstance] = useState("");
  const [allergySeverity, setAllergySeverity] =
    useState<NewAllergy["severity"]>("mild");
  const [newAllergies, setNewAllergies] = useState<NewAllergy[]>([]);
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
        status: "active",
      };
      resolvedTreatmentId = newId;
    } else if (treatmentMode !== "none" && treatmentMode !== "new") {
      resolvedTreatmentId = treatmentMode; // existing treatment id
    }

    const builtOrdonnances = buildOrdonnances(ordonnances, resolvedTreatmentId);

    setIsSaving(true);
    setError(null);
    try {
      await onSaved({
        summary,
        doctorName: doctorName.trim(),
        newAllergies: finalAllergies,
        ordonnances: builtOrdonnances,
        newTreatment,
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
              onClick={() => setTreatmentMode("none")}
              className={treatmentMode === "none" ? "btn btn-filled" : "btn btn-outline"}
              style={{ fontSize: 13 }}
            >
              Aucun traitement
            </button>
            <button
              type="button"
              onClick={() => setTreatmentMode("new")}
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
                onClick={() => setTreatmentMode(t.id)}
                className={treatmentMode === t.id ? "btn btn-filled" : "btn btn-outline"}
                style={{ fontSize: 13 }}
              >
                {t.diagnosis}
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
