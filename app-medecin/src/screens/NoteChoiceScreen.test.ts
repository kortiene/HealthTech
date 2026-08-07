// VNode-level structural tests for NoteChoiceScreen (#119).
//
// Environment: vitest + node (no DOM). preact/hooks stubbed — NoteChoiceScreen
// is a pure presentational component with no hooks, so no mocking needed.
//
// Coverage:
//   - Both choice cards render ("Note écrite", "Note vocale")
//   - Close button is present with correct aria-label
//   - onWritten prop is wired to the "Note écrite" card
//   - onVoice prop is wired to the "Note vocale" card
//   - onCancel prop is wired to the close button
//   - No nav / aside / tablist chrome

import { describe, expect, it, vi } from "vitest";

vi.mock("preact/hooks", () => ({
  useState: (initial: unknown) => [initial, () => {}],
  useEffect: () => {},
  useRef: () => ({ current: undefined }),
}));

import { NoteChoiceScreen } from "./NoteChoiceScreen";

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

function containsText(node: unknown, text: string): boolean {
  if (typeof node === "string") return node.includes(text);
  if (!node || typeof node !== "object") return false;
  const n = node as VNode;
  const children = n.props?.["children"];
  if (Array.isArray(children))
    return (children as unknown[]).some((c) => containsText(c, text));
  return containsText(children, text);
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

// ── Tests ──────────────────────────────────────────────────────────────────────

describe("NoteChoiceScreen — structure (#119)", () => {
  // _NoteCard is a function component VNode — its label/description are props,
  // not expanded text nodes. We inspect the VNode props directly.

  it("written card has label='Note écrite'", () => {
    const vnode = NoteChoiceScreen({ onWritten: noop, onVoice: noop, onCancel: noop });
    const nodes = findAll(vnode, (n) => n.props?.["label"] === "Note écrite");
    expect(nodes.length).toBeGreaterThan(0);
  });

  it("voice card has label='Note vocale'", () => {
    const vnode = NoteChoiceScreen({ onWritten: noop, onVoice: noop, onCancel: noop });
    const nodes = findAll(vnode, (n) => n.props?.["label"] === "Note vocale");
    expect(nodes.length).toBeGreaterThan(0);
  });

  it("written card has description='Formulaire structuré'", () => {
    const vnode = NoteChoiceScreen({ onWritten: noop, onVoice: noop, onCancel: noop });
    const nodes = findAll(vnode, (n) => n.props?.["description"] === "Formulaire structuré");
    expect(nodes.length).toBeGreaterThan(0);
  });

  it("voice card has description='Enregistrement audio'", () => {
    const vnode = NoteChoiceScreen({ onWritten: noop, onVoice: noop, onCancel: noop });
    const nodes = findAll(vnode, (n) => n.props?.["description"] === "Enregistrement audio");
    expect(nodes.length).toBeGreaterThan(0);
  });

  it("instructional text is present as rendered paragraph", () => {
    const vnode = NoteChoiceScreen({ onWritten: noop, onVoice: noop, onCancel: noop });
    expect(containsText(vnode, "Quel type de note")).toBe(true);
  });

  it("close button has aria-label='Fermer'", () => {
    const vnode = NoteChoiceScreen({ onWritten: noop, onVoice: noop, onCancel: noop });
    expect(containsAttr(vnode, "aria-label", "Fermer")).toBe(true);
  });

  it("renders no <nav> element", () => {
    const vnode = NoteChoiceScreen({ onWritten: noop, onVoice: noop, onCancel: noop });
    expect(containsType(vnode, "nav")).toBe(false);
  });
});

describe("NoteChoiceScreen — prop wiring (#119)", () => {
  // _NoteCard renders as a component VNode (type === function), not a raw <button>.
  // We search for any node with the matching onClick prop, regardless of type.

  it("onWritten is wired into the VNode tree", () => {
    const onWritten = vi.fn();
    const vnode = NoteChoiceScreen({ onWritten, onVoice: noop, onCancel: noop });
    const nodes = findAll(vnode, (n) => n.props?.["onClick"] === onWritten);
    expect(nodes.length).toBeGreaterThan(0);
  });

  it("onVoice is wired into the VNode tree", () => {
    const onVoice = vi.fn();
    const vnode = NoteChoiceScreen({ onWritten: noop, onVoice, onCancel: noop });
    const nodes = findAll(vnode, (n) => n.props?.["onClick"] === onVoice);
    expect(nodes.length).toBeGreaterThan(0);
  });

  it("onCancel is wired to the close button (aria-label='Fermer')", () => {
    const onCancel = vi.fn();
    const vnode = NoteChoiceScreen({ onWritten: noop, onVoice: noop, onCancel });
    const buttons = findAll(vnode, (n) => n.type === "button");
    const closeBtn = buttons.find((b) => b.props?.["aria-label"] === "Fermer");
    expect(closeBtn).toBeDefined();
    expect(closeBtn?.props?.["onClick"]).toBe(onCancel);
  });

  it("onWritten and onVoice are distinct nodes", () => {
    const onWritten = vi.fn();
    const onVoice = vi.fn();
    const vnode = NoteChoiceScreen({ onWritten, onVoice, onCancel: noop });
    const writtenNodes = findAll(vnode, (n) => n.props?.["onClick"] === onWritten);
    const voiceNodes = findAll(vnode, (n) => n.props?.["onClick"] === onVoice);
    expect(writtenNodes.length).toBeGreaterThan(0);
    expect(voiceNodes.length).toBeGreaterThan(0);
    expect(writtenNodes[0]).not.toBe(voiceNodes[0]);
  });
});
