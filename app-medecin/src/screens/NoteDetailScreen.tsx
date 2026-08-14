import { useEffect, useRef, useState } from "preact/hooks";
import { AppBar } from "../components/AppBar";
import { Icon } from "../components/Icon";
import { Spinner } from "../components/Spinner";
import {
  formatDateFr,
  type Consultation,
  type MediaDescriptor,
  type OrdonnanceLineJson,
  type OrdonnanceLineStatus,
} from "../stubs/data";

export interface NoteDetailScreenProps {
  consultation: Consultation;
  consultationIndex: number;
  backendUrl?: string;
  writeToken?: string;
  onAmend: (consultationIndex: number, text: string, author: string) => Promise<void>;
  onCloseOrdonnanceLine: (
    consultationIndex: number,
    ordonnanceId: string,
    lineIndex: number,
    status: OrdonnanceLineStatus,
  ) => Promise<void>;
  onBack: () => void;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function statusLabel(s: OrdonnanceLineStatus | undefined) {
  switch (s) {
    case "completed": return "Terminé";
    case "expired":   return "Expiré";
    default:          return "Actif";
  }
}

function statusColor(s: OrdonnanceLineStatus | undefined) {
  switch (s) {
    case "completed": return "#6b7280";
    case "expired":   return "#c2410c";
    default:          return "#006c67";
  }
}

function statusBg(s: OrdonnanceLineStatus | undefined) {
  switch (s) {
    case "completed": return "#f3f4f6";
    case "expired":   return "#fff7ed";
    default:          return "var(--color-primary-50)";
  }
}

// Option A: auto-expiry when duration_days has elapsed since consultation date.
// "completed" and "expired" stored statuses always win (doctor override).
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

// ── Component ─────────────────────────────────────────────────────────────────

// ── Image tile (mint-access → XOR decrypt → blob URL) ────────────────────────

function ImageTile({ media, backendUrl }: { media: MediaDescriptor; backendUrl: string }) {
  const [objectUrl, setObjectUrl] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  const blobRef = useRef<string | null>(null);

  useEffect(() => {
    let active = true;
    fetch(`${backendUrl}/media/${media.mediaId}/access`, { method: "POST" })
      .then((r) => { if (!r.ok) throw new Error(`access:${r.status}`); return r.json(); })
      .then((grant: { url: string }) => {
        const capUrl = grant.url.startsWith("http") ? grant.url : `${backendUrl}${grant.url}`;
        return fetch(capUrl);
      })
      .then((r) => { if (!r.ok) throw new Error(`fetch:${r.status}`); return r.arrayBuffer(); })
      .then((buf) => {
        if (!active) return;
        const bytes = new Uint8Array(buf);
        const dec = new Uint8Array(bytes.length);
        for (let i = 0; i < bytes.length; i++) dec[i] = bytes[i] ^ 0x5a;
        const blob = new Blob([dec], { type: media.mime || "image/jpeg" });
        const url = URL.createObjectURL(blob);
        blobRef.current = url;
        setObjectUrl(url);
      })
      .catch(() => { if (active) setFailed(true); });
    return () => {
      active = false;
      if (blobRef.current) { URL.revokeObjectURL(blobRef.current); blobRef.current = null; }
    };
  }, [backendUrl, media.mediaId, media.mime]);

  const tile: preact.JSX.CSSProperties = {
    width: 80, height: 80, borderRadius: "var(--radius-sm)", flexShrink: 0,
    overflow: "hidden", background: "var(--color-neutral-100)",
    display: "flex", alignItems: "center", justifyContent: "center",
  };

  if (failed) return <div style={tile}><Icon name="broken_image" size={24} color="var(--color-neutral-400)" /></div>;
  if (!objectUrl) return <div style={tile}><Spinner size={20} color="var(--color-neutral-400)" /></div>;
  return (
    <div style={{ ...tile, cursor: "pointer" }} onClick={() => window.open(objectUrl, "_blank")}>
      <img src={objectUrl} alt="pièce jointe" style={{ width: "100%", height: "100%", objectFit: "cover" }} />
    </div>
  );
}

// ── Audio player (mint-access → XOR decrypt → <audio>) ───────────────────────

function AudioPlayer({ media, backendUrl }: { media: MediaDescriptor; backendUrl: string }) {
  const [objectUrl, setObjectUrl] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  const blobRef = useRef<string | null>(null);

  useEffect(() => {
    let active = true;
    fetch(`${backendUrl}/media/${media.mediaId}/access`, { method: "POST" })
      .then((r) => { if (!r.ok) throw new Error(`access:${r.status}`); return r.json(); })
      .then((grant: { url: string }) => {
        const capUrl = grant.url.startsWith("http") ? grant.url : `${backendUrl}${grant.url}`;
        return fetch(capUrl);
      })
      .then((r) => { if (!r.ok) throw new Error(`fetch:${r.status}`); return r.arrayBuffer(); })
      .then((buf) => {
        if (!active) return;
        const bytes = new Uint8Array(buf);
        const dec = new Uint8Array(bytes.length);
        for (let i = 0; i < bytes.length; i++) dec[i] = bytes[i] ^ 0x5a;
        const blob = new Blob([dec], { type: media.mime || "audio/webm" });
        const url = URL.createObjectURL(blob);
        blobRef.current = url;
        setObjectUrl(url);
      })
      .catch(() => { if (active) setFailed(true); });
    return () => {
      active = false;
      if (blobRef.current) { URL.revokeObjectURL(blobRef.current); blobRef.current = null; }
    };
  }, [backendUrl, media.mediaId, media.mime]);

  const rowStyle: preact.JSX.CSSProperties = {
    display: "flex", alignItems: "center", gap: 8,
    padding: "6px 12px", background: "var(--color-neutral-100)",
    borderRadius: "var(--radius-sm)",
  };

  if (failed) {
    return (
      <div style={rowStyle}>
        <Icon name="mic_off" size={14} color="var(--color-neutral-400)" />
        <p className="text-caption" style={{ margin: 0, color: "var(--color-neutral-400)" }}>Lecture indisponible</p>
      </div>
    );
  }
  if (!objectUrl) {
    return (
      <div style={rowStyle}>
        <Spinner size={14} color="var(--color-neutral-400)" />
        <p className="text-caption" style={{ margin: 0, color: "var(--color-neutral-500)" }}>Chargement…</p>
      </div>
    );
  }
  return <audio controls src={objectUrl} style={{ width: "100%", height: 36 }} />;
}

// ── Component ─────────────────────────────────────────────────────────────────

export function NoteDetailScreen({
  consultation: c,
  consultationIndex,
  backendUrl,
  writeToken,
  onAmend,
  onCloseOrdonnanceLine,
  onBack,
}: NoteDetailScreenProps) {
  type Draft = { text: string; author: string };

  const [drafts, setDrafts] = useState<Draft[]>([]);
  const [draftText, setDraftText] = useState("");
  const [draftAuthor, setDraftAuthor] = useState("");
  const [showAmendForm, setShowAmendForm] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const canWrite = !!writeToken;

  function addDraft() {
    if (!draftText.trim()) return;
    setDrafts((prev) => [...prev, { text: draftText.trim(), author: draftAuthor.trim() || "Médecin" }]);
    setDraftText("");
    setDraftAuthor("");
  }

  function removeDraft(i: number) {
    setDrafts((prev) => prev.filter((_, idx) => idx !== i));
  }

  async function saveAllDrafts() {
    if (drafts.length === 0) return;
    setIsSaving(true);
    setError(null);
    try {
      for (const d of drafts) {
        await onAmend(consultationIndex, d.text, d.author);
      }
      setDrafts([]);
      setShowAmendForm(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Échec de l'amendement — réessayez.");
    } finally {
      setIsSaving(false);
    }
  }

  function cancelAmendForm() {
    setShowAmendForm(false);
    setDrafts([]);
    setDraftText("");
    setDraftAuthor("");
  }

  async function handleCloseLine(
    ordId: string,
    lineIdx: number,
    newStatus: OrdonnanceLineStatus,
  ) {
    setIsSaving(true);
    setError(null);
    try {
      await onCloseOrdonnanceLine(consultationIndex, ordId, lineIdx, newStatus);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Échec — réessayez.");
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <div style={{ minHeight: "100%", paddingBottom: 80 }}>
      <AppBar title="Détail de la consultation">
        <button type="button" className="btn-icon" onClick={onBack} aria-label="Retour">
          <Icon name="arrow_back" size={22} />
        </button>
      </AppBar>

      <main style={{ padding: "var(--space-md)", display: "flex", flexDirection: "column", gap: "var(--space-lg)" }}>

        {/* En-tête consultation */}
        <div style={{ display: "flex", flexDirection: "column", gap: 4 }}>
          <p className="text-title-sm" style={{ color: "var(--color-primary-700)" }}>
            {formatDateFr(c.date)}
            {c.doctorName && <span style={{ color: "var(--color-neutral-500)", fontWeight: 400 }}> · {c.doctorName}</span>}
          </p>
          {c.createdAt && (
            <p className="text-caption">{new Date(c.createdAt).toLocaleTimeString("fr-FR", { hour: "2-digit", minute: "2-digit" })}</p>
          )}
        </div>

        {/* Note */}
        <div>
          <div style={{ display: "flex", alignItems: "center", gap: "var(--space-sm)", marginBottom: "var(--space-sm)" }}>
            <span className="icon-badge" style={{ background: "var(--color-primary-100)", width: 32, height: 32 }}>
              <Icon name="edit_note" size={16} color="var(--color-primary-700)" />
            </span>
            <h2 className="text-title-sm" style={{ margin: 0 }}>Note</h2>
          </div>
          <div style={{ background: "var(--color-neutral-50)", borderRadius: "var(--radius-sm)", padding: "var(--space-md)" }}>
            <p className="text-body" style={{ color: "var(--color-neutral-900)", whiteSpace: "pre-wrap", margin: 0 }}>
              {c.summary}
            </p>
          </div>
        </div>

        {/* Amendements existants */}
        {c.amendments && c.amendments.length > 0 && (
          <div>
            <div style={{ display: "flex", alignItems: "center", gap: "var(--space-sm)", marginBottom: "var(--space-sm)" }}>
              <span className="icon-badge" style={{ background: "#fef9c3", width: 32, height: 32 }}>
                <Icon name="edit" size={16} color="#92400e" />
              </span>
              <h2 className="text-title-sm" style={{ margin: 0 }}>
                Amendement{c.amendments.length > 1 ? "s" : ""}
              </h2>
            </div>
            <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-sm)" }}>
              {c.amendments.map((a, i) => (
                <div key={i} style={{ background: "#fefce8", border: "1px solid #fde68a", borderRadius: "var(--radius-sm)", padding: "var(--space-sm) var(--space-md)" }}>
                  <p className="text-caption" style={{ marginBottom: 4 }}>
                    {a.author} · {new Date(a.at).toLocaleDateString("fr-FR", { day: "2-digit", month: "short", year: "numeric" })}
                  </p>
                  <p className="text-body" style={{ color: "var(--color-neutral-900)", whiteSpace: "pre-wrap", margin: 0 }}>
                    {a.text}
                  </p>
                </div>
              ))}
            </div>
          </div>
        )}

        {/* Formulaire d'amendement */}
        {canWrite && (
          <div>
            {!showAmendForm ? (
              <button
                type="button"
                className="btn btn-outline"
                style={{ fontSize: 13, gap: "var(--space-xs)" }}
                onClick={() => setShowAmendForm(true)}
                disabled={isSaving}
              >
                <Icon name="edit" size={16} color="var(--color-primary-700)" />
                Amender cette note
              </button>
            ) : (
              <div style={{ background: "var(--color-white)", border: "1px solid var(--color-neutral-200)", borderRadius: "var(--radius-sm)", padding: "var(--space-md)", display: "flex", flexDirection: "column", gap: "var(--space-sm)" }}>
                <p className="text-title-sm" style={{ margin: 0 }}>Amendements à ajouter</p>

                {/* Draft list with delete buttons */}
                {drafts.length > 0 && (
                  <div style={{ display: "flex", flexDirection: "column", gap: 6 }}>
                    {drafts.map((d, i) => (
                      <div key={i} style={{ display: "flex", alignItems: "flex-start", gap: 8, background: "#fefce8", border: "1px solid #fde68a", borderRadius: "var(--radius-sm)", padding: "8px 10px" }}>
                        <div style={{ flex: 1, minWidth: 0 }}>
                          <p className="text-caption" style={{ marginBottom: 2 }}>{d.author}</p>
                          <p className="text-body" style={{ margin: 0, whiteSpace: "pre-wrap" }}>{d.text}</p>
                        </div>
                        <button
                          type="button"
                          onClick={() => removeDraft(i)}
                          disabled={isSaving}
                          aria-label="Supprimer ce brouillon"
                          style={{ flexShrink: 0, padding: 4, background: "none", border: "none", cursor: "pointer", color: "var(--color-neutral-500)", borderRadius: 4 }}
                        >
                          <Icon name="close" size={16} />
                        </button>
                      </div>
                    ))}
                  </div>
                )}

                {/* Input for next draft */}
                <input
                  className="field-input"
                  placeholder="Dr. Nom Prénom (auteur)"
                  value={draftAuthor}
                  onInput={(e) => setDraftAuthor((e.target as HTMLInputElement).value)}
                  disabled={isSaving}
                />
                <textarea
                  className="field-textarea"
                  placeholder="Texte de l'amendement…"
                  value={draftText}
                  onInput={(e) => setDraftText((e.target as HTMLTextAreaElement).value)}
                  disabled={isSaving}
                  style={{ minHeight: 80 }}
                />
                <button
                  type="button"
                  className="btn btn-outline"
                  style={{ fontSize: 13, gap: "var(--space-xs)", alignSelf: "flex-start" }}
                  onClick={addDraft}
                  disabled={!draftText.trim() || isSaving}
                >
                  <Icon name="add" size={16} color="var(--color-primary-700)" />
                  Ajouter à la liste
                </button>

                <div style={{ display: "flex", gap: "var(--space-sm)", borderTop: "1px solid var(--color-neutral-100)", paddingTop: "var(--space-sm)" }}>
                  <button
                    type="button"
                    className="btn btn-outline"
                    style={{ fontSize: 13 }}
                    onClick={cancelAmendForm}
                    disabled={isSaving}
                  >
                    Annuler
                  </button>
                  <button
                    type="button"
                    className="btn btn-filled"
                    style={{ fontSize: 13 }}
                    onClick={saveAllDrafts}
                    disabled={isSaving || drafts.length === 0}
                  >
                    {isSaving
                      ? "Enregistrement…"
                      : `Enregistrer ${drafts.length > 0 ? drafts.length : ""} amendement${drafts.length > 1 ? "s" : ""}`}
                  </button>
                </div>
              </div>
            )}
          </div>
        )}

        {/* Ordonnances */}
        {c.ordonnances && c.ordonnances.length > 0 && (
          <div>
            <div style={{ display: "flex", alignItems: "center", gap: "var(--space-sm)", marginBottom: "var(--space-sm)" }}>
              <span className="icon-badge" style={{ background: "var(--color-primary-100)", width: 32, height: 32 }}>
                <Icon name="medication" size={16} color="var(--color-primary-700)" />
              </span>
              <h2 className="text-title-sm" style={{ margin: 0 }}>
                Ordonnance{c.ordonnances.length > 1 ? "s" : ""}
              </h2>
            </div>
            <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-sm)" }}>
              {c.ordonnances.map((ord) => (
                <div key={ord.id} style={{ background: "var(--color-white)", border: "1px solid var(--color-neutral-200)", borderRadius: "var(--radius-sm)", overflow: "hidden" }}>
                  {ord.label && (
                    <div style={{ padding: "6px 12px", background: "var(--color-primary-50)", borderBottom: "1px solid var(--color-neutral-200)" }}>
                      <p className="text-label" style={{ color: "var(--color-primary-700)", margin: 0 }}>{ord.label}</p>
                    </div>
                  )}
                  {ord.lines.map((line, li) => {
                    const st = effectiveStatus(line, c.date);
                    const isActive = !st || st === "active";
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
                            <p className="text-caption" style={{ margin: 0, color: "var(--color-neutral-500)" }}>
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
                          background: statusBg(st),
                          color: statusColor(st),
                          border: `1px solid ${statusColor(st)}40`,
                        }}>
                          {statusLabel(st)}
                        </span>
                        {canWrite && isActive && (
                          <div style={{ display: "flex", gap: 4, flexShrink: 0 }}>
                            <button
                              type="button"
                              onClick={() => handleCloseLine(ord.id, li, "completed")}
                              disabled={isSaving}
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
                              }}
                            >
                              Terminé
                            </button>
                            {!line.duration_days && (
                              <button
                                type="button"
                                onClick={() => handleCloseLine(ord.id, li, "expired")}
                                disabled={isSaving}
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
                                }}
                              >
                                Expiré
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
          </div>
        )}

        {/* Médias */}
        {c.media && c.media.length > 0 && (
          <div>
            <div style={{ display: "flex", alignItems: "center", gap: "var(--space-sm)", marginBottom: "var(--space-sm)" }}>
              <span className="icon-badge" style={{ background: "var(--color-neutral-100)", width: 32, height: 32 }}>
                <Icon name="attach_file" size={16} color="var(--color-neutral-700)" />
              </span>
              <h2 className="text-title-sm" style={{ margin: 0 }}>Pièces jointes</h2>
            </div>
            <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-sm)" }}>
              {/* Notes vocales */}
              {c.media.filter((m) => m.mime.startsWith("audio/")).map((m) =>
                backendUrl
                  ? <AudioPlayer key={m.mediaId} media={m} backendUrl={backendUrl} />
                  : (
                    <div key={m.mediaId} style={{ display: "flex", alignItems: "center", gap: 6, padding: "6px 12px", background: "var(--color-neutral-100)", borderRadius: "var(--radius-sm)" }}>
                      <Icon name="mic" size={14} color="var(--color-neutral-600)" />
                      <p className="text-caption" style={{ margin: 0 }}>Note vocale</p>
                    </div>
                  )
              )}
              {/* Images */}
              <div style={{ display: "flex", flexWrap: "wrap", gap: "var(--space-sm)" }}>
                {c.media.filter((m) => m.mime.startsWith("image/")).map((m) =>
                  backendUrl
                    ? <ImageTile key={m.mediaId} media={m} backendUrl={backendUrl} />
                    : (
                      <div key={m.mediaId} style={{ display: "flex", alignItems: "center", gap: 6, padding: "6px 12px", background: "var(--color-neutral-100)", borderRadius: "var(--radius-sm)" }}>
                        <Icon name="image" size={14} color="var(--color-neutral-600)" />
                        <p className="text-caption" style={{ margin: 0 }}>{m.mime.split("/")[1]?.toUpperCase()}</p>
                      </div>
                    )
                )}
              </div>
            </div>
          </div>
        )}

        {error && (
          <div role="alert" style={{ display: "flex", alignItems: "center", gap: "var(--space-sm)", padding: "var(--space-sm) var(--space-md)", background: "var(--color-error-bg)", borderRadius: "var(--radius-sm)", border: "1px solid rgba(220,38,38,0.2)" }}>
            <Icon name="error" size={20} color="var(--color-error)" />
            <p className="text-body" style={{ color: "var(--color-error)", margin: 0 }}>{error}</p>
          </div>
        )}
      </main>
    </div>
  );
}
