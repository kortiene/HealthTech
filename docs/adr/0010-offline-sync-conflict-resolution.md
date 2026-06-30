# ADR 0010 — Offline-sync drain & conflict resolution

**Status:** Accepted (2026-06-30) · Issue [#22](https://github.com/kortiene/HealthTech/issues/22) · Implements US-2.4 (E2 — Résilience médecin) · Extends [ADR 0006](./0006-offline-storage-and-keys.md)

> Satisfies the #22 acceptance criterion **"stratégie de résolution de conflits documentée."**
> The drain mechanics live in `app-patient/lib/src/doctor/sync_service.dart`; this ADR records the
> conflict-resolution decision behind it.

## Context

[#21](https://github.com/kortiene/HealthTech/issues/21) made offline data loss impossible by **enqueuing**
the end-of-session blob (`nonce(12)||ct||tag(16)`) + the anonymous UUID into a durable SQLCipher queue
([ADR 0006](./0006-offline-storage-and-keys.md)). It explicitly deferred the **drain** — re-emitting those
queued blobs to the sovereign backend on network return — to #22.

The drain must guarantee **no loss and no duplicate after reconnection**, and must handle the case where the
**server blob has diverged** since the offline edit (another consultation, a patient-side sync).

**The structuring constraint:** the queued blob was encrypted with the **ephemeral session key** (~120 s,
carried by the QR, #16), which is **wiped at session end** (#19). The doctor's device therefore **can no
longer decrypt** what it queued. At drain time #22 can only perform an **opaque, blind `PUT`** of the bytes —
it cannot read, merge, or re-encrypt the data. Every conflict option below follows from this fact.

## Decision

### Drain (delivery)

A `SyncService.drain()` walks `OfflineUploadQueue.pending()` in **FIFO** order and, for each eligible item,
`PUT /blob/{uuid}` via the existing zero-knowledge `BackendClient`, then `remove(id)` **only after** a
confirmed 2xx. **No new cryptography**; the bytes are PUT as-is.

No-loss / no-duplicate rests on two properties:

- **No loss** — an item is never removed before a successful PUT. Any failure leaves it queued, increments
  `attempts`, stamps a **redacted** `last_error`, and schedules a bounded exponential **backoff** retry. Past
  `maxAttempts` it stays queued and is flagged to the UI as a *persistent failure* — **never silently purged**.
- **No duplicate** — (a) `PUT /blob/{uuid}` is **idempotent at the UUID** server-side (it rewrites the blob,
  no duplicate insert); (b) `remove` happens only after confirmation, so a crash between `put` and `remove`
  causes at worst an **identical re-PUT** (same bytes, same UUID) next drain. *At-least-once delivery +
  idempotent PUT = exactly one final server state.*

A single-drain **mutex** makes `drain()` re-entrant-safe (no concurrent double-PUT). The drain trigger is
decoupled behind an injectable `SyncTrigger` (app resume/start, manual "Synchroniser", opportunistic
post-PUT) so the connectivity-package choice stays a #1 decision and the drain logic is host-testable.

### Conflict resolution — A → B → C

Because the device cannot decrypt the queued blob, **no semantic merge is possible on the doctor's device**.
The options reduce to three:

- **(A) Blind last-writer-wins — default, delivered by #22.** The drain PUTs the bytes; the server rewrites
  the blob at that UUID. Simple, idempotent, no duplicate. **Residual risk:** if the server blob diverged
  between the offline edit and the drain, the PUT **silently overwrites** that version → potential loss of a
  concurrent edit. **Acceptable as the default** because, in the real journey, a patient's consultations are
  **sequential** (one doctor device per consultation; an offline second scan would fail for lack of a `GET`),
  so the divergence window is narrow. Tracked here as a known, mitigated-by-(B) risk.
- **(B) Divergence detection + preservation — recommended once #9 allows it.** Capture, at **scan** time
  (#17), an opaque **version token** of the server blob (ETag / generation counter exposed by #9), store it
  with the queued item (`base_version`), then issue a **conditional PUT** (`If-Match`) at drain. If the server
  moved (precondition failed), **do not overwrite** → `markConflict` + flag to the UI. The data is neither
  lost (stays queued) nor overwritten. The hooks (`markConflict`, `UploadState.conflict`) are **wired but
  inactive** until #9 exposes versioning. *Depends on a server capability to confirm (#9); otherwise degrade
  cleanly to (A).*
- **(C) Patient-side reconciliation — cross-cutting, out of #22.** Only the **patient** (master key, #11/#14)
  can decrypt and therefore truly merge divergent versions. #22 guarantees **delivery** of every version;
  reconciliation is an explicit **follow-up issue** ("sync patient post-consultation", flagged in #20/#21).

**Multiple versions of one `blob_uuid` in the queue** (#21 keeps each distinct ciphertext via
`UNIQUE(blob_uuid, ciphertext_hash)`): drained in **FIFO** order, each PUT in turn; the final server state is
the chronologically **last** — deterministic and consistent with last-writer-wins.

> **Default shipped by #22:** **(A)** blind last-writer-wins + idempotent at-least-once delivery, **with the
> (B) hooks** (`base_version`, `markConflict`) wired but inactive until #9 exposes versioning.

## Consequences

**Positive**
- The #22 acceptance criteria are met for the realistic (sequential) journey: no loss, no duplicate, and a
  documented conflict strategy.
- The drain reuses the exact opaque `PUT /blob/{uuid}` path — zero-knowledge is preserved and conceptually
  reinforced (offline upload is indistinguishable from a normal one on the wire).
- The session key is never on the drain path, so a drain can run after session end (or in background) without
  re-exposing key material.

**Negative / risks**
- **(A) can overwrite an unseen concurrent version.** Mitigated by the sequential journey and by (B) when #9
  lands; tracked as a known risk until then.
- **Backoff calibration** (`maxAttempts`, base/max backoff) must suit unstable Edge/3G and low-end battery
  (#29) — values are configurable via `RetryPolicy`.
- **Migration v1→v2** of the SQLCipher table is not exercised in host-only CI; a device-backed e2e is a
  follow-up (#1 + emulator).

## Alternatives considered

- **Decrypt-and-merge on the doctor device** — impossible: the session key is wiped (#19). Rejected by
  construction.
- **Server-side conflict resolution** — impossible: the server is zero-knowledge and holds only opaque bytes.
- **Drop-on-conflict / overwrite-always without detection** — violates "no loss"; rejected. (A) is the
  pragmatic floor only because the journey is sequential and (B) is the planned upgrade.
