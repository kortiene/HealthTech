import { useEffect, useRef, useState } from "preact/hooks";
import { AppBar } from "../components/AppBar";
import { Icon } from "../components/Icon";
import { Spinner } from "../components/Spinner";
import {
  formatDateFr,
  type Consultation,
  type MediaDescriptor,
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
  const [amendText, setAmendText] = useState("");
  const [amendAuthor, setAmendAuthor] = useState("");
  const [showAmendForm, setShowAmendForm] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const canWrite = !!writeToken;

  async function handleAmend() {
    if (!amendText.trim()) return;
    setIsSaving(true);
    setError(null);
    try {
      await onAmend(consultationIndex, amendText.trim(), amendAuthor.trim() || "Médecin");
      setAmendText("");
      setAmendAuthor("");
      setShowAmendForm(false);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Échec de l'amendement — réessayez.");
    } finally {
      setIsSaving(false);
    }
  }

  async function handleCloseLine(
    ordId: string,
    lineIdx: number,
    current: OrdonnanceLineStatus | undefined,
  ) {
    if (current === "completed") return;
    setIsSaving(true);
    setError(null);
    try {
      await onCloseOrdonnanceLine(consultationIndex, ordId, lineIdx, "completed");
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
                <p className="text-title-sm" style={{ margin: 0 }}>Ajouter un amendement</p>
                <input
                  className="field-input"
                  placeholder="Dr. Nom Prénom (auteur de l'amendement)"
                  value={amendAuthor}
                  onInput={(e) => setAmendAuthor((e.target as HTMLInputElement).value)}
                  disabled={isSaving}
                />
                <textarea
                  className="field-textarea"
                  placeholder="Texte de l'amendement…"
                  value={amendText}
                  onInput={(e) => setAmendText((e.target as HTMLTextAreaElement).value)}
                  disabled={isSaving}
                  style={{ minHeight: 80 }}
                />
                <div style={{ display: "flex", gap: "var(--space-sm)" }}>
                  <button
                    type="button"
                    className="btn btn-outline"
                    style={{ fontSize: 13 }}
                    onClick={() => { setShowAmendForm(false); setAmendText(""); setAmendAuthor(""); }}
                    disabled={isSaving}
                  >
                    Annuler
                  </button>
                  <button
                    type="button"
                    className="btn btn-filled"
                    style={{ fontSize: 13 }}
                    onClick={handleAmend}
                    disabled={isSaving || !amendText.trim()}
                  >
                    {isSaving ? "Enregistrement…" : "Enregistrer l'amendement"}
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
                    const st = line.status;
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
                          <button
                            type="button"
                            onClick={() => handleCloseLine(ord.id, li, st)}
                            disabled={isSaving}
                            aria-label={`Clôturer ${line.medication}`}
                            style={{
                              flexShrink: 0,
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
                            Clôturer
                          </button>
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
            <div style={{ display: "flex", flexWrap: "wrap", gap: "var(--space-sm)", alignItems: "flex-start" }}>
              {c.media.filter((m) => m.mime.startsWith("audio/")).map((m) => (
                <div key={m.mediaId} style={{ display: "flex", alignItems: "center", gap: 6, padding: "6px 12px", background: "var(--color-neutral-100)", borderRadius: "var(--radius-sm)" }}>
                  <Icon name="mic" size={14} color="var(--color-neutral-600)" />
                  <p className="text-caption" style={{ margin: 0 }}>Note vocale</p>
                </div>
              ))}
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
