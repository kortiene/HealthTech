import { render } from "preact";
import { useEffect, useState } from "preact/hooks";
import { registerSW } from "virtual:pwa-register";
import { App } from "./app";
import "./style.css";

// Register the Service Worker (caches app shell only — never /blob/* or /media/*).
// The SW updates silently in the background with autoUpdate.
if (typeof window !== "undefined") {
  registerSW({ immediate: true });
}

function Root() {
  const [offline, setOffline] = useState(!navigator.onLine);

  useEffect(() => {
    const on = () => setOffline(false);
    const off = () => setOffline(true);
    window.addEventListener("online", on);
    window.addEventListener("offline", off);
    return () => {
      window.removeEventListener("online", on);
      window.removeEventListener("offline", off);
    };
  }, []);

  return (
    <>
      {offline && (
        <div
          style={{
            position: "fixed",
            top: 0,
            left: 0,
            right: 0,
            zIndex: 9999,
            background: "#EF6C00",
            color: "#fff",
            padding: "8px 16px",
            fontSize: 13,
            fontFamily: "Inter, sans-serif",
            display: "flex",
            alignItems: "center",
            gap: 8,
          }}
        >
          <span>⚠</span>
          Mode hors-ligne — les modifications ne seront pas enregistrées
        </div>
      )}
      <App />
    </>
  );
}

const root = document.getElementById("app");
if (root) {
  render(<Root />, root);
}
