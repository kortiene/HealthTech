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

/**
 * Idle auto-close window (ms): wipe RAM + reload after 30 min — see ADR 0002 (#122).
 * A pre-close warning is shown WARN_BEFORE_MS before this fires.
 */
export const IDLE_TIMEOUT_MS = 30 * 60 * 1000; // 30 min

/**
 * Show the pre-close warning this long before IDLE_TIMEOUT_MS (2 min, #122):
 * the doctor gets a persistent banner + « Prolonger » at T-28 min.
 */
export const WARN_BEFORE_MS = 2 * 60 * 1000; // 2 min

/**
 * Format a millisecond duration as "m:ss" for the session-warning countdown.
 * Rounds UP (ceil) so the display never prematurely reaches "0:00".
 * Clamps negative values to "0:00".
 */
export function formatCountdown(ms: number): string {
  const totalSec = Math.max(0, Math.ceil(ms / 1000));
  const min = Math.floor(totalSec / 60);
  const sec = totalSec % 60;
  return `${min}:${String(sec).padStart(2, "0")}`;
}
