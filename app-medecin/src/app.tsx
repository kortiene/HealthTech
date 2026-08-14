import { useState } from "preact/hooks";
import { type SessionCrypto } from "./crypto";
import type { NewConsultation } from "./screens/EditScreen";
import { NoteDetailScreen } from "./screens/NoteDetailScreen";
import { NoteScreen } from "./screens/NoteScreen";
import { RecordScreen } from "./screens/RecordScreen";
import { ScanScreen, type QrPayload } from "./screens/ScanScreen";
import { TreatmentsScreen } from "./screens/TreatmentsScreen";
import type { NewVoiceConsultation } from "./screens/VoiceNoteScreen";
import { type MedicalRecord, type OrdonnanceLineStatus } from "./stubs/data";

type Screen = "scan" | "record" | "note" | "note-detail" | "treatments";

export function App() {
  const [screen, setScreen] = useState<Screen>("scan");
  const [pendingCount, setPendingCount] = useState(0);
  const [scannedRecord, setScannedRecord] = useState<MedicalRecord | null>(
    null,
  );
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const [rawFlutter, setRawFlutter] = useState<any>(null);
  const [qrPayload, setQrPayload] = useState<QrPayload | null>(null);
  const [sessionCrypto, setSessionCrypto] = useState<SessionCrypto | null>(null);
  const [selectedConsultIdx, setSelectedConsultIdx] = useState<number>(0);

  async function handleConsultationSaved(
    consultation: NewConsultation,
  ): Promise<void> {
    if (!qrPayload || !rawFlutter || !sessionCrypto)
      throw new Error("Session expirée — rescannez le QR.");

    const now = new Date().toISOString();
    const today = now.slice(0, 10);
    const newEntry = {
      id: crypto.randomUUID(),
      date: today,
      created_at: now,
      practitioner_ref: consultation.doctorName || "",
      summary: consultation.summary,
      ...(consultation.ordonnances.length > 0
        ? { ordonnances: consultation.ordonnances }
        : {}),
      ...(consultation.media && consultation.media.length > 0
        ? {
            media: consultation.media.map((m) => ({
              uuid: m.mediaId,
              url: null,
              content_key: m.contentKey,
              content_hash: m.contentHash,
              alg: "A256GCM",
              mime: m.mime,
              size_bytes: m.sizeBytes ?? 0,
              added_at: now,
            })),
          }
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
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        ...(rawFlutter.treatments ?? []).map((t: any) =>
          t.id === consultation.closedTreatmentId
            ? { ...t, status: "completed", ended_at: today }
            : t,
        ),
        ...(consultation.newTreatment
          ? [{ ...consultation.newTreatment, created_at: now }]
          : []),
      ],
      allergies: [...(rawFlutter.allergies ?? []), ...newAllergiesFlutter],
      chronic_conditions: [
        ...(rawFlutter.chronic_conditions ??
          rawFlutter.chronicConditions ??
          []),
        ...consultation.newConditions.map((c) => ({
          name: c.name,
          severity: c.severity,
          ...(c.icd10 ? { icd10: c.icd10 } : {}),
          ...(c.since ? { since: c.since } : {}),
          added_at: now,
        })),
      ],
      updated_at: now,
    };

    // Re-chiffre avec la clé de session et PUT vers le backend.
    // Le write token (wt) est le Bearer — le backend rejette les PUTs sans wt (#118).
    const encrypted = await sessionCrypto.encrypt(
      new TextEncoder().encode(JSON.stringify(updatedRaw)),
    );
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
                createdAt: now,
                doctorName: consultation.doctorName || undefined,
                summary: consultation.summary,
                ...(consultation.ordonnances.length > 0
                  ? { ordonnances: consultation.ordonnances }
                  : {}),
                ...(consultation.media && consultation.media.length > 0
                  ? { media: consultation.media }
                  : {}),
              },
            ],
            treatments: [
              ...prev.treatments.map((t) =>
                t.id === consultation.closedTreatmentId
                  ? { ...t, status: "completed", ended_at: today }
                  : t,
              ),
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
            chronicConditions: [
              ...prev.chronicConditions,
              ...consultation.newConditions.map((c) => ({
                name: c.name,
                icd10: c.icd10 ?? "",
                since: c.since,
                severity: c.severity,
                addedAt: now,
              })),
            ],
          }
        : prev,
    );
    setPendingCount((n) => n + 1);
    setScreen("record");
  }

  async function handleAmendConsultation(
    consultIdx: number,
    text: string,
    author: string,
  ): Promise<void> {
    if (!qrPayload || !rawFlutter || !sessionCrypto)
      throw new Error("Session expirée — rescannez le QR.");
    const now = new Date().toISOString();
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const updatedConsultations = [...(rawFlutter.consultations ?? [])] as any[];
    const c = { ...updatedConsultations[consultIdx] };
    c.amendments = [...(c.amendments ?? []), { text, author, at: now }];
    updatedConsultations[consultIdx] = c;
    const updatedRaw = { ...rawFlutter, consultations: updatedConsultations, updated_at: now };
    const encrypted = await sessionCrypto.encrypt(new TextEncoder().encode(JSON.stringify(updatedRaw)));
    const res = await fetch(`${qrPayload.url}/blob/${qrPayload.uuid}`, {
      method: "PUT",
      headers: {
        "Content-Type": "application/octet-stream",
        ...(qrPayload.wt ? { Authorization: `Bearer ${qrPayload.wt}` } : {}),
      },
      body: encrypted.buffer as ArrayBuffer,
    });
    if (!res.ok)
      throw new Error(res.status >= 500 ? "Serveur indisponible — réessayez." : "Échec de l'enregistrement — réessayez.");
    setRawFlutter(updatedRaw);
    setScannedRecord((prev) => {
      if (!prev) return prev;
      const consultations = [...prev.consultations];
      consultations[consultIdx] = {
        ...consultations[consultIdx],
        amendments: [
          ...(consultations[consultIdx].amendments ?? []),
          { text, author, at: now },
        ],
      };
      return { ...prev, consultations };
    });
  }

  async function handleCloseOrdonnanceLine(
    consultIdx: number,
    ordId: string,
    lineIdx: number,
    status: OrdonnanceLineStatus,
  ): Promise<void> {
    if (!qrPayload || !rawFlutter || !sessionCrypto)
      throw new Error("Session expirée — rescannez le QR.");
    const now = new Date().toISOString();
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const updatedConsultations = [...(rawFlutter.consultations ?? [])] as any[];
    const c = { ...updatedConsultations[consultIdx] };
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    c.ordonnances = (c.ordonnances ?? []).map((ord: any) => {
      if (ord.id !== ordId) return ord;
      const lines = [...ord.lines];
      lines[lineIdx] = { ...lines[lineIdx], status };
      return { ...ord, lines };
    });
    updatedConsultations[consultIdx] = c;
    const updatedRaw = { ...rawFlutter, consultations: updatedConsultations, updated_at: now };
    const encrypted = await sessionCrypto.encrypt(new TextEncoder().encode(JSON.stringify(updatedRaw)));
    const res = await fetch(`${qrPayload.url}/blob/${qrPayload.uuid}`, {
      method: "PUT",
      headers: {
        "Content-Type": "application/octet-stream",
        ...(qrPayload.wt ? { Authorization: `Bearer ${qrPayload.wt}` } : {}),
      },
      body: encrypted.buffer as ArrayBuffer,
    });
    if (!res.ok)
      throw new Error(res.status >= 500 ? "Serveur indisponible — réessayez." : "Échec de l'enregistrement — réessayez.");
    setRawFlutter(updatedRaw);
    setScannedRecord((prev) => {
      if (!prev) return prev;
      const consultations = [...prev.consultations];
      const prevC = consultations[consultIdx];
      consultations[consultIdx] = {
        ...prevC,
        ordonnances: (prevC.ordonnances ?? []).map((ord) => {
          if (ord.id !== ordId) return ord;
          const lines = [...ord.lines];
          lines[lineIdx] = { ...lines[lineIdx], status };
          return { ...ord, lines };
        }),
      };
      return { ...prev, consultations };
    });
  }

  async function handleVoiceConsultationSaved(
    consultation: NewVoiceConsultation,
  ): Promise<void> {
    if (!qrPayload || !rawFlutter || !sessionCrypto)
      throw new Error("Session expirée — rescannez le QR.");

    const addedAt = new Date().toISOString();
    const newEntry = {
      id: crypto.randomUUID(),
      date: addedAt.slice(0, 10),
      created_at: addedAt,
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
    const encrypted = await sessionCrypto.encrypt(
      new TextEncoder().encode(JSON.stringify(updatedRaw)),
    );
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
                createdAt: addedAt,
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
        onScanned={(record, raw, payload, sc) => {
          setScannedRecord(record);
          setRawFlutter(raw);
          setQrPayload(payload);
          setSessionCrypto(sc);
          setPendingCount(0);
          setScreen("record");
        }}
      />
    );
  }

  if (screen === "note") {
    return (
      <div class="page-frame">
        <NoteScreen
          record={scannedRecord!}
          backendUrl={qrPayload?.url ?? ""}
          writeToken={qrPayload?.wt}
          onWrittenSaved={handleConsultationSaved}
          onVoiceSaved={handleVoiceConsultationSaved}
          onCancel={() => setScreen("record")}
        />
      </div>
    );
  }

  if (screen === "note-detail" && scannedRecord) {
    return (
      <div class="page-frame">
        <NoteDetailScreen
          consultation={scannedRecord.consultations[selectedConsultIdx]}
          consultationIndex={selectedConsultIdx}
          backendUrl={qrPayload?.url}
          writeToken={qrPayload?.wt}
          onAmend={handleAmendConsultation}
          onCloseOrdonnanceLine={handleCloseOrdonnanceLine}
          onBack={() => setScreen("record")}
        />
      </div>
    );
  }

  if (screen === "treatments" && scannedRecord) {
    return (
      <div class="page-frame">
        <TreatmentsScreen
          record={scannedRecord}
          writeToken={qrPayload?.wt}
          onCloseOrdonnanceLine={handleCloseOrdonnanceLine}
          onBack={() => setScreen("record")}
        />
      </div>
    );
  }

  return (
    <div class="page-frame">
      <RecordScreen
        record={scannedRecord}
        pendingCount={pendingCount}
        readOnly={!qrPayload?.wt}
        backendUrl={qrPayload?.url ?? ""}
        onSynced={() => setPendingCount(0)}
        onAddNote={() => setScreen("note")}
        onViewNote={(idx) => {
          setSelectedConsultIdx(idx);
          setScreen("note-detail");
        }}
        onViewTreatments={() => setScreen("treatments")}
        onTerminated={() => {
          setPendingCount(0);
          setScannedRecord(null);
          setRawFlutter(null);
          setQrPayload(null);
          setScreen("scan");
        }}
      />
    </div>
  );
}
