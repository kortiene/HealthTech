import { Icon } from "./Icon";

export type SnackBarTone = "neutral" | "warning" | "error" | "success";

interface SnackBarProps {
  message: string;
  tone?: SnackBarTone;
  onDismiss?: () => void;
}

const toneStyles: Record<SnackBarTone, { bg: string; fg: string; icon: string }> = {
  neutral: { bg: "var(--color-neutral-900)", fg: "var(--color-white)", icon: "info" },
  warning: { bg: "var(--color-accent-700)", fg: "var(--color-white)", icon: "wifi_off" },
  error: { bg: "var(--color-error)", fg: "var(--color-white)", icon: "error" },
  success: { bg: "var(--color-primary-700)", fg: "var(--color-white)", icon: "check_circle" },
};

/**
 * Snackbar flottant. Un état hors-ligne utilise `tone="warning"` (ambre) —
 * jamais rouge, jamais présenté comme un échec (§3.4). Les erreurs utilisent
 * `role="alert"` pour être annoncées immédiatement (§3.1).
 */
export function SnackBar({ message, tone = "neutral", onDismiss }: SnackBarProps) {
  const s = toneStyles[tone];
  return (
    <div
      role={tone === "error" ? "alert" : "status"}
      style={{
        position: "fixed",
        left: "var(--space-md)",
        right: "var(--space-md)",
        bottom: "var(--space-md)",
        display: "flex",
        alignItems: "center",
        gap: "var(--space-sm)",
        padding: "var(--space-md)",
        borderRadius: "var(--radius-sm)",
        background: s.bg,
        color: s.fg,
        boxShadow: "0 8px 24px rgba(0,0,0,0.18)",
        zIndex: 50,
      }}
    >
      <Icon name={s.icon} size={20} color={s.fg} />
      <p className="text-body-lg" style={{ flex: 1, color: s.fg }}>
        {message}
      </p>
      {onDismiss && (
        <button
          type="button"
          className="btn-icon"
          style={{ color: s.fg, minWidth: "36px", minHeight: "36px" }}
          onClick={onDismiss}
          aria-label="Fermer"
        >
          <Icon name="close" size={18} color={s.fg} />
        </button>
      )}
    </div>
  );
}
