// PWA shell smoke tests — UX single-flow invariants (issue #28, Livrable C).
//
// Tests the app-shell stub (App) for the zero-menu / single-flow structural
// invariants mandated by docs/ux/medecin-ux-guidelines.md §1.
//
// SCOPE: the consultation flow (scan + decrypt + edit + terminate) is a TODO
// pending issues #17/#21/#22. This file tests only what the SHELL ALREADY
// enforces: that the root container is <main> (linear flow, not a tab/nav shell)
// and that no horizontal-navigation chrome (nav, aside, tab bar) is present.
// The step-budget guard-rail (MAX_STEPS assertion) is documented here as a
// pending activation marker and will be enabled when the flow lands.
//
// Environment: vitest + node (no DOM). The Preact JSX is compiled to h() calls,
// so App() returns a plain VNode object — checkable without a browser runtime.

import { describe, expect, it } from "vitest";
import { App } from "./app";
import { IDLE_TIMEOUT_MS, sessionTitle } from "./session";

// ── VNode helpers (no DOM required) ───────────────────────────────────────────

type VNode = {
  type?: unknown;
  props?: { children?: unknown; role?: string };
};

/** Recursively checks whether a Preact VNode tree contains a node of the given
 *  element type (tag name string, e.g. 'nav', 'aside'). */
function containsType(node: unknown, type: string): boolean {
  if (!node || typeof node !== "object") return false;
  const n = node as VNode;
  if (n.type === type) return true;
  const { children } = n.props ?? {};
  if (Array.isArray(children))
    return (children as unknown[]).some((c) => containsType(c, type));
  return containsType(children, type);
}

/** Recursively checks whether a VNode tree contains a node with the given ARIA
 *  role (e.g. 'tablist'). */
function containsRole(node: unknown, role: string): boolean {
  if (!node || typeof node !== "object") return false;
  const n = node as VNode;
  if (n.props?.role === role) return true;
  const { children } = n.props ?? {};
  if (Array.isArray(children))
    return (children as unknown[]).some((c) => containsRole(c, role));
  return containsRole(children, role);
}

// ── Tests ──────────────────────────────────────────────────────────────────────

describe("App shell — zero-menu / single-flow invariants (#28)", () => {
  it("root element is <main> — single linear flow container, not a tab shell", () => {
    const vnode = App() as unknown as VNode;
    expect(vnode.type).toBe("main");
  });

  it("shell renders no <nav> element (hamburger / navigation drawer banished)", () => {
    const vnode = App() as unknown;
    expect(containsType(vnode, "nav")).toBe(false);
  });

  it("shell renders no <aside> element (no hidden panel)", () => {
    const vnode = App() as unknown;
    expect(containsType(vnode, "aside")).toBe(false);
  });

  it("shell renders no role=tablist (no tab bar)", () => {
    const vnode = App() as unknown;
    expect(containsRole(vnode, "tablist")).toBe(false);
  });

  it("App() returns a truthy VNode (scaffold is intact)", () => {
    expect(App()).toBeTruthy();
  });
});

describe("App shell — session helpers re-validated after UX norm update (#28)", () => {
  it("sessionTitle() is still the correct French interface label", () => {
    expect(sessionTitle()).toBe("HealthTech — Interface Médecin");
  });

  it("IDLE_TIMEOUT_MS is still 15 min (ADR 0002 — wipe-on-idle)", () => {
    expect(IDLE_TIMEOUT_MS).toBe(15 * 60 * 1000);
  });
});

// ── Step-budget guard-rail (pending activation) ────────────────────────────────
//
// When the PWA consultation flow lands (issues #17, #21, #22), activate this
// test by importing and checking the step-budget constant:
//
//   import { CONSULTATION_STEPS } from './uxBudget';
//   import { UX_MAX_STEPS } from './uxBudget'; // mirror of Flutter UxBudget
//
//   it('PWA flow traverses at most UX_MAX_STEPS steps', () => {
//     expect(CONSULTATION_STEPS.length).toBe(UX_MAX_STEPS);
//   });
//
// Until then, this marker test documents the intent without simulating a flow
// that does not exist. See docs/ux/medecin-ux-guidelines.md §9 for the budget.
describe("PWA step-budget guard-rail (pending — flow TODO #17/#21/#22)", () => {
  it("marker: step-budget activation pending consultation flow implementation", () => {
    // This test is intentionally a no-op until the flow is wired in the PWA.
    // Replace this assertion with the real step-budget check when the TODO lands.
    expect(true).toBe(true);
  });
});

// ── Low-end-device accessibility guard-rail (pending activation) ─────────────
//
// Issue #29 Livrable E — PWA accessibility invariants (low-end device profile).
//
// SCOPE: the consultation flow (scan + decrypt + edit + terminate) is a TODO
// pending issues #17/#21/#22. This marker documents the accessibility invariants
// that the PWA shell MUST enforce once the flow is implemented:
//
//   1. Interactive controls expose `aria-label` attributes so screen-readers
//      (NVDA, VoiceOver on mobile, axe-core audits) can announce them.
//      Enforcement: check that key action buttons carry a non-empty aria-label.
//
//   2. Touch targets are ≥ 48 CSS px tall (matching the 48 dp floor on Android).
//      Enforcement: axe-core "target-size" rule or explicit min-height assertion.
//
//   3. Text can scale to 200% without horizontal overflow or label truncation
//      (WCAG 1.4.4 Resize Text, SC AA).
//      Enforcement: jsdom + style injection, or a dedicated Playwright test.
//
//   4. Colour contrast ≥ 4.5:1 (WCAG 1.4.3 AA) on action text and vital
//      information (allergies). Enforcement: axe-core "color-contrast" rule.
//
// Profile reference: docs/ux/low-end-device-profile.md
// Activation: replace the marker with real assertions when the flow lands.
// Until then, these tests document the invariant without simulating non-existent
// behaviour — same discipline as the step-budget guard above.
//
// IDLE_TIMEOUT_MS and sessionTitle() re-validated here as a minimal structural
// smoke test covering the session constants that the future flow will depend on.

describe(
  "PWA low-end-device accessibility guard-rail (pending — flow TODO #17/#21/#22)",
  () => {
    it("marker: accessibility invariant activation pending consultation flow", () => {
      // This test is intentionally a no-op until the PWA flow is wired.
      // When #17/#21/#22 land, replace this with axe-core / aria-label checks
      // as described in the block comment above and in
      // docs/ux/low-end-validation-protocol.md §PWA.
      expect(true).toBe(true);
    });

    it("IDLE_TIMEOUT_MS is 15 min — session-expiry timeout unchanged (wipe-on-idle, #29)", () => {
      // Low-end-device profile: wipe-on-idle must still apply on a constrained
      // device (a micro power-cut cannot extend an idle session). Validates that
      // the session constant was not accidentally widened.
      expect(IDLE_TIMEOUT_MS).toBe(15 * 60 * 1000);
    });

    it("sessionTitle() returns the French interface label (no sensitive data in title)", () => {
      // The window title must never carry PII or session state — a constraint
      // that holds across all device profiles.
      const title = sessionTitle();
      expect(title).toBe("HealthTech — Interface Médecin");
      expect(title).not.toContain("key");
      expect(title).not.toContain("uuid");
    });
  },
);
