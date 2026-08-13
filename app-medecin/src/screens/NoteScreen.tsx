import { useEffect, useRef, useState } from "preact/hooks";
import { AppBar } from "../components/AppBar";
import { Icon } from "../components/Icon";
import { SnackBar } from "../components/SnackBar";
import type {
  MedicalRecord,
  OrdonnanceJson,
  TreatmentJson,
} from "../stubs/data";
import type { NewConsultation, NewAllergy, NewCondition } from "./EditScreen";
import type { NewVoiceConsultation } from "./VoiceNoteScreen";

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

type NoteMode = "written" | "voice";
type Phase = "idle" | "recording" | "preview";

// ── Helpers ───────────────────────────────────────────────────────────────────

function newLine(): MedLine {
  return { id: crypto.randomUUID(), medication: "", dose: "", frequency: "", durationDays: "" };
}

function newOrdonnance(): LocalOrdonnance {
  return { id: crypto.randomUUID(), label: "", lines: [newLine()] };
}

function buildOrdonnances(local: LocalOrdonnance[], treatmentId?: string): OrdonnanceJson[] {
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
          ...(l.durationDays.trim() ? { duration_days: parseInt(l.durationDays, 10) } : {}),
        })),
      } satisfies OrdonnanceJson;
    })
    .filter((o): o is OrdonnanceJson => o !== null);
}

function formatDuration(ms: number): string {
  const totalSec = Math.floor(ms / 1000);
  const min = Math.floor(totalSec / 60);
  const sec = totalSec % 60;
  return `${min}:${String(sec).padStart(2, "0")}`;
}

// ── Props ─────────────────────────────────────────────────────────────────────

export interface NoteScreenProps {
  record: MedicalRecord;
  backendUrl: string;
  writeToken?: string;
  onWrittenSaved: (consultation: NewConsultation) => Promise<void>;
  onVoiceSaved: (consultation: NewVoiceConsultation) => Promise<void>;
  onCancel: () => void;
}

// ── Component ─────────────────────────────────────────────────────────────────

