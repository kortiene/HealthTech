// Size guard for the patient medical record (issue #15).
//
// The plaintext JSON (UTF-8) must stay ≤ 500 Kio so that the AES-256-GCM blob
// uploads and decrypts in < 3 s on an Edge/3G connection (PRD §4 / NFR §5).
// Encryption overhead (nonce + tag = 28 bytes) is negligible and not counted
// against the plaintext budget.
//
// Guard thresholds:
//   warnBytes  = 409 600 bytes (400 Kio, 80 %)  — RecordSizeWarning
//   maxBytes   = 512 000 bytes (500 Kio, 100 %) — RecordTooLargeException
//
// Truncation strategy: drop the oldest consultation (by `date` ASC) until the
// serialised size falls below maxBytes. If the record is still too large after
// removing all consultations, RecordTooLargeException is re-thrown.

import 'dart:convert';

import 'medical_record.dart';

/// Serialised UTF-8 size at which a [RecordSizeWarning] is emitted.
const int warnPlaintextBytes = 409600; // 400 Kio

/// Serialised UTF-8 size above which [RecordTooLargeException] is thrown.
const int maxPlaintextBytes = 512000; // 500 Kio (PRD §4)

/// Thrown when the record plaintext exceeds [maxPlaintextBytes].
class RecordTooLargeException implements Exception {
  const RecordTooLargeException(this.sizeBytes);

  final int sizeBytes;

  @override
  String toString() =>
      'RecordTooLargeException: record is $sizeBytes bytes '
      '(limit: $maxPlaintextBytes bytes / 500 Kio).';
}

/// Thrown when the record plaintext is between [warnPlaintextBytes] and
/// [maxPlaintextBytes]. Does not block serialisation — the caller should
/// prompt the user to review old consultations.
class RecordSizeWarning implements Exception {
  const RecordSizeWarning(this.sizeBytes);

  final int sizeBytes;

  @override
  String toString() =>
      'RecordSizeWarning: record is $sizeBytes bytes '
      '(≥ 80 % of the 500 Kio limit). '
      'Consider truncating old consultations.';
}

/// Validates and, when needed, truncates [MedicalRecord] plaintext size.
abstract final class RecordSizeGuard {
  /// Returns the UTF-8 byte length of the serialised [record].
  static int measure(MedicalRecord record) =>
      utf8.encode(jsonEncode(record.toJson())).length;

  /// Validates [record] size.
  ///
  /// Throws [RecordTooLargeException] if `size >= maxPlaintextBytes`.
  /// Throws [RecordSizeWarning] if `size >= warnPlaintextBytes`.
  /// Returns silently if size is within the safe zone.
  static void validate(MedicalRecord record) {
    final size = measure(record);
    if (size >= maxPlaintextBytes) throw RecordTooLargeException(size);
    if (size >= warnPlaintextBytes) throw RecordSizeWarning(size);
  }

  /// Returns a copy of [record] guaranteed to be below [maxPlaintextBytes].
  ///
  /// Drops the oldest consultations (sorted by `date` ASC) until the record
  /// fits. Throws [RecordTooLargeException] if the fixed sections alone exceed
  /// the limit (no consultations left to remove).
  static MedicalRecord truncate(MedicalRecord record) {
    if (measure(record) < maxPlaintextBytes) return record;

    // Sort consultations oldest-first for deterministic removal order.
    final sorted = [...record.consultations]
      ..sort((a, b) => a.date.compareTo(b.date));

    while (sorted.isNotEmpty) {
      sorted.removeAt(0); // remove oldest
      final candidate = record.copyWith(
        consultations: List.unmodifiable(sorted),
      );
      if (measure(candidate) < maxPlaintextBytes) return candidate;
    }

    // Even with no consultations the record is still too large.
    throw RecordTooLargeException(
      measure(record.copyWith(consultations: const [])),
    );
  }
}
