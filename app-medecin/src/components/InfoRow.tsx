interface InfoRowProps {
  label: string;
  value: string;
  critical?: boolean;
}

/** Ligne label / valeur — body-lg minimum pour l'information vitale (§2.2). */
export function InfoRow({ label, value, critical = false }: InfoRowProps) {
  return (
    <div style={{ display: "flex", alignItems: "flex-start", gap: "var(--space-sm)", padding: "6px 0" }}>
      <span className="text-label" style={{ width: "130px", flexShrink: 0 }}>
        {label}
      </span>
      <span className={critical ? "text-body-lg" : "text-body"} style={{ color: "var(--color-neutral-900)" }}>
        {value}
      </span>
    </div>
  );
}
