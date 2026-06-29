// Consultation re-encryption service (issue #18 — US-2.2).
//
// After [mergeConsultation] appends the doctor's note/ordonnance to the in-RAM
// [MedicalRecord], this service re-encrypts the merged record with the EPHEMERAL
// session key held in the [QrPayload] — the doctor never holds the patient
// master key. It mirrors AccessTokenService._encryptWithSession exactly: wrap
// the session key in a Rust handle, encrypt, and wipe the handle in a `finally`
// block. The produced `nonce||ct||tag` blob stays in RAM and is handed to the
// #19 session-end flow; #18 never PUTs it to the backend.
//
// The 500 Kio plaintext budget (RecordSizeGuard) is enforced BEFORE encryption.
// Because truncation drops the OLDEST consultations first and the new note is
// the newest, the just-added consultation is preserved — and if the record is
// so full that it cannot survive, we fail loudly ("dossier plein") rather than
// silently dropping the doctor's addition.

import 'dart:typed_data';

import '../qr/access_token.dart';
import '../record/medical_record.dart';
import '../record/record_size_guard.dart';
import '../rust/crypto_core_bindings.dart';

/// Thrown when the merged record cannot fit within the 500 Kio budget without
/// sacrificing the newly added consultation. Surfaced to the UI as a generic
/// "dossier plein" message — never leaks record contents.
class RecordFullException implements Exception {
  const RecordFullException();

  @override
  String toString() =>
      'RecordFullException: dossier plein — impossible d’ajouter la note';
}

/// Re-encrypts a merged [MedicalRecord] with the consultation session key.
///
/// Inject a [CryptoCore]; tests supply the XOR `_FakeCryptoCore` used across the
/// doctor flow. Production wires [FrbCryptoCore].
class ConsultationEditService {
  ConsultationEditService({required CryptoCore crypto}) : _crypto = crypto;

  final CryptoCore _crypto;

  /// Re-encrypt [merged] with [payload]'s session key, after enforcing the size
  /// budget while guaranteeing [newConsultationId] survives.
  ///
  /// Returns the `nonce(12) || ciphertext || tag(16)` blob (RAM-only; handed to
  /// #19, never uploaded here). The transient key handle is wiped in `finally`.
  ///
  /// Throws [RecordFullException] when the record is too large to keep the new
  /// consultation. Propagates [DecryptError]/[CryptoCoreUnavailable] from the
  /// crypto core unchanged.
  Future<Uint8List> reEncrypt(
    MedicalRecord merged,
    QrPayload payload, {
    required String newConsultationId,
  }) async {
    final safe = _guardKeepingNewest(merged, newConsultationId);
    final plaintext = Uint8List.fromList(safe.toUtf8Bytes());
    final handle = await _crypto.handleFromUnsealed(payload.sessionKey);
    try {
      return await _crypto.encryptRecord(handle, plaintext);
    } finally {
      await _crypto.wipe(handle);
    }
  }

  /// Truncate [merged] to the 500 Kio budget but never drop [newConsultationId].
  ///
  /// [RecordSizeGuard.truncate] removes the oldest consultations first; the new
  /// note (newest) normally survives. If it does not — or the fixed sections
  /// alone exceed the limit — a [RecordFullException] is raised so the UI can
  /// tell the doctor the record is full instead of silently losing the note.
  MedicalRecord _guardKeepingNewest(
    MedicalRecord merged,
    String newConsultationId,
  ) {
    final safe = _truncateOrThrow(merged);
    final kept = safe.consultations.any((c) => c.id == newConsultationId);
    if (!kept) throw const RecordFullException();
    return safe;
  }

  MedicalRecord _truncateOrThrow(MedicalRecord merged) {
    try {
      return RecordSizeGuard.truncate(merged);
    } on RecordTooLargeException {
      throw const RecordFullException();
    }
  }
}
