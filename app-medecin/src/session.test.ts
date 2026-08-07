// Unit tests for session.ts — constants + pure helpers (#122).
//
// All tests are pure (no DOM, no timers, no Preact) and run in the default
// Node vitest environment. Timer-driven integration tests (warn/close sequence
// in RecordScreen) live in RecordScreen.timer.test.tsx (jsdom env).

import { describe, expect, it } from "vitest";
import {
  SESSION_IDLE_MINUTES,
  IDLE_TIMEOUT_MS,
  WARN_BEFORE_MS,
  formatCountdown,
} from "./session";

// ── Constants ─────────────────────────────────────────────────────────────────

describe("session constants (#122)", () => {
  it("SESSION_IDLE_MINUTES is 10 (primary config knob)", () => {
    expect(SESSION_IDLE_MINUTES).toBe(10);
  });

  it("IDLE_TIMEOUT_MS is derived from SESSION_IDLE_MINUTES", () => {
    expect(IDLE_TIMEOUT_MS).toBe(SESSION_IDLE_MINUTES * 60 * 1000);
    expect(IDLE_TIMEOUT_MS).toBe(600_000);
  });

  it("IDLE_TIMEOUT_MS is 10 min (wipe-on-idle, ADR 0002)", () => {
    expect(IDLE_TIMEOUT_MS).toBe(10 * 60 * 1000);
    expect(IDLE_TIMEOUT_MS).toBe(600_000);
  });

  it("WARN_BEFORE_MS is 2 min (pre-close warning window)", () => {
    expect(WARN_BEFORE_MS).toBe(2 * 60 * 1000);
    expect(WARN_BEFORE_MS).toBe(120_000);
  });

  it("warning fires before close (WARN_BEFORE_MS < IDLE_TIMEOUT_MS)", () => {
    expect(WARN_BEFORE_MS).toBeLessThan(IDLE_TIMEOUT_MS);
  });

  it("quiet window is exactly 8 min (IDLE_TIMEOUT_MS − WARN_BEFORE_MS)", () => {
    expect(IDLE_TIMEOUT_MS - WARN_BEFORE_MS).toBe(8 * 60 * 1000);
    expect(IDLE_TIMEOUT_MS - WARN_BEFORE_MS).toBe(480_000);
  });

  it("warning window covers exactly the last 2 min before close", () => {
    const warnAt = IDLE_TIMEOUT_MS - WARN_BEFORE_MS;
    expect(IDLE_TIMEOUT_MS - warnAt).toBe(WARN_BEFORE_MS);
  });
});

// ── formatCountdown ───────────────────────────────────────────────────────────

describe("formatCountdown — mm:ss display (#122)", () => {
  it("0 ms → '0:00'", () => {
    expect(formatCountdown(0)).toBe("0:00");
  });

  it("negative ms clamps to '0:00'", () => {
    expect(formatCountdown(-1)).toBe("0:00");
    expect(formatCountdown(-60_000)).toBe("0:00");
  });

  it("1000 ms → '0:01'", () => {
    expect(formatCountdown(1_000)).toBe("0:01");
  });

  it("partial ms rounds UP to the next second (ceil)", () => {
    expect(formatCountdown(1)).toBe("0:01");
    expect(formatCountdown(999)).toBe("0:01");
  });

  it("59000 ms → '0:59'", () => {
    expect(formatCountdown(59_000)).toBe("0:59");
  });

  it("60000 ms → '1:00' (minute boundary)", () => {
    expect(formatCountdown(60_000)).toBe("1:00");
  });

  it("90000 ms → '1:30'", () => {
    expect(formatCountdown(90_000)).toBe("1:30");
  });

  it("119000 ms → '1:59'", () => {
    expect(formatCountdown(119_000)).toBe("1:59");
  });

  it("119001 ms → '2:00' (ceil: 119.001 s rounds up to 120 s)", () => {
    expect(formatCountdown(119_001)).toBe("2:00");
  });

  it("WARN_BEFORE_MS (120000 ms) → '2:00' (initial banner display)", () => {
    expect(formatCountdown(WARN_BEFORE_MS)).toBe("2:00");
  });

  it("seconds are zero-padded to two digits", () => {
    expect(formatCountdown(1_000)).toMatch(/^\d+:0\d$/);
    expect(formatCountdown(9_000)).toBe("0:09");
  });

  it("large values format correctly (no minute cap)", () => {
    expect(formatCountdown(90 * 60 * 1_000)).toBe("90:00");
  });

  it("IDLE_TIMEOUT_MS → '10:00'", () => {
    expect(formatCountdown(IDLE_TIMEOUT_MS)).toBe("10:00");
  });

  it("61000 ms → '1:01' (non-zero minutes AND non-zero seconds)", () => {
    expect(formatCountdown(61_000)).toBe("1:01");
  });

  it("60001 ms → '1:01' (ceil: 60.001 s rounds up to 61 s = 1:01)", () => {
    expect(formatCountdown(60_001)).toBe("1:01");
  });

  it("600000 ms → '10:00' (10-minute boundary, double-digit minutes)", () => {
    expect(formatCountdown(600_000)).toBe("10:00");
  });
});
