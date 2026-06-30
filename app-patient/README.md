# app-patient

Patient-facing mobile app for the HealthTech platform. Mobile-first, offline-first,
entry-level Android target (`minSdk 24`), iOS later from the same Dart codebase.

This package is a **scaffold only** (issue #2): compiling stubs with `TODO(#N)`
markers, not features.

## Purpose

- Generate/hold the patient master key in hardware and encrypt the medical record
  **client-side before any transit** (zero-knowledge).
- View and create the record fully offline (≤500 KB mirror + pending-upload queue).
- Share a short-lived QR grant so a doctor can read the record during a consultation.

## ADRs implemented

- **[ADR 0001](../docs/adr/0001-patient-app-flutter.md)** — Patient app: Flutter
  (`flutter_rust_bridge` to crypto-core, `--split-per-abi` build, Kotlin Keystore shim).
- **[ADR 0006](../docs/adr/0006-offline-storage-and-keys.md)** — Offline storage & keys
  (SQLCipher via `drift` + `sqlcipher_flutter_libs`, Keystore-wrapped DB key).
- Crypto contract from **[ADR 0003](../docs/adr/0003-shared-crypto-core-rust.md)**.

## Crypto boundary (non-negotiable)

- **All cryptography comes ONLY from the Rust `crypto-core`** via `flutter_rust_bridge`.
  There is **no Dart cipher** — no `pointycastle`, no `dart:crypto` AES (forbidden by
  ADR 0001/0003). Dart holds only what the UI renders; plaintext stays in Rust.
- The **StrongBox/TEE master-key sealing is a Kotlin platform-channel shim** (#11), in
  `android/app/src/main/kotlin/com/healthtech/patient/` (`KeystoreSealer.kt` +
  `MainActivity.kt`). Flutter plugins do not expose `setIsStrongBoxBacked` / TEE fallback,
  so this shim is mandatory. `flutter_secure_storage` is used **only** for non-critical
  items, never the master key.
- The SQLCipher DB key is unsealed from the Keystore-wrapped blob **in-memory only**
  (`TODO(#14)`).

### Master-key flow (#11)

`lib/src/secure/master_key_service.dart` orchestrates the lifecycle:

```
generateMasterKey (Rust core) → exportSealable → KeystoreChannel.seal (hardware KEK)
  → persist ONLY the sealed blob → wipe the clear copy
```

- `KeystoreChannel` (`lib/src/secure/keystore_channel.dart`) is the Dart side of the
  `healthtech/keystore` `MethodChannel`. Contract: `seal(clearKey) -> sealedBlob`,
  `unseal(sealedBlob) -> clearKey` (RAM-only), `exists() -> bool`, `clear()`. Native error
  codes `KEYSTORE_UNAVAILABLE` / `STRONGBOX_UNSUPPORTED` / `KEY_INVALIDATED` map to typed
  `KeystoreException`s. **No software fallback** (G3): keystore unavailability throws, it
  never returns a software key.
- The sealed blob (already hardware-wrapped, not a clear secret) is persisted via
  `SealedBlobStore` (`lib/src/secure/sealed_blob_store.dart`) — a private app file by
  default. The clear master key never touches disk.
- `MasterKeyService.probeState()` routes at startup: absent → onboarding (#13); present →
  open; `KEY_INVALIDATED` → recovery (#12, PBKDF2).
- iOS is an **amorce** stub (`ios/Runner/KeystoreChannelPlugin.swift`, `TODO(#11/iOS)`):
  same channel contract, fails loudly until the Secure Enclave path is hardened
  (ADR 0001 — Android first).
- The Rust↔Dart FRB seam (`lib/src/rust/crypto_core_bindings.dart`) defines `CryptoCore`
  with an opaque `MasterKeyHandle`; the generated bindings are produced by FRB codegen.

## Gate before build-out (ADR 0001)

A **device-lab footprint gate on a real near-full low-end Infinix** (~2 GB RAM, 32 GB)
**precedes** building out this app: measure per-ABI installed size, cold start, and steady
RSS against the hard budgets (installed ≤ ~25–30 MB arm64, no OOM/jank under storage
pressure). If the numbers regress unacceptably, the fallback is native Kotlin (#29). This
gate is non-negotiable.

## TODO map (backlog)

| TODO | Issue | What |
| --- | --- | --- |
| `#11` | keygen | Master key in Rust core, sealed via Kotlin Keystore (StrongBox/TEE) shim |
| `#13` | onboarding | First-run flow, recovery passphrase/security questions |
| `#16` | QR | Generate (`qr_flutter`, 120 s TTL) + scan (`mobile_scanner`) |
| `#14` | backup | SQLCipher mirror + pending-upload queue, recovery restore |
| `#17` | scan | Scan QR → fetch blob → decrypt **in RAM only** → read-only viewer |
| `#18` | edit | Quick-edit note/ordonnance → append-only merge → **session-key re-encryption in RAM** |
| `#21` | offline queue | Failed end-of-session PUT → **enqueue encrypted blob** (SQLCipher) instead of losing it |
| `#22` | sync drain | On network return, **drain the queue** to the backend — no loss, no duplicate; conflict strategy documented |

### Doctor consultation edit (#18)

During an open consultation the doctor taps **« Ajouter une note / ordonnance »** in the
record viewer. The note + structured prescription are merged **append-only** into the in-RAM
record (`mergeConsultation` never overwrites existing history), then the updated record is
**re-encrypted in RAM with the ephemeral session key** held in the `QrPayload`
(`ConsultationEditService.reEncrypt`) — the doctor never holds the patient master key, and the
transient key handle is wiped in a `finally` block. The plaintext lives only in the
`TextEditingController`s and the in-RAM `MedicalRecord`; nothing is written to disk or logged.
The `RecordSizeGuard` 500 Kio budget is enforced before encryption and guarantees the
newly added consultation is never the entry truncated (it fails loudly with "dossier plein"
instead). The re-encrypted blob is held on a RAM-only `ConsultationSession`; the cloud upload
and the end-of-session RAM wipe are **#19's** responsibility.

### Consultation-loop e2e (#20)

`test/e2e/consultation_loop_e2e_test.dart` chains the **real** #16–#19 services end to
end — patient generates the QR → doctor scans, decrypts in RAM, appends a note +
ordonnance, re-encrypts with the session key, terminates (cloud PUT + RAM wipe) → the
update is observable by re-decrypting the server blob within the 120 s window. It runs
on the host (no device/emulator) via shared fakes in
`test/support/consultation_loop_harness.dart` (a stateful in-memory blob backend +
a deterministic XOR `CryptoCore`).

> **This is a wiring test, not a crypto proof.** The XOR fake does **not** validate
> AES-256-GCM, the `nonce||ct||tag` format, or "wrong key" rejection — real cryptography
> is covered by the crypto-core NIST vectors (#10) and, later, by a device-backed e2e
> (`integration_test/`, follow-up). Run it like any other test: `flutter test`.

### Secure offline upload queue (#21)

When the doctor validates a consultation **offline**, the end-of-session PUT (#19)
fails with `BackendUnavailable`. Before #21 that lost the freshly re-encrypted
prescription, because `ConsultationSession.wipe` zeroes the pending blob in a
`finally`. `#21` makes that loss impossible: the **opaque AES-256-GCM ciphertext**
(never plaintext, never the session key) is persisted to a durable queue and the
consultation is *validated offline, awaiting sync*.

- **`OfflineUploadQueue`** (`lib/src/doctor/offline_upload_queue.dart`) — the queue
  contract `enqueue / pending / remove / count`, the `PendingUpload` row model, the
  `SessionEndOutcome` enum (`uploaded` / `queued` / `nothingToUpload`) and the
  `OfflineQueueUnavailable` exception. `enqueue` is idempotent on
  `(blobUuid, ciphertext)` and takes a **defensive copy** of the bytes (the caller's
  blob is wiped immediately after). `InMemoryUploadQueue` is the host-only impl used
  in tests.
- **`SqlCipherUploadQueue`** (`lib/src/doctor/sqlcipher_upload_queue.dart`) — the
  production impl: a dedicated **SQLCipher** (AES-256 full-DB) `drift` database whose
  key is 32 CSPRNG bytes **sealed by the hardware Keystore** (envelope encryption, same
  model as the master key #11), opened with `PRAGMA key` + WAL. Defence in depth: even
  an unlocked DB reveals only the already-opaque ciphertext. No software fallback —
  `KeystoreUnavailable` fails loudly (ADR 0006).
- **`SessionEndService.terminate`** now returns a `SessionEndOutcome` and **enqueues
  instead of losing** `pendingBlob` on `BackendUnavailable`, preserving the RAM wipe in
  `finally`. `RecordViewScreen` surfaces a "enregistrée hors-ligne" snackbar.

> The network **drain** of this queue on reconnect (retry, conflict resolution, the
> `attempts` increment) is **#22** (below) — no network logic lives in #21. The real SQLCipher
> binding is not exercised by host-only `flutter test` (no native lib, like
> `path_provider`/FRB); the queue **logic** is covered by `InMemoryUploadQueue` tests
> and a device-backed e2e is a follow-up.

### Synchronisation on network return (#22)

`#21` guaranteed no offline data loss; `#22` delivers the missing half — the **drain**. On network
return, the queue is replayed to the sovereign backend with **no loss and no duplicate**.

- **`SyncService`** (`lib/src/doctor/sync_service.dart`) — `drain()` walks
  `OfflineUploadQueue.pending()` in **FIFO** order and, for each eligible item, `PUT /blob/{uuid}`
  via `BackendClient`, then `remove(id)` **only after** a confirmed 2xx. The ordering is the whole
  point: **put then remove**, so a crash in between re-PUTs an identical blob next drain (idempotent
  UUID) — *at-least-once delivery + idempotent PUT = exactly one final server state, no duplicate*.
  A single-drain **mutex** makes it re-entrant-safe. On a network outage it stops early and returns a
  `SyncSummary { synced, failed, conflicts, skipped, persistentFailures, remaining }` — it never
  throws to the caller. **No new cryptography**: the queued bytes are PUT as-is; the drain never needs
  the (wiped) session key.
- **`RetryPolicy`** — bounded exponential backoff (`baseBackoff·2^(n-1)` capped at `maxBackoff`) and a
  `maxAttempts` cap. Past the cap an item is a **persistent failure**: kept in the queue and flagged to
  the UI, **never silently purged**.
- **`SyncTrigger`** (`lib/src/doctor/sync_trigger.dart`) — the "network is back" signal, decoupled from
  any connectivity package (a #1 decision). Ships with dependency-free triggers: `AppLifecycleSyncTrigger`
  (app resume / start) and `ManualSyncTrigger` (the "Synchroniser" button + the opportunistic post-PUT
  signal). `SyncService` subscribes and drains per event (the mutex debounces overlaps).
- **Queue extension** — `OfflineUploadQueue` gains `markAttempt` / `markConflict`; `PendingUpload`
  gains read-only `lastAttemptAtIso` / `lastError` (redacted) / `state`. The SQLCipher table moves to
  **schemaVersion 2** (`last_attempt_at`, `last_error`, `state`) with a v1→v2 migration.
- **UI** — `RecordViewScreen` shows a "N en attente" badge, a "Synchroniser" action, drains
  opportunistically after a successful end-of-session PUT, and alerts on conflict / persistent failure.

> **Conflict strategy ([ADR 0010](../docs/adr/0010-offline-sync-conflict-resolution.md)).** The device
> cannot decrypt the queued blob (session key wiped, #19) so it cannot merge. Default is **(A) blind
> last-writer-wins** via the idempotent PUT; **(B)** divergence detection + preservation (`markConflict`,
> `UploadState.conflict`) is wired but **inactive** until the backend (#9) exposes conditional PUT /
> versioning; **(C)** patient-side reconciliation (master key) is a follow-up. The real SQLCipher
> migration v1→v2 is a device-backed e2e (not run in host-only CI).

## Build & test

> Flutter SDK is **not installed in the scaffolding environment**, so these files were
> created structurally and cannot be run here. The exact commands are:

```sh
# Build (per-ABI split is MANDATORY — ADR 0001)
flutter build appbundle --split-per-abi

# Test
flutter test
```

First-time setup (once an SDK is available): `flutter pub get`, then run the
`flutter_rust_bridge` codegen + `dart run build_runner build` to generate the
`lib/src/rust/**` bindings and drift `*.g.dart` (`TODO(#11)`, `TODO(#14)`).
