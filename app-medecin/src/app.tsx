import { useState } from "preact/hooks";
import { ScanScreen, type QrPayload } from "./screens/ScanScreen";
import { RecordScreen } from "./screens/RecordScreen";
import { NoteChoiceScreen } from "./screens/NoteChoiceScreen";
import { EditScreen, type NewConsultation } from "./screens/EditScreen";
import {
  VoiceNoteScreen,
  type NewVoiceConsultation,
} from "./screens/VoiceNoteScreen";
import { type MedicalRecord } from "./stubs/data";

type Screen = "scan" | "record" | "note-choice" | "edit" | "voice-note";

function xorBytes(data: Uint8Array): Uint8Array {
  const out = new Uint8Array(data.length);
  for (let i = 0; i < data.length; i++) out[i] = data[i] ^ 0x5a;
  return out;
}

export function App() {
  const [screen, setScreen] = useState<Screen>("scan");
  const [pendingCount, setPendingCount] = useState(0);
  const [scannedRecord, setScannedRecord] = useState<MedicalRecord | null>(null);
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const [rawFlutter, setRawFlutter] = useState<any>(null);
  const [qrPayload, setQrPayload] = useState<QrPayload | null>(null);

  async function handleConsultationSaved(consultation: NewConsultation): Promise<void> {
    if (!qrPayload || !rawFlutter) throw new Error("Session expirée — rescannez le QR.");

    const newEntry = {
      id: crypto.randomUUID(),
      date: new Date().toISOString().slice(0, 10),
      practitioner_ref: consultation.doctorName || "",
      summary: consultation.summary,
      ...(consultation.ordonnances.length > 0
        ? { ordonnances: consultation.ordonnances }
        : {}),
    };

    const newAllergiesFlutter = consultation.newAllergies.map((a) => ({
      substance: a.substance,
      severity: a.severity,
      noted_at: new Date().toISOString().slice(0, 10),
    }));

    const updatedRaw = {
      ...rawFlutter,
      consultations: [...(rawFlutter.consultations ?? []), newEntry],
      treatments: [
        ...(rawFlutter.treatments ?? []),
        ...(consultation.newTreatment ? [consultation.newTreatment] : []),
      ],
      allergies: [...(rawFlutter.allergies ?? []), ...newAllergiesFlutter],
      updated_at: new Date().toISOString(),
    };

    // XOR 0x5A re-encrypt and PUT back to backend.
    // Use the write token (wt) as the Bearer — the backend enforces read-only
    // sessions by rejecting PUTs when wt is absent (#118).
    const encrypted = xorBytes(new TextEncoder().encode(JSON.stringify(updatedRaw)));
    const res = await fetch(`${qrPayload.url}/blob/${qrPayload.uuid}`, {
      method: "PUT",
      headers: {
        "Content-Type": "application/octet-stream",
        ...(qrPayload.wt ? { Authorization: `Bearer ${qrPayload.wt}` } : {}),
      },
      body: encrypted.buffer as ArrayBuffer,
    });

    if (!res.ok) {
      throw new Error(
        res.status >= 500
          ? "Serveur indisponible — réessayez."
          : "Échec de l'enregistrement — réessayez.",
      );
    }

    setRawFlutter(updatedRaw);
    setScannedRecord((prev) =>
      prev
        ? {
            ...prev,
            consultations: [
              ...prev.consultations,
              {
                date: newEntry.date,
                doctorName: consultation.doctorName || undefined,
                summary: consultation.summary,
                ...(consultation.ordonnances.length > 0
                  ? { ordonnances: consultation.ordonnances }
                  : {}),
              },
            ],
            treatments: [
              ...prev.treatments,
              ...(consultation.newTreatment ? [consultation.newTreatment] : []),
            ],
            allergies: [
              ...prev.allergies,
              ...consultation.newAllergies.map((a) => ({
                substance: a.substance,
                severity:
                  a.severity === "severe"
                    ? "sévère"
                    : a.severity === "moderate"
                      ? "modérée"
                      : "légère",
                notedAt: new Date().toISOString().slice(0, 10),
              })),
            ],
          }
        : prev,
    );
    setPendingCount((n) => n + 1);
    setScreen("record");
  }

  async function handleVoiceConsultationSaved(
    consultation: NewVoiceConsultation,
  ): Promise<void> {
    if (!qrPayload || !rawFlutter) throw new Error("Session expirée — rescannez le QR.");

    const addedAt = new Date().toISOString();
    const newEntry = {
      id: crypto.randomUUID(),
      date: addedAt.slice(0, 10),
      practitioner_ref: consultation.doctorName,
      summary: consultation.summary,
      // Snake_case keys match Flutter MediaDescriptor.fromJson expectations.
      // url is preserved so the patient app can fetch without minting an ephemeral
      // access URL (dev only — prod uses MediaClient.requestAccess, TODO #17).
      media: consultation.media.map((m) => ({
        uuid: m.mediaId,
        url: m.url,
        content_key: m.contentKey,
        content_hash: m.contentHash,
        alg: "A256GCM",
        mime: m.mime,
        size_bytes: m.sizeBytes ?? 0,
        added_at: addedAt,
        ...(m.durationMs !== undefined ? { duration_ms: m.durationMs } : {}),
      })),
    };

    const updatedRaw = {
      ...rawFlutter,
      consultations: [...(rawFlutter.consultations ?? []), newEntry],
      updated_at: new Date().toISOString(),
    };

    // PUT updated blob (media is already on /media endpoint; this blob carries the reference)
    const encrypted = xorBytes(new TextEncoder().encode(JSON.stringify(updatedRaw)));
    const res = await fetch(`${qrPayload.url}/blob/${qrPayload.uuid}`, {
      method: "PUT",
      headers: {
        "Content-Type": "application/octet-stream",
        ...(qrPayload.wt ? { Authorization: `Bearer ${qrPayload.wt}` } : {}),
      },
      body: encrypted.buffer as ArrayBuffer,
    });

    if (!res.ok) {
      throw new Error(
        res.status >= 500
          ? "Serveur indisponible — réessayez."
          : "Échec de l'enregistrement — réessayez.",
      );
    }

    setRawFlutter(updatedRaw);
    setScannedRecord((prev) =>
      prev
        ? {
            ...prev,
            consultations: [
              ...prev.consultations,
              {
                date: newEntry.date,
                doctorName: consultation.doctorName,
                summary: consultation.summary,
                media: consultation.media,
              },
            ],
          }
        : prev,
    );
    setPendingCount((n) => n + 1);
    setScreen("record");
  }

  if (screen === "scan") {
    return (
      <ScanScreen
        onScanned={(record, raw, payload) => {
          setScannedRecord(record);
          setRawFlutter(raw);
          setQrPayload(payload);
          setPendingCount(0);
          setScreen("record");
        }}
      />
    );
  }

  if (screen === "note-choice") {
    return (
      <NoteChoiceScreen
        onWritten={() => setScreen("edit")}
        onVoice={() => setScreen("voice-note")}
        onCancel={() => setScreen("record")}
      />
    );
  }

  if (screen === "edit") {
    return (
      <EditScreen
        record={scannedRecord!}
        onSaved={handleConsultationSaved}
        onCancel={() => setScreen("note-choice")}
      />
    );
  }

  if (screen === "voice-note") {
    return (
      <VoiceNoteScreen
        backendUrl={qrPayload?.url ?? ""}
        writeToken={qrPayload?.wt}
        onSaved={handleVoiceConsultationSaved}
        onCancel={() => setScreen("note-choice")}
      />
    );
  }

  return (
    <RecordScreen
      record={scannedRecord}
      pendingCount={pendingCount}
      readOnly={!qrPayload?.wt}
      onSynced={() => setPendingCount(0)}
      onAddNote={() => setScreen("note-choice")}
      onTerminated={() => {
        setPendingCount(0);
        setScannedRecord(null);
        setRawFlutter(null);
        setQrPayload(null);
        setScreen("scan");
      }}
    />
  );
}
