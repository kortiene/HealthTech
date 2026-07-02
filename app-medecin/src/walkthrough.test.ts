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
