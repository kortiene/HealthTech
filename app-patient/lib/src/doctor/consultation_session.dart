// RAM-only consultation session holder (issue #18 — US-2.2).
//
// Threads the single source of truth for an open consultation between the
// read-only viewer (#17), the edit flow (#18), and the end-of-session
// upload/wipe (#19). Everything here lives ONLY in RAM: the decrypted
// [MedicalRecord], the re-encrypted pending blob, and the [QrPayload] session
// key. Nothing is written to disk or logged.
//
// #18 stops at producing [pendingBlob] in RAM; #19 owns the cloud PUT and the
// authoritative end-of-session wipe.

import 'dart:typed_data';

import '../qr/access_token.dart';
import '../record/medical_record.dart';

/// Mutable, RAM-only holder for one doctor consultation session.
///
/// Construct it from the decrypted record and the [QrPayload] obtained at scan
/// time. The edit flow calls [applyMerge] to swap in the merged record and the
/// freshly re-encrypted blob; [wipe] scrubs the session key and the pending
/// blob when the session ends.
class ConsultationSession {
  ConsultationSession({
    required this.payload,
    required MedicalRecord record,
  }) : _current = record;

  /// Holds the 120 s session key (RAM-only) used for re-encryption and wiped
  /// at session end.
  final QrPayload payload;

  MedicalRecord _current;
  Uint8List? _pendingBlob;

  /// The current in-RAM record — reflects every applied merge.
  MedicalRecord get current => _current;

  /// The latest session-key re-encrypted blob awaiting upload by #19, or null
  /// if no edit has been saved yet.
  Uint8List? get pendingBlob => _pendingBlob;

  /// Replace the current record and the pending re-encrypted blob after a save.
  ///
  /// [merged] becomes the new source of truth shown to the doctor; [blob] is
  /// the session-key ciphertext (`nonce||ct||tag`) handed to #19 for upload.
  void applyMerge(MedicalRecord merged, Uint8List blob) {
    _current = merged;
    _pendingBlob = blob;
  }

  /// Best-effort RAM scrub: wipe the session key and the pending blob bytes.
  ///
  /// The authoritative end-of-session wipe (including the 15-min idle timer)
  /// remains #19's responsibility; this scrubs what #18 holds.
  void wipe() {
    payload.wipe();
    final blob = _pendingBlob;
    if (blob != null) blob.fillRange(0, blob.length, 0);
    _pendingBlob = null;
  }
}
