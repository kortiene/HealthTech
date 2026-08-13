import { useEffect, useRef, useState } from "preact/hooks";
import { AllergySectionCard } from "../components/AllergySectionCard";
import { AppBar } from "../components/AppBar";
import { Icon } from "../components/Icon";
import { SectionCard } from "../components/SectionCard";
import { SnackBar, type SnackBarTone } from "../components/SnackBar";
import { Spinner } from "../components/Spinner";
import { SyncBadge } from "../components/SyncBadge";
import { TerminateButton } from "../components/TerminateButton";
import { IDLE_TIMEOUT_MS, WARN_BEFORE_MS, formatCountdown } from "../session";
import {
  formatDateFr,
  previewRecord,
  type ChronicCondition,
  type Consultation,
  type MedicalRecord,
  type MediaDescriptor,
  type Medication,
} from "../stubs/data";
import { TerminatingOverlay } from "./TerminatingOverlay";

interface RecordScreenProps {
  record: MedicalRecord | null;
  pendingCount: number;
  /** True when the QR was shared in read-only mode — doctor cannot add notes (#118). */
  readOnly?: boolean;
  onSynced: () => void;
  onAddNote: () => void;
  onTerminated: () => void;
  /** Backend origin used to fetch image media at /media/{uuid} (XOR-0x5A in dev). */
  backendUrl?: string;
}

// ─── Patient hero banner ──────────────────────────────────────────────────────

function PatientHeroBanner({ record }: { record: MedicalRecord }) {
  const age = new Date().getFullYear() - record.birthYear;
  const hasSevereAllergy = record.allergies.some((a) =>
    a.severity.toLowerCase().includes("sév"),
  );

  return (
    <div
      style={{
        background:
          "linear-gradient(135deg, var(--color-primary-900) 0%, var(--color-primary-700) 100%)",
        padding: "var(--space-lg) var(--space-md) var(--space-md)",
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: "var(--space-md)",
          marginBottom: "var(--space-md)",
        }}
      >
        <div
          style={{
            width: 52,
            height: 52,
            borderRadius: "50%",
            background: "rgba(255,255,255,0.12)",
            border: "2px solid rgba(255,255,255,0.3)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            fontSize: 22,
            fontWeight: 700,
            color: "white",
            flexShrink: 0,
          }}
        >
          {record.givenName[0]?.toUpperCase()}
        </div>
        <div>
          <p
            className="text-headline"
            style={{ color: "var(--color-white)", fontWeight: 700 }}
          >
            {record.givenName}
          </p>
          <p
            className="text-body"
            style={{ color: "rgba(255,255,255,0.6)", margin: "2px 0 0" }}
          >
            {age} ans · {record.sex}
          </p>
        </div>
      </div>

      <div
        style={{ display: "flex", flexWrap: "wrap", gap: "var(--space-xs)" }}
      >
        <HeroChip label={record.bloodType} accent="blood" />
        {record.heightCm != null && (
          <HeroChip label={`${record.heightCm} cm`} />
        )}
        {record.weightKg != null && (
          <HeroChip label={`${record.weightKg} kg`} />
        )}
        {record.cmuNumber != null && (
          <HeroChip label="CMU ✓" accent="success" />
        )}
        {hasSevereAllergy && (
          <HeroChip label="Allergie sévère" accent="allergy" />
        )}
      </div>
    </div>
  );
}

type ChipAccent = "default" | "blood" | "success" | "allergy";

function HeroChip({
  label,
  accent = "default",
}: {
  label: string;
  accent?: ChipAccent;
}) {
  const styles: Record<ChipAccent, { bg: string; color: string }> = {
    default: { bg: "rgba(255,255,255,0.12)", color: "rgba(255,255,255,0.85)" },
    blood: { bg: "rgba(220,38,38,0.28)", color: "#fca5a5" },
    success: { bg: "rgba(5,150,105,0.28)", color: "#6ee7b7" },
    allergy: { bg: "rgba(185,28,28,0.28)", color: "#fca5a5" },
  };
  const s = styles[accent];
  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        padding: "5px 12px",
        borderRadius: "var(--radius-pill)",
        background: s.bg,
        color: s.color,
        fontSize: 12,
        fontWeight: 600,
        lineHeight: 1,
      }}
    >
      {label}
    </span>
  );
}

