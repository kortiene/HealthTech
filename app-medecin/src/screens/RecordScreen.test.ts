// VNode-level structural and accessibility tests for RecordScreen (#122).
//
// Environment: vitest + node (no DOM). preact/hooks is stubbed so components
// can be called outside a render cycle. Preact's h() is a pure VNode factory
// that does not need a browser runtime.
//
// Coverage strategy:
//   - SessionWarningBanner: called directly with props to inspect its VNode for
//     accessibility attributes, user-visible text, prop wiring, and layout.
//   - RecordScreen: state injection via mockReturnValueOnce to test both the
//     default (isWarning=false) and warning-active (isWarning=true) render paths,
//     including the suppression guard when isTerminating=true.
//
// Timer-driven behaviour tests (warn at T-28 min, close at T-30 min, extend
// resets both timers) live in RecordScreen.timer.test.tsx — jsdom env +
// vi.useFakeTimers().

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Stub preact/hooks — useState is a vi.fn() so individual tests can override
// specific calls via mockReturnValueOnce while falling back to the default
// (return the initial value) for all others.
vi.mock("preact/hooks", () => ({
  useState: vi.fn((initial: unknown) => [initial, () => {}]),
  useEffect: vi.fn(),
  useRef: vi.fn(() => ({ current: undefined })),
}));

import * as hooks from "preact/hooks";
import { RecordScreen, SessionWarningBanner } from "./RecordScreen";
import { WARN_BEFORE_MS, IDLE_TIMEOUT_MS } from "../session";

// Restore the default useState implementation before each test so tests that
// use mockReturnValueOnce do not bleed into subsequent tests.
beforeEach(() => {
  vi.mocked(hooks.useState).mockImplementation((initial?: unknown) => [initial, () => {}]);
});

afterEach(() => {
  vi.mocked(hooks.useState).mockReset();
});

// ── VNode helpers ─────────────────────────────────────────────────────────────

type VNode = { type?: unknown; props?: Record<string, unknown> };

function containsType(node: unknown, tag: string): boolean {
  if (!node || typeof node !== "object") return false;
  const n = node as VNode;
  if (n.type === tag) return true;
  const children = n.props?.["children"];
  if (Array.isArray(children))
    return (children as unknown[]).some((c) => containsType(c, tag));
  return containsType(children, tag);
}

function containsAttr(node: unknown, attr: string, value: unknown): boolean {
  if (!node || typeof node !== "object") return false;
  const n = node as VNode;
  if (n.props?.[attr] === value) return true;
  const children = n.props?.["children"];
  if (Array.isArray(children))
    return (children as unknown[]).some((c) => containsAttr(c, attr, value));
  return containsAttr(children, attr, value);
}

function containsRole(node: unknown, role: string): boolean {
  return containsAttr(node, "role", role);
}

function containsText(node: unknown, text: string): boolean {
  if (typeof node === "string") return node.includes(text);
  if (!node || typeof node !== "object") return false;
  const n = node as VNode;
  const children = n.props?.["children"];
  if (Array.isArray(children))
    return (children as unknown[]).some((c) => containsText(c, text));
  return containsText(children, text);
}

// Returns true if any node in the tree has type === fn (component VNode check).
function containsVNodeType(node: unknown, fn: unknown): boolean {
  if (!node || typeof node !== "object") return false;
  const n = node as VNode;
  if (n.type === fn) return true;
  const children = n.props?.["children"];
  if (Array.isArray(children))
    return (children as unknown[]).some((c) => containsVNodeType(c, fn));
  return containsVNodeType(children, fn);
}

// Returns the first VNode matching the predicate, or null.
function findNode(node: unknown, predicate: (n: VNode) => boolean): VNode | null {
  if (!node || typeof node !== "object") return null;
  const n = node as VNode;
  if (predicate(n)) return n;
  const children = n.props?.["children"];
  if (Array.isArray(children)) {
    for (const c of children as unknown[]) {
      const found = findNode(c, predicate);
      if (found) return found;
    }
  }
  return findNode(children as unknown, predicate);
}

// ── SessionWarningBanner — VNode structure + accessibility (#122) ─────────────

