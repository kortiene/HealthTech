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
 * SESSION_IDLE_MINUTES, #19). See crypto-core/README.md.
 */

/** App-shell title rendered on first paint. */
export function sessionTitle(): string {
  return "HealthTech — Interface Médecin";
}

/**
 * Primary knob for the idle auto-close window (ADR 0002, #122).
 * Change this single number to adjust the timeout everywhere.
 * All downstream constants are derived from it.
 *
 * Production: 30  (minutes)
 * Manual dev test: change to 1 or 2 to observe the warning banner quickly.
 */
export const SESSION_IDLE_MINUTES = 10;

/** Idle auto-close threshold in ms — derived from SESSION_IDLE_MINUTES. */
export const IDLE_TIMEOUT_MS = SESSION_IDLE_MINUTES * 60 * 1000;

/**
 * The pre-close warning banner is shown this long before IDLE_TIMEOUT_MS (#122):
 * the doctor sees a persistent "session will close in m:ss" banner + « Prolonger ».
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
