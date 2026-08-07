import { describe, expect, it } from "vitest";
import { IDLE_TIMEOUT_MS, WARN_BEFORE_MS, sessionTitle } from "./session";

describe("session helpers", () => {
  it("exposes the doctor interface title", () => {
    expect(sessionTitle()).toBe("HealthTech — Interface Médecin");
  });

  it("auto-closes after 10 minutes of inactivity (ADR 0002, #122)", () => {
    expect(IDLE_TIMEOUT_MS).toBe(600_000);
  });

  it("shows pre-close warning 2 min before idle close (WARN_BEFORE_MS, #122)", () => {
    expect(WARN_BEFORE_MS).toBe(120_000);
  });

  it("warning fires before auto-close (WARN_BEFORE_MS < IDLE_TIMEOUT_MS)", () => {
    expect(WARN_BEFORE_MS).toBeLessThan(IDLE_TIMEOUT_MS);
  });
});
