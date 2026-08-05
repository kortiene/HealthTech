interface SpinnerProps {
  size?: number;
  color?: string;
}

/** Indicateur de chargement circulaire. */
export function Spinner({ size = 24, color = "var(--color-primary-700)" }: SpinnerProps) {
  return (
    <span
      role="status"
      aria-label="Chargement en cours"
      style={{
        display: "inline-block",
        width: `${size}px`,
        height: `${size}px`,
        border: `${Math.max(2, size / 10)}px solid var(--color-primary-100)`,
        borderTopColor: color,
        borderRadius: "50%",
        animation: "healthtech-spin 0.8s linear infinite",
      }}
    />
  );
}

const styleId = "healthtech-spinner-keyframes";
if (typeof document !== "undefined" && !document.getElementById(styleId)) {
  const style = document.createElement("style");
  style.id = styleId;
  style.textContent = `@keyframes healthtech-spin { to { transform: rotate(360deg); } }`;
  document.head.appendChild(style);
}
