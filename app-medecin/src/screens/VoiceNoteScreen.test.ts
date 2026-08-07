// VNode-level structural tests for VoiceNoteScreen (#120).
//
// Environment: vitest + node (no DOM). preact/hooks stubbed — useState returns
// initial value, useEffect/useRef are no-ops. The component tree is inspected
// as a plain VNode object.
//
// Coverage:
//   - Idle phase: mic button, doctor-name input, aria-labels
//   - Recording phase: stop button, live-region, timer display
//   - Preview phase: audio element, Recommencer button, Enregistrer button
//   - onCancel wired to close button
//   - No nav / aside / tablist chrome

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("preact/hooks", () => ({
  useState: vi.fn((initial: unknown) => [initial, () => {}]),
  useEffect: vi.fn(),
  useRef: vi.fn(() => ({ current: null })),
}));

import * as hooks from "preact/hooks";
import { VoiceNoteScreen } from "./VoiceNoteScreen";

// ── VNode helpers ──────────────────────────────────────────────────────────────

type VNode = { type?: unknown; props?: Record<string, unknown> };

function findAll(node: unknown, pred: (n: VNode) => boolean): VNode[] {
  if (!node || typeof node !== "object") return [];
  const n = node as VNode;
  const found: VNode[] = pred(n) ? [n] : [];
  const children = n.props?.["children"];
  if (Array.isArray(children)) {
    for (const c of children as unknown[]) found.push(...findAll(c, pred));
  } else {
    found.push(...findAll(children, pred));
  }
  return found;
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

function containsType(node: unknown, tag: string): boolean {
  if (!node || typeof node !== "object") return false;
  const n = node as VNode;
  if (n.type === tag) return true;
  const children = n.props?.["children"];
  if (Array.isArray(children))
    return (children as unknown[]).some((c) => containsType(c, tag));
  return containsType(children, tag);
}

const noop = () => {};
const noopAsync = async () => {};

const defaultProps = {
  backendUrl: "http://backend.test",
  writeToken: undefined,
  onSaved: noopAsync,
  onCancel: noop,
};

beforeEach(() => {
  vi.mocked(hooks.useState).mockImplementation(
    (initial?: unknown) => [initial, () => {}],
  );
});

afterEach(() => {
  vi.mocked(hooks.useState).mockReset();
});

// ── Idle phase (initial state) ─────────────────────────────────────────────────

describe("VoiceNoteScreen — idle phase (#120)", () => {
  it("renders doctor-name input field", () => {
    const vnode = VoiceNoteScreen(defaultProps);
    const inputs = findAll(vnode, (n) => n.type === "input");
    expect(inputs.length).toBeGreaterThan(0);
  });

  it("doctor-name input has id='voice-doctor-name'", () => {
    const vnode = VoiceNoteScreen(defaultProps);
    expect(containsAttr(vnode, "id", "voice-doctor-name")).toBe(true);
  });

  it("start-recording button has aria-label", () => {
    const vnode = VoiceNoteScreen(defaultProps);
    expect(
      containsAttr(vnode, "aria-label", "Démarrer l'enregistrement"),
    ).toBe(true);
  });

  it("close button has aria-label='Fermer'", () => {
    const vnode = VoiceNoteScreen(defaultProps);
    expect(containsAttr(vnode, "aria-label", "Fermer")).toBe(true);
  });

  it("no <nav> element", () => {
    const vnode = VoiceNoteScreen(defaultProps);
    expect(containsType(vnode, "nav")).toBe(false);
  });
});

// ── Recording phase ────────────────────────────────────────────────────────────

describe("VoiceNoteScreen — recording phase (#120)", () => {
  beforeEach(() => {
    vi.mocked(hooks.useState)
      .mockReturnValueOnce(["", () => {}])          // doctorName
      .mockReturnValueOnce(["recording", () => {}]) // phase
      .mockReturnValueOnce([5000, () => {}])         // durationMs
      .mockReturnValueOnce([null, () => {}])         // audioUrl
      .mockReturnValueOnce([null, () => {}])         // audioBlob
      .mockReturnValueOnce([false, () => {}])        // isSaving
      .mockReturnValueOnce([null, () => {}]);        // error
  });

  it("stop button is present", () => {
    const vnode = VoiceNoteScreen(defaultProps);
    expect(containsAttr(vnode, "aria-label", "Arrêter l'enregistrement")).toBe(
      true,
    );
  });

  it("live region is present (aria-live=polite)", () => {
    const vnode = VoiceNoteScreen(defaultProps);
    expect(containsAttr(vnode, "aria-live", "polite")).toBe(true);
  });
});

// ── Preview phase ──────────────────────────────────────────────────────────────

describe("VoiceNoteScreen — preview phase (#120)", () => {
  const fakeUrl = "blob:http://localhost/fake-audio";

  beforeEach(() => {
    vi.mocked(hooks.useState)
      .mockReturnValueOnce(["Dr. Koné", () => {}])  // doctorName
      .mockReturnValueOnce(["preview", () => {}])   // phase
      .mockReturnValueOnce([12000, () => {}])        // durationMs
      .mockReturnValueOnce([fakeUrl, () => {}])      // audioUrl
      .mockReturnValueOnce([new Blob(), () => {}])   // audioBlob
      .mockReturnValueOnce([false, () => {}])        // isSaving
      .mockReturnValueOnce([null, () => {}]);        // error
  });

  it("renders native <audio> element with blob src", () => {
    const vnode = VoiceNoteScreen(defaultProps);
    expect(containsAttr(vnode, "src", fakeUrl)).toBe(true);
  });

  it("Recommencer button is present", () => {
    const vnode = VoiceNoteScreen(defaultProps);
    const buttons = findAll(vnode, (n) => n.type === "button");
    const restart = buttons.find((b) =>
      String(b.props?.["children"]).includes("Recommencer") ||
      findAll(b, (n) =>
        typeof n.props?.["children"] === "string" &&
        (n.props["children"] as string).includes("Recommencer"),
      ).length > 0
    );
    expect(restart).toBeDefined();
  });

  it("Enregistrer button is present", () => {
    const vnode = VoiceNoteScreen(defaultProps);
    expect(containsAttr(vnode, "aria-label", "Enregistrer la consultation")).toBe(
      true,
    );
  });
});

// ── Prop wiring ────────────────────────────────────────────────────────────────

describe("VoiceNoteScreen — prop wiring (#120)", () => {
  it("onCancel is wired to the close button", () => {
    const onCancel = vi.fn();
    const vnode = VoiceNoteScreen({ ...defaultProps, onCancel });
    const buttons = findAll(vnode, (n) => n.type === "button");
    const closeBtn = buttons.find((b) => b.props?.["aria-label"] === "Fermer");
    expect(closeBtn).toBeDefined();
    expect(closeBtn?.props?.["onClick"]).toBe(onCancel);
  });
});
