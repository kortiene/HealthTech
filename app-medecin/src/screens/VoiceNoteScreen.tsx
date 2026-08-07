import { useEffect, useRef, useState } from "preact/hooks";
import { AppBar } from "../components/AppBar";
import { Icon } from "../components/Icon";
import { SnackBar } from "../components/SnackBar";
import type { MediaDescriptor } from "../stubs/data";

export interface NewVoiceConsultation {
  doctorName: string;
  summary: string;
  media: MediaDescriptor[];
}

export interface VoiceNoteScreenProps {
  backendUrl: string;
  writeToken?: string;
  onSaved: (consultation: NewVoiceConsultation) => Promise<void>;
  onCancel: () => void;
}

type Phase = "idle" | "recording" | "preview";

function formatDuration(ms: number): string {
  const totalSec = Math.floor(ms / 1000);
  const min = Math.floor(totalSec / 60);
  const sec = totalSec % 60;
  return `${min}:${String(sec).padStart(2, "0")}`;
}

export function VoiceNoteScreen({
  backendUrl,
  writeToken,
  onSaved,
  onCancel,
}: VoiceNoteScreenProps) {
  const [doctorName, setDoctorName] = useState("");
  const [phase, setPhase] = useState<Phase>("idle");
  const [durationMs, setDurationMs] = useState(0);
  const [audioUrl, setAudioUrl] = useState<string | null>(null);
  const [audioBlob, setAudioBlob] = useState<Blob | null>(null);
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

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

  async function handleSave() {
    if (!audioBlob || !doctorName.trim() || isSaving) return;
    setIsSaving(true);
    setError(null);

    try {
      const plainBytes = new Uint8Array(await audioBlob.arrayBuffer());

      // SHA-256 of plaintext — independent integrity check on top of GCM tag (#23)
      const hashBuffer = await crypto.subtle.digest("SHA-256", plainBytes);
      const contentHash = btoa(
        String.fromCharCode(...new Uint8Array(hashBuffer)),
      );

      // XOR 0x5A stub encrypt — WASM AES-256-GCM when #17 lands
      const encrypted = new Uint8Array(plainBytes.length);
      for (let i = 0; i < plainBytes.length; i++)
        encrypted[i] = plainBytes[i] ^ 0x5a;

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

      await onSaved({
        doctorName: doctorName.trim(),
        summary: "Note vocale — enregistrement joint",
        media: [
          {
            mediaId,
            url: `${backendUrl}/media/${mediaId}`,
            mime: audioBlob.type || "audio/webm",
            durationMs,
            // 32 zero bytes — real per-media key when WASM crypto-core lands (#17)
            contentKey: btoa(String.fromCharCode(...new Uint8Array(32))),
            contentHash,
          },
        ],
      });
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "Erreur inconnue — réessayez.",
      );
      setIsSaving(false);
    }
  }

  return (
    <div style={{ minHeight: "100%", background: "var(--color-neutral-50)" }}>
      <AppBar title="Note vocale">
        <button
          type="button"
          onClick={onCancel}
          aria-label="Fermer"
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            width: 36,
            height: 36,
            borderRadius: "50%",
            border: "none",
            background: "transparent",
            cursor: "pointer",
          }}
        >
          <Icon name="close" size={22} color="var(--color-neutral-700)" />
        </button>
      </AppBar>

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
        {/* ── Doctor name field ── */}
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

        {/* ── Phase: idle ── */}
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
            <p
              className="text-caption"
              style={{ color: "var(--color-neutral-500)", margin: 0 }}
            >
              Appuyer pour enregistrer
            </p>
          </div>
        )}

        {/* ── Phase: recording ── */}
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
              <span className="text-headline" style={{ fontVariantNumeric: "tabular-nums" }}>
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
            <p
              className="text-caption"
              style={{ color: "var(--color-neutral-500)", margin: 0 }}
            >
              Appuyer pour arrêter
            </p>
          </div>
        )}

        {/* ── Phase: preview ── */}
        {phase === "preview" && audioUrl && (
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              gap: "var(--space-md)",
            }}
          >
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
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: "var(--space-sm)",
                }}
              >
                <Icon name="mic" size={18} color="var(--color-primary-700)" />
                <p
                  className="text-caption"
                  style={{ margin: 0, color: "var(--color-neutral-500)" }}
                >
                  {formatDuration(durationMs)} · aperçu
                </p>
              </div>
              {/* Native audio element — plays the local blob before upload */}
              {/* eslint-disable-next-line jsx-a11y/media-has-caption */}
              <audio
                controls
                src={audioUrl}
                style={{ width: "100%", height: 36 }}
              />
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
                onClick={handleSave}
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

      {error && (
        <SnackBar
          message={error}
          tone="error"
          onDismiss={() => setError(null)}
        />
      )}

      {/* Pulsing animation for recording indicator */}
      <style>{`
        @keyframes ht-rec-pulse {
          0%, 100% { opacity: 1; }
          50%       { opacity: 0.3; }
        }
      `}</style>
    </div>
  );
}
