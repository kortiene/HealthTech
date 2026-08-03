import type { ComponentChildren } from "preact";

interface AppBarProps {
  title: string;
  subtitle?: string;
  children?: ComponentChildren;
}

/** Barre supérieure — fond blanc, séparateur bas subtil (cf. Flutter AppBarTheme). */
export function AppBar({ title, subtitle, children }: AppBarProps) {
  return (
    <header
      role="banner"
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "space-between",
        gap: "var(--space-sm)",
        minHeight: "56px",
        padding: "0 var(--space-md)",
        background: "var(--color-white)",
        borderBottom: "1px solid var(--color-neutral-200)",
        position: "sticky",
        top: 0,
        zIndex: 10,
      }}
    >
      <div style={{ display: "flex", alignItems: "baseline", gap: "6px", minWidth: 0 }}>
        <h1 className="text-title" style={{ whiteSpace: "nowrap" }}>
          {title}
        </h1>
        {subtitle && (
          <span
            className="text-title"
            style={{ color: "var(--color-neutral-500)", fontWeight: 400, overflow: "hidden", textOverflow: "ellipsis" }}
          >
            · {subtitle}
          </span>
        )}
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: "var(--space-sm)", flexShrink: 0 }}>
        {children}
      </div>
    </header>
  );
}
