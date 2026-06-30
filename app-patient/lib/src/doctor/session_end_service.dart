// End-of-session upload, offline queue and RAM wipe (issues #19 + #21).
//
// [SessionEndService.terminate] is the authoritative end-of-session entry
// point, invoked either by the doctor's explicit "Terminer" tap or by the
// 15-minute idle timer in [RecordViewScreen].  It:
//   1. PUTs the pending session-key ciphertext blob to the backend when an
//      edit was saved during this session (pendingBlob != null).
//   2. #21: when the PUT fails because the network is down ([BackendUnavailable]),
//      the encrypted blob is ENQUEUED to the durable offline queue instead of
//      being lost — the consultation is validated offline (US-2.4), to be synced
//      later by #22.  Returns a [SessionEndOutcome] so the UI can distinguish
//      "uploaded" from "queued (awaiting sync)".
//   3. Calls [ConsultationSession.wipe] in a `finally` block — always, even
//      when the PUT fails — to zero the session key and pending blob bytes.
//
// Zero-knowledge invariant: the server (and the queue) receive only opaque
// ciphertext; the session key is ALWAYS wiped so no key material persists beyond
// this call.  The offline queue stores the ciphertext + UUID only, never the
// session key.  The enqueue takes a defensive COPY of the bytes BEFORE the
// `finally` wipe zeroes them in place.
//
// Failure of the queue itself ([OfflineQueueUnavailable], e.g. KeystoreUnavailable
// or disk full) is the only path that can still lose data; it propagates after
// the wipe so the UI can alert the doctor loudly.

import '../cloud/backend_client.dart';
import 'consultation_session.dart';
import 'offline_upload_queue.dart';

/// Terminates a doctor consultation session: uploads the pending blob (if any),
/// queues it offline when the network is down, then wipes the session from RAM.
///
/// Inject a [BackendClient] and an [OfflineUploadQueue] for testability;
/// production wires the client that points to [QrPayload.backendUrl] and a
/// SQLCipher-backed queue.
class SessionEndService {
  SessionEndService({
    required BackendClient client,
    required OfflineUploadQueue queue,
  })  : _client = client,
        _queue = queue;

  final BackendClient _client;
  final OfflineUploadQueue _queue;

  /// Upload [session.pendingBlob] (if any); on a network failure, enqueue it to
  /// the offline queue; then wipe the session.
  ///
  /// Returns:
  ///   - [SessionEndOutcome.uploaded] when the PUT succeeded;
  ///   - [SessionEndOutcome.queued] when the backend was unreachable and the
  ///     blob was persisted to the offline queue (consultation validated
  ///     offline, awaiting #22 sync);
  ///   - [SessionEndOutcome.nothingToUpload] when no edit was committed.
  ///
  /// [ConsultationSession.wipe] is called in a `finally` block — the session is
  /// ALWAYS wiped, even when the PUT throws or the enqueue fails.
  ///
  /// Throws [OfflineQueueUnavailable] (after wiping) when both the PUT and the
  /// offline enqueue fail — the only path that can still lose the edit.
  Future<SessionEndOutcome> terminate(ConsultationSession session) async {
    final blob = session.pendingBlob;
    try {
      if (blob == null) {
        return SessionEndOutcome.nothingToUpload;
      }
      try {
        await _client.put(session.payload.uuid, blob);
        return SessionEndOutcome.uploaded;
      } on BackendUnavailable {
        // Offline: do NOT lose the prescription — enqueue it encrypted.
        // enqueue copies the bytes defensively before the `finally` wipe.
        await _queue.enqueue(session.payload.uuid, blob);
        return SessionEndOutcome.queued;
      }
    } finally {
      session.wipe(); // invariant unchanged: session key + pendingBlob zeroed
    }
  }
}
