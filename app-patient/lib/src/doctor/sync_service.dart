// Offline upload-queue drain on network return (issue #22, US-2.4, M3
// "Résilience hors-ligne & médias").
//
// #21 made offline data loss impossible by ENQUEUEING the end-of-session blob;
// #22 delivers the missing half: the DRAIN. On network return a [SyncTrigger]
// fires, [SyncService.drain] walks the durable [OfflineUploadQueue] in FIFO
// order, re-emits each `PUT /blob/{uuid}` through the existing zero-knowledge
// [BackendClient], and removes each item ONLY after a confirmed (2xx) PUT.
//
// NO-LOSS / NO-DUPLICATE invariant (the issue's acceptance criterion):
//   - put THEN remove. An item is never removed before a PUT succeeds; any
//     failure leaves it queued, increments `attempts`, and schedules a retry.
//   - a crash between `put` and `remove` survives (durable queue) and is re-PUT
//     next drain — `PUT /blob/{uuid}` is idempotent at the UUID, so at-least-once
//     delivery + idempotent PUT = exactly one final server state, no duplicate.
//
// SECURITY INVARIANTS:
//   - The drain NEVER needs the session key (wiped at session end, #19). It only
//     transports OPAQUE bytes already AES-256-GCM encrypted (#16/#18). No new
//     cryptography, no re-encryption, no decryption — see [Non-Goals] in the spec.
//   - The server stays zero-knowledge: the offline blob takes the exact same
//     opaque `PUT /blob/{uuid}` path as a normal upload.
//   - Observability carries ONLY blob UUID + state + attempts + HTTP status.
//     NEVER ciphertext, keys, or PII (mirrors [BackendClient]'s redacted errors).
//
// CONFLICT STRATEGY: the device cannot decrypt the queued blob (session key
// wiped) so it cannot merge. Default is blind last-writer-wins via the idempotent
// PUT (option A). Divergence detection + preservation (option B, `markConflict`)
// is wired but inactive until the backend (#9) exposes conditional PUT/versioning.
// Patient-side reconciliation (option C) is a follow-up. Full rationale: see
// `docs/adr/0010-offline-sync-conflict-resolution.md`.

import 'dart:async';

import '../cloud/backend_client.dart';
import 'offline_upload_queue.dart';
import 'sync_trigger.dart';

/// Bounded exponential-backoff retry policy for the drain.
///
/// An item that has failed [attempts] times is eligible again only after
/// `min(baseBackoff * 2^(attempts-1), maxBackoff)` has elapsed since its last
/// attempt. Past [maxAttempts] it is a "persistent failure": kept in the queue
/// and surfaced to the UI, but no longer auto-retried (never silently purged).
class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 5,
    this.baseBackoff = const Duration(seconds: 30),
    this.maxBackoff = const Duration(minutes: 30),
  });

  /// Cap on auto-retries before an item is flagged a persistent failure.
  final int maxAttempts;

  /// Backoff for the first retry; doubles each subsequent attempt up to [maxBackoff].
  final Duration baseBackoff;

  /// Upper bound on the backoff window (keeps a flaky Edge/3G link from
  /// stretching retries unboundedly; protects battery on low-end devices, #29).
  final Duration maxBackoff;

  /// Backoff to wait after [attempts] failed tries (>= 1).
  Duration backoffFor(int attempts) {
    if (attempts <= 0) return Duration.zero;
    // Cap the shift so the multiply can't overflow on a runaway attempts count.
    final shift = (attempts - 1).clamp(0, 30);
    final scaled = baseBackoff * (1 << shift);
    return scaled > maxBackoff ? maxBackoff : scaled;
  }

  /// Whether [item] should be PUT now, given [now]. Conflicts and persistent
  /// failures are excluded; a never-tried item is always eligible; otherwise the
  /// backoff window since [PendingUpload.lastAttemptAtIso] must have elapsed.
  bool isEligible(PendingUpload item, DateTime now) {
    if (item.state == UploadState.conflict) return false;
    if (item.attempts >= maxAttempts) return false;
    if (item.attempts == 0 || item.lastAttemptAtIso == null) return true;
    final last = DateTime.tryParse(item.lastAttemptAtIso!);
    if (last == null) return true; // unparseable stamp → don't get stuck.
    return !now.isBefore(last.add(backoffFor(item.attempts)));
  }
}

/// Outcome of one [SyncService.drain], for the UI and (redacted) logs.
class SyncSummary {
  const SyncSummary({
    this.synced = 0,
    this.failed = 0,
    this.conflicts = 0,
    this.skipped = 0,
    this.persistentFailures = 0,
    this.remaining = 0,
    this.didRun = true,
  });

  /// A no-op result for a re-entrant call that found a drain already running.
  static const SyncSummary alreadyRunning = SyncSummary(didRun: false);

  /// Items PUT successfully and removed this drain.
  final int synced;

  /// Items whose PUT failed this drain (kept, `attempts` incremented).
  final int failed;

