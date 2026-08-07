// Stub — sera implémenté dans l'issue #120 (feat(pwa): note vocale médecin).
import { AppBar } from "../components/AppBar";
import { Icon } from "../components/Icon";

export interface VoiceNoteScreenProps {
  onCancel: () => void;
}

export function VoiceNoteScreen({ onCancel }: VoiceNoteScreenProps) {
  return (
    <div style={{ minHeight: "100%" }}>
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
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          justifyContent: "center",
          gap: "var(--space-md)",
          padding: "var(--space-xl) var(--space-md)",
          textAlign: "center",
        }}
      >
        <div
          style={{
            width: 72,
            height: 72,
            borderRadius: "50%",
            background: "var(--color-neutral-100)",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <Icon name="mic" size={36} color="var(--color-neutral-400)" />
        </div>
        <p className="text-body-lg" style={{ margin: 0, fontWeight: 600 }}>
          Note vocale
        </p>
        <p className="text-body" style={{ margin: 0, color: "var(--color-neutral-500)" }}>
          Fonctionnalité à venir — issue #120
        </p>
      </div>
    </div>
  );
}
