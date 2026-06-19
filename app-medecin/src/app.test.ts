import { describe, expect, it } from "vitest";
import { IDLE_TIMEOUT_MS, sessionTitle } from "./session";

describe("session helpers", () => {
  it("exposes the doctor interface title", () => {
    expect(sessionTitle()).toBe("HealthTech — Interface Médecin");
  });

  it("auto-closes after 15 minutes of inactivity (ADR 0002)", () => {
    expect(IDLE_TIMEOUT_MS).toBe(900_000);
  });
});
