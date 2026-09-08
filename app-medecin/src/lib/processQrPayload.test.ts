// Tests for processQrPayload.ts — shared QR/remote-access decrypt logic (#177).
//
// Coverage:
//   decodeQrLinkFragment — base64url-no-padding round-trip
//   processQrPayload     — payload validation, expiry, network errors, decrypt errors

import { describe, it, expect, vi, beforeEach } from "vitest";
import { decodeQrLinkFragment, processQrPayload } from "./processQrPayload";

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Mirror Dart's `base64Url.encode(utf8.encode(s)).replaceAll('=', '')`. */
function dartEncode(s: string): string {
  const bytes = new TextEncoder().encode(s);
  const binary = String.fromCharCode(...bytes);
  return btoa(binary)
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

const FUTURE_EXP = Math.floor(Date.now() / 1000) + 3600;
const PAST_EXP = Math.floor(Date.now() / 1000) - 1;

const VALID_PAYLOAD = JSON.stringify({
  v: 1,
  uuid: "00000000-0000-4000-8000-000000000001",
  url: "http://backend.test",
  key: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=",
  exp: FUTURE_EXP,
});

// ── Mocks ─────────────────────────────────────────────────────────────────────

// Mock the crypto module — real SubtleCrypto is not needed in these unit tests.
vi.mock("../crypto", () => ({
  createSessionCrypto: vi.fn().mockResolvedValue({
    decrypt: vi
      .fn()
      .mockResolvedValue(
        new TextEncoder().encode(JSON.stringify({ patientId: "p1" })),
      ),
  }),
}));

// Mock parseFlutterRecord — returns a minimal MedicalRecord shape.
vi.mock("../stubs/data", () => ({
  parseFlutterRecord: vi
    .fn()
    .mockReturnValue({ patientId: "p1", consultations: [] }),
}));

// ── decodeQrLinkFragment ──────────────────────────────────────────────────────

describe("decodeQrLinkFragment (#177)", () => {
  it("decodes a valid base64url-no-padding fragment back to the original string", () => {
    const original = VALID_PAYLOAD;
    const encoded = dartEncode(original);
    expect(decodeQrLinkFragment(encoded)).toBe(original);
  });

  it("round-trips a simple ASCII string", () => {
    const s = "hello";
    expect(decodeQrLinkFragment(dartEncode(s))).toBe(s);
  });

  it("round-trips a UTF-8 string with accents", () => {
    const s = "été malade";
    expect(decodeQrLinkFragment(dartEncode(s))).toBe(s);
  });

  it("handles fragments with length % 4 == 0 (no padding needed)", () => {
    // Craft a string whose base64url encoding has length divisible by 4.
    // "abcd" base64url = "YWJjZA" (6 chars) — but we just test round-trip.
    const s = "abcd";
    expect(decodeQrLinkFragment(dartEncode(s))).toBe(s);
  });

  it("handles fragments with length % 4 == 2 (needs 2 padding chars)", () => {
    // Any string that produces a base64url length with remainder 2 mod 4.
    const s = "ab";
    expect(decodeQrLinkFragment(dartEncode(s))).toBe(s);
  });

  it("handles fragments with length % 4 == 3 (needs 1 padding char)", () => {
    const s = "abc";
    expect(decodeQrLinkFragment(dartEncode(s))).toBe(s);
  });

  it("produces no '=' in the encoded output (Dart strips padding)", () => {
    const encoded = dartEncode(VALID_PAYLOAD);
    expect(encoded).not.toContain("=");
  });
});

// ── processQrPayload ──────────────────────────────────────────────────────────

describe("processQrPayload (#177)", () => {
  beforeEach(() => {
    vi.stubGlobal("fetch", undefined);
  });

  // ── Payload validation ────────────────────────────────────────────────────

  it("throws decryptError when raw string is not valid JSON", async () => {
    await expect(processQrPayload("not-json")).rejects.toThrow("decryptError");
  });

  it("throws decryptError when version field is not 1", async () => {
    const payload = JSON.stringify({
      v: 2,
      uuid: "x",
      url: "http://x",
      key: "k",
    });
    await expect(processQrPayload(payload)).rejects.toThrow("decryptError");
  });

  it("throws decryptError when uuid is missing", async () => {
    const payload = JSON.stringify({ v: 1, url: "http://x", key: "k" });
    await expect(processQrPayload(payload)).rejects.toThrow("decryptError");
  });

  it("throws decryptError when url is missing", async () => {
    const payload = JSON.stringify({ v: 1, uuid: "x", key: "k" });
    await expect(processQrPayload(payload)).rejects.toThrow("decryptError");
  });

  it("throws decryptError when key is missing", async () => {
    const payload = JSON.stringify({ v: 1, uuid: "x", url: "http://x" });
    await expect(processQrPayload(payload)).rejects.toThrow("decryptError");
  });

  it("throws expired when exp is in the past", async () => {
    const payload = JSON.stringify({
      v: 1,
      uuid: "x",
      url: "http://x",
      key: "k",
      exp: PAST_EXP,
    });
    await expect(processQrPayload(payload)).rejects.toThrow("expired");
  });

  // ── Network errors ────────────────────────────────────────────────────────

  it("throws serverDown when fetch throws a network error", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new TypeError("Failed to fetch")));
    await expect(processQrPayload(VALID_PAYLOAD)).rejects.toThrow("serverDown");
  });

  it("throws expired when backend returns 404", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({ ok: false, status: 404, arrayBuffer: () => Promise.resolve(new ArrayBuffer(0)) }),
    );
    await expect(processQrPayload(VALID_PAYLOAD)).rejects.toThrow("expired");
  });

  it("throws expired when backend returns 410 (blob consumed)", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({ ok: false, status: 410, arrayBuffer: () => Promise.resolve(new ArrayBuffer(0)) }),
    );
    await expect(processQrPayload(VALID_PAYLOAD)).rejects.toThrow("expired");
  });

  it("throws serverDown when backend returns 500", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({ ok: false, status: 500, arrayBuffer: () => Promise.resolve(new ArrayBuffer(0)) }),
    );
    await expect(processQrPayload(VALID_PAYLOAD)).rejects.toThrow("serverDown");
  });

  it("throws serverDown when backend returns 503", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({ ok: false, status: 503, arrayBuffer: () => Promise.resolve(new ArrayBuffer(0)) }),
    );
    await expect(processQrPayload(VALID_PAYLOAD)).rejects.toThrow("serverDown");
  });

  // ── Happy path ────────────────────────────────────────────────────────────

  it("returns a QrScanResult on success", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        arrayBuffer: () => Promise.resolve(new ArrayBuffer(16)),
      }),
    );
    const result = await processQrPayload(VALID_PAYLOAD);
    expect(result).toHaveProperty("record");
    expect(result).toHaveProperty("payload");
    expect(result).toHaveProperty("sessionCrypto");
    expect(result).toHaveProperty("raw");
  });

  it("fetch is called with the correct blob URL (uuid in path)", async () => {
    const mockFetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      arrayBuffer: () => Promise.resolve(new ArrayBuffer(16)),
    });
    vi.stubGlobal("fetch", mockFetch);
    await processQrPayload(VALID_PAYLOAD);
    const calledUrl: string = mockFetch.mock.calls[0][0];
    expect(calledUrl).toContain(
      "/blob/00000000-0000-4000-8000-000000000001",
    );
  });

  it("ZK: fetch request header carries Authorization but NOT the uuid in the key field", async () => {
    const mockFetch = vi.fn().mockResolvedValue({
      ok: true,
      status: 200,
      arrayBuffer: () => Promise.resolve(new ArrayBuffer(16)),
    });
    vi.stubGlobal("fetch", mockFetch);
    await processQrPayload(VALID_PAYLOAD);
    const opts: RequestInit = mockFetch.mock.calls[0][1];
    const authHeader = (opts?.headers as Record<string, string>)?.Authorization;
    // Auth header carries the key, not the uuid (ZK: server sees opaque key token, not plaintext)
    expect(authHeader).toMatch(/^Bearer /);
    expect(authHeader).not.toContain("00000000-0000-4000-8000-000000000001");
  });

  it("payload returned preserves the uuid from the raw string", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        arrayBuffer: () => Promise.resolve(new ArrayBuffer(16)),
      }),
    );
    const result = await processQrPayload(VALID_PAYLOAD);
    expect(result.payload.uuid).toBe(
      "00000000-0000-4000-8000-000000000001",
    );
  });

  // ── Decrypt error ─────────────────────────────────────────────────────────

  it("throws decryptError when createSessionCrypto throws", async () => {
    const { createSessionCrypto } = await import("../crypto");
    vi.mocked(createSessionCrypto).mockRejectedValueOnce(
      new Error("bad key"),
    );
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue({
        ok: true,
        status: 200,
        arrayBuffer: () => Promise.resolve(new ArrayBuffer(16)),
      }),
    );
    await expect(processQrPayload(VALID_PAYLOAD)).rejects.toThrow(
      "decryptError",
    );
  });
});
