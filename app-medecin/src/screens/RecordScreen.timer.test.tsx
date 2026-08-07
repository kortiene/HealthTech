// @vitest-environment jsdom
//
// Timer integration tests for RecordScreen's idle session logic (#122).
//
// These tests use jsdom (real DOM) + vi.useFakeTimers() to verify that:
//   - The warning banner appears after SESSION_IDLE_MINUTES - 2 min of inactivity
//   - The banner does NOT appear before the threshold
//   - A click on the screen resets the idle timer (banner dismissed)
//   - onTerminated fires after SESSION_IDLE_MINUTES of inactivity
//
// The gap noted in RecordScreen.test.ts is filled here.
//
// Timing constants:
//   WARN fires at:  IDLE_TIMEOUT_MS - WARN_BEFORE_MS  (default: 28 min)
//   CLOSE fires at: IDLE_TIMEOUT_MS                   (default: 30 min)
//   terminateSession has a 900 ms internal delay before calling onTerminated

import { h, render } from "preact";
import { act } from "preact/test-utils";
import { afterEach, beforeEach, expect, it, vi } from "vitest";
import { IDLE_TIMEOUT_MS, WARN_BEFORE_MS } from "../session";
import { RecordScreen } from "./RecordScreen";

const noop = () => {};

function mountRecord(onTerminated = noop): HTMLDivElement {
  const container = document.createElement("div");
  document.body.appendChild(container);
  act(() => {
    render(
      h(RecordScreen, {
        record: null,
        pendingCount: 0,
        onSynced: noop,
        onAddNote: noop,
        onTerminated,
      }),
      container,
    );
  });
  return container;
}

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
  document.body.innerHTML = "";
});

// ─── Warning banner appearance ─────────────────────────────────────────────────

it("no warning banner on fresh mount (SESSION_IDLE_MINUTES not yet elapsed)", () => {
  const container = mountRecord();
  expect(container.querySelector('[role="alert"]')).toBeNull();
});

it("no warning banner 1 s before the warn threshold", async () => {
  const container = mountRecord();

  await act(async () => {
    vi.advanceTimersByTime(IDLE_TIMEOUT_MS - WARN_BEFORE_MS - 1000);
  });

  expect(container.querySelector('[role="alert"]')).toBeNull();
});

it("warning banner appears 1 ms after the warn threshold", async () => {
  const container = mountRecord();

  await act(async () => {
    vi.advanceTimersByTime(IDLE_TIMEOUT_MS - WARN_BEFORE_MS + 1);
  });

  expect(container.querySelector('[role="alert"]')).not.toBeNull();
});

it("warning banner contains « Prolonger » button", async () => {
  const container = mountRecord();

  await act(async () => {
    vi.advanceTimersByTime(IDLE_TIMEOUT_MS - WARN_BEFORE_MS + 1);
  });

  const button = container.querySelector('[aria-label="Prolonger la session"]');
  expect(button).not.toBeNull();
});

// ─── Timer reset via user activity ────────────────────────────────────────────

it("clicking the screen resets the idle timer and hides the banner", async () => {
  const container = mountRecord();

  // Trigger the banner
  await act(async () => {
    vi.advanceTimersByTime(IDLE_TIMEOUT_MS - WARN_BEFORE_MS + 1);
  });
  expect(container.querySelector('[role="alert"]')).not.toBeNull();

  // Simulate user click → calls onClick={resetIdleTimer} on the outer div
  await act(async () => {
    (container.firstElementChild as HTMLElement)?.click();
  });

  expect(container.querySelector('[role="alert"]')).toBeNull();
});

it("clicking before threshold postpones banner by a full cycle", async () => {
  const container = mountRecord();

  // Advance to 10 s before warn, then click
  await act(async () => {
    vi.advanceTimersByTime(IDLE_TIMEOUT_MS - WARN_BEFORE_MS - 10_000);
  });
  await act(async () => {
    (container.firstElementChild as HTMLElement)?.click();
  });

  // Advance another IDLE_TIMEOUT_MS - WARN_BEFORE_MS - 1 s: still no banner
  await act(async () => {
    vi.advanceTimersByTime(IDLE_TIMEOUT_MS - WARN_BEFORE_MS - 1000);
  });
  expect(container.querySelector('[role="alert"]')).toBeNull();
});

// ─── Auto-close ────────────────────────────────────────────────────────────────

it("calls onTerminated after IDLE_TIMEOUT_MS of inactivity", async () => {
  const onTerminated = vi.fn();
  mountRecord(onTerminated);

  // IDLE_TIMEOUT_MS fires closeTimer → terminateSession → 900 ms delay → onTerminated
  await act(async () => {
    vi.advanceTimersByTime(IDLE_TIMEOUT_MS + 1000);
  });

  expect(onTerminated).toHaveBeenCalledOnce();
});
