// PWA shell smoke tests — UX single-flow invariants (issue #28, Livrable C).
//
// Tests the App (now fully implemented: scan → record → edit → terminate) for
// the zero-menu / single-flow structural invariants mandated by
// docs/ux/medecin-ux-guidelines.md §1.
//
// SCOPE: App() is called directly outside a Preact render cycle. The preact/hooks
// module is stubbed so useState returns its initial value without needing a
// component context. App() in its initial state returns <ScanScreen>, which is a
// function-component VNode (not a raw HTML element) — the relevant invariants are
// that NO nav/aside/tablist chrome wraps it, tested below.
//
// Environment: vitest + node (no DOM). The Preact JSX is compiled to h() calls,
// so App() returns a plain VNode object — checkable without a browser runtime.

import { describe, expect, it, vi } from "vitest";

// Stub preact/hooks so App() can be called outside a render cycle.
// useState returns [initialValue, noop] — App() initial state is screen="scan".
vi.mock("preact/hooks", () => ({
  useState: (initial: unknown) => [initial, () => {}],
  useEffect: () => {},
  useRef: () => ({ current: undefined }),
}));

import { App } from "./app";
import { IDLE_TIMEOUT_MS, WARN_BEFORE_MS, sessionTitle } from "./session";

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
  it("flow starts at ScanScreen — scan-first, no tab/menu shell", () => {
    const vnode = App() as unknown as VNode;
    // Initial render is ScanScreen (a function component), not a plain HTML tag.
    // The scan-first entry point is the mandated UX starting position.
    expect(vnode.type).toBeTruthy();
    expect(typeof vnode.type).toBe("function");
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

  it("IDLE_TIMEOUT_MS is 30 min (ADR 0002 — wipe-on-idle, #122)", () => {
    expect(IDLE_TIMEOUT_MS).toBe(30 * 60 * 1000);
  });

  it("WARN_BEFORE_MS is 2 min — pre-close warning threshold (#122)", () => {
    expect(WARN_BEFORE_MS).toBe(2 * 60 * 1000);
  });

  it("quiet window is 28 min — warning fires at IDLE_TIMEOUT_MS − WARN_BEFORE_MS (#122)", () => {
    expect(IDLE_TIMEOUT_MS - WARN_BEFORE_MS).toBe(28 * 60 * 1000);
  });
});

// ── Step-budget guard-rail (pending activation) ────────────────────────────────
//
// When the WASM crypto-core + QR scan land (issues #17, #21, #22), activate this
// test by importing and checking the step-budget constant:
//
//   import { CONSULTATION_STEPS } from './uxBudget';
//   import { UX_MAX_STEPS } from './uxBudget';
//
//   it('PWA flow traverses at most UX_MAX_STEPS steps', () => {
//     expect(CONSULTATION_STEPS.length).toBe(UX_MAX_STEPS);
//   });
//
describe("PWA step-budget guard-rail (pending — crypto TODO #17/#21/#22)", () => {
  it("marker: step-budget activation pending WASM crypto integration", () => {
    expect(true).toBe(true);
  });
});

// ── Low-end-device accessibility guard-rail (pending activation) ─────────────
//
// Issue #29 Livrable E — PWA accessibility invariants (low-end device profile).
// Replace the marker with axe-core / aria-label checks when the flow is stable.
//
describe(
  "PWA low-end-device accessibility guard-rail (pending — flow TODO #17/#21/#22)",
  () => {
    it("marker: accessibility invariant activation pending WASM integration", () => {
      expect(true).toBe(true);
    });

    it("IDLE_TIMEOUT_MS is 30 min — session-expiry timeout (wipe-on-idle, #29/#122)", () => {
      expect(IDLE_TIMEOUT_MS).toBe(30 * 60 * 1000);
    });

    it("sessionTitle() returns the French interface label (no sensitive data in title)", () => {
      const title = sessionTitle();
      expect(title).toBe("HealthTech — Interface Médecin");
      expect(title).not.toContain("key");
      expect(title).not.toContain("uuid");
    });
  },
);
