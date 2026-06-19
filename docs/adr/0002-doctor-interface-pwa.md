# ADR 0002 — Doctor interface: installable PWA (Preact + TypeScript)

**Status:** Accepted (2026-06-19) · Issue [#1](https://github.com/kortiene/HealthTech/issues/1) · Implements Epic E2

## Context

The professional interface must be **web and mobile**, ultra-fast, learnable in **< 5 minutes**, and run
the security-critical consultation loop: scan the patient's 120 s QR → download the encrypted blob →
**decrypt in RAM only (never to disk)** → edit a note/prescription → re-encrypt → upload → wipe; auto-close
after 15 min inactivity. It must load fast on clinic 3G/flaky wifi.

## Decision

Build the doctor interface as an **installable PWA using Preact + TypeScript + Vite**, with all crypto
running in the **WebAssembly build of the shared Rust core** ([ADR 0003](./0003-shared-crypto-core-rust.md))
inside a Web Worker. QR scan via `getUserMedia` + a WASM QR decoder (`zxing-wasm`/`jsQR`). The decrypted
record lives **only** in JS/WASM linear memory — never IndexedDB/localStorage/Cache/disk. On "Terminer",
15-min idle, tab close, or after upload, buffers are overwritten and **the page is reloaded to force a
fresh heap**. The Service Worker caches only the app shell (code), never plaintext or blobs.

## Consequences

**Positive**
- One client serves web + mobile (home-screen install) with **no second native app** and no app-store
  friction; the same WASM crypto path as the patient app (one implementation everywhere).
- Preact (~4 KB vs React) → smallest first-scan payload, fast on 3G; ultra-simple single-flow UI supports
  the < 5 min training goal.
- RAM-only is enforced *by construction* (no plaintext persistence APIs are used; blob fetched fresh each
  session).

**Negative / risks**
- **RAM-only zeroization is best-effort, not provable to an ARTCI auditor**: JS engines may GC/page copies
  of plaintext. Mitigations: page-reload-to-drop-heap, minimal plaintext lifetime, WASM buffer zeroize.
  Flagged for the pentest (#25). If high assurance is ever required, wrap the same WASM/native core in a
  thin native shell.
- Browser cannot run SQLCipher → the offline queue stores only AES-256-GCM ciphertext in IndexedDB
  (see [ADR 0006](./0006-offline-storage-and-keys.md)).
- Camera/QR and Web Worker behavior vary across low-end browsers; needs device-lab testing (#29).

## Alternatives considered

- **React** — heavier first payload than Preact for no benefit at this UI complexity. Rejected for 3G.
- **Native-mobile-first (Flutter/Kotlin) for the doctor** — duplicates the client and forces a second
  crypto integration surface; rejected. A native shell remains an *optional* later add-on over the same core.
- **Flutter Web** — large payload, poor for an ultra-fast web target. Rejected.
