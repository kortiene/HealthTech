// End-of-session upload and RAM wipe (issue #19 — US-2.3).
//
// [SessionEndService.terminate] is the authoritative end-of-session entry
// point, invoked either by the doctor's explicit "Terminer" tap or by the
// 15-minute idle timer in [RecordViewScreen].  It:
//   1. PUTs the pending session-key ciphertext blob to the backend when an
//      edit was saved during this session (pendingBlob != null).
//   2. Calls [ConsultationSession.wipe] in a `finally` block — always, even
//      when the PUT fails — to zero the session key and pending blob bytes.
//
// Zero-knowledge invariant: the server receives only opaque ciphertext; the
// session key is always wiped so no key material persists beyond this call.
// [BackendUnavailable] propagates after wiping when the PUT fails — the UI
// informs the doctor of the sync failure without leaking session details.

import '../cloud/backend_client.dart';
import 'consultation_session.dart';

/// Terminates a doctor consultation session: uploads the pending blob (if any)
/// then wipes the session from RAM.
///
/// Inject a [BackendClient] for testability; production wires the client that
/// points to [QrPayload.backendUrl].
class SessionEndService {
  SessionEndService({required BackendClient client}) : _client = client;

  final BackendClient _client;

  /// Upload [session.pendingBlob] (if any) then wipe the session.
  ///
  /// When no edit was committed ([session.pendingBlob] is null), the PUT is
  /// skipped and only the wipe runs.  [ConsultationSession.wipe] is called in
  /// a `finally` block — the session is ALWAYS wiped, even when PUT throws.
  ///
  /// Throws [BackendUnavailable] after wiping when the cloud upload fails.
  Future<void> terminate(ConsultationSession session) async {
    try {
      final blob = session.pendingBlob;
      if (blob != null) {
        await _client.put(session.payload.uuid, blob);
      }
    } finally {
      session.wipe();
    }
  }
}
