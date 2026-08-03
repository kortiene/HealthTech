import { Spinner } from "../components/Spinner";

/** Overlay bloquant affiché pendant la fermeture sécurisée de la session. */
export function TerminatingOverlay() {
  return (
    <div
      role="alertdialog"
      aria-label="Fermeture sécurisée en cours"
      style={{
        position: "fixed",
        inset: 0,
        background: "rgba(0,0,0,0.45)",
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        zIndex: 100,
      }}
    >
      <div
        className="card"
        style={{
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: "var(--space-md)",
          padding: "var(--space-lg)",
          minWidth: "220px",
        }}
      >
        <Spinner />
        <p className="text-title-sm">Fermeture sécurisée…</p>
      </div>
    </div>
  );
}
