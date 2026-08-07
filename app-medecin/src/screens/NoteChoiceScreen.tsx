import { AppBar } from "../components/AppBar";
import { Icon } from "../components/Icon";

export interface NoteChoiceScreenProps {
  onWritten: () => void;
  onVoice: () => void;
  onCancel: () => void;
}

function _NoteCard({
  icon,
  label,
  description,
  onClick,
}: {
  icon: string;
  label: string;
  description: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      style={{
        flex: 1,
        minHeight: 160,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        gap: "var(--space-sm)",
        padding: "var(--space-lg) var(--space-md)",
        background: "var(--color-white)",
        border: "1.5px solid var(--color-neutral-200)",
        borderRadius: "var(--radius-md)",
        cursor: "pointer",
        textAlign: "center",
        transition: "border-color 0.15s, box-shadow 0.15s",
      }}
    >
      <div
        style={{
          width: 52,
          height: 52,
          borderRadius: "50%",
          background: "var(--color-primary-50)",
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          flexShrink: 0,
        }}
      >
        <Icon name={icon} size={26} color="var(--color-primary-700)" />
      </div>
      <p
        className="text-body-lg"
        style={{ margin: 0, fontWeight: 600, color: "var(--color-neutral-900)" }}
      >
        {label}
      </p>
      <p
        className="text-caption"
        style={{ margin: 0, color: "var(--color-neutral-500)" }}
      >
        {description}
      </p>
    </button>
  );
}

export function NoteChoiceScreen({
  onWritten,
  onVoice,
  onCancel,
}: NoteChoiceScreenProps) {
  return (
    <div
      style={{ minHeight: "100%", background: "var(--color-neutral-50)" }}
    >
      <AppBar title="Nouvelle note">
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
        }}
      >
        <p
          className="text-body"
          style={{
            margin: 0,
            color: "var(--color-neutral-600)",
            textAlign: "center",
          }}
        >
          Quel type de note souhaitez-vous ajouter ?
        </p>

        <div style={{ display: "flex", gap: "var(--space-md)" }}>
          <_NoteCard
            icon="edit_note"
            label="Note écrite"
            description="Formulaire structuré"
            onClick={onWritten}
          />
          <_NoteCard
            icon="mic"
            label="Note vocale"
            description="Enregistrement audio"
            onClick={onVoice}
          />
        </div>
      </div>
    </div>
  );
}