// ─── Pathologies ─────────────────────────────────────────────────────────────

const SEVERITY_LABEL: Record<number, string> = {
  1: "Légère",
  2: "Modérée",
  3: "Importante",
  4: "Sévère",
  5: "Critique",
};
const SEVERITY_COLOR: Record<number, string> = {
  1: "#059669",
  2: "#84CC16",
  3: "#F59E0B",
  4: "#F97316",
  5: "#DC2626",
};

function ConditionRow({ condition }: { condition: ChronicCondition }) {
  const sev = condition.severity;
  const docCount = condition.documents?.length ?? 0;
  const sevColor = sev !== undefined ? (SEVERITY_COLOR[sev] ?? "#6B7280") : undefined;
  return (
    <div
      style={{
        display: "flex",
        alignItems: "flex-start",
        gap: "var(--space-sm)",
        padding: "10px var(--space-sm)",
        borderLeft: "3px solid var(--color-primary-500)",
        background: "var(--color-primary-50)",
        borderRadius: "0 var(--radius-sm) var(--radius-sm) 0",
        marginBottom: "var(--space-xs)",
      }}
    >
      {/* Gauche : nom + since */}
      <div style={{ flex: 1, minWidth: 0 }}>
        <p className="text-body-lg" style={{ margin: 0, fontWeight: 500 }}>
          {condition.name}
        </p>
        {condition.since && (
          <p style={{ margin: 0, fontSize: 12, color: "var(--color-neutral-500)" }}>
            Depuis {condition.since}
          </p>
        )}
      </div>
      {/* Droite : badges empilés verticalement */}
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          alignItems: "flex-end",
          gap: 4,
          flexShrink: 0,
        }}
      >
        {condition.icd10 && (
          <span
            style={{
              padding: "2px 8px",
              borderRadius: "var(--radius-pill)",
              background: "var(--color-neutral-100)",
              border: "1px solid var(--color-neutral-200)",
              fontSize: 11,
              fontWeight: 700,
              color: "var(--color-neutral-500)",
              fontFamily: "monospace",
              letterSpacing: "0.04em",
            }}
          >
            {condition.icd10}
          </span>
        )}
        {sevColor !== undefined && (
          <span
            style={{
              padding: "2px 8px",
              borderRadius: "var(--radius-pill)",
              background: sevColor + "1A",
              border: `1px solid ${sevColor}`,
              fontSize: 11,
              fontWeight: 700,
              color: sevColor,
            }}
          >
            {SEVERITY_LABEL[sev!] ?? `Sév. ${sev}`}
          </span>
        )}
        {docCount > 0 && (
          <span
            style={{
              padding: "2px 7px",
              borderRadius: "var(--radius-pill)",
              background: "var(--color-neutral-100)",
              border: "1px solid var(--color-neutral-200)",
              fontSize: 11,
              fontWeight: 600,
              color: "var(--color-neutral-500)",
            }}
          >
            📎 {docCount}
          </span>
        )}
      </div>
    </div>
  );
}

// ─── Médicaments ─────────────────────────────────────────────────────────────

