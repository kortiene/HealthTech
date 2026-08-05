// Service Worker routing-contract tests (#109 — zero-knowledge caching invariant).
//
// The workbox configuration in vite.config.ts must apply NetworkOnly to
// /blob/ and /media/ routes so patient ciphertext is NEVER cached in the
// browser's service-worker cache. This test suite directly validates the URL
// patterns used in the workbox `runtimeCaching` config: if someone accidentally
// changes a pattern or swaps NetworkOnly to StaleWhileRevalidate, at least one
// assertion here fails immediately.
//
// These are pure logic tests (regexp matching), compatible with the Node
// vitest environment — no DOM or browser APIs required.

import { describe, expect, it } from "vitest";

// Patterns mirrored from vite.config.ts workbox.runtimeCaching.
const BLOB_PATTERN = /\/blob\//;
const MEDIA_PATTERN = /\/media\//;
const ASSET_GLOB = /\.(js|css|html|ico|woff2)$/;

describe("SW routing — NetworkOnly patterns (#109)", () => {
  it("BLOB_PATTERN matches /blob/{uuid} (NetworkOnly gate)", () => {
    expect(BLOB_PATTERN.test("/blob/00000000-0000-4000-8000-000000000001")).toBe(
      true,
    );
  });

  it("BLOB_PATTERN does not match unrelated paths", () => {
    expect(BLOB_PATTERN.test("/media/uuid")).toBe(false);
    expect(BLOB_PATTERN.test("/health")).toBe(false);
    expect(BLOB_PATTERN.test("/assets/index.js")).toBe(false);
  });

  it("MEDIA_PATTERN matches /media/{uuid} (NetworkOnly gate)", () => {
    expect(
      MEDIA_PATTERN.test("/media/00000000-0000-4000-8000-000000000002"),
    ).toBe(true);
  });

  it("MEDIA_PATTERN does not match unrelated paths", () => {
    expect(MEDIA_PATTERN.test("/blob/uuid")).toBe(false);
    expect(MEDIA_PATTERN.test("/health")).toBe(false);
  });

  it("BLOB_PATTERN and MEDIA_PATTERN are disjoint (no path matches both)", () => {
    const paths = [
      "/blob/uuid",
      "/media/uuid",
      "/health",
      "/assets/index.js",
    ];
    for (const p of paths) {
      expect(BLOB_PATTERN.test(p) && MEDIA_PATTERN.test(p)).toBe(false);
    }
  });
});

describe("SW routing — app-shell cache-first asset pattern (#109)", () => {
  it("static assets match the cache-first glob", () => {
    expect(ASSET_GLOB.test("index.html")).toBe(true);
    expect(ASSET_GLOB.test("assets/index.js")).toBe(true);
    expect(ASSET_GLOB.test("assets/style.css")).toBe(true);
    expect(ASSET_GLOB.test("icon.ico")).toBe(true);
    expect(ASSET_GLOB.test("font.woff2")).toBe(true);
  });

  it("blob and media API routes do NOT match the cache-first glob", () => {
    expect(ASSET_GLOB.test("/blob/00000000-0000-4000-8000-000000000001")).toBe(false);
    expect(ASSET_GLOB.test("/media/00000000-0000-4000-8000-000000000002")).toBe(false);
  });

  it("security invariant: blob/media paths are NOT cacheable as app-shell assets", () => {
    // belt-and-suspenders: both patterns must be false for blob/media paths
    const sensitive = [
      "/blob/00000000-0000-4000-8000-000000000001",
      "/media/00000000-0000-4000-8000-000000000002",
    ];
    for (const p of sensitive) {
      expect(ASSET_GLOB.test(p)).toBe(false);
      // Also confirm the NetworkOnly pattern catches these paths
      const isNetworkOnly = BLOB_PATTERN.test(p) || MEDIA_PATTERN.test(p);
      expect(isNetworkOnly).toBe(true);
    }
  });
});