describe("SessionWarningBanner — VNode structure + a11y (#122)", () => {
  it("top-level element has role=alert for screen-reader announcement", () => {
    const vnode = SessionWarningBanner({
      remainingMs: WARN_BEFORE_MS,
      onExtend: () => {},
    }) as unknown as VNode;
    expect(vnode.props?.["role"]).toBe("alert");
  });

  it("top-level element has aria-live=assertive", () => {
    const vnode = SessionWarningBanner({
      remainingMs: WARN_BEFORE_MS,
      onExtend: () => {},
    }) as unknown as VNode;
    expect(vnode.props?.["aria-live"]).toBe("assertive");
  });

  it("renders the Prolonger button (action available to the doctor)", () => {
    const vnode = SessionWarningBanner({
      remainingMs: WARN_BEFORE_MS,
      onExtend: () => {},
    }) as unknown as VNode;
    expect(containsText(vnode, "Prolonger")).toBe(true);
  });

  it("Prolonger button has aria-label for screen readers", () => {
    const vnode = SessionWarningBanner({
      remainingMs: WARN_BEFORE_MS,
      onExtend: () => {},
    }) as unknown as VNode;
    expect(containsAttr(vnode, "aria-label", "Prolonger la session")).toBe(true);
  });

  it("extend action is a button, not a link (no navigation side-effect)", () => {
    const vnode = SessionWarningBanner({
      remainingMs: WARN_BEFORE_MS,
      onExtend: () => {},
    }) as unknown as VNode;
    expect(containsType(vnode, "button")).toBe(true);
    expect(containsType(vnode, "a")).toBe(false);
  });

  it("Prolonger button onClick is wired directly to the onExtend prop", () => {
    const onExtend = vi.fn();
    const vnode = SessionWarningBanner({
      remainingMs: WARN_BEFORE_MS,
      onExtend,
    }) as unknown;
    const btn = findNode(vnode, (n) => n.type === "button");
    expect(btn?.props?.["onClick"]).toBe(onExtend);
  });

  it("banner is position:fixed pinned to top:0 (overlays content, no layout shift)", () => {
    const vnode = SessionWarningBanner({
      remainingMs: WARN_BEFORE_MS,
      onExtend: () => {},
    }) as unknown as VNode;
    const style = vnode.props?.["style"] as Record<string, unknown> | undefined;
    expect(style?.["position"]).toBe("fixed");
    expect(style?.["top"]).toBe(0);
  });

  it("shows '2:00' countdown when remainingMs = WARN_BEFORE_MS (initial state)", () => {
    const vnode = SessionWarningBanner({
      remainingMs: WARN_BEFORE_MS,
      onExtend: () => {},
    }) as unknown as VNode;
    expect(containsText(vnode, "2:00")).toBe(true);
  });

  it("shows '0:01' countdown when 1 second remains", () => {
    const vnode = SessionWarningBanner({
      remainingMs: 1_000,
      onExtend: () => {},
    }) as unknown as VNode;
    expect(containsText(vnode, "0:01")).toBe(true);
  });

  it("shows '0:00' countdown when remainingMs = 0", () => {
    const vnode = SessionWarningBanner({
      remainingMs: 0,
      onExtend: () => {},
    }) as unknown as VNode;
    expect(containsText(vnode, "0:00")).toBe(true);
  });

  it("banner copy does not contain patient data — French generic message only", () => {
    const vnode = SessionWarningBanner({
      remainingMs: WARN_BEFORE_MS,
      onExtend: () => {},
    }) as unknown as VNode;
    // Confirm generic warning text present
    expect(containsText(vnode, "session se fermera")).toBe(true);
    // Confirm no PII, keys, or IDs leak into the banner
    expect(containsText(vnode, "uuid")).toBe(false);
    expect(containsText(vnode, "key")).toBe(false);
    expect(containsText(vnode, "patient")).toBe(false);
  });

  it("banner does not display IDLE_TIMEOUT_MS value as raw milliseconds", () => {
    const vnode = SessionWarningBanner({
      remainingMs: WARN_BEFORE_MS,
      onExtend: () => {},
    }) as unknown as VNode;
    expect(containsText(vnode, String(IDLE_TIMEOUT_MS))).toBe(false);
    expect(containsText(vnode, String(WARN_BEFORE_MS))).toBe(false);
  });
});

// ── RecordScreen initial state — no spurious warning banner ───────────────────

