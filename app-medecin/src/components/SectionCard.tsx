import type { ComponentChildren } from "preact";
import { Icon } from "./Icon";

interface SectionCardProps {
  title: string;
  icon: string;
  accentColor?: string;
  accentBg?: string;
  children: ComponentChildren;
}

/** Carte de section du dossier médical — `role="region"` (§3.1). */
export function SectionCard({
  title,
  icon,
  accentColor = "var(--color-primary-700)",
  accentBg = "var(--color-primary-100)",
  children,
}: SectionCardProps) {
  return (
    <section
      role="region"
      aria-label={title}
      className="card"
      style={{
        borderColor: accentColor !== "var(--color-primary-700)" ? accentColor : undefined,
        marginBottom: "var(--space-md)",
      }}
    >
      <div style={{ display: "flex", alignItems: "center", gap: "var(--space-sm)", marginBottom: "var(--space-sm)" }}>
        <span className="icon-badge" style={{ background: accentBg }}>
          <Icon name={icon} size={20} color={accentColor} />
        </span>
        <h2 className="text-title-sm">{title}</h2>
      </div>
      <div style={{ display: "flex", flexDirection: "column", gap: "var(--space-xs)" }}>{children}</div>
    </section>
  );
}
