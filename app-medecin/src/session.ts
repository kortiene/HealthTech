/**
 * Pure, dependency-free helpers for the doctor PWA shell.
 *
 * No crypto lives here — all AES-256-GCM / PBKDF2 logic runs in the shared
 * Rust crypto-core compiled to WASM inside a Web Worker (ADR 0003), wired in
 * TODO(#17). Platform crypto (WebCrypto AES) is forbidden by ADR 0003.
 *
 * The crypto-core API + wire format are FROZEN by #10: decryptRecord consumes a
 * `nonce(12) || ciphertext || tag(16)` blob and the module is stateless / no-I/O,
 * so the doctor record is decrypted in RAM only and wiped on idle (see
 * IDLE_TIMEOUT_MS, #19). See crypto-core/README.md.
 */

/** App-shell title rendered on first paint. */
export function sessionTitle(): string {
  return "HealthTech — Interface Médecin";
}

/** Idle auto-close window (ms): wipe RAM + reload after 15 min — see ADR 0002. */
export const IDLE_TIMEOUT_MS = 15 * 60 * 1000;