describe("RecordScreen — initial state (isWarning=false, #122)", () => {
  const noop = () => {};

  it("no role=alert in VNode tree when session is fresh (isWarning=false)", () => {
    const vnode = RecordScreen({
      record: null,
      pendingCount: 0,
      onSynced: noop,
      onAddNote: noop,
      onTerminated: noop,
    }) as unknown;
    expect(containsRole(vnode, "alert")).toBe(false);
  });

  it("no role=alertdialog in VNode tree before terminate is triggered", () => {
    const vnode = RecordScreen({
      record: null,
      pendingCount: 0,
      onSynced: noop,
      onAddNote: noop,
      onTerminated: noop,
    }) as unknown;
    expect(containsRole(vnode, "alertdialog")).toBe(false);
  });

  it("root element attaches resetIdleTimer on both scroll and click", () => {
    const vnode = RecordScreen({
      record: null,
      pendingCount: 0,
      onSynced: noop,
      onAddNote: noop,
      onTerminated: noop,
    }) as unknown as VNode;
    expect(typeof vnode.props?.["onScroll"]).toBe("function");
    expect(typeof vnode.props?.["onClick"]).toBe("function");
  });

  it("scroll and click handlers are the same function (single reset seam for #120)", () => {
    const vnode = RecordScreen({
      record: null,
      pendingCount: 0,
      onSynced: noop,
      onAddNote: noop,
      onTerminated: noop,
    }) as unknown as VNode;
    expect(vnode.props?.["onScroll"]).toBe(vnode.props?.["onClick"]);
  });
});

// ── RecordScreen — isWarning state transitions (#122) ─────────────────────────
//
// These tests inject state via mockReturnValueOnce to simulate the component
// after the idle timer fires. RecordScreen's useState call order:
//   1. isSyncing      (false)
//   2. isTerminating  (false)
//   3. snack          (null)
//   4. isWarning      (false → overridden to true in these tests)

describe("RecordScreen — isWarning=true state (#122)", () => {
  const noop = () => {};

  it("SessionWarningBanner VNode is present when isWarning=true", () => {
    vi.mocked(hooks.useState)
      .mockReturnValueOnce([false, vi.fn()])  // isSyncing
      .mockReturnValueOnce([false, vi.fn()])  // isTerminating
      .mockReturnValueOnce([null,  vi.fn()])  // snack
      .mockReturnValueOnce([true,  vi.fn()]); // isWarning → true

    const vnode = RecordScreen({
      record: null,
      pendingCount: 0,
      onSynced: noop,
      onAddNote: noop,
      onTerminated: noop,
    }) as unknown;
    expect(containsVNodeType(vnode, SessionWarningBanner)).toBe(true);
  });

  it("banner receives remainingMs=WARN_BEFORE_MS (correct initial countdown)", () => {
    vi.mocked(hooks.useState)
      .mockReturnValueOnce([false, vi.fn()])
      .mockReturnValueOnce([false, vi.fn()])
      .mockReturnValueOnce([null,  vi.fn()])
      .mockReturnValueOnce([true,  vi.fn()]);

    const vnode = RecordScreen({
      record: null,
      pendingCount: 0,
      onSynced: noop,
      onAddNote: noop,
      onTerminated: noop,
    }) as unknown;
    const bannerVNode = findNode(vnode, (n) => n.type === SessionWarningBanner);
    expect(bannerVNode?.props?.["remainingMs"]).toBe(WARN_BEFORE_MS);
  });

  it("banner onExtend prop is a function (resetIdleTimer seam reachable)", () => {
    vi.mocked(hooks.useState)
      .mockReturnValueOnce([false, vi.fn()])
      .mockReturnValueOnce([false, vi.fn()])
      .mockReturnValueOnce([null,  vi.fn()])
      .mockReturnValueOnce([true,  vi.fn()]);

    const vnode = RecordScreen({
      record: null,
      pendingCount: 0,
      onSynced: noop,
      onAddNote: noop,
      onTerminated: noop,
    }) as unknown;
    const bannerVNode = findNode(vnode, (n) => n.type === SessionWarningBanner);
    expect(typeof bannerVNode?.props?.["onExtend"]).toBe("function");
  });

  it("banner is suppressed when isTerminating=true (session close in progress)", () => {
    vi.mocked(hooks.useState)
      .mockReturnValueOnce([false, vi.fn()])  // isSyncing
      .mockReturnValueOnce([true,  vi.fn()])  // isTerminating → true
      .mockReturnValueOnce([null,  vi.fn()])  // snack
      .mockReturnValueOnce([true,  vi.fn()]); // isWarning → true

    const vnode = RecordScreen({
      record: null,
      pendingCount: 0,
      onSynced: noop,
      onAddNote: noop,
      onTerminated: noop,
    }) as unknown;
    // isWarning && !isTerminating is false → banner absent
    expect(containsVNodeType(vnode, SessionWarningBanner)).toBe(false);
  });
});
