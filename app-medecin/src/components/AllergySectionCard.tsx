import { Icon } from "./Icon";

export interface AllergyItem {
  substance: string;
  severity: string;
}

interface AllergySectionCardProps {
  allergies: AllergyItem[];
}

function isSevere(severity: string) {
  return severity.toLowerCase().includes("sév");
}

/**
 * Section Allergies — pills compactes, sévères en rouge, modérées en ambre.
 * `role="region"` + aria-label pour lecteurs d'écran (§3.3).
 */
export function AllergySectionCard({ allergies }: AllergySectionCardProps) {
  if (allergies.length === 0) return null;

  const hasSevere = allergies.some((a) => isSevere(a.severity));

  return (
    <section
      role="region"
      aria-label={`Allergies — ${allergies.length} enregistrée(s)`}
      style={{
        background: hasSevere ? "var(--color-allergy-bg)" : "var(--color-white)",
        border: `1.5px solid ${hasSevere ? "var(--color-allergy)" : "var(--color-neutral-200)"}`,
        borderRadius: "var(--radius-md)",
        padding: "var(--space-md)",
        marginBottom: "var(--space-md)",
      }}
    >
      <div
        style={{
          display: "flex",
          alignItems: "center",
          gap: "var(--space-sm)",
          marginBottom: "var(--space-sm)",
        }}
      >
        <Icon name="warning_amber" size={18} color="var(--color-allergy)" filled />
        <h2 className="text-title-sm" style={{ color: "var(--color-allergy)" }}>
          Allergies
        </h2>
        <span
          style={{
            marginLeft: "auto",
            padding: "2px 8px",
            borderRadius: "var(--radius-pill)",
            background: "var(--color-allergy)",
            color: "var(--color-white)",
            fontSize: 11,
            fontWeight: 700,
          }}
        >
          {allergies.length}
        </span>
      </div>

      <div style={{ display: "flex", flexWrap: "wrap", gap: "var(--space-xs)" }}>
        {allergies.map((a) => {
          const severe = isSevere(a.severity);
          return (
            <span
              key={a.substance}
              aria-label={`${a.substance} — ${a.severity}`}
              style={{
                display: "inline-flex",
                alignItems: "center",
                gap: 5,
                padding: "6px 12px",
                borderRadius: "var(--radius-pill)",
                background: severe ? "var(--color-allergy)" : "rgba(217,119,6,0.1)",
                border: `1px solid ${severe ? "transparent" : "rgba(217,119,6,0.35)"}`,
                color: severe ? "var(--color-white)" : "var(--color-accent-700)",
                fontSize: 13,
                fontWeight: severe ? 700 : 500,
                lineHeight: 1,
              }}
            >
              {severe && (
                <Icon name="warning_amber" size={12} color="white" filled />
              )}
              {a.substance}
              <span
                style={{
                  background: severe ? "rgba(255,255,255,0.22)" : "rgba(0,0,0,0.08)",
                  borderRadius: "var(--radius-pill)",
                  padding: "2px 6px",
                  fontSize: 11,
                  fontWeight: 600,
                  letterSpacing: "0.02em",
                }}
              >
                {a.severity}
              </span>
            </span>
          );
        })}
      </div>
    </section>
  );
}
