interface TerminateButtonProps {
  onTerminate: () => void;
  disabled?: boolean;
}

/** Bouton "Terminer" — couleur accent-700, toujours visible dans l'AppBar (§4.7). */
export function TerminateButton({ onTerminate, disabled = false }: TerminateButtonProps) {
  return (
    <button type="button" className="btn btn-accent" style={{ minHeight: "44px", padding: "0 var(--space-md)" }} onClick={onTerminate} disabled={disabled}>
      Terminer
    </button>
  );
}
