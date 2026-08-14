import { useState } from "preact/hooks";
import { AppBar } from "../components/AppBar";
import { Icon } from "../components/Icon";
import {
  formatDateFr,
  type MedicalRecord,
  type OrdonnanceJson,
  type OrdonnanceLineJson,
  type OrdonnanceLineStatus,
  type TreatmentJson,
} from "../stubs/data";

export interface TreatmentsScreenProps {
  record: MedicalRecord;
  writeToken?: string;
  onCloseOrdonnanceLine: (
    consultationIndex: number,
    ordonnanceId: string,
    lineIndex: number,
    status: OrdonnanceLineStatus,
  ) => Promise<void>;
  onBack: () => void;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

type LineStatus = OrdonnanceLineStatus | undefined;

function statusLabel(s: LineStatus) {
  switch (s) {
    case "completed": return "Terminé";
    case "expired":   return "Expiré";
    default:          return "Actif";
  }
}
function statusColor(s: LineStatus) {
  switch (s) {
    case "completed": return "#6b7280";
    case "expired":   return "#c2410c";
    default:          return "#006c67";
  }
}
function statusBg(s: LineStatus) {
  switch (s) {
    case "completed": return "#f3f4f6";
    case "expired":   return "#fff7ed";
    default:          return "var(--color-primary-50)";
  }
}

// Option A: auto-expiry when duration_days has elapsed since consultation date.
function effectiveStatus(
  line: OrdonnanceLineJson,
  consultationDate: string,
): OrdonnanceLineStatus | undefined {
  if (line.status === "completed" || line.status === "expired") return line.status;
  if (line.duration_days) {
    const expiry = new Date(consultationDate);
    expiry.setDate(expiry.getDate() + line.duration_days);
    if (Date.now() >= expiry.getTime()) return "expired";
  }
  return line.status;
}

/** Returns true if ALL lines in an ordonnance are non-active. */
function ordonnanceIsClosed(lines: OrdonnanceLineJson[]) {
  return lines.every((l) => l.status === "completed" || l.status === "expired");
}

/** Returns true if at least one line is active. */
function treatmentHasActiveLines(record: MedicalRecord, treatmentId: string) {
  for (const c of record.consultations) {
    for (const ord of c.ordonnances ?? []) {
      if (ord.treatment_id !== treatmentId) continue;
      if (!ordonnanceIsClosed(ord.lines)) return true;
    }
  }
  return false;
}

// ── Component ─────────────────────────────────────────────────────────────────

export function TreatmentsScreen({
  record,
  writeToken,
  onCloseOrdonnanceLine,
  onBack,
}: TreatmentsScreenProps) {
  const [tab, setTab] = useState<"active" | "closed">("active");
  const [saving, setSaving] = useState<string | null>(null); // key = `c${ci}-o${oi}-l${li}`
  const [error, setError] = useState<string | null>(null);

  const canWrite = !!writeToken;

  function treatmentSort(a: TreatmentJson, b: TreatmentJson) {
    const dateCmp = b.started_at.localeCompare(a.started_at);
    if (dateCmp !== 0) return dateCmp;
    return (b.createdAt ?? b.started_at).localeCompare(a.createdAt ?? a.started_at);
  }
  const activeTreatments = record.treatments
    .filter((t) => t.status === "active" && treatmentHasActiveLines(record, t.id))
    .sort(treatmentSort);
  const closedTreatments = record.treatments
    .filter((t) => t.status !== "active" || !treatmentHasActiveLines(record, t.id))
    .sort(treatmentSort);

  async function handleCloseLine(
    consultIdx: number,
    ordId: string,
    lineIdx: number,
    key: string,
    newStatus: OrdonnanceLineStatus,
  ) {
    setSaving(key);
    setError(null);
    try {
      await onCloseOrdonnanceLine(consultIdx, ordId, lineIdx, newStatus);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Échec — réessayez.");
    } finally {
      setSaving(null);
    }
  }

  const displayed = tab === "active" ? activeTreatments : closedTreatments;

  return (
    <div style={{ minHeight: "100%", paddingBottom: 80 }}>
      <AppBar title="Traitements">
        <button type="button" className="btn-icon" onClick={onBack} aria-label="Retour">
          <Icon name="arrow_back" size={22} />
        </button>
      </AppBar>

      {/* Onglets */}
      <div style={{ display: "flex", borderBottom: "1px solid var(--color-neutral-200)", background: "var(--color-white)" }}>
        {(["active", "closed"] as const).map((t) => {
          const count = t === "active" ? activeTreatments.length : closedTreatments.length;
          const isActive = tab === t;
          return (
            <button
              key={t}
              type="button"
              onClick={() => setTab(t)}
              style={{
                flex: 1,
                padding: "12px var(--space-md)",
                background: "none",
                border: "none",
                borderBottom: isActive ? "2px solid var(--color-primary-700)" : "2px solid transparent",
                cursor: "pointer",
                fontSize: 14,
                fontWeight: isActive ? 700 : 400,
                color: isActive ? "var(--color-primary-700)" : "var(--color-neutral-500)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                gap: 6,
              }}
            >
              {t === "active" ? "En cours" : "Terminés"}
              <span style={{
                fontSize: 11,
                fontWeight: 700,
                padding: "1px 6px",
                borderRadius: "var(--radius-pill)",
                background: isActive ? "var(--color-primary-100)" : "var(--color-neutral-100)",
                color: isActive ? "var(--color-primary-700)" : "var(--color-neutral-500)",
              }}>
                {count}
              </span>
            </button>
          );
        })}
      </div>

      <main style={{ padding: "var(--space-md)", display: "flex", flexDirection: "column", gap: "var(--space-lg)" }}>
        {error && (
          <div role="alert" style={{ display: "flex", alignItems: "center", gap: "var(--space-sm)", padding: "var(--space-sm) var(--space-md)", background: "var(--color-error-bg)", borderRadius: "var(--radius-sm)", border: "1px solid rgba(220,38,38,0.2)" }}>
            <Icon name="error" size={18} color="var(--color-error)" />
            <p className="text-body" style={{ color: "var(--color-error)", margin: 0 }}>{error}</p>
          </div>
        )}

        {displayed.length === 0 && (
          <div style={{ textAlign: "center", padding: "var(--space-xl) 0" }}>
            <p className="text-body" style={{ color: "var(--color-neutral-400)" }}>
              {tab === "active" ? "Aucun traitement en cours" : "Aucun traitement terminé"}
            </p>
          </div>
        )}

        {displayed.map((treatment) => {
          const allOrdonnances: { consultIdx: number; date: string; createdAt?: string; doctor?: string; ord: OrdonnanceJson }[] = [];

          record.consultations.forEach((c, ci) => {
            (c.ordonnances ?? []).forEach((ord) => {
              if (ord.treatment_id === treatment.id) {
                allOrdonnances.push({ consultIdx: ci, date: c.date, createdAt: c.createdAt, doctor: c.doctorName, ord });
              }
            });
          });

          allOrdonnances.sort((a, b) => {
            const dateCmp = b.date.localeCompare(a.date);
            if (dateCmp !== 0) return dateCmp;
            return (b.createdAt ?? b.date).localeCompare(a.createdAt ?? a.date);
          });

          const totalLines = allOrdonnances.reduce((n, o) => n + o.ord.lines.length, 0);
          const activeLines = allOrdonnances.reduce(
            (n, o) => n + o.ord.lines.filter((l) => !l.status || l.status === "active").length, 0,
          );

          return (
            <div key={treatment.id} style={{ background: "var(--color-white)", border: "1px solid var(--color-neutral-200)", borderRadius: "var(--radius-md)", overflow: "hidden" }}>
              {/* En-tête traitement */}
              <div style={{ padding: "var(--space-sm) var(--space-md)", background: "var(--color-primary-50)", borderBottom: "1px solid var(--color-neutral-200)", display: "flex", alignItems: "center", gap: "var(--space-sm)" }}>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <p className="text-title-sm" style={{ margin: "0 0 2px", color: "var(--color-primary-900)" }}>
                    {treatment.diagnosis}
                  </p>
                  <p className="text-caption" style={{ margin: 0 }}>
                    Depuis {formatDateFr(treatment.started_at)}
                    {treatment.doctor_ref && ` · Dr. ${treatment.doctor_ref}`}
                  </p>
                </div>
                <div style={{ flexShrink: 0, textAlign: "right" }}>
                  <p style={{ margin: 0, fontSize: 12, fontWeight: 700, color: activeLines > 0 ? "var(--color-primary-700)" : "#6b7280" }}>
                    {activeLines}/{totalLines} actifs
                  </p>
                </div>
              </div>

              {/* Ordonnances groupées par consultation */}
              {allOrdonnances.length === 0 ? (
                <p className="text-caption" style={{ padding: "var(--space-md)", margin: 0, color: "var(--color-neutral-400)" }}>
                  Aucune ordonnance liée
                </p>
              ) : (
                <div>
                  {allOrdonnances.map(({ consultIdx, date, doctor, ord }) => (
                    <div key={ord.id} style={{ borderBottom: "1px solid var(--color-neutral-100)" }}>
                      {/* En-tête ordonnance */}
                      <div style={{ padding: "6px 12px", display: "flex", alignItems: "center", gap: 6, background: "var(--color-neutral-50)" }}>
                        <Icon name="description" size={13} color="var(--color-neutral-500)" />
                        <p className="text-caption" style={{ margin: 0 }}>
                          {formatDateFr(date)}{doctor && ` · ${doctor}`}
                          {ord.label && ` — ${ord.label}`}
                        </p>
                      </div>

                      {/* Lignes médicament */}
                      {ord.lines.map((line, li) => {
                        const st = effectiveStatus(line, date);
                        const isActive = !st || st === "active";
                        const key = `c${consultIdx}-o${ord.id}-l${li}`;
                        return (
                          <div
                            key={li}
                            style={{
                              display: "flex",
                              alignItems: "center",
                              gap: "var(--space-sm)",
                              padding: "10px 12px",
                              borderBottom: li < ord.lines.length - 1 ? "1px solid var(--color-neutral-100)" : "none",
                              background: statusBg(st),
                            }}
                          >
                            <div style={{ flex: 1, minWidth: 0 }}>
                              <p className="text-body" style={{ color: "var(--color-neutral-900)", margin: "0 0 2px", fontWeight: 600 }}>
                                {line.medication}
                              </p>
                              {(line.dose || line.frequency || line.duration_days) && (
                                <p className="text-caption" style={{ margin: 0 }}>
                                  {[line.dose, line.frequency, line.duration_days ? `${line.duration_days}j` : ""].filter(Boolean).join(" · ")}
                                </p>
                              )}
                            </div>
                            <span style={{
                              flexShrink: 0,
                              fontSize: 11,
                              fontWeight: 700,
                              padding: "2px 8px",
                              borderRadius: "var(--radius-pill)",
                              color: statusColor(st),
                              border: `1px solid ${statusColor(st)}40`,
                              background: statusBg(st),
                            }}>
                              {statusLabel(st)}
                            </span>
                            {canWrite && isActive && (
                              <div style={{ display: "flex", gap: 4, flexShrink: 0 }}>
                                <button
                                  type="button"
                                  onClick={() => handleCloseLine(consultIdx, ord.id, li, key, "completed")}
                                  disabled={saving === key}
                                  aria-label={`Terminer ${line.medication}`}
                                  style={{
                                    padding: "4px 10px",
                                    fontSize: 12,
                                    fontWeight: 600,
                                    background: "none",
                                    border: "1px solid var(--color-neutral-300)",
                                    borderRadius: "var(--radius-sm)",
                                    cursor: "pointer",
                                    color: "var(--color-neutral-600)",
                                    whiteSpace: "nowrap",
                                    opacity: saving === key ? 0.5 : 1,
                                  }}
                                >
                                  {saving === key ? "…" : "Terminé"}
                                </button>
                                {!line.duration_days && (
                                  <button
                                    type="button"
                                    onClick={() => handleCloseLine(consultIdx, ord.id, li, key, "expired")}
                                    disabled={saving === key}
                                    aria-label={`Arrêt anticipé ${line.medication}`}
                                    style={{
                                      padding: "4px 10px",
                                      fontSize: 12,
                                      fontWeight: 600,
                                      background: "none",
                                      border: "1px solid #f97316",
                                      borderRadius: "var(--radius-sm)",
                                      cursor: "pointer",
                                      color: "#c2410c",
                                      whiteSpace: "nowrap",
                                      opacity: saving === key ? 0.5 : 1,
                                    }}
                                  >
                                    {saving === key ? "…" : "Expiré"}
                                  </button>
                                )}
                              </div>
                            )}
                          </div>
                        );
                      })}
                    </div>
                  ))}
                </div>
              )}
            </div>
          );
        })}
      </main>
    </div>
  );
}
