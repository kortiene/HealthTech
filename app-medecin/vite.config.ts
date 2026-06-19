import { defineConfig } from "vite";
import preact from "@preact/preset-vite";

// PWA config (manifest + Service Worker that caches ONLY the app shell —
// never plaintext, blobs, or session keys) is wired in TODO(#21).
// WASM crypto-core is loaded inside a Web Worker — TODO(#17).
export default defineConfig({
  plugins: [preact()],
  test: {
    globals: true,
    environment: "node",
  },
});
