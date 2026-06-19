# app-medecin — HealthTech doctor interface (PWA)

Installable **Preact + TypeScript + Vite** PWA for healthcare professionals.

## Purpose

The professional consultation client: scan the patient's 120 s QR
(`getUserMedia` + WASM QR decoder) → download the encrypted blob → **decrypt in
RAM only, never to disk** → edit a note/prescription → re-encrypt → upload →
wipe buffers and **reload to drop the heap**. Auto-closes after 15 min idle.
One client serves web + home-screen install with no second native app.

All AES-256-GCM / PBKDF2 crypto runs in the **same shared Rust `crypto-core`
compiled to WASM** inside a **Web Worker** — platform/WebCrypto AES is forbidden.
The Service Worker caches only the app shell (code), never plaintext or blobs;
the offline queue stores only ciphertext in IndexedDB.

This is a **scaffold** (issue #2): a compiling app-shell stub only. Real features
are marked with `TODO(#N)`:

- `TODO(#17)` — load the Rust crypto-core WASM (`wasm-bindgen`) in a Web Worker
- `TODO(#21)` — QR scan, consultation flow, PWA manifest + Service Worker (app-shell cache)
- `TODO(#22)` — offline ciphertext queue (IndexedDB), drained on reconnect

## ADRs implemented

- [ADR 0002 — Doctor interface: installable PWA (Preact + TypeScript)](../docs/adr/0002-doctor-interface-pwa.md)
- [ADR 0003 — Shared cryptography core: one Rust crate](../docs/adr/0003-shared-crypto-core-rust.md) (WASM consumer)
- [ADR 0006 — Offline storage & key management](../docs/adr/0006-offline-storage-and-keys.md) (web ciphertext-in-IndexedDB)

## Build & test

```sh
npm install
npm test      # vitest run — must be green
```

Other scripts: `npm run dev` (Vite dev server), `npm run build`
(`tsc --noEmit && vite build`), `npm run preview`.
