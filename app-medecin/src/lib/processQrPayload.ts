// Shared QR / access-link payload processing (#177).
//
// Extracted from ScanScreen.handleQrData so the same decrypt flow can be
// reused by the hash-based teleconsultation route (/access#<fragment>).
//
// Zero-knowledge invariant: the session key lives only in the QR image or
// the URL fragment — it is never transmitted to the server.  This module
// fetches the opaque ciphertext blob and decrypts it in RAM only.

import { createSessionCrypto, type SessionCrypto } from "../crypto";
import { parseFlutterRecord, type MedicalRecord } from "../stubs/data";

// ── Types ─────────────────────────────────────────────────────────────────────

/** Payload embedded in the QR code or URL fragment for a consultation session. */
export interface QrPayload {
  v: number;
  uuid: string;
  url: string;
  /** Session key (AES-256, base64url) — decryption in RAM only, never stored. */
  key: string;
  exp?: number;
  /** Write token (base64url). Present only in read-write sessions. */
  wt?: string;
}

/** Successful result of processing a QR or link payload. */
export interface QrScanResult {
  record: MedicalRecord;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  raw: any;
  payload: QrPayload;
  sessionCrypto: SessionCrypto;
}

// ── Public error keys (thrown as Error.message) ───────────────────────────────

export type QrScanError = "expired" | "serverDown" | "decryptError";

// ── Helpers ───────────────────────────────────────────────────────────────────

/**
 * Decode a base64url-no-padding string (as produced by `QrPayload.toLinkFragment`
 * in app-patient) back to a UTF-8 string.
 *
 * The algorithm:
 *   1. Replace URL-safe alphabet (`-` → `+`, `_` → `/`).
 *   2. Add back the `=` padding stripped by Dart's `replaceAll('=', '')`.
 *   3. Decode with `atob` (Latin-1 codepoints → binary).
 *   4. Re-interpret as UTF-8 with TextDecoder.
 */
export function decodeQrLinkFragment(fragment: string): string {
  const base64 = fragment.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  const binary = atob(padded);
  const bytes = Uint8Array.from(binary, (c) => c.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

// ── Core function ─────────────────────────────────────────────────────────────

/**
 * Parse a raw QR/link string, validate it, fetch the encrypted blob from the
 * backend and decrypt it in RAM.
 *
 * Throws an `Error` whose `message` is a `QrScanError` key:
 *   - `"decryptError"` — JSON invalid, wrong version, or decrypt failed.
 *   - `"expired"`      — `exp` is in the past or the backend returns 404/410.
 *   - `"serverDown"`   — network error or non-success HTTP status.
 */
export async function processQrPayload(raw: string): Promise<QrScanResult> {
  // 1. Parse and validate the payload structure.
  let payload: QrPayload;
  try {
    payload = JSON.parse(raw) as QrPayload;
  } catch {
    throw new Error("decryptError");
  }

  if (payload.v !== 1 || !payload.uuid || !payload.url || !payload.key) {
    throw new Error("decryptError");
  }
  if (payload.exp && payload.exp * 1000 < Date.now()) {
    throw new Error("expired");
  }

  // 2. Fetch the opaque encrypted blob (server never sees the key).
  let res: Response;
  try {
    res = await fetch(`${payload.url}/blob/${payload.uuid}`, {
      headers: { Authorization: `Bearer ${payload.key}` },
    });
  } catch {
    throw new Error("serverDown");
  }

  if (res.status === 404 || res.status === 410) throw new Error("expired");
  if (!res.ok) throw new Error("serverDown");

  // 3. Decrypt in RAM using the session key from the QR/fragment.
  const buf = await res.arrayBuffer();
  try {
    const sc = await createSessionCrypto(payload.key);
    const decrypted = await sc.decrypt(new Uint8Array(buf));
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    const recordRaw: any = JSON.parse(new TextDecoder().decode(decrypted));
    const record = parseFlutterRecord(recordRaw);
    return { record, raw: recordRaw, payload, sessionCrypto: sc };
  } catch {
    throw new Error("decryptError");
  }
}
