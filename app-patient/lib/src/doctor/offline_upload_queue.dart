// Secure offline pending-upload queue — interface + in-memory impl (issue #21,
// US-2.4, M3 "Résilience hors-ligne").
//
// When the doctor validates a consultation while the network is down, the
// end-of-session PUT (#19) fails with [BackendUnavailable]. Before #21 that lost
// the freshly re-encrypted prescription because [ConsultationSession.wipe] zeroes
// the pending blob in a `finally`. This queue makes that loss impossible: the
// opaque ciphertext (already AES-256-GCM, #16/#18) is persisted DURABLY and the
// consultation is "validated, awaiting sync". The actual network drain is #22.
//
// SECURITY INVARIANTS (ADR 0006):
//   - The queue stores ONLY the opaque ciphertext (`nonce(12)||ct||tag(16)`) and
//     the anonymous blob UUID. NEVER the session key, NEVER plaintext, NEVER PII.
//   - The production store ([SqlCipherUploadQueue]) is a SQLCipher (AES-256
//     full-DB) database whose key is sealed by the hardware Keystore — a second
//     curtain on top of the already-encrypted blob. Even an unlocked DB reveals
//     only opaque ciphertext.
//   - [enqueue] takes a DEFENSIVE COPY of the bytes: the caller's blob is zeroed
//     by `wipe()` immediately after, so a stored view would be corrupted.
//   - Logs/observability carry only UUID + state + attempt count — never bytes.
//
// #21 delivers enqueue + durable storage + pending/remove/count. #22 adds network
// detection, retry, the [PendingUpload.attempts] increment and conflict
// resolution — do NOT add retry logic here.

import 'dart:math';
import 'dart:typed_data';

/// Sync lifecycle state of a queued upload, persisted by the queue.
///
/// Only [pending] items are drained by the #22 [SyncService]; [conflict] items
/// are excluded from the normal drain and surfaced to the UI for patient-side
/// reconciliation (a follow-up issue — the doctor device cannot decrypt to
/// merge, the session key is wiped). `syncing`/`synced` are transient drain
/// states that are never persisted (a synced item is [remove]d, not relabelled).
enum UploadState {
  /// Awaiting (or retrying) a backend PUT — the only state the drain attempts.
  pending,

  /// The server blob diverged from this offline edit (option B, #9 versioning).
  /// Preserved, never overwritten; flagged to the UI; out of the normal drain.
  conflict,
}

/// Parse a persisted [UploadState] name; unknown/legacy values fall back to
/// [UploadState.pending] (forward-compatible with a v1 row migrated in).
UploadState uploadStateFromName(String? name) {
  switch (name) {
    case 'conflict':
      return UploadState.conflict;
    case 'pending':
    default:
      return UploadState.pending;
  }
}

/// One encrypted upload awaiting sync: opaque ciphertext + anonymous UUID.
///
/// [ciphertext] is the `nonce(12)||ct||tag(16)` session-key blob from #18 — it is
/// NEVER plaintext and the queue never (de)encrypts it. [attempts], [lastAttemptAtIso],
/// [lastError] and [state] are owned by the #22 sync loop ([SyncService]); #21
/// always enqueues an item at `attempts: 0`, `state: pending`, no last attempt.
class PendingUpload {
  PendingUpload({
    required this.id,
    required this.blobUuid,
    required Uint8List ciphertext,
    required this.enqueuedAtIso,
    this.attempts = 0,
    this.lastAttemptAtIso,
    this.lastError,
    this.state = UploadState.pending,
  }) : ciphertext = Uint8List.fromList(ciphertext);

  /// Local queue identifier (RFC-4122 v4, generated on-device).
  final String id;

  /// Anonymous record UUID — the `/blob/{uuid}` key the drain (#22) will PUT to.
  final String blobUuid;

  /// Opaque AES-256-GCM ciphertext (`nonce||ct||tag`) — JAMAIS de clair.
  final Uint8List ciphertext;

  /// Sync attempts so far — incremented by #22, never by #21.
  final int attempts;

  /// ISO-8601 enqueue timestamp — drives FIFO order and debugging.
  final String enqueuedAtIso;

  /// ISO-8601 timestamp of the last drain attempt — drives backoff. Null until
  /// the #22 drain has tried this item at least once.
  final String? lastAttemptAtIso;

  /// REDACTED last-failure category (HTTP status / exception type), NEVER bytes,
  /// keys or PII. Null until a drain attempt has failed.
  final String? lastError;

  /// Sync lifecycle state — owned by #22; #21 always enqueues [UploadState.pending].
  final UploadState state;
}

/// Result of [SessionEndService.terminate], so the UI can tell the doctor whether
/// the consultation was uploaded, queued offline, or had nothing to send.
enum SessionEndOutcome {
  /// The pending blob was PUT to the backend successfully.
  uploaded,

  /// The backend was unreachable; the blob was persisted to the offline queue.
  /// The consultation is validated and will sync later (#22).
  queued,

  /// No edit was committed this session — nothing to upload or queue.
  nothingToUpload,
}

/// Thrown when the offline queue itself cannot persist a pending upload (e.g.
/// [KeystoreUnavailable], disk full). This is the ONLY case in which an
/// end-of-session can still lose data; the UI must alert the doctor loudly.
class OfflineQueueUnavailable implements Exception {
  const OfflineQueueUnavailable(this.message);
  final String message;
  @override
  String toString() => 'offline queue unavailable: $message';
}

