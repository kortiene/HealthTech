import { useEffect, useRef, useState } from "preact/hooks";
import jsQR from "jsqr";
import { Icon } from "../components/Icon";
import { SnackBar, type SnackBarTone } from "../components/SnackBar";
import { Spinner } from "../components/Spinner";
import { parseFlutterRecord, type MedicalRecord } from "../stubs/data";

type ScanError = "expired" | "serverDown" | "decryptError" | "cameraError";

export interface QrPayload {
  v: number;
  uuid: string;
  url: string;
  key: string;
  exp?: number;
}

export interface ScanScreenProps {
  onScanned: (record: MedicalRecord, raw: unknown, payload: QrPayload) => void;
}

const ERROR_MESSAGES: Record<ScanError, string> = {
  expired: "QR expiré — demandez un nouveau code au patient",
  serverDown: "Serveur indisponible — vérifiez la connexion",
  decryptError: "Erreur de déchiffrement — QR invalide",
  cameraError: "Impossible d'accéder à la caméra — autorisez dans les paramètres du navigateur",
};

const SCAN_SIZE = "min(260px, 72vw)";

const CORNERS = [
  { top: -1, left: -1, borderTopWidth: 3, borderLeftWidth: 3, borderRightWidth: 0, borderBottomWidth: 0, borderTopLeftRadius: 6 },
  { top: -1, right: -1, borderTopWidth: 3, borderRightWidth: 3, borderLeftWidth: 0, borderBottomWidth: 0, borderTopRightRadius: 6 },
  { bottom: -1, left: -1, borderBottomWidth: 3, borderLeftWidth: 3, borderTopWidth: 0, borderRightWidth: 0, borderBottomLeftRadius: 6 },
  { bottom: -1, right: -1, borderBottomWidth: 3, borderRightWidth: 3, borderTopWidth: 0, borderLeftWidth: 0, borderBottomRightRadius: 6 },
] as const;

function xorBytes(data: Uint8Array): Uint8Array {
  const out = new Uint8Array(data.length);
  for (let i = 0; i < data.length; i++) out[i] = data[i] ^ 0x5a;
  return out;
}