export function NoteScreen({
  record,
  backendUrl,
  writeToken,
  onWrittenSaved,
  onVoiceSaved,
  onCancel,
}: NoteScreenProps) {
  // ── Common state ─────────────────────────────────────────────────────────
  const [mode, setMode] = useState<NoteMode>("written");
  const [doctorName, setDoctorName] = useState("");
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  // ── Written mode state ───────────────────────────────────────────────────
  const [note, setNote] = useState("");
  const [hospital, setHospital] = useState("");
  const [contact, setContact] = useState("");
  const [treatmentMode, setTreatmentMode] = useState<"none" | "new" | string>("none");
  const [newDiagnosis, setNewDiagnosis] = useState("");
  const [closeTreatment, setCloseTreatment] = useState(false);
  const [ordonnances, setOrdonnances] = useState<LocalOrdonnance[]>([newOrdonnance()]);
  const [allergySubstance, setAllergySubstance] = useState("");
  const [allergySeverity, setAllergySeverity] = useState<NewAllergy["severity"]>("mild");
  const [newAllergies, setNewAllergies] = useState<NewAllergy[]>([]);
  const [conditionType, setConditionType] = useState<"allergy" | "condition">("allergy");
  const [conditionName, setConditionName] = useState("");
  const [conditionIcd10, setConditionIcd10] = useState("");
  const [conditionSince, setConditionSince] = useState("");
  const [conditionSeverity, setConditionSeverity] = useState(1);
  const [newConditions, setNewConditions] = useState<NewCondition[]>([]);

  // ── Voice mode state ─────────────────────────────────────────────────────
  const [phase, setPhase] = useState<Phase>("idle");
  const [durationMs, setDurationMs] = useState(0);
  const [audioUrl, setAudioUrl] = useState<string | null>(null);
  const [audioBlob, setAudioBlob] = useState<Blob | null>(null);

  const mediaRecorderRef = useRef<MediaRecorder | null>(null);
  const chunksRef = useRef<Blob[]>([]);
  const streamRef = useRef<MediaStream | null>(null);
  const timerRef = useRef<number | undefined>(undefined);
  const startTimeRef = useRef<number>(0);

  useEffect(() => {
    return () => {
      window.clearInterval(timerRef.current);
      streamRef.current?.getTracks().forEach((t) => t.stop());
      if (audioUrl) URL.revokeObjectURL(audioUrl);
    };
  }, []);

  const activeExistingTreatments = record.treatments.filter((t) => t.status === "active");

  // ── Written mode helpers ─────────────────────────────────────────────────

  function addAllergy() {
    const s = allergySubstance.trim();
    if (!s) return;
    setNewAllergies((prev) => [...prev, { substance: s, severity: allergySeverity }]);
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
        severity: conditionSeverity,
      },
    ]);
    setConditionName("");
    setConditionIcd10("");
    setConditionSince("");
    setConditionSeverity(1);
  }

  function removeCondition(i: number) {
    setNewConditions((prev) => prev.filter((_, idx) => idx !== i));
  }

  function updateLine(ordId: string, lineId: string, field: keyof MedLine, value: string) {
    setOrdonnances((prev) =>
      prev.map((o) =>
        o.id === ordId
          ? { ...o, lines: o.lines.map((l) => (l.id === lineId ? { ...l, [field]: value } : l)) }
          : o,
      ),
    );
  }

  function removeLine(ordId: string, lineId: string) {
    setOrdonnances((prev) =>
      prev.map((o) =>
        o.id === ordId
          ? { ...o, lines: o.lines.length > 1 ? o.lines.filter((l) => l.id !== lineId) : o.lines }
          : o,
      ),
    );
  }

  function addLine(ordId: string) {
    setOrdonnances((prev) =>
      prev.map((o) => (o.id === ordId ? { ...o, lines: [...o.lines, newLine()] } : o)),
    );
  }

  function updateLabel(ordId: string, label: string) {
    setOrdonnances((prev) => prev.map((o) => (o.id === ordId ? { ...o, label } : o)));
  }

  function removeOrdonnance(ordId: string) {
    setOrdonnances((prev) => (prev.length > 1 ? prev.filter((o) => o.id !== ordId) : prev));
  }

  // ── Voice mode helpers ────────────────────────────────────────────────────

  async function startRecording() {
    setError(null);
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      streamRef.current = stream;
      const mimeType = MediaRecorder.isTypeSupported("audio/webm;codecs=opus")
        ? "audio/webm;codecs=opus"
        : "audio/webm";
      const recorder = new MediaRecorder(stream, { mimeType });
      chunksRef.current = [];
      recorder.ondataavailable = (e) => {
        if (e.data.size > 0) chunksRef.current.push(e.data);
      };
      recorder.onstop = () => {
        const blob = new Blob(chunksRef.current, { type: mimeType });
        setAudioBlob(blob);
        if (audioUrl) URL.revokeObjectURL(audioUrl);
        setAudioUrl(URL.createObjectURL(blob));
        setPhase("preview");
        stream.getTracks().forEach((t) => t.stop());
      };
      recorder.start(1000);
      mediaRecorderRef.current = recorder;
      startTimeRef.current = Date.now();
      setDurationMs(0);
      setPhase("recording");
      timerRef.current = window.setInterval(() => {
        setDurationMs(Date.now() - startTimeRef.current);
      }, 500);
    } catch {
      setError(
        "Impossible d'accéder au microphone — autorisez dans les paramètres du navigateur.",
      );
    }
  }

  function stopRecording() {
    window.clearInterval(timerRef.current);
    mediaRecorderRef.current?.stop();
  }

  function restart() {
    setPhase("idle");
    setAudioBlob(null);
    if (audioUrl) {
      URL.revokeObjectURL(audioUrl);
      setAudioUrl(null);
    }
    setDurationMs(0);
  }

  // ── Save handlers ─────────────────────────────────────────────────────────

  async function handleWrittenSave() {
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
            severity: conditionSeverity,
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
      resolvedTreatmentId = treatmentMode;
    }

    const builtOrdonnances = buildOrdonnances(ordonnances, resolvedTreatmentId);
    const closedTreatmentId =
      treatmentMode !== "none" && treatmentMode !== "new" && closeTreatment
        ? treatmentMode
        : undefined;

    setIsSaving(true);
    setError(null);
    try {
      await onWrittenSaved({
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
      setError(e instanceof Error ? e.message : "Échec de l'enregistrement — réessayez.");
    }
  }

  async function handleVoiceSave() {
    if (!audioBlob || !doctorName.trim() || isSaving) return;
    setIsSaving(true);
    setError(null);
    try {
      const plainBytes = new Uint8Array(await audioBlob.arrayBuffer());
      const hashBuffer = await crypto.subtle.digest("SHA-256", plainBytes);
      const contentHash = btoa(String.fromCharCode(...new Uint8Array(hashBuffer)));
      // XOR 0x5A stub encrypt — WASM AES-256-GCM when #17 lands
      const encrypted = new Uint8Array(plainBytes.length);
      for (let i = 0; i < plainBytes.length; i++) encrypted[i] = plainBytes[i] ^ 0x5a;
      const mediaId = crypto.randomUUID();
      const res = await fetch(`${backendUrl}/media/${mediaId}`, {
        method: "PUT",
        headers: {
          "Content-Type": "application/octet-stream",
          ...(writeToken ? { Authorization: `Bearer ${writeToken}` } : {}),
        },
        body: encrypted.buffer as ArrayBuffer,
      });
      if (!res.ok) {
        throw new Error(
          res.status >= 500
            ? "Serveur indisponible — réessayez."
            : "Échec de l'upload audio — réessayez.",
        );
      }
      await onVoiceSaved({
        doctorName: doctorName.trim(),
        summary: "Note vocale — enregistrement joint",
        media: [
          {
            mediaId,
            url: `${backendUrl}/media/${mediaId}`,
            mime: audioBlob.type || "audio/webm",
            durationMs,
            sizeBytes: plainBytes.length,
            // 32 zero bytes — real per-media key when WASM crypto-core lands (#17)
            contentKey: btoa(String.fromCharCode(...new Uint8Array(32))),
            contentHash,
          },
        ],
      });
    } catch (err) {
      setError(err instanceof Error ? err.message : "Erreur inconnue — réessayez.");
      setIsSaving(false);
    }
  }

  // ── Render ────────────────────────────────────────────────────────────────

  return (
    <div style={{ minHeight: "100%", paddingBottom: 80 }}>
      <AppBar title={mode === "written" ? "Note écrite" : "Note vocale"}>
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
          <strong style={{ color: "var(--color-neutral-900)" }}>{record.givenName}</strong>
          {record.birthYear
            ? ` — ${new Date().getFullYear() - record.birthYear} ans · ${record.sex}`
            : ""}
        </p>
      </div>

      {/* FAB — basculer entre note écrite et note vocale */}
      {phase !== "recording" && !isSaving && (
        <button
          type="button"
          onClick={() => setMode(mode === "written" ? "voice" : "written")}
          aria-label={mode === "written" ? "Passer en note vocale" : "Passer en note écrite"}
          style={{
            position: "fixed",
            bottom: 24,
            right: 20,
            zIndex: 200,
            padding: "13px 22px",
            borderRadius: 28,
            background: "#ea580c",
            border: "none",
            cursor: "pointer",
            display: "flex",
            alignItems: "center",
            gap: 8,
            boxShadow: "0 4px 20px rgba(234,88,12,0.40)",
            color: "#fff",
          }}
        >
          <Icon
            name={mode === "written" ? "mic" : "edit_note"}
            size={20}
            color="#fff"
          />
          <span style={{ fontSize: 14, fontWeight: 600, whiteSpace: "nowrap" }}>
            {mode === "written" ? "Note vocale" : "Note écrite"}
          </span>
        </button>
      )}

      {/* ── Written mode ─────────────────────────────────────────────────── */}
      {mode === "written" && (
        <main
          style={{
            padding: "var(--space-md)",
            display: "flex",
            flexDirection: "column",
            gap: "var(--space-lg)",
          }}
        >
          {/* Médecin + Établissement + Contact */}
          <div
            style={{
              display: "grid",
              gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))",
              gap: "var(--space-md)",
            }}
          >
            <div>
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
                onInput={(e) => setDoctorName((e.target as HTMLInputElement).value)}
              />
            </div>
            <div>
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
            <div>
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
                style={{ background: "var(--color-primary-100)", width: 32, height: 32 }}
              >
                <Icon name="edit_note" size={16} color="var(--color-primary-700)" />
              </span>
              <label className="text-title-sm field-label" htmlFor="note" style={{ margin: 0 }}>
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
                style={{ background: "var(--color-primary-100)", width: 32, height: 32 }}
              >
                <Icon name="medical_services" size={16} color="var(--color-primary-700)" />
              </span>
              <h2 className="text-title-sm" style={{ margin: 0 }}>
                Traitement
              </h2>
            </div>

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
                onClick={() => {
                  setTreatmentMode("none");
                  setCloseTreatment(false);
                }}
                className={treatmentMode === "none" ? "btn btn-filled" : "btn btn-outline"}
                style={{ fontSize: 13 }}
              >
                Aucun traitement
              </button>
              <button
                type="button"
                onClick={() => {
                  setTreatmentMode("new");
                  setCloseTreatment(false);
                }}
                className={treatmentMode === "new" ? "btn btn-filled" : "btn btn-outline"}
                style={{ fontSize: 13 }}
              >
                <Icon
                  name="add"
                  size={16}
                  color={treatmentMode === "new" ? "var(--color-white)" : "var(--color-primary-700)"}
                />
                Nouveau traitement
              </button>
              {activeExistingTreatments.map((t) => (
                <button
                  key={t.id}
                  type="button"
                  onClick={() => {
                    setTreatmentMode(t.id);
                    setCloseTreatment(false);
                  }}
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
                  onInput={(e) => setNewDiagnosis((e.target as HTMLInputElement).value)}
                />
              </div>
            )}

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
                  onChange={(e) => setCloseTreatment((e.target as HTMLInputElement).checked)}
                />
                <span className="text-body">Clore ce traitement à cette consultation</span>
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
                style={{ background: "var(--color-primary-100)", width: 32, height: 32 }}
              >
                <Icon name="medication" size={16} color="var(--color-primary-700)" />
              </span>
              <h2 className="text-title-sm" style={{ margin: 0 }}>
                Ordonnance{ordonnances.length > 1 ? "s" : ""}
              </h2>
            </div>

            <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-md)" }}>
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
                      onInput={(e) => updateLabel(ord.id, (e.target as HTMLInputElement).value)}
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

                  <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-xs)" }}>
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
                              updateLine(ord.id, line.id, "medication", (e.target as HTMLInputElement).value)
                            }
                          />
                          {ord.lines.length > 1 && (
                            <button
                              type="button"
                              className="btn-icon"
                              onClick={() => removeLine(ord.id, line.id)}
                              aria-label="Retirer ce médicament"
                              style={{ flexShrink: 0, color: "var(--color-neutral-500)" }}
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
                              updateLine(ord.id, line.id, "dose", (e.target as HTMLInputElement).value)
                            }
                          />
                          <input
                            className="field-input"
                            placeholder="Fréquence"
                            value={line.frequency}
                            onInput={(e) =>
                              updateLine(ord.id, line.id, "frequency", (e.target as HTMLInputElement).value)
                            }
                          />
                          <input
                            className="field-input"
                            type="number"
                            placeholder="Jours"
                            value={line.durationDays}
                            onInput={(e) =>
                              updateLine(ord.id, line.id, "durationDays", (e.target as HTMLInputElement).value)
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
              onClick={() => setOrdonnances((prev) => [...prev, newOrdonnance()])}
            >
              <Icon name="add" size={18} color="var(--color-primary-700)" />
              Ajouter une ordonnance
            </button>
          </div>

          {/* Conditions médicales — written mode only */}
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
                style={{ background: "var(--color-allergy-bg)", width: 32, height: 32 }}
              >
                <Icon name="monitor_heart" size={16} color="var(--color-allergy)" />
              </span>
              <h2 className="text-title-sm" style={{ margin: 0 }}>
                Conditions médicales
              </h2>
            </div>

            {/* Chips — conditions et allergies déjà ajoutées */}
            {(newAllergies.length > 0 || newConditions.length > 0) && (
              <div
                style={{
                  display: "flex",
                  flexWrap: "wrap",
                  gap: 6,
                  marginBottom: "var(--space-sm)",
                }}
              >
                {newAllergies.map((a, i) => (
                  <span
                    key={`a-${i}`}
                    style={{
                      display: "inline-flex",
                      alignItems: "center",
                      gap: 4,
                      padding: "4px 6px 4px 10px",
                      borderRadius: 99,
                      background: "var(--color-allergy-bg)",
                      border: "1px solid var(--color-allergy)",
                      fontSize: 13,
                    }}
                  >
                    <span
                      style={{
                        fontSize: 10,
                        fontWeight: 700,
                        letterSpacing: "0.04em",
                        color: "var(--color-allergy)",
                        textTransform: "uppercase",
                      }}
                    >
                      Allergie
                    </span>
                    <span style={{ fontWeight: 600, color: "var(--color-neutral-900)", marginLeft: 2 }}>
                      {a.substance}
                    </span>
                    <span
                      style={{
                        fontSize: 12,
                        marginLeft: 2,
                        color:
                          a.severity === "severe"
                            ? "var(--color-error)"
                            : a.severity === "moderate"
                              ? "var(--color-allergy)"
                              : "var(--color-neutral-600)",
                      }}
                    >
                      · {a.severity === "severe" ? "Sévère" : a.severity === "moderate" ? "Modérée" : "Légère"}
                    </span>
                    <button
                      type="button"
                      onClick={() => removeAllergy(i)}
                      aria-label={`Retirer ${a.substance}`}
                      style={{
                        marginLeft: 2,
                        background: "none",
                        border: "none",
                        cursor: "pointer",
                        padding: 0,
                        display: "flex",
                        alignItems: "center",
                        color: "var(--color-neutral-400)",
                      }}
                    >
                      <Icon name="close" size={14} />
                    </button>
                  </span>
                ))}
                {newConditions.map((c, i) => (
                  <span
                    key={`c-${i}`}
                    style={{
                      display: "inline-flex",
                      alignItems: "center",
                      gap: 4,
                      padding: "4px 6px 4px 10px",
                      borderRadius: 99,
                      background: "var(--color-primary-50)",
                      border: "1px solid var(--color-primary-200)",
                      fontSize: 13,
                    }}
                  >
                    <span
                      style={{
                        fontSize: 10,
                        fontWeight: 700,
                        letterSpacing: "0.04em",
                        color: "var(--color-primary-700)",
                        textTransform: "uppercase",
                      }}
                    >
                      Antécédent
                    </span>
                    <span style={{ fontWeight: 600, color: "var(--color-neutral-900)", marginLeft: 2 }}>
                      {c.name}
                    </span>
                    <span style={{ fontSize: 12, marginLeft: 2, color: "var(--color-neutral-600)" }}>
                      · {["Légère", "Modérée", "Importante", "Sévère", "Critique"][c.severity - 1] ?? `Sév. ${c.severity}`}
                    </span>
                    <button
                      type="button"
                      onClick={() => removeCondition(i)}
                      aria-label={`Retirer ${c.name}`}
                      style={{
                        marginLeft: 2,
                        background: "none",
                        border: "none",
                        cursor: "pointer",
                        padding: 0,
                        display: "flex",
                        alignItems: "center",
                        color: "var(--color-neutral-400)",
                      }}
                    >
                      <Icon name="close" size={14} />
                    </button>
                  </span>
                ))}
              </div>
            )}

            {/* Formulaire compact — radio + champ texte + sévérité */}
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
              <div style={{ display: "flex", gap: "var(--space-lg)" }}>
                <label
                  style={{ display: "flex", alignItems: "center", gap: "var(--space-xs)", cursor: "pointer" }}
                >
                  <input
                    type="radio"
                    name="cond-type"
                    checked={conditionType === "allergy"}
                    onChange={() => setConditionType("allergy")}
                    style={{ accentColor: "var(--color-allergy)", width: 15, height: 15 }}
                  />
                  <span className="text-body">Allergie</span>
                </label>
                <label
                  style={{ display: "flex", alignItems: "center", gap: "var(--space-xs)", cursor: "pointer" }}
                >
                  <input
                    type="radio"
                    name="cond-type"
                    checked={conditionType === "condition"}
                    onChange={() => setConditionType("condition")}
                    style={{ accentColor: "var(--color-primary-700)", width: 15, height: 15 }}
                  />
                  <span className="text-body">Antécédent</span>
                </label>
              </div>

              <div
                style={{
                  display: "grid",
                  gridTemplateColumns: "1fr auto",
                  gap: "var(--space-sm)",
                  alignItems: "center",
                }}
              >
                <input
                  className="field-input"
                  placeholder={
                    conditionType === "allergy"
                      ? "Substance ou allergène — ↵ pour ajouter"
                      : "Nom de la pathologie"
                  }
                  value={conditionType === "allergy" ? allergySubstance : conditionName}
                  onInput={(e) => {
                    const val = (e.target as HTMLInputElement).value;
                    conditionType === "allergy" ? setAllergySubstance(val) : setConditionName(val);
                  }}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") {
                      e.preventDefault();
                      if (conditionType === "allergy") addAllergy();
                      // Antécédent : Entrée depuis le nom ne déclenche pas encore l'ajout
                      // car ICD-10 / Depuis peuvent encore être remplis
                    }
                  }}
                />
                {conditionType === "allergy" ? (
                  <select
                    className="field-input"
                    value={allergySeverity}
                    onChange={(e) =>
                      setAllergySeverity(
                        (e.target as HTMLSelectElement).value as NewAllergy["severity"],
                      )
                    }
                    style={{ width: "auto" }}
                  >
                    <option value="mild">Légère</option>
                    <option value="moderate">Modérée</option>
                    <option value="severe">Sévère</option>
                  </select>
                ) : (
                  <select
                    className="field-input"
                    value={conditionSeverity}
                    onChange={(e) =>
                      setConditionSeverity(Number((e.target as HTMLSelectElement).value))
                    }
                    style={{ width: "auto" }}
                  >
                    <option value={1}>Légère</option>
                    <option value={2}>Modérée</option>
                    <option value={3}>Importante</option>
                    <option value={4}>Sévère</option>
                    <option value={5}>Critique</option>
                  </select>
                )}
              </div>

              {/* ICD-10 + Depuis — antécédent uniquement */}
              {conditionType === "condition" && (
                <div
                  style={{
                    display: "grid",
                    gridTemplateColumns: "repeat(auto-fit, minmax(140px, 1fr))",
                    gap: "var(--space-sm)",
                  }}
                >
                  <input
                    className="field-input"
                    placeholder="Code ICD-10 (optionnel)"
                    value={conditionIcd10}
                    onInput={(e) => setConditionIcd10((e.target as HTMLInputElement).value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") { e.preventDefault(); addCondition(); }
                    }}
                  />
                  <input
                    className="field-input"
                    placeholder="Depuis (ex : 2020) — ↵ pour ajouter"
                    value={conditionSince}
                    onInput={(e) => setConditionSince((e.target as HTMLInputElement).value)}
                    onKeyDown={(e) => {
                      if (e.key === "Enter") { e.preventDefault(); addCondition(); }
                    }}
                  />
                </div>
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
              <p className="text-body" style={{ color: "var(--color-error)", margin: 0 }}>
                {error}
              </p>
            </div>
          )}

          <button
            type="button"
            className="btn btn-filled btn-block"
            disabled={isSaving}
            onClick={handleWrittenSave}
          >
            {isSaving ? "Enregistrement…" : "Enregistrer la consultation"}
          </button>
        </main>
      )}

      {/* ── Voice mode ───────────────────────────────────────────────────── */}
      {mode === "voice" && (
        <div
          style={{
            padding: "var(--space-xl) var(--space-md)",
            display: "flex",
            flexDirection: "column",
            gap: "var(--space-lg)",
            maxWidth: 480,
            margin: "0 auto",
          }}
        >
          {/* Doctor name */}
          <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-xs)" }}>
            <label
              htmlFor="voice-doctor-name"
              className="text-caption"
              style={{ color: "var(--color-neutral-600)", fontWeight: 600 }}
            >
              Médecin *
            </label>
            <input
              id="voice-doctor-name"
              type="text"
              value={doctorName}
              onInput={(e) => setDoctorName((e.target as HTMLInputElement).value)}
              placeholder="Dr. Nom Prénom"
              disabled={isSaving}
              style={{
                padding: "10px var(--space-md)",
                borderRadius: "var(--radius-sm)",
                border: "1.5px solid var(--color-neutral-300)",
                fontSize: 16,
                outline: "none",
                background: "var(--color-white)",
              }}
            />
          </div>

          {/* Phase: idle */}
          {phase === "idle" && (
            <div
              style={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                gap: "var(--space-md)",
                padding: "var(--space-xl) 0",
              }}
            >
              <button
                type="button"
                onClick={startRecording}
                aria-label="Démarrer l'enregistrement"
                style={{
                  width: 80,
                  height: 80,
                  borderRadius: "50%",
                  background: "var(--color-primary-700)",
                  border: "none",
                  cursor: "pointer",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  boxShadow: "0 4px 16px rgba(21,101,192,0.35)",
                }}
              >
                <Icon name="mic" size={36} color="var(--color-white)" />
              </button>
              <p className="text-caption" style={{ color: "var(--color-neutral-500)", margin: 0 }}>
                Appuyer pour enregistrer
              </p>
            </div>
          )}

          {/* Phase: recording */}
          {phase === "recording" && (
            <div
              style={{
                display: "flex",
                flexDirection: "column",
                alignItems: "center",
                gap: "var(--space-md)",
                padding: "var(--space-xl) 0",
              }}
            >
              <div
                aria-live="polite"
                aria-label={`Enregistrement en cours : ${formatDuration(durationMs)}`}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "var(--space-sm)",
                  color: "var(--color-accent-700)",
                }}
              >
                <span
                  style={{
                    width: 10,
                    height: 10,
                    borderRadius: "50%",
                    background: "var(--color-accent-700)",
                    animation: "ht-rec-pulse 1s ease-in-out infinite",
                    flexShrink: 0,
                  }}
                />
                <span
                  className="text-headline"
                  style={{ fontVariantNumeric: "tabular-nums" }}
                >
                  {formatDuration(durationMs)}
                </span>
              </div>

              <button
                type="button"
                onClick={stopRecording}
                aria-label="Arrêter l'enregistrement"
                style={{
                  width: 80,
                  height: 80,
                  borderRadius: "50%",
                  background: "var(--color-accent-700)",
                  border: "none",
                  cursor: "pointer",
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  boxShadow: "0 4px 16px rgba(198,40,40,0.35)",
                }}
              >
                <Icon name="stop" size={36} color="var(--color-white)" />
              </button>
              <p className="text-caption" style={{ color: "var(--color-neutral-500)", margin: 0 }}>
                Appuyer pour arrêter
              </p>
            </div>
          )}

          {/* Phase: preview */}
          {phase === "preview" && audioUrl && (
            <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-md)" }}>
              <div
                style={{
                  background: "var(--color-white)",
                  borderRadius: "var(--radius-sm)",
                  border: "1.5px solid var(--color-neutral-200)",
                  padding: "var(--space-md)",
                  display: "flex",
                  flexDirection: "column",
                  gap: "var(--space-sm)",
                }}
              >
                <div style={{ display: "flex", alignItems: "center", gap: "var(--space-sm)" }}>
                  <Icon name="mic" size={18} color="var(--color-primary-700)" />
                  <p className="text-caption" style={{ margin: 0, color: "var(--color-neutral-500)" }}>
                    {formatDuration(durationMs)} · aperçu
                  </p>
                </div>
                {/* eslint-disable-next-line jsx-a11y/media-has-caption */}
                <audio controls src={audioUrl} style={{ width: "100%", height: 36 }} />
              </div>

              <div style={{ display: "flex", gap: "var(--space-md)" }}>
                <button
                  type="button"
                  onClick={restart}
                  disabled={isSaving}
                  style={{
                    flex: 1,
                    padding: "12px var(--space-md)",
                    borderRadius: "var(--radius-sm)",
                    border: "1.5px solid var(--color-neutral-300)",
                    background: "var(--color-white)",
                    cursor: "pointer",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    gap: "var(--space-xs)",
                  }}
                >
                  <Icon name="refresh" size={18} color="var(--color-neutral-700)" />
                  <span className="text-body" style={{ fontWeight: 600 }}>
                    Recommencer
                  </span>
                </button>

                <button
                  type="button"
                  onClick={handleVoiceSave}
                  disabled={isSaving || !doctorName.trim()}
                  aria-label="Enregistrer la consultation"
                  style={{
                    flex: 1,
                    padding: "12px var(--space-md)",
                    borderRadius: "var(--radius-sm)",
                    border: "none",
                    background:
                      isSaving || !doctorName.trim()
                        ? "var(--color-neutral-300)"
                        : "var(--color-primary-700)",
                    color: "var(--color-white)",
                    cursor: isSaving || !doctorName.trim() ? "not-allowed" : "pointer",
                    display: "flex",
                    alignItems: "center",
                    justifyContent: "center",
                    gap: "var(--space-xs)",
                  }}
                >
                  <Icon name="save" size={18} color="var(--color-white)" />
                  <span className="text-body" style={{ fontWeight: 600 }}>
                    {isSaving ? "Envoi…" : "Enregistrer"}
                  </span>
                </button>
              </div>
            </div>
          )}
        </div>
      )}

      {mode === "voice" && error && (
        <SnackBar message={error} tone="error" onDismiss={() => setError(null)} />
      )}

      <style>{`
        @keyframes ht-rec-pulse {
          0%, 100% { opacity: 1; }
          50%       { opacity: 0.3; }
        }
      `}</style>
    </div>
  );
}