function MedicationCard({ med }: { med: Medication }) {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        gap: "var(--space-sm)",
        padding: "var(--space-sm)",
        background: "var(--color-neutral-100)",
        borderRadius: "var(--radius-sm)",
        marginBottom: "var(--space-xs)",
      }}
    >
      <div
        style={{
          width: 38,
          height: 38,
          background: "var(--color-primary-100)",
          borderRadius: "var(--radius-sm)",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          flexShrink: 0,
        }}
      >
        <Icon name="medication" size={20} color="var(--color-primary-700)" />
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <p
          className="text-body-lg"
          style={{
            fontWeight: 600,
            color: "var(--color-neutral-900)",
            margin: 0,
          }}
        >
          {med.name}
        </p>
        <p
          className="text-caption"
          style={{ color: "var(--color-neutral-500)", margin: "2px 0 0" }}
        >
          {med.frequency}
        </p>
      </div>
      <span
        style={{
          padding: "4px 10px",
          background: "var(--color-white)",
          border: "1px solid var(--color-neutral-200)",
          borderRadius: "var(--radius-pill)",
          fontSize: 12,
          fontWeight: 600,
          color: "var(--color-primary-700)",
          whiteSpace: "nowrap",
          flexShrink: 0,
        }}
      >
        {med.dose}
      </span>
    </div>
  );
}

// ─── Media image strip (justificatifs) ───────────────────────────────────────

function MediaImageTile({ media, backendUrl }: { media: MediaDescriptor; backendUrl: string }) {
  const [objectUrl, setObjectUrl] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);
  const blobRef = useRef<string | null>(null);

  useEffect(() => {
    let active = true;
    // Two-step: POST /media/{uuid}/access → signed capability URL → GET bytes.
    // Direct GET /media/{uuid} requires ?exp=…&sig=… (ADR 0005); the access
    // endpoint mints a short-TTL signed URL without extra auth.
    fetch(`${backendUrl}/media/${media.mediaId}/access`, { method: "POST" })
      .then((r) => { if (!r.ok) throw new Error(`access:${r.status}`); return r.json(); })
      .then((grant: { url: string }) => {
        const capUrl = grant.url.startsWith("http")
          ? grant.url
          : `${backendUrl}${grant.url}`;
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

  const tileStyle = {
    width: 72,
    height: 72,
    borderRadius: "var(--radius-sm)",
    flexShrink: 0,
    overflow: "hidden" as const,
    background: "var(--color-neutral-100)",
    display: "flex",
    alignItems: "center",
    justifyContent: "center",
  };

  if (failed) {
    return (
      <div style={tileStyle}>
        <Icon name="broken_image" size={24} color="var(--color-neutral-400)" />
      </div>
    );
  }
  if (!objectUrl) {
    return (
      <div style={tileStyle}>
        <Spinner size={20} color="var(--color-neutral-400)" />
      </div>
    );
  }
  return (
    <div
      style={{ ...tileStyle, cursor: "pointer" }}
      onClick={() => window.open(objectUrl, "_blank")}
    >
      <img
        src={objectUrl}
        alt="justificatif"
        style={{ width: "100%", height: "100%", objectFit: "cover" }}
      />
    </div>
  );
}

// ─── Consultations timeline ───────────────────────────────────────────────────

function ConsultationTimeline({
  consultations,
  backendUrl,
}: {
  consultations: Consultation[];
  backendUrl?: string;
}) {
  const sorted = [...consultations].sort(
    (a, b) => new Date(b.date).getTime() - new Date(a.date).getTime(),
  );
  const last = sorted.length - 1;

  return (
    <section style={{ marginBottom: "var(--space-md)" }}>
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: "var(--space-sm)",
          marginBottom: "var(--space-md)",
        }}
      >
        <span
          className="icon-badge"
          style={{ background: "var(--color-primary-100)" }}
        >
          <Icon
            name="folder_shared"
            size={18}
            color="var(--color-primary-700)"
          />
        </span>
        <h2 className="text-title-sm">Consultations</h2>
        <span
          style={{
            marginLeft: "auto",
            padding: "2px 8px",
            borderRadius: "var(--radius-pill)",
            background: "var(--color-primary-100)",
            color: "var(--color-primary-700)",
            fontSize: 12,
            fontWeight: 700,
          }}
        >
          {sorted.length}
        </span>
      </div>

      {sorted.map((c, i) => (
        <div key={c.date + c.summary} style={{ display: "flex", gap: 12 }}>
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              width: 20,
              flexShrink: 0,
            }}
          >
            <div
              style={{
                width: 12,
                height: 12,
                borderRadius: "50%",
                background:
                  i === 0
                    ? "var(--color-primary-700)"
                    : "var(--color-neutral-200)",
                boxShadow:
                  i === 0 ? "0 0 0 3px var(--color-primary-100)" : "none",
                flexShrink: 0,
                marginTop: 6,
              }}
            />
            {i < last && (
              <div
                style={{
                  width: 2,
                  flex: 1,
                  background: "var(--color-neutral-200)",
                  margin: "4px 0 0",
                  minHeight: 16,
                }}
              />
            )}
          </div>

          <div
            style={{
              flex: 1,
              background: "var(--color-white)",
              border: "1px solid var(--color-neutral-200)",
              borderRadius: "var(--radius-sm)",
              padding: "var(--space-sm) var(--space-md)",
              marginBottom: "var(--space-sm)",
            }}
          >
            <p
              className="text-label"
              style={{
                color: "var(--color-primary-700)",
                marginBottom: 4,
                fontWeight: 600,
              }}
            >
              {formatDateFr(c.date)}
              {c.doctorName && (
                <span
                  style={{ color: "var(--color-neutral-500)", fontWeight: 400 }}
                >
                  {" "}
                  · {c.doctorName}
                </span>
              )}
            </p>
            <p
              className="text-body"
              style={{ color: "var(--color-neutral-900)", margin: "0 0 4px" }}
            >
              {c.summary}
            </p>
            {c.prescription && (
              <div
                style={{
                  marginTop: "var(--space-xs)",
                  padding: "6px 10px",
                  background: "var(--color-primary-50)",
                  borderRadius: "var(--radius-sm)",
                  display: "flex",
                  gap: 6,
                  alignItems: "flex-start",
                }}
              >
                <Icon
                  name="medication"
                  size={13}
                  color="var(--color-primary-700)"
                />
                <p
                  className="text-caption"
                  style={{
                    color: "var(--color-primary-900)",
                    margin: 0,
                    lineHeight: 1.5,
                  }}
                >
                  {c.prescription}
                </p>
              </div>
            )}
            {c.media?.some((m) => m.mime.startsWith("audio/")) && (
              <div
                style={{
                  marginTop: "var(--space-xs)",
                  padding: "6px 10px",
                  background: "var(--color-neutral-100)",
                  borderRadius: "var(--radius-sm)",
                  display: "flex",
                  gap: 6,
                  alignItems: "center",
                }}
              >
                <Icon name="mic" size={13} color="var(--color-neutral-600)" />
                <p
                  className="text-caption"
                  style={{ color: "var(--color-neutral-600)", margin: 0 }}
                >
                  Note vocale jointe
                </p>
              </div>
            )}
            {backendUrl && c.media?.some((m) => m.mime.startsWith("image/")) && (
              <div
                style={{
                  marginTop: "var(--space-xs)",
                  display: "flex",
                  gap: 6,
                  flexWrap: "wrap",
                }}
              >
                {c.media
                  .filter((m) => m.mime.startsWith("image/"))
                  .map((m) => (
                    <MediaImageTile key={m.mediaId} media={m} backendUrl={backendUrl} />
                  ))}
              </div>
            )}
          </div>
        </div>
      ))}
    </section>
  );
}

