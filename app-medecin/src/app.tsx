import { useState } from "preact/hooks";
import { ScanScreen, type QrPayload } from "./screens/ScanScreen";
import { RecordScreen } from "./screens/RecordScreen";
import { EditScreen, type NewConsultation } from "./screens/EditScreen";
import { type MedicalRecord } from "./stubs/data";

type Screen = "scan" | "record" | "edit";

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
      practitioner_ref: consultation.doctorName || '',
      summary: consultation.summary,
      ...(consultation.prescription ? { prescription: consultation.prescription } : {}),
    };

    const newAllergiesFlutter = consultation.newAllergies.map((a) => ({
      substance: a.substance,
      severity: a.severity,
      noted_at: new Date().toISOString().slice(0, 10),
    }));

    const updatedRaw = {
      ...rawFlutter,
      consultations: [...(rawFlutter.consultations ?? []), newEntry],
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
          : "Échec de l'enregistrement — réessayez."
      );
    }

    // Update in-memory state so RecordScreen reflects the new consultation immediately
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
                prescription: consultation.prescription,
              },
            ],
            allergies: [
              ...prev.allergies,
              ...consultation.newAllergies.map((a) => ({
                substance: a.substance,
                severity: a.severity === "severe" ? "sévère" : a.severity === "moderate" ? "modérée" : "légère",
                notedAt: new Date().toISOString().slice(0, 10),
              })),
            ],
          }
        : prev
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

  if (screen === "edit") {
    return (
      <EditScreen
        record={scannedRecord!}
        onSaved={handleConsultationSaved}
        onCancel={() => setScreen("record")}
      />
    );
  }

  return (
    <RecordScreen
      record={scannedRecord}
      pendingCount={pendingCount}
      readOnly={!qrPayload?.wt}
      onSynced={() => setPendingCount(0)}
      onAddNote={() => setScreen("edit")}
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