export function ScanScreen({ onScanned }: ScanScreenProps) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const scanningRef = useRef(false);
  const intervalRef = useRef<number | null>(null);

  const [processing, setProcessing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [cameraReady, setCameraReady] = useState(false);

  useEffect(() => {
    const id = "ht-scan-kf";
    if (!document.getElementById(id)) {
      const s = document.createElement("style");
      s.id = id;
      s.textContent = `
        @keyframes ht-scan-line {
          0%   { top: 4px; opacity: 0; }
          10%  { opacity: 1; }
          90%  { opacity: 1; }
          100% { top: calc(100% - 6px); opacity: 0; }
        }
        @keyframes ht-corner-pulse {
          0%, 100% { opacity: 0.6; }
          50%       { opacity: 1; }
        }
      `;
      document.head.appendChild(s);
    }
    startCamera();
    return () => stopCamera();
  }, []);

  async function startCamera() {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: "environment" },
        audio: false,
      });
      streamRef.current = stream;
      const video = videoRef.current;
      if (video) {
        video.srcObject = stream;
        await video.play();
        setCameraReady(true);
        startScanLoop();
      }
    } catch {
      setError(ERROR_MESSAGES.cameraError);
    }
  }

  function stopCamera() {
    if (intervalRef.current !== null) clearInterval(intervalRef.current);
    streamRef.current?.getTracks().forEach((t) => t.stop());
    streamRef.current = null;
    scanningRef.current = false;
  }

  function startScanLoop() {
    intervalRef.current = window.setInterval(() => {
      if (scanningRef.current) return;
      const video = videoRef.current;
      const canvas = canvasRef.current;
      if (!video || !canvas || video.readyState < 2) return;
      const w = video.videoWidth;
      const h = video.videoHeight;
      if (!w || !h) return;
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext("2d");
      if (!ctx) return;
      ctx.drawImage(video, 0, 0, w, h);
      const imageData = ctx.getImageData(0, 0, w, h);
      const code = jsQR(imageData.data, w, h);
      if (code) {
        scanningRef.current = true;
        handleQrData(code.data);
      }
    }, 100);
  }

  async function handleQrData(raw: string) {
    setError(null);
    setProcessing(true);
    try {
      let payload: QrPayload;
      try {
        payload = JSON.parse(raw) as QrPayload;
      } catch {
        throw new Error("decryptError");
      }

      if (payload.v !== 1 || !payload.uuid || !payload.url) {
        throw new Error("decryptError");
      }
      if (payload.exp && payload.exp * 1000 < Date.now()) {
        throw new Error("expired");
      }

      let res: Response;
      try {
        res = await fetch(`${payload.url}/blob/${payload.uuid}`, {
          headers: { Authorization: `Bearer ${payload.key}` },
        });
      } catch {
        throw new Error("serverDown");
      }

      if (res.status === 404 || res.status === 410) throw new Error("expired");
      if (!res.ok) throw new Error("serverDown");

      const buf = await res.arrayBuffer();
      const decrypted = xorBytes(new Uint8Array(buf));
      const text = new TextDecoder().decode(decrypted);

      let recordRaw: unknown;
      try {
        recordRaw = JSON.parse(text);
      } catch {
        throw new Error("decryptError");
      }

      const record = parseFlutterRecord(recordRaw);
      setProcessing(false);
      onScanned(record, recordRaw, payload);
    } catch (err) {
      setProcessing(false);
      scanningRef.current = false;
      const key = (err instanceof Error ? err.message : "") as ScanError;
      setError(ERROR_MESSAGES[key] ?? ERROR_MESSAGES.decryptError);
    }
  }

  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        background: "#080e0d",
        display: "flex",
        flexDirection: "column",
        color: "var(--color-white)",
      }}
    >
      {/* Header */}
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: "var(--space-sm)",
          padding: "var(--space-md)",
          paddingTop: "max(var(--space-md), env(safe-area-inset-top))",
        }}
      >
        <div
          style={{
            width: 36,
            height: 36,
            background: "var(--color-primary-700)",
            borderRadius: "var(--radius-sm)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            flexShrink: 0,
          }}
        >
          <Icon name="medical_services" size={20} color="white" />
        </div>
        <div>
          <h1 className="text-title" style={{ color: "var(--color-white)", lineHeight: 1.2 }}>
            HealthTech Médecin
          </h1>
          <p className="text-caption" style={{ color: "rgba(255,255,255,0.45)", margin: 0 }}>
            Scanner le QR du patient
          </p>
        </div>
      </div>

      {/* Main scan area */}
      <div
        style={{
          flex: 1,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          gap: "var(--space-lg)",
          padding: "0 var(--space-lg)",
        }}
      >
        {/* Scan frame */}
        <div style={{ position: "relative", width: SCAN_SIZE, aspectRatio: "1" }}>
          {/* Corner brackets */}
          {CORNERS.map((c, i) => (
            <div
              key={i}
              style={{
                position: "absolute",
                width: 28,
                height: 28,
                borderStyle: "solid",
                borderColor: "var(--color-primary-500)",
                animation: "ht-corner-pulse 2.4s ease-in-out infinite",
                animationDelay: `${i * 0.15}s`,
                zIndex: 2,
                ...c,
              }}
            />
          ))}

          {/* Live camera feed */}
          <video
            ref={videoRef}
            autoPlay
            playsInline
            muted
            style={{
              position: "absolute",
              inset: 0,
              width: "100%",
              height: "100%",
              objectFit: "cover",
              borderRadius: 4,
              display: cameraReady ? "block" : "none",
            }}
          />
          <canvas ref={canvasRef} style={{ display: "none" }} />

          {/* Placeholder when camera not yet ready */}
          {!cameraReady && (
            <div
              style={{
                position: "absolute",
                inset: 0,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                borderRadius: 4,
              }}
            >
              <Icon name="qr_code_scanner" size={72} color="rgba(255,255,255,0.08)" />
            </div>
          )}

          {/* Processing overlay */}
          {processing && (
            <div
              style={{
                position: "absolute",
                inset: 0,
                background: "rgba(0,0,0,0.65)",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                borderRadius: 4,
                zIndex: 3,
              }}
            >
              <Spinner color="var(--color-primary-500)" />
            </div>
          )}

          {/* Scan line */}
          {cameraReady && !processing && (
            <div
              style={{
                position: "absolute",
                left: 10,
                right: 10,
                height: 2,
                background:
                  "linear-gradient(90deg, transparent, var(--color-primary-500), transparent)",
                boxShadow: "0 0 8px var(--color-primary-500)",
                animation: "ht-scan-line 2s ease-in-out infinite",
                zIndex: 2,
              }}
            />
          )}
        </div>

        {/* Status text */}
        {processing ? (
          <p
            className="text-body"
            style={{ color: "var(--color-primary-500)", textAlign: "center" }}
          >
            Chargement du dossier…
          </p>
        ) : (
          <p
            className="text-body"
            style={{ color: "rgba(255,255,255,0.45)", textAlign: "center", maxWidth: 240 }}
          >
            {cameraReady
              ? "Cadrez le QR présenté par le patient dans le cadre"
              : "Initialisation de la caméra…"}
          </p>
        )}
      </div>

      {error && (
        <SnackBar
          message={error}
          tone={"error" as SnackBarTone}
          onDismiss={() => {
            setError(null);
            scanningRef.current = false;
          }}
        />
      )}
    </div>
  );
}