// ─── Bannière d'avertissement de fermeture ────────────────────────────────────

/**
 * Bannière persistante fixée en haut, affichée `WARN_BEFORE_MS` avant la
 * fermeture automatique pour inactivité. Affiche un compte à rebours vivant et
 * un bouton « Prolonger ». Le compte à rebours est purement indicatif : la
 * fermeture autoritaire reste pilotée par `closeTimer` dans RecordScreen (pas
 * par l'intervalle ci-dessous), pour éviter toute dérive.
 */
function _SessionWarningBanner({
  remainingMs,
  onExtend,
}: {
  remainingMs: number;
  onExtend: () => void;
}) {
  const [remaining, setRemaining] = useState(remainingMs);

  useEffect(() => {
    setRemaining(remainingMs);
    const id = window.setInterval(() => {
      setRemaining((prev) => Math.max(0, prev - 1000));
    }, 1000);
    return () => window.clearInterval(id);
  }, [remainingMs]);

  return (
    <div
      role="alert"
      aria-live="assertive"
      style={{
        position: "fixed",
        top: 0,
        left: 0,
        right: 0,
        display: "flex",
        alignItems: "center",
        gap: "var(--space-sm)",
        padding: "var(--space-md)",
        background: "var(--color-accent-700)",
        color: "var(--color-white)",
        boxShadow: "0 8px 24px rgba(0,0,0,0.18)",
        zIndex: 60,
      }}
    >
      <Icon name="schedule" size={20} color="var(--color-white)" />
      <p
        className="text-body-lg"
        style={{ flex: 1, margin: 0, color: "var(--color-white)" }}
      >
        Votre session se fermera dans {formatCountdown(remaining)} faute
        d'activité.
      </p>
      <button
        type="button"
        onClick={onExtend}
        aria-label="Prolonger la session"
        style={{
          minHeight: "44px",
          padding: "0 var(--space-md)",
          borderRadius: "var(--radius-sm)",
          background: "var(--color-white)",
          color: "var(--color-accent-700)",
          border: "none",
          fontWeight: 700,
          cursor: "pointer",
          flexShrink: 0,
        }}
      >
        Prolonger
      </button>
    </div>
  );
}