/// Durable, encrypted queue of pending uploads. No network logic lives here —
/// the #22 sync loop drains it via [pending] / [remove].
abstract class OfflineUploadQueue {
  /// Persist a pending upload atomically and durably (survives a crash).
  ///
  /// Idempotent on `(blobUuid, ciphertext)`: re-enqueuing the identical
  /// end-of-session (re-tap "Terminer", app relaunch) does not create a
  /// duplicate. The bytes are copied defensively — the caller may wipe its blob
  /// immediately after. Throws [OfflineQueueUnavailable] if storage fails.
  Future<void> enqueue(String blobUuid, Uint8List ciphertext);

  /// List pending uploads in FIFO (enqueue) order, for the #22 drain. Removes
  /// nothing. Returned [PendingUpload]s hold copies of the stored bytes.
  Future<List<PendingUpload>> pending();

  /// Remove a synced upload by its [PendingUpload.id] (called by #22 after a
  /// successful PUT). Removing an unknown id is a no-op.
  Future<void> remove(String id);

  /// Number of pending uploads — for a "N en attente de synchro" UI badge.
  Future<int> count();

  /// Record a FAILED drain attempt for [id]: increment [PendingUpload.attempts],
  /// stamp [PendingUpload.lastAttemptAtIso] and persist a REDACTED
  /// [PendingUpload.lastError] (HTTP status / exception category — NEVER bytes,
  /// keys or PII). The item is NEVER removed; the retry/backoff decision belongs
  /// to the #22 [SyncService]. Marking an unknown id is a no-op.
  Future<void> markAttempt(String id, {required String redactedError});

  /// Mark [id] as an unresolved drain-side conflict (server blob diverged,
  /// option B). The item stays persisted, moves to [UploadState.conflict] (so
  /// the normal drain skips it), and is flagged to the UI for patient-side
  /// reconciliation. NEVER overwrites the server. Marking an unknown id is a
  /// no-op. [redactedReason] is a category only (e.g. `412 precondition`).
  Future<void> markConflict(String id, {required String redactedReason});
}

/// Generate an RFC-4122 v4 queue id from the OS CSPRNG.
String generateUploadId() {
  final rng = Random.secure();
  final b = Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
  b[6] = (b[6] & 0x0F) | 0x40; // version 4
  b[8] = (b[8] & 0x3F) | 0x80; // variant RFC 4122
  String hex(int v) => v.toRadixString(16).padLeft(2, '0');
  return '${hex(b[0])}${hex(b[1])}${hex(b[2])}${hex(b[3])}-'
      '${hex(b[4])}${hex(b[5])}-'
      '${hex(b[6])}${hex(b[7])}-'
      '${hex(b[8])}${hex(b[9])}-'
      '${hex(b[10])}${hex(b[11])}${hex(b[12])}${hex(b[13])}${hex(b[14])}${hex(b[15])}';
}

/// In-memory queue for host-only tests and environments without native
/// SQLCipher. Honours the same contract (FIFO, idempotence, defensive copy).
///
/// Inject [idFactory] / [clock] for deterministic tests; production uses the
/// CSPRNG id and the wall clock.
class InMemoryUploadQueue implements OfflineUploadQueue {
  InMemoryUploadQueue({
    String Function()? idFactory,
    DateTime Function()? clock,
  })  : _idFactory = idFactory ?? generateUploadId,
        _clock = clock ?? (() => DateTime.now().toUtc());

  final String Function() _idFactory;
  final DateTime Function() _clock;
  final List<PendingUpload> _items = [];

  @override
  Future<void> enqueue(String blobUuid, Uint8List ciphertext) async {
    // Idempotence: identical (uuid, bytes) already queued → no duplicate.
    final isDuplicate = _items.any(
      (it) => it.blobUuid == blobUuid && _bytesEqual(it.ciphertext, ciphertext),
    );
    if (isDuplicate) return;
    _items.add(
      PendingUpload(
        id: _idFactory(),
        blobUuid: blobUuid,
        // PendingUpload copies the bytes; the caller's blob may be wiped next.
        ciphertext: ciphertext,
        enqueuedAtIso: _clock().toIso8601String(),
      ),
    );
  }

  @override
  Future<List<PendingUpload>> pending() async => List.unmodifiable(
        _items.map(
          (it) => PendingUpload(
            id: it.id,
            blobUuid: it.blobUuid,
            ciphertext:
                it.ciphertext, // PendingUpload copies again on the way out
            enqueuedAtIso: it.enqueuedAtIso,
            attempts: it.attempts,
            lastAttemptAtIso: it.lastAttemptAtIso,
            lastError: it.lastError,
            state: it.state,
          ),
        ),
      );

  @override
  Future<void> remove(String id) async =>
      _items.removeWhere((it) => it.id == id);

  @override
  Future<int> count() async => _items.length;

  @override
  Future<void> markAttempt(String id, {required String redactedError}) async {
    final i = _items.indexWhere((it) => it.id == id);
    if (i < 0) return;
    final it = _items[i];
    _items[i] = PendingUpload(
      id: it.id,
      blobUuid: it.blobUuid,
      ciphertext: it.ciphertext,
      enqueuedAtIso: it.enqueuedAtIso,
      attempts: it.attempts + 1,
      lastAttemptAtIso: _clock().toIso8601String(),
      lastError: redactedError,
      state: it.state,
    );
  }

  @override
  Future<void> markConflict(String id, {required String redactedReason}) async {
    final i = _items.indexWhere((it) => it.id == id);
    if (i < 0) return;
    final it = _items[i];
    _items[i] = PendingUpload(
      id: it.id,
      blobUuid: it.blobUuid,
      ciphertext: it.ciphertext,
      enqueuedAtIso: it.enqueuedAtIso,
      attempts: it.attempts,
      lastAttemptAtIso: it.lastAttemptAtIso,
      lastError: redactedReason,
      state: UploadState.conflict,
    );
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