  /// Items moved to [UploadState.conflict] this drain (option B).
  final int conflicts;

  /// Eligible-but-skipped items (still inside their backoff window).
  final int skipped;

  /// Items at/over [RetryPolicy.maxAttempts] — flagged, never auto-retried.
  final int persistentFailures;

  /// Items still in the queue after this drain (`queue.count()`).
  final int remaining;

  /// False when a concurrent drain was already running (mutex) and this call
  /// returned immediately without touching the queue.
  final bool didRun;

  @override
  String toString() => 'SyncSummary(synced: $synced, failed: $failed, '
      'conflicts: $conflicts, skipped: $skipped, '
      'persistentFailures: $persistentFailures, remaining: $remaining, '
      'didRun: $didRun)';
}

/// Drains the offline [OfflineUploadQueue] to the backend on network return.
///
/// Inject a [BackendClient] (the sovereign backend) and the SAME
/// [OfflineUploadQueue] used by `SessionEndService` (shared queue). Optionally
/// pass a [SyncTrigger]: the service subscribes and calls [drain] on each event
/// (the internal mutex debounces overlapping triggers). [clock] is injectable
/// for deterministic backoff tests.
class SyncService {
  SyncService({
    required BackendClient client,
    required OfflineUploadQueue queue,
    RetryPolicy retry = const RetryPolicy(),
    SyncTrigger? trigger,
    DateTime Function()? clock,
  })  : _client = client,
        _queue = queue,
        _retry = retry,
        _clock = clock ?? (() => DateTime.now().toUtc()) {
    if (trigger != null) {
      _triggerSub = trigger.events.listen((_) => drain());
    }
  }

  final BackendClient _client;
  final OfflineUploadQueue _queue;
  final RetryPolicy _retry;
  final DateTime Function() _clock;

  StreamSubscription<void>? _triggerSub;
  bool _draining = false;

  /// Whether a drain is currently in flight (single-drain mutex).
  bool get isDraining => _draining;

  /// Drain the queue once: PUT each eligible item (FIFO), [remove] the confirmed
  /// ones, [markAttempt] the failures. Re-entrant-safe — a single mutex prevents
  /// a second concurrent drain (no double-PUT). Returns a [SyncSummary]; on a
  /// network outage it stops early and returns cleanly (never throws to the
  /// caller for a [BackendUnavailable]).
  Future<SyncSummary> drain() async {
    if (_draining) return SyncSummary.alreadyRunning;
    _draining = true;
    try {
      final items = await _queue.pending(); // FIFO by enqueued_at
      var synced = 0;
      var failed = 0;
      var conflicts = 0;
      var skipped = 0;
      var persistentFailures = 0;

      for (final item in items) {
        if (item.state == UploadState.conflict) {
          conflicts++;
          continue;
        }
        if (item.attempts >= _retry.maxAttempts) {
          // Persistent failure: kept and flagged, never auto-retried/purged.
          persistentFailures++;
          continue;
        }
        if (!_retry.isEligible(item, _clock())) {
          skipped++; // still inside its backoff window
          continue;
        }
        try {
          // Opaque bytes, same path as a normal upload — no (de)cryption here.
          await _client.put(item.blobUuid, item.ciphertext);
          // put THEN remove: a crash here re-PUTs an identical blob next drain
          // (idempotent UUID) — at-least-once + idempotent = no duplicate.
          await _queue.remove(item.id);
          synced++;
        } on BackendUnavailable catch (e) {
          // Network still down or 5xx. Keep the item, record a REDACTED attempt,
          // and STOP — hammering a likely-still-offline backend is pointless;
          // the next SyncTrigger will retry.
          await _queue.markAttempt(item.id, redactedError: _redact(e));
          failed++;
          break;
        }
      }

      return SyncSummary(
        synced: synced,
        failed: failed,
        conflicts: conflicts,
        skipped: skipped,
        persistentFailures: persistentFailures,
        remaining: await _queue.count(),
      );
    } finally {
      _draining = false;
    }
  }

  /// Number of items still queued — for the "N en attente" UI badge. Thin
  /// pass-through to the shared queue so callers need not hold it directly.
  Future<int> queueCount() => _queue.count();

  /// Cancel the [SyncTrigger] subscription (if any). Does NOT close the queue or
  /// the client — those are owned by the caller and may be shared.
  Future<void> dispose() async {
    await _triggerSub?.cancel();
    _triggerSub = null;
  }

  /// Reduce a [BackendUnavailable] to a short, PII-free category for the queue's
  /// `last_error` column. [BackendUnavailable.message] is already redacted by
  /// [BackendClient] (UUID + HTTP status only, never the body); we keep just the
  /// first line and clamp the length defensively.
  static String _redact(BackendUnavailable e) {
    final firstLine = e.message.split('\n').first.trim();
    return firstLine.length <= 120 ? firstLine : firstLine.substring(0, 120);
  }
}
