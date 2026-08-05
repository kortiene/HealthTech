interface IconProps {
  /** Nom ligature Material Symbols, ex: "qr_code_scanner" */
  name: string;
  size?: number;
  color?: string;
  filled?: boolean;
  className?: string;
}

/** Icône Material Symbols Rounded — outline au repos, filled à l'état actif (§2.4). */
export function Icon({ name, size = 24, color, filled = false, className }: IconProps) {
  return (
    <span
      className={`material-symbol${className ? ` ${className}` : ""}`}
      style={{
        fontSize: `${size}px`,
        color,
        fontVariationSettings: `'FILL' ${filled ? 1 : 0}, 'wght' 400, 'GRAD' 0, 'opsz' 24`,
      }}
      aria-hidden="true"
    >
      {name}
    </span>
  );
}
