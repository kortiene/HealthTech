import { Icon } from "./Icon";
import { Spinner } from "./Spinner";

interface SyncBadgeProps {
  pendingCount: number;
  isSyncing: boolean;
  onSync: () => void;
}

/** Badge "N en attente — synchroniser" — couleur accent, jamais un état d'erreur. */
export function SyncBadge({ pendingCount, isSyncing, onSync }: SyncBadgeProps) {
  if (pendingCount <= 0) return null;

  return (
    <button
      type="button"
      onClick={onSync}
      disabled={isSyncing}
      aria-label={`${pendingCount} consultation(s) en attente — synchroniser`}
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: "6px",
        minHeight: "var(--tap-target-min)",
        padding: "0 var(--space-sm)",
        borderRadius: "var(--radius-pill)",
        background: "var(--color-accent-100)",
        color: "var(--color-accent-700)",
        border: "none",
        fontWeight: 500,
        fontSize: "var(--text-label-size)",
        cursor: isSyncing ? "default" : "pointer",
      }}
    >
      {isSyncing ? <Spinner size={16} color="var(--color-accent-700)" /> : <Icon name="sync" size={18} color="var(--color-accent-700)" />}
      {pendingCount} en attente
    </button>
  );
}
