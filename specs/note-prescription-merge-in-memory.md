# Ajout de note / ordonnance & fusion en mémoire (issue #18 — US-2.2)

> **Issue :** #18 — *Ajout de note / ordonnance & fusion en mémoire* · Épic E2 (Interface Professionnel de Santé) · Effort **M** · Priorité **Must** · Implémente **US-2.2** · Dépend de **#17**
> **Jalon :** M2 — Boucle de consultation (`#16 → #17 → #18 → #19 → #20`).
> **Étiquettes :** `feature` `ux`

## Problem Statement

Issue #17 delivered the read-only half of the consultation loop: a doctor scans the
patient's 120 s QR code, the session blob is downloaded and decrypted **in RAM only**,
and the resulting `MedicalRecord` is shown read-only in `RecordViewScreen`
(`app-patient/lib/src/ui/record_view_screen.dart`). The session key is held in the
`QrPayload` on the Dart heap and wiped on screen dispose.

US-2.2 requires the doctor to *act* during the consultation: add a clinical note and/or
issue a prescription. Today there is no edit surface at all — the viewer is read-only and
the in-RAM `MedicalRecord` is immutable. The gap this spec closes:

1. A **quick-edit form** for a consultation note and a prescription (PRD §3, US-2.2:
   *« Formulaire d'édition rapide »*).
2. **In-RAM merge** of the doctor's additions into the existing decrypted record
   **without overwriting history** (PRD §3: *« Les ajouts sont fusionnés avec le dossier
   existant en mémoire vive »*; acceptance: *« note/ordonnance fusionnée sans écraser
   l'historique »*).
3. A **prescription template** (*« modèle d'ordonnance »*) so the doctor produces a
   structured, legible ordonnance rather than free text.
4. **Re-encryption of the updated record** in RAM (acceptance: *« Rechiffrement du dossier
   mis à jour »*).

The actual upload of the re-encrypted blob to the cloud and the end-of-session RAM wipe are
**issue #19's** responsibility (US-2.3). This spec stops at producing the merged, re-encrypted
ciphertext in RAM and exposing it to the session-end flow; see Non-Goals.

## Goals

- Add an immutable, append-only **merge function** that takes the in-RAM `MedicalRecord`
  plus a doctor's note/prescription input and returns a **new** `MedicalRecord` with a new
  `Consultation` (and, when prescribed, new `Medication` entries) appended — never mutating
  or removing existing allergies, conditions, medications, consultations, or immunizations.
- Add a **prescription template model** that structures drug lines (name, dose, frequency,
  duration) and renders them into the existing `Consultation.prescription` text field, while
  also appending corresponding `Medication` entries to the record's medication list.
- Add a **quick-edit form screen** reachable from `RecordViewScreen`, optimized for the
  doctor's speed-first workflow (NFR UX: prise en main < 5 min, interface épurée).
- **Re-encrypt the merged record in RAM** using the session key already held in the
  `QrPayload` (the doctor never holds the patient master key), via the existing Rust
  `crypto-core` seam (`CryptoCore.encryptRecord`), wiping the transient key handle in a
  `finally` block — mirroring `AccessTokenService._encryptWithSession`.
- Enforce the **≤ 500 Kio plaintext budget** on the merged record before re-encryption,
  guaranteeing the *newly added* consultation is never the one truncated.
- Keep the doctor's plaintext additions **in RAM only** — never written to disk, never logged.
- Hand the merged record (and/or its re-encrypted blob) to the session-end flow so #19 can
  upload it and wipe RAM.

## Non-Goals

- **Cloud upload of the updated blob and end-of-session RAM wipe** — owned by **#19**
  (US-2.3, *« Fin de session : rechiffrement, renvoi cloud & wipe RAM »*). This spec
  re-encrypts in RAM but does not `PUT` to the backend nor implement the 15-min idle wipe.
- **Offline ciphertext queue / SQLCipher** when the network is down — owned by **#21/#22**
  (US-2.4). This spec assumes the merged blob is handed to #19; persistence on network
  failure is out of scope here.
- **Doctor identity / authentication** — there is no practitioner auth in the codebase yet.
  How `practitioner_ref` (an opaque UUID per the schema) is obtained is an open question
  (see Risks); this spec uses a session-scoped placeholder/locally entered value and flags it.
- **Attaching heavy medical images** to the consultation — only ephemeral URLs are allowed
  in `Consultation.imageUrls` (PRD §4); image capture/upload is #23 and out of scope.
- **Patient-side re-absorption of the doctor's edits under the master key** — the broader
  re-keying / conflict-resolution concern (the QR session overwrote the canonical
  master-key blob, see Risks) is not solved here.
- **Migrating the doctor flow to the `app-medecin` PWA** — see Relevant Repository Context;
  this spec follows the #17 precedent (Flutter `app-patient`) and flags the discrepancy.

## Relevant Repository Context

**Stack status (backlog #1 still partly open).** ADRs have fixed: Flutter for the patient
app (ADR 0001), Rust `crypto-core` reached only via `flutter_rust_bridge` with **no cipher
code in Dart** (ADR 0003), and a zero-knowledge `PUT/GET /blob/{uuid}` backend (ADR 0004).
A separate **doctor PWA** (`app-medecin/`, Preact + Vite + TypeScript) exists per ADR 0002,
but its `src/app.tsx` / `src/session.ts` are still a scaffold with stale `TODO(#17)` /
`TODO(#21)` comments. **Issue #17 actually implemented the doctor consultation flow inside
the Flutter `app-patient` project** (`lib/src/doctor/scan_service.dart`,
`lib/src/ui/scan_screen.dart`, `lib/src/ui/record_view_screen.dart`), with a "Scanner
(médecin)" button on the patient home screen (`main.dart`). **This spec follows that
precedent** (Flutter `app-patient`) for continuity with #17, and flags the
PWA-vs-Flutter target as a decision to confirm against ADR 0002 / backlog #1 (see Risks).

**Existing building blocks this spec composes (all in `app-patient/lib/src/`):**

- `record/medical_record.dart` — the versioned plaintext schema (#15). `MedicalRecord` is
  **immutable** with a `copyWith(...)` that already accepts `consultations`, `medications`,
  `updatedAt`, etc. `Consultation { id, date, practitionerRef, summary, prescription?,
  imageUrls }`; `Medication { name, dose, frequency, prescribedAt, prescribedBy? }`. Lists
  are append-friendly; `consultations` is documented "sorted oldest-first".
- `record/record_size_guard.dart` — `RecordSizeGuard.measure/validate/truncate` enforce the
  500 Kio budget. **`truncate` drops the *oldest* consultations first** (by `date` ASC) —
  important interaction with the "ne pas écraser l'historique" requirement.
- `doctor/scan_service.dart` — `ScanService.fetchAndDecrypt(payload)` returns the in-RAM
  `MedicalRecord`; wipes the Rust handle in `finally`. Pattern to mirror for re-encryption.
- `ui/record_view_screen.dart` — read-only viewer; holds the `QrPayload` and wipes its
  `sessionKey` in `dispose()`. This is where the "Add note / prescription" entry point lives.
- `qr/access_token.dart` — `QrPayload` (holds the 32-byte `sessionKey`, RAM-only, `wipe()`);
  `AccessTokenService._encryptWithSession(sessionKey, plaintext)` shows the exact
  `handleFromUnsealed → encryptRecord → wipe(finally)` idiom to reuse on the doctor side.
- `rust/crypto_core_bindings.dart` — the frozen `CryptoCore` seam (#10): `handleFromUnsealed`,
  `encryptRecord` (returns `nonce(12) || ciphertext || tag(16)`), `decryptRecord`, `wipe`.
  `FrbCryptoCore` throws `CryptoCoreUnavailable` until FRB codegen runs (tests use fakes).
- `cloud/backend_client.dart` — `BackendClient.put/get`; only #19 will call `put` for the
  updated blob.

**Conventions (from `memory/project_backlog_state.md` and the existing code):**

- Inject collaborators via constructors (e.g. `ScanService({required crypto, client})`);
  tests supply a `_FakeCryptoCore` (XOR-based, invertible) and `MockClient`. UI screens
  take an injected controller/service and default to production deps.
- `flutter analyze` on Flutter 3.41.5 treats `info` issues as errors; honour
  `prefer_const_constructors`, `prefer_const_declarations`, `unnecessary_const`. Run
  `dart format lib/ test/` (old style, sdk >= 3.5.0).
- No Rust toolchain in the ADW phase env — write Rust (if any) to rustfmt defaults; but this
  issue is **pure Dart** and adds **no** new Rust surface (the crypto seam is reused as-is).
- French UI strings, English code/comments/identifiers.

## Proposed Implementation

Three layers, smallest blast radius first. All new code lives under
`app-patient/lib/src/` and follows the immutable / injected-deps patterns above.

### 1. Domain: prescription template model — `record/prescription.dart`

A small, pure, serializable model representing a structured ordonnance:

- `PrescriptionLine { drug, dose, frequency, durationDays?, instructions? }` (all UTF-8
  text except `durationDays:int?`).
- `Prescription { lines: List<PrescriptionLine> }` with:
  - `renderText()` → a deterministic, human-legible multi-line string suitable for the
    existing `Consultation.prescription` (String) field, e.g.
    `"Amoxicilline — 500 mg — 3×/jour — 7 j"` per line.
  - `toMedications(prescribedAt, prescribedBy)` → `List<Medication>` mapping each line to a
    `Medication` so the patient's structured medication list stays in sync.
- Keep it dependency-free and JSON-free unless a structured persisted form is needed; the
  canonical persisted form remains the existing schema fields (`Consultation.prescription`
  text + `Medication[]`). **No `MedicalRecord` schema change** (see Data Model section).

### 2. Domain: append-only merge — `doctor/consultation_merge.dart`

A pure function (no I/O, no crypto) that is the heart of "fusion sans écraser l'historique":

```
MedicalRecord mergeConsultation(
  MedicalRecord existing, {
  required String practitionerRef,
  required String date,          // ISO yyyy-MM-dd
  required String summary,       // the clinical note (may be empty if prescription-only)
  Prescription? prescription,
  required String newConsultationId,   // opaque UUID, generated by the caller
  required String nowIso,              // ISO-8601 UTC for updatedAt
})
```

Behaviour:

- Builds one new `Consultation { id: newConsultationId, date, practitionerRef, summary,
  prescription: prescription?.renderText(), imageUrls: const [] }`.
- Returns `existing.copyWith(`
  - `consultations: [...existing.consultations, newConsultation]` — **append only**;
  - `medications: prescription == null ? existing.medications : [...existing.medications,
    ...prescription.toMedications(date, practitionerRef)]` — **append only**;
  - `updatedAt: nowIso`  `)`.
- **Invariant (tested):** every pre-existing entry in *all* list sections is still present
  and unchanged in the result; only additions occur, and `createdAt`/`patientId`/`v`/
  `demographics` are untouched. This is the machine-checkable form of "sans écraser
  l'historique".
- Determinism: the function does not call `DateTime.now()` or generate IDs itself — the
  caller injects `newConsultationId` and `nowIso` (testability + matches how
  `access_token.dart` keeps generation at the edge).

### 3. Re-encryption in RAM — extend `doctor/scan_service.dart` (or a sibling `ConsultationEditService`)

Add a method that re-encrypts the merged record with the **session key** (the doctor has no
master key), enforcing the size budget first:

```
Future<Uint8List> reEncrypt(MedicalRecord merged, QrPayload payload) async {
  final safe = _guardKeepingNewest(merged);          // size guard, see below
  final plaintext = Uint8List.fromList(safe.toUtf8Bytes());
  final handle = await _crypto.handleFromUnsealed(payload.sessionKey);
  try {
    return await _crypto.encryptRecord(handle, plaintext);   // nonce||ct||tag
  } finally {
    await _crypto.wipe(handle);
  }
}
```

- Mirrors `AccessTokenService._encryptWithSession` exactly (same wipe-in-`finally` idiom).
- **Size budget interaction:** call `RecordSizeGuard` before encrypting. Because
  `truncate` drops the *oldest* consultations and the new note is appended last (newest by
  `date`), the new consultation is preserved. If the doctor enters a date that is not the
  newest, sort/guard logic must still guarantee the just-added entry survives — implement
  `_guardKeepingNewest` to (a) try `RecordSizeGuard.truncate`, and (b) assert the new
  consultation id is still present, else surface a `RecordTooLargeException`-style error to
  the UI ("dossier plein — impossible d'ajouter") rather than silently dropping it.
- The returned blob stays in RAM and is handed to the #19 session-end flow (e.g. stored on
  the session/controller state). This spec does **not** upload it.

### 4. UI: quick-edit form — `ui/consultation_edit_screen.dart` + entry point

- Add an "Ajouter une note / ordonnance" action (FloatingActionButton or AppBar action) to
  `RecordViewScreen`.
- `ConsultationEditScreen` is a `StatefulWidget` with:
  - a multiline **note** `TextField` (summary),
  - a dynamic **prescription** section: a list of `PrescriptionLine` rows (drug, dose,
    frequency, duration) with add/remove, seeded by a one-tap **template** (e.g. an empty
    line, or common presets — keep minimal for v1),
  - a **"Enregistrer"** button that builds the `Prescription`, calls `mergeConsultation`,
    then `reEncrypt`, and returns the updated `MedicalRecord` (+ blob) to the caller.
- Inject the merge/re-encrypt service for testability; default to production deps.
- **RAM hygiene:** dispose all `TextEditingController`s in `dispose()`. The plaintext the
  doctor types lives only in controllers + the in-RAM record; nothing is persisted. The
  authoritative session wipe remains #19, but this screen must not leak controllers.
- After save, update the in-RAM `MedicalRecord` shown by `RecordViewScreen` so the doctor
  sees the appended consultation immediately (consultation history is append-only and
  visible).

### State threading

`RecordViewScreen` currently holds `record` + `payload`. To carry the merged record and the
re-encrypted blob to the session-end flow (#19), introduce a small mutable session holder
(e.g. a `ConsultationSession` object owning `MedicalRecord current`, `Uint8List?
pendingBlob`, and the `QrPayload`) injected into `RecordViewScreen`, so #18's edits and
#19's upload/wipe operate on one source of truth. Keep this holder RAM-only.

## Affected Files / Packages / Modules

**New (Dart, `app-patient/lib/src/`):**

- `record/prescription.dart` — `Prescription` / `PrescriptionLine` template model.
- `doctor/consultation_merge.dart` — `mergeConsultation(...)` append-only merge.
- `ui/consultation_edit_screen.dart` — quick-edit form.
- *(optional)* `doctor/consultation_session.dart` — RAM-only session holder threading the
  record + pending blob between #18 and #19.

**Modified:**

- `lib/src/ui/record_view_screen.dart` — add the "Ajouter une note / ordonnance" entry
  point; consume the session holder; re-render after merge.
- `lib/src/doctor/scan_service.dart` *(or new `ConsultationEditService`)* — add `reEncrypt`
  + size-guard-keeping-newest helper.
- `lib/main.dart` — wire the new screen/service into the scan → view navigation if the
  session holder is constructed at the `_HomeScreen`/`ScanScreen` level.

**New tests (mirroring existing layout):**

- `test/record/prescription_test.dart`
- `test/doctor/consultation_merge_test.dart`
- `test/doctor/consultation_edit_service_test.dart` (re-encryption + size guard)
- `test/ui/consultation_edit_screen_test.dart` (widget test)

**Read for context (no change expected):**

- `lib/src/record/medical_record.dart`, `record_size_guard.dart`,
  `lib/src/qr/access_token.dart`, `lib/src/rust/crypto_core_bindings.dart`,
  `lib/src/cloud/backend_client.dart`.

**Docs:** `BACKLOG.md` (mark #18), `PRD_HealthTech.md` (no change expected),
`app-patient/README.md` (consultation-edit note), `docs/compliance/controles.md` (RAM-only
edit evidence, if a control maps).

## API / Interface Changes

- **Network / backend:** none. No new endpoints; the existing `PUT/GET /blob/{uuid}` is
  untouched and is only invoked by #19. The doctor side re-encrypts in RAM only here.
- **QR / access-token surface:** none. `QrPayload` and the 120 s token are consumed
  unchanged; no new field is added to the QR.
- **New public Dart API (intra-app, must be documented with dartdoc):**
  - `Prescription`, `PrescriptionLine`, `Prescription.renderText()`,
    `Prescription.toMedications(...)`.
  - `mergeConsultation(...)` in `consultation_merge.dart`.
  - `ConsultationEditService.reEncrypt(...)` (or the added method on `ScanService`).
  - `ConsultationEditScreen` widget constructor.
- **CLI:** none.

## Data Model / Protocol Changes

- **No `MedicalRecord` schema change** — `recordSchemaVersion` stays **1**. The merge uses
  the existing `Consultation` and `Medication` shapes and the existing `prescription` text
  field; nothing new is persisted to the encrypted blob structure.
- **Encrypted-blob format:** unchanged — the re-encrypted blob is the standard
  `nonce(12) || ciphertext || tag(16)` AES-256-GCM output from `CryptoCore.encryptRecord`
  (#10), produced with the **session key**, indexed by the same anonymous UUID. The server
  still sees only opaque bytes.
- **No new on-disk persistence** is introduced by #18 (the merged blob lives in RAM until
  #19; offline persistence is #21).
- If the optional prescription preset/template library is later persisted, that is a doctor-
  side, non-PII config and must be designed separately — out of scope here.

## Security & Compliance Considerations

- **Doctor holds only the ephemeral session key.** Re-encryption uses
  `QrPayload.sessionKey` via `handleFromUnsealed → encryptRecord`; the doctor never has the
  patient master key. The transient key handle is wiped in a `finally` block. **Never weaken
  this** — no Dart-side crypto, no WebCrypto; all cipher ops stay in the Rust core (ADR 0003).
- **In-RAM-only plaintext.** The note/prescription the doctor types lives only in
  `TextEditingController`s and the in-RAM `MedicalRecord`; nothing is written to disk by #18.
  Dispose all controllers; the authoritative end-of-session RAM wipe is #19 (and the
  `QrPayload.sessionKey` is still wiped by `RecordViewScreen.dispose`).
- **Zero-knowledge preserved.** The re-encrypted blob is opaque ciphertext; the server can
  neither read nor decrypt it. No new server capability is added.
- **Ephemeral access window.** The edit must occur within the consultation session opened by
  the ~120 s QR; the session key validity is the patient's gate. If the session blob has
  expired server-side, #19's upload (not #18) will surface the failure.
- **No logging of plaintext / keys / PII.** Never log the note text, prescription contents,
  drug names, `summary`, the session key, or `practitioner_ref`. Error UI strings must be
  generic (mirror `ScanService` coarse messages).
- **≤ 500 Kio budget.** Enforce `RecordSizeGuard` on the merged record before re-encryption;
  guarantee the newly added consultation is never the entry truncated (truncation drops
  oldest), and fail loudly to the UI if the record is full rather than silently dropping data.
- **No heavy images on device.** `Consultation.imageUrls` stays empty for #18; only ephemeral
  URLs are ever allowed (PRD §4), and image attachment is #23.
- **Data residency (ARTCI / loi n°2013-450).** Unchanged — no new data leaves the device in
  #18; the eventual upload (#19) targets the in-country backend. Map the "RAM-only doctor
  edit, no plaintext at rest" control into `docs/compliance/controles.md` if a requirement
  references it.

## Testing Plan

- **Unit — merge (`consultation_merge_test.dart`):**
  - Appends exactly one `Consultation`; all pre-existing consultations/allergies/conditions/
    medications/immunizations remain present and unchanged (the "sans écraser l'historique"
    invariant), `patientId`/`createdAt`/`v`/`demographics` untouched, `updatedAt` bumped.
  - Prescription present → corresponding `Medication` entries appended (count + fields).
  - Prescription absent → medications list unchanged.
  - Note-only and prescription-only inputs both produce a valid consultation.
- **Unit — prescription model (`prescription_test.dart`):**
  - `renderText()` is deterministic and legible for multi-line prescriptions; empty
    prescription renders empty / null appropriately.
  - `toMedications()` maps each line to a `Medication` with correct `prescribedAt`/`prescribedBy`.
- **Unit — re-encryption + size guard (`consultation_edit_service_test.dart`):**
  - Uses the XOR `_FakeCryptoCore` (as in `scan_service_test.dart`): `reEncrypt` produces a
    blob that round-trips back to the merged record; the fake handle is wiped after success
    **and** after a thrown error (`finally` honoured).
  - Re-encryption uses `handleFromUnsealed(payload.sessionKey)` (session key), never the
    master key; never issues a `PUT` (cloud upload is #19).
  - Size guard: a record padded near 500 Kio still retains the newly added consultation after
    `truncate`; oldest consultations are dropped first; a record that cannot fit surfaces the
    "dossier plein" error and does **not** drop the new note silently.
- **Widget — edit screen (`consultation_edit_screen_test.dart`):**
  - Entering a note + a prescription line and tapping "Enregistrer" returns an updated record
    whose newest consultation reflects the input; the appended consultation appears in
    `RecordViewScreen` after save.
  - All `TextEditingController`s are disposed (no leak); no plaintext is persisted.
- **Crypto-vector:** none new — the AES-256-GCM vectors are owned by #10; #18 reuses the
  frozen seam. (Add an assertion that the re-encrypted blob length == plaintext + 28 bytes
  overhead under the real core, gated behind FRB availability.)
- **Resilience / offline:** out of scope for #18 (network upload is #19/#21). Add a TODO
  reference so #19's tests cover "merge succeeded but upload failed → queued".
- **E2E (deferred to #20):** the full patient-QR → scan → **edit** → terminate loop is the
  #20 integration test; #18 should leave the seams injectable so #20 can drive them.

## Documentation Updates

- **`BACKLOG.md`** — annotate #18 as specced/in-progress (consistent with how prior issues
  were tracked); note the dependency satisfied by #17.
- **`app-patient/README.md`** — document the consultation-edit flow and the RAM-only,
  session-key re-encryption boundary; clarify that upload/wipe is #19.
- **`docs/compliance/controles.md`** — if a control/preuve references doctor-side editing,
  record the "RAM-only edit, no plaintext at rest, session-key re-encryption" evidence.
- **ADR** — *no new ADR required* if the doctor flow stays in Flutter `app-patient`. **If**
  the team decides to honour ADR 0002 and move the doctor UI to the `app-medecin` PWA, that
  is an ADR-level decision and a re-plan (see Risks) — capture it before coding.
- **PRD** — no change expected.

## Risks and Open Questions

1. **Doctor flow target — Flutter `app-patient` vs. Preact PWA `app-medecin`.** ADR 0002
   designates a doctor PWA, but #17 built the flow in the Flutter patient app and the PWA is
   still a stale scaffold (`TODO(#17)`). This spec follows #17 for continuity. **Confirm**
   whether to keep building the doctor UI in `app-patient` or pivot to `app-medecin`
   (backlog #1 / ADR 0002). A pivot would change every "Affected Files" entry.
2. **`practitioner_ref` provenance.** The schema expects an opaque practitioner UUID, but
   there is **no doctor identity/auth** in the codebase. v1 uses a session-scoped
   placeholder or a locally entered value. **Confirm** the intended source (doctor login,
   device-bound ID, or deferred to a later issue).
3. **Session blob was overwritten by the QR step.** `AccessTokenService.generate` `PUT`s the
   *session-key*-encrypted blob under the patient's UUID, overwriting the master-key blob
   server-side. The patient must later re-absorb the doctor's edits and re-key under the
   master key. This re-keying / conflict-resolution path is **not** solved by #18 (likely
   #19/#22). Flag so #19 does not assume the master-key blob is still canonical on the server.
4. **500 Kio budget vs. "never overwrite history".** Truncation drops the oldest
   consultations to fit — a real (if rare) tension with "sans écraser l'historique". This
   spec keeps the *new* note and drops oldest only when forced, and fails loudly when the
   record cannot fit. **Confirm** this trade-off is acceptable, or whether old-entry archival
   (e.g. to images/#23 or a server-side history) is needed.
5. **Date/ID generation in tests.** The merge function takes injected `nowIso` and
   `newConsultationId` to stay deterministic; production callers use `DateTime.now()` and a
   secure UUID. Ensure the UUID source is the OS CSPRNG (as in `access_token.dart`).
6. **Prescription template scope.** "Modèle d'ordonnance" could mean a single structured
   form or a library of presets. v1 ships the structured `Prescription` model + a minimal
   blank/template line; a preset library is a follow-up.

## Implementation Checklist

1. **Confirm** open question #1 (doctor flow target). If `app-patient` (default), proceed;
   if `app-medecin`, stop and re-plan against the PWA stack.
2. Add `record/prescription.dart`: `PrescriptionLine`, `Prescription` with `renderText()` and
   `toMedications(prescribedAt, prescribedBy)`; dartdoc each public member.
3. Add `doctor/consultation_merge.dart`: pure append-only `mergeConsultation(...)` returning a
   new `MedicalRecord` via `copyWith` (inject `nowIso` + `newConsultationId`).
4. Extend `doctor/scan_service.dart` (or new `ConsultationEditService`) with `reEncrypt(merged,
   payload)` using `handleFromUnsealed → encryptRecord → wipe(finally)`; add
   `_guardKeepingNewest` enforcing `RecordSizeGuard` while preserving the new consultation.
5. Add the RAM-only `ConsultationSession` holder (record + pending blob + payload) if threading
   state between #18 and #19.
6. Add `ui/consultation_edit_screen.dart`: note field + dynamic prescription lines + template
   seed + "Enregistrer"; inject the service; dispose all controllers; return the updated record.
7. Wire the "Ajouter une note / ordonnance" entry point into `record_view_screen.dart`; re-render
   the appended consultation after save; update `main.dart` wiring if needed.
8. Write unit tests: `prescription_test.dart`, `consultation_merge_test.dart` (history-preservation
   invariant), `consultation_edit_service_test.dart` (round-trip, handle wiped on success+error,
   session-key-only, no PUT, size-guard keeps newest).
9. Write `consultation_edit_screen_test.dart` widget test (save flow + controller disposal).
10. Confirm **no** plaintext/keys/PII are logged anywhere on the edit path; error strings are
    generic.
11. Run `dart format lib/ test/` and ensure `flutter analyze` is clean (treat `info` as error:
    `prefer_const_constructors`, `prefer_const_declarations`, `unnecessary_const`).
12. Update `BACKLOG.md`, `app-patient/README.md`, and `docs/compliance/controles.md` as listed.
13. Leave injectable seams for the #20 e2e and the #19 upload/wipe; reference open questions
    #2/#3/#4 in code TODOs so downstream issues pick them up.
