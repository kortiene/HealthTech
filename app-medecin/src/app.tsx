import { sessionTitle } from "./session";

/**
 * Minimal app-shell stub for the doctor PWA (ADR 0002).
 *
 * The real consultation loop — scan the patient's 120 s QR (getUserMedia +
 * WASM QR decoder), download the encrypted blob, decrypt in a Web Worker
 * backed by the Rust crypto-core compiled to WASM (RAM-only, never to disk),
 * edit, re-encrypt, upload, then wipe + reload to drop the heap — lands in:
 *   - WASM crypto-core bindings ............ TODO(#17)
 *   - QR scan + consultation flow .......... TODO(#21)
 *   - offline ciphertext queue (IndexedDB) . TODO(#22)
 */
export function App() {
  return (
    <main>
      <h1>{sessionTitle()}</h1>
      <p>Scaffold — consultation flow à venir (TODO(#21)).</p>
    </main>
  );
}