// ─── RecordScreen ─────────────────────────────────────────────────────────────

/**
 * Écran Dossier médical. Ordre des sections figé (§3.2) :
 * Hero → Allergies → Pathologies → Médicaments → Consultations.
 */
export function RecordScreen({
  record: recordProp,
  pendingCount,
  readOnly = false,
  onSynced,
  onAddNote,
  onTerminated,
  backendUrl,
}: RecordScreenProps) {
  const record = recordProp ?? previewRecord;
  const [isSyncing, setIsSyncing] = useState(false);
  const [isTerminating, setIsTerminating] = useState(false);
  const [snack, setSnack] = useState<{
    message: string;
    tone: SnackBarTone;
  } | null>(null);
  const [isWarning, setIsWarning] = useState(false);
  const warnTimer = useRef<number | undefined>(undefined);
  const closeTimer = useRef<number | undefined>(undefined);

  /**
   * Canonical "I am active" signal — resets the two-phase idle timer and clears
   * any pre-close warning. Called on every scroll/click over the record, and by
   * the « Prolonger » button.
   *
   * #120 integration seam: when VoiceNoteScreen / MediaRecorder lands, the
   * recorder must call this on each `dataavailable` event (and on `start`) so an
   * active recording counts as activity and never auto-closes mid-recording.
   * Lift this into a shared session-activity hook or pass it down as `onActivity`.
   */
  function resetIdleTimer() {
    if (warnTimer.current) window.clearTimeout(warnTimer.current);
    if (closeTimer.current) window.clearTimeout(closeTimer.current);
    setIsWarning(false);
    warnTimer.current = window.setTimeout(
      () => setIsWarning(true),
      IDLE_TIMEOUT_MS - WARN_BEFORE_MS,
    );
    closeTimer.current = window.setTimeout(
      () => terminateSession(),
      IDLE_TIMEOUT_MS,
    );
  }

  useEffect(() => {
    resetIdleTimer();
    return () => {
      if (warnTimer.current) window.clearTimeout(warnTimer.current);
      if (closeTimer.current) window.clearTimeout(closeTimer.current);
    };
  }, []);

  async function syncNow() {
    if (pendingCount === 0 || isSyncing) return;
    setIsSyncing(true);
    try {
      await new Promise((r) => setTimeout(r, 1000));
      const synced = pendingCount;
      onSynced();
      setIsSyncing(false);
      setSnack({
        message: `${synced} consultation(s) synchronisée(s).`,
        tone: "success",
      });
    } catch {
      setIsSyncing(false);
      setSnack({
        message: "Échec de la synchronisation — nouvelle tentative en attente.",
        tone: "error",
      });
    }
  }

  async function terminateSession() {
    setIsTerminating(true);
    try {
      await new Promise((r) => setTimeout(r, 900));
      const offline = false;
      if (offline) {
        setIsTerminating(false);
        setSnack({
          message:
            "Consultation enregistrée hors-ligne — synchro à la reconnexion",
          tone: "warning",
        });
      } else {
        onTerminated();
      }
    } catch {
      setIsTerminating(false);
      setSnack({
        message: "Échec de l'enregistrement — réessayez.",
        tone: "error",
      });
    }
  }

  return (
    <div
      onScroll={resetIdleTimer}
      onClick={resetIdleTimer}
      style={{ minHeight: "100%", paddingBottom: "88px" }}
    >
      <AppBar title="Dossier médical" subtitle={record.givenName}>
        <SyncBadge
          pendingCount={pendingCount}
          isSyncing={isSyncing}
          onSync={syncNow}
        />
        <TerminateButton onTerminate={terminateSession} />
      </AppBar>

      {isWarning && !isTerminating && (
        <_SessionWarningBanner
          remainingMs={WARN_BEFORE_MS}
          onExtend={resetIdleTimer}
        />
      )}

      <PatientHeroBanner record={record} />

      {readOnly && (
        <div
          role="status"
          aria-label="Mode lecture seule — vous ne pouvez pas ajouter de note"
          style={{
            display: "flex",
            alignItems: "center",
            gap: "var(--space-sm)",
            padding: "10px var(--space-md)",
            background: "rgba(0,0,0,0.06)",
            borderBottom: "1px solid var(--color-neutral-200)",
          }}
        >
          <Icon name="lock" size={15} color="var(--color-neutral-500)" />
          <p
            className="text-caption"
            style={{
              margin: 0,
              color: "var(--color-neutral-500)",
              fontWeight: 600,
            }}
          >
            Mode lecture seule — aucune note ne peut être ajoutée
          </p>
        </div>
      )}

      <main style={{ padding: "var(--space-md)" }}>
        <AllergySectionCard allergies={record.allergies} />

        {record.chronicConditions.length > 0 && (
          <SectionCard title="Pathologies chroniques" icon="history">
            {[...record.chronicConditions]
              .sort((a, b) =>
                (b.addedAt ?? "").localeCompare(a.addedAt ?? ""),
              )
              .map((c) => (
                <ConditionRow key={c.icd10 || c.name} condition={c} />
              ))}
          </SectionCard>
        )}

        {record.medications.length > 0 && (
          <SectionCard title="Médicaments en cours" icon="medication">
            {record.medications.map((m) => (
              <MedicationCard key={m.name} med={m} />
            ))}
          </SectionCard>
        )}

        {record.consultations.length > 0 && (
          <ConsultationTimeline consultations={record.consultations} backendUrl={backendUrl} />
        )}
      </main>

      {!readOnly && (
        <button
          type="button"
          onClick={onAddNote}
          aria-label="Ajouter une note ou une ordonnance"
          style={{
            position: "fixed",
            right: "var(--space-md)",
            bottom: "var(--space-md)",
            display: "inline-flex",
            alignItems: "center",
            gap: "var(--space-sm)",
            minHeight: "56px",
            padding: "0 var(--space-lg)",
            borderRadius: "var(--radius-lg)",
            background: "var(--color-primary-700)",
            color: "var(--color-white)",
            border: "none",
            boxShadow: "0 8px 24px rgba(0,108,103,0.35)",
            fontWeight: 600,
            cursor: "pointer",
            fontSize: 15,
          }}
        >
          <Icon name="note_add" size={22} color="var(--color-white)" />
          Ajouter une note
        </button>
      )}

      {snack && (
        <SnackBar
          message={snack.message}
          tone={snack.tone}
          onDismiss={() => setSnack(null)}
        />
      )}
      {isTerminating && <TerminatingOverlay />}
    </div>
  );
}

// Exported for VNode/a11y unit tests only — not part of the public component API.
export { _SessionWarningBanner as SessionWarningBanner };
