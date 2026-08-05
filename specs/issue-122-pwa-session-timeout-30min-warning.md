# PWA Doctor Session — 30-min Idle Timeout + Pre-Close Warning

_Issue #122 — `feat(pwa): session médecin — timeout 30 min + avertissement avant fermeture` (labels: enhancement, ux)_

## Problem Statement

The doctor PWA (`app-medecin/`) auto-closes the consultation session after **15 minutes** of inactivity and wipes the in-RAM medical record (`IDLE_TIMEOUT_MS = 15 * 60 * 1000`). Two gaps hurt the doctor’s experience:

1. **Silent closure.** No warning precedes the wipe. A doctor mid-note can lose in-progress input the instant the timer fires.
2. **Window too short.** 15 min is aggressive for a real consultation with interruptions.

The request: raise the idle window to **30 min** and show a persistent, dismissible **“Prolonger”** warning **2 minutes before** auto-close (at T-28 min), with a live countdown, while preserving the existing wipe-on-idle security guarantee.

## Goals

- Raise the idle auto-close window to **30 min** (`IDLE_TIMEOUT_MS = 30 * 60 * 1000`).
- Introduce `WARN_BEFORE_MS = 2 * 60 * 1000` and emit a warning at `IDLE_TIMEOUT_MS - WARN_BEFORE_MS` (T-28 min).
- Render a persistent warning banner (styled consistently with `TerminatingOverlay`) with the copy _« Votre session se fermera dans 2 min faute d’activité. »_, a live countdown, and a **« Prolonger »** button.
- **« Prolonger »** resets both timers and hides the banner (`isWarning → false`).
- Any activity (scroll, click — the existing reset surface) resets both timers _and_ clears the warning state.
- At T-0 (30 min), preserve the existing secure-close behaviour (`TerminatingOverlay` + `onTerminated` → wipe + return to scan).
- Provide an **activity hook** so that, once voice recording (#120) lands, `MediaRecorder` `dataavailable` events count as activity and prevent closure mid-recording. (See Non-Goals — the recording screen does not exist yet.)
- Keep `session.ts` as the single source of truth for both constants; `RecordScreen.tsx` must import them (it currently redefines `IDLE_TIMEOUT_MS` locally).
- Update the three existing tests that assert the 15-min value so the suite stays green.

## Non-Goals

- **Implementing voice recording / `VoiceNoteScreen` / `MediaRecorder` (#120).** No such component or `MediaRecorder` usage exists in the tree today. This spec only defines the activity-reset hook the future recording screen will call; it does not build the recorder. Do not add `MediaRecorder` wiring that references a non-existent screen.
- Changing the wipe-on-idle security model, the reload-to-drop-heap behaviour, or the crypto path (ADR 0002 / ADR 0003).
- Server-side session/idle enforcement — timeout is a client-only UX safeguard; the server remains zero-knowledge and stateless w.r.t. sessions.
- Configurable/persisted timeout preferences, or cross-tab session coordination.
- Reworking `SnackBar` semantics; the warning is a distinct persistent banner, not an ephemeral snackbar.

## Relevant Repository Context

- **Affected package:** `app-medecin/` — the healthcare-professional PWA. Its stack **is** decided by **ADR 0002**: **Preact + TypeScript + Vite**, tested with **vitest** (`npm test` → `vitest run`). This is the local exception to the “stack undecided (#1)” note — no stack decision is open for this package. (Backlog #1’s open stack question concerns the wider platform, not this PWA.)
- **`app-medecin/src/session.ts`** — pure, dependency-free helpers. Exports `sessionTitle()` and `IDLE_TIMEOUT_MS = 15 * 60 * 1000` (line 20), documented as “wipe RAM + reload after 15 min — see ADR 0002”.
- **`app-medecin/src/screens/RecordScreen.tsx`** — owns the idle timer today. Notable current state:
  - Line 19 **redefines** `const IDLE_TIMEOUT_MS = 15 * 60 * 1000;` locally instead of importing from `session.ts` (duplication to fix).
  - Single `idleTimer = useRef<number>()`; `resetIdleTimer()` clears + re-arms one `setTimeout(terminateSession, IDLE_TIMEOUT_MS)`.
  - `useEffect(..., [])` arms on mount and clears on unmount.
  - Reset surface: the root `<div onScroll={resetIdleTimer} onClick={resetIdleTimer}>` (line 395).
  - `terminateSession()` sets `isTerminating` → shows `<TerminatingOverlay/>` → calls `onTerminated`.
  - Existing state pattern: `useState` for `isSyncing`, `isTerminating`, `snack`.
- **`app-medecin/src/screens/TerminatingOverlay.tsx`** — full-screen `role="alertdialog"` overlay: dimmed backdrop, centered `.card` with `<Spinner/>` + “Fermeture sécurisée…”. Reuse its `.card`, spacing tokens (`var(--space-*)`, `var(--radius-*)`) and color tokens for the banner’s visual language.
- **`app-medecin/src/components/SnackBar.tsx`** — fixed-position status component with tones (`neutral|warning|error|success`) and an optional dismiss button; `warning` tone uses ambre (`--color-accent-700`). Good style reference for a persistent top banner, though the warning banner is a new component (it carries a countdown + action, is not auto-dismissed).
- **`app-medecin/src/app.tsx`** — the screen FSM (`scan | record | edit`). `onTerminated` resets all in-memory state (`scannedRecord`, `rawFlutter`, `qrPayload`, `pendingCount`) and returns to `scan`. No change required, but confirm the warning/timeout live only on `record` (and later on the voice/edit surfaces if they hold decrypted data).
- **Tests hardcoding the 15-min value (all must change):**
  - `app-medecin/src/app.test.ts:9-10` — `expect(IDLE_TIMEOUT_MS).toBe(900_000)`.
  - `app-medecin/src/walkthrough.test.ts:96-97` — `toBe(15 * 60 * 1000)`.
  - `app-medecin/src/walkthrough.test.ts:131-133` — `toBe(15 * 60 * 1000)`.
- **Docs referencing 15 min (must update):** `session.ts` comment (line 19), `app-medecin/README.md:10`, `docs/adr/0002-doctor-interface-pwa.md` (lines ~9–10 and ~18).
- **Conventions:** French microcopy, action-first; single-flow / zero-menu UX norm (`docs/ux/medecin-ux-guidelines.md`); inline style objects with CSS custom-property tokens; timers via `window.setTimeout` / `window.clearTimeout` with numeric ref handles; accessibility roles on overlays (`role="alertdialog"`, `aria-label`).

## Proposed Implementation

### 1. `session.ts` — constants (single source of truth)

```ts
/** Idle auto-close window (ms): wipe RAM + reload after 30 min — see ADR 0002. */
export const IDLE_TIMEOUT_MS = 30 * 60 * 1000; // 30 min

/** Show the pre-close warning this long before IDLE_TIMEOUT_MS (2 min). */
export const WARN_BEFORE_MS = 2 * 60 * 1000; // 2 min
```

Update the file’s doc comment (line 19 and the header block’s “wiped on idle” note) to say 30 min. Keep the module pure/no-I/O.

### 2. `RecordScreen.tsx` — two-phase idle timer

- **Remove** the local `const IDLE_TIMEOUT_MS` (line 19); **import** `{ IDLE_TIMEOUT_MS, WARN_BEFORE_MS }` from `../session`.
- Add state: `const [isWarning, setIsWarning] = useState(false);`
- Replace the single `idleTimer` ref with **two** ref handles: `warnTimer` and `closeTimer` (both `useRef<number | undefined>`).
- Rewrite `resetIdleTimer()`:
  ```ts
  function resetIdleTimer() {
    if (warnTimer.current) window.clearTimeout(warnTimer.current);
    if (closeTimer.current) window.clearTimeout(closeTimer.current);
    setIsWarning(false);
    warnTimer.current = window.setTimeout(
      () => setIsWarning(true),
      IDLE_TIMEOUT_MS - WARN_BEFORE_MS,
    );
    closeTimer.current = window.setTimeout(
      () => terminateSession(),
      IDLE_TIMEOUT_MS,
    );
  }
  ```
- `useEffect(..., [])`: call `resetIdleTimer()` on mount; on cleanup clear **both** timers.
- The root `<div onScroll onClick>` continues to call `resetIdleTimer` — this now also clears the warning. **Important:** clicking the **« Prolonger »** button naturally bubbles to the root `onClick` and resets; still wire the button’s own `onClick={resetIdleTimer}` explicitly so behaviour is intentional and testable, and so it works even if bubbling is later stopped.
- **Countdown:** the banner needs a live “dans N s / N min” display. Recommended approach: the banner component owns a 1-second `setInterval` (or recomputes from a target timestamp) that starts when it mounts (i.e. when `isWarning` becomes true). Pass it the remaining window (`WARN_BEFORE_MS`) or a target close time. Keep the countdown **display-only**; the authoritative close is `closeTimer`, not the interval, to avoid drift. Clear the interval on unmount.

### 3. `_SessionWarningBanner` component

A new small component (co-located in `RecordScreen.tsx` following the file’s existing `_`-prefixed/local-helper convention, or a sibling `components/SessionWarningBanner.tsx` — pick one and be consistent with neighbours; co-location matches the current file’s style of local sub-components).

Requirements:
- Fixed banner pinned to the **top** (`position: fixed; top: 0; left/right: 0; zIndex` above content but interplay-safe with `AppBar`).
- Reuse `TerminatingOverlay`/`.card` visual tokens; use the `warning`/ambre palette (`--color-accent-700`) consistent with `SnackBar`’s warning tone.
- Copy: _« Votre session se fermera dans {mm:ss ou N min} faute d’activité. »_ — action-first French per the UX norm.
- A **« Prolonger »** button (min 44–48px touch target, matching existing buttons) → `onExtend` prop → `resetIdleTimer()`.
- Accessibility: `role="alert"` (or `role="status"` with `aria-live="assertive"`) so screen readers announce it; `aria-label` on the button.
- Props: `{ remainingMs: number; onExtend: () => void }` (or a target timestamp). Rendered only when `isWarning === true`.
- Render it near the top of `RecordScreen`’s tree (e.g. just under `AppBar`), and keep `{isTerminating && <TerminatingOverlay/>}` unchanged. When `isTerminating`, the warning banner is moot (session closing).

### 4. Activity hook for future voice recording (#120) — interface only

Since `VoiceNoteScreen`/`MediaRecorder` do **not** exist yet, do **not** wire a recorder. Instead, make the reset mechanism reusable so #120 can hook in with one line:
- Keep `resetIdleTimer` as the canonical “I am active” signal.
- **Document** (code comment + this spec) that when #120 lands, the recorder must call the session activity-reset on each `MediaRecorder` `dataavailable` event (and/or on `start`), e.g. by lifting the timer into a shared session-activity hook or passing an `onActivity` callback down to the recording surface.
- Optional (recommended, low-risk): extract the timer logic into a tiny `useIdleTimer({ onWarn, onClose })` hook or an `onActivity` prop so the future voice screen and `RecordScreen` share one implementation instead of duplicating. If extracted, place it under `app-medecin/src/` (e.g. `session.ts` stays constants-only; hook goes in `hooks/useIdleTimer.ts` or inline). Flag the extraction as a design choice to confirm (see Open Questions).

### 5. Tests & docs — see dedicated sections below.

## Affected Files / Packages / Modules

**Modify:**
- `app-medecin/src/session.ts` — bump `IDLE_TIMEOUT_MS` to 30 min, add `WARN_BEFORE_MS`, update comments.
- `app-medecin/src/screens/RecordScreen.tsx` — import constants, two-timer logic, `isWarning` state, render banner, explicit extend handler.
- `app-medecin/src/app.test.ts` — update the 15-min assertion.
- `app-medecin/src/walkthrough.test.ts` — update both 15-min assertions.
- `app-medecin/README.md` — “Auto-closes after 15 min idle” → 30 min (+ note the 2-min warning).
- `docs/adr/0002-doctor-interface-pwa.md` — update the two “15 min” idle references (or add an addendum noting the #122 change to 30 min + warning).

**Create:**
- `_SessionWarningBanner` (co-located) or `app-medecin/src/components/SessionWarningBanner.tsx`.
- Optionally `app-medecin/src/hooks/useIdleTimer.ts` (if extracting).
- New/extended test file for banner + timer behaviour (e.g. `app-medecin/src/screens/RecordScreen.test.tsx` or `session.test.ts` additions).

**Read for reference (no change expected):**
- `app-medecin/src/screens/TerminatingOverlay.tsx`, `app-medecin/src/components/SnackBar.tsx`, `app-medecin/src/app.tsx`, `docs/ux/medecin-ux-guidelines.md`.

## API / Interface Changes

- **Public module API (`session.ts`):** adds an exported constant `WARN_BEFORE_MS` and changes the value of exported `IDLE_TIMEOUT_MS` (15 → 30 min). These are internal-to-package exports (consumed by `RecordScreen` and tests); document them in `session.ts` doc comments.
- **New component prop surface:** `_SessionWarningBanner({ remainingMs | targetCloseAt, onExtend })` — internal to `app-medecin`.
- **Optional hook API:** `useIdleTimer({ timeoutMs, warnBeforeMs, onWarn, onClose }) → { reset }` if extracted.
- No CLI, network endpoint, or QR/access-token surface changes.

## Data Model / Protocol Changes

None. No record schema, encrypted-blob format, persistence, or serialization changes. The timeout is a client-side UI timer only; nothing is written to disk or the network.

## Security & Compliance Considerations

- **Wipe-on-idle guarantee preserved and strengthened.** The record is decrypted **in RAM only** and wiped on idle (ADR 0002/0003). Raising the window to 30 min extends the in-RAM exposure window by 15 min — an intentional UX/security trade-off approved by this issue. The warning does **not** weaken the close: T-0 still triggers the existing `terminateSession` → `onTerminated` → state wipe + reload-to-drop-heap path.
- **« Prolonger » resets the full 30-min window** (not just the 2-min warning). This is the intended behaviour per the issue; note in the ADR that a doctor can repeatedly extend while actively working — acceptable since each extension requires an explicit human action.
- **No plaintext/PII/keys in logs or the banner.** The banner shows only a generic French message and a countdown — never patient data. Do not `console.log` timer events with any record context.
- **Zero-knowledge server untouched.** No session state leaves the client; the server continues to store only opaque AES-256-GCM blobs keyed by anonymous UUIDs (~120 s ephemeral QR access unchanged).
- **Data residency (ARTCI / loi n°2013-450), ≤500 KB plaintext budget, no heavy images on device (ephemeral URL only):** unaffected — this change is presentation-layer timing only.
- **Future #120 note:** when `MediaRecorder` activity resets the timer, ensure recorded audio buffers themselves follow the same RAM-only / wipe discipline; that is #120’s responsibility, not this issue’s.

## Testing Plan

Framework: **vitest** (`npm test` in `app-medecin/`). Use fake timers (`vi.useFakeTimers()`) to drive the two-phase timer deterministically.

**Unit (constants):**
- `IDLE_TIMEOUT_MS === 30 * 60 * 1000` (1_800_000).
- `WARN_BEFORE_MS === 2 * 60 * 1000` (120_000).
- Sanity: `WARN_BEFORE_MS < IDLE_TIMEOUT_MS` and warn fires at 28 min.

**Component/behaviour (RecordScreen):**
- Warning banner is **not** shown initially.
- After advancing fake time to `IDLE_TIMEOUT_MS - WARN_BEFORE_MS`, `isWarning` becomes true and the banner (with « Prolonger ») renders.
- Advancing to `IDLE_TIMEOUT_MS` triggers `terminateSession` (`TerminatingOverlay` shown / `onTerminated` called).
- Clicking « Prolonger » at T-29 hides the banner and, after another 28 min, the warning reappears (proves full reset).
- A simulated activity event (scroll/click) during the warning window clears `isWarning` and resets both timers.
- Countdown display decrements (assert text after advancing the interval, e.g. shows a smaller value after 1 min).
- Accessibility: banner exposes an alert/live role and the button has an `aria-label`/accessible name.

**Update existing tests** (`app.test.ts`, `walkthrough.test.ts`) from 15-min to 30-min assertions, keeping the ADR-reference comments accurate.

**Not applicable here:** crypto-vector tests (no crypto touched), offline/degraded-network resilience (no network path touched) — state this so reviewers don’t expect them.

## Documentation Updates

- `docs/adr/0002-doctor-interface-pwa.md` — change the idle references from 15 min to 30 min and note the new 2-min pre-close warning with « Prolonger » (either edit in place or add a short “Update #122” note). Confirm whether the ADR value is normative (may need an ADR amendment rather than a silent edit — see Open Questions).
- `app-medecin/README.md` line 10 — “Auto-closes after 15 min idle” → “Auto-closes after 30 min idle, with a 2-min pre-close warning”.
- `session.ts` doc comments — reflect 30 min and the warning constant.
- `docs/ux/medecin-ux-guidelines.md` — optionally record the warning-banner pattern/microcopy as part of the single-flow UX norm.
- `BACKLOG.md` — if #122 is tracked there, mark it and cross-reference #120 (voice) and #29 (idle/wipe invariant).

## Risks and Open Questions

- **ADR 0002 normativity.** The 15-min value is documented in an ADR (“wipe-on-idle”). Changing it may warrant an ADR amendment/superseding note rather than an in-place edit. _Confirm the preferred doc-governance approach._
- **Extended RAM exposure.** 30 min doubles the maximum in-RAM plaintext window vs. today. Confirm this is acceptable to the security/compliance owner (it is the explicit ask of #122, but should be acknowledged in the ADR).
- **#120 dependency ordering.** The “recording counts as activity” requirement cannot be built or tested end-to-end until `VoiceNoteScreen` + `MediaRecorder` exist (#120). This spec delivers only the reusable activity-reset seam. _Confirm #122 ships without the voice hook wired, or is gated on #120._ Recommendation: ship #122 now (timeout + banner + hook seam) and wire `dataavailable` in #120.
- **Timer extraction.** Whether to extract a shared `useIdleTimer` hook now (cleaner for #120) or keep timer logic inline in `RecordScreen` for a smaller diff. Recommendation: light inline implementation now with an `onActivity`-friendly shape; extract when #120 needs it. _Confirm._
- **Countdown source of truth.** Using a 1-s `setInterval` for display can drift; recommend deriving the displayed remaining time from a target timestamp captured when the warning arms, with the authoritative close still on `closeTimer`. Under vitest fake timers, prefer advancing timers over wall-clock reads.
- **Banner vs. AppBar layering.** A top-fixed banner must not obscure critical `AppBar` controls (Terminate/Sync). Confirm placement (below AppBar vs. overlaying) with the UX norm.
- **Background-tab throttling.** Browsers throttle `setTimeout` in backgrounded tabs, so real close time may exceed 30 min if the tab is hidden — acceptable (fails safe toward keeping the doctor’s view), but note it.

## Implementation Checklist

1. `session.ts`: set `IDLE_TIMEOUT_MS = 30 * 60 * 1000`; add `export const WARN_BEFORE_MS = 2 * 60 * 1000`; update doc comments (30 min + warning).
2. `RecordScreen.tsx`: delete local `IDLE_TIMEOUT_MS`; import `{ IDLE_TIMEOUT_MS, WARN_BEFORE_MS }` from `../session`.
3. Add `const [isWarning, setIsWarning] = useState(false)` and two timer refs (`warnTimer`, `closeTimer`).
4. Rewrite `resetIdleTimer()` to clear both timers, `setIsWarning(false)`, and arm warn (`IDLE_TIMEOUT_MS - WARN_BEFORE_MS`) + close (`IDLE_TIMEOUT_MS`) timers.
5. Update the mount `useEffect` cleanup to clear both timers.
6. Create `_SessionWarningBanner` (top-fixed, ambre/warning palette, `TerminatingOverlay` visual tokens, live countdown, « Prolonger » button, alert/live role) with props `{ remainingMs | targetCloseAt, onExtend }`.
7. Render `{isWarning && !isTerminating && <_SessionWarningBanner onExtend={resetIdleTimer} .../>}` near the top of the tree; keep `TerminatingOverlay` unchanged.
8. Wire « Prolonger » `onClick` explicitly to `resetIdleTimer` (in addition to root bubbling).
9. Add a code comment at the reset seam documenting the #120 `MediaRecorder` `dataavailable` → activity-reset integration point (optionally extract `useIdleTimer`).
10. Update `app.test.ts` (900_000 → 1_800_000) and both `walkthrough.test.ts` assertions (15 → 30 min); fix ADR-reference comment text.
11. Add banner/timer behaviour tests using `vi.useFakeTimers()` (warn at T-28, close at T-0, extend resets, activity resets, countdown decrements, a11y role/name).
12. Update docs: `app-medecin/README.md`, `docs/adr/0002-doctor-interface-pwa.md` (amendment note), `docs/ux/medecin-ux-guidelines.md` (banner pattern), and `BACKLOG.md`/#122 status if tracked.
13. Run `npm test` in `app-medecin/` and confirm the suite is green; run `npm run build` (`tsc --noEmit && vite build`) to confirm type-safety.
