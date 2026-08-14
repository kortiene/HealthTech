// Post-QR-session media migration (issue #152).
//
// After a QR session merge the doctor may have attached media files
// (photos, scans) whose descriptors carry url: null — the bytes are on the
// backend but have not yet been downloaded to the patient device. This
// violates local-first: the patient would need network to view those files.
//
// [downloadPendingMedia] fixes that by:
//   1. Requesting a short-TTL access URL for each url: null descriptor.
//   2. Fetching the opaque ciphertext.
//   3. Verifying integrity in RAM (SHA-256 of plaintext via MediaCipher).
//   4. Writing the ciphertext to a local file:// path (flushed before returning).
//   5. Returning the updated record (url: null → url: file://) plus a list of
//      backend UUIDs that the caller must DELETE after persisting the record.
//
// Invariants:
//   - Idempotent: descriptors already at file:// are skipped.
//   - Crash-safe: url remains null until step 4 + 5 are confirmed. On restart
//     the download retries automatically (url: null still present).
//   - Zero-data-loss: the backend DELETE must happen only after the updated
//     record is persisted locally — enforced by the caller (see main.dart).

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../cloud/media_client.dart';
import '../record/media_cipher.dart';
import '../record/medical_record.dart';

/// Downloads all url: null [MediaDescriptor]s in [record], writes their
/// ciphertext to local storage, verifies integrity, and returns the updated
/// record alongside the backend UUIDs that are now safe to delete.
///
/// [dir] overrides the storage directory (for tests). Defaults to
/// [getApplicationDocumentsDirectory].
///
/// The caller MUST persist the returned record locally BEFORE calling
/// [MediaClient.deleteMedia] on any of the returned UUIDs.
Future<(MedicalRecord, List<String>)> downloadPendingMedia(
  MedicalRecord record,
  MediaClient mediaClient,
  MediaCipher mediaCipher, {
  Directory? dir,
}) async {
  final storageDir = dir ?? await getApplicationDocumentsDirectory();
  final toDelete = <String>[];

  // ── consultations ─────────────────────────────────────────────────────────
  var consultsChanged = false;
  final updatedConsults = <Consultation>[];
  for (final c in record.consultations) {
    final (updatedMedia, pending) = await _migrateDescriptors(
      c.media,
      storageDir,
      mediaClient,
      mediaCipher,
    );
    toDelete.addAll(pending);
    if (pending.isEmpty) {
      updatedConsults.add(c);
    } else {
      consultsChanged = true;
      updatedConsults.add(Consultation(
        id: c.id,
        date: c.date,
        practitionerRef: c.practitionerRef,
        summary: c.summary,
        prescription: c.prescription,
        ordonnances: c.ordonnances,
        imageUrls: c.imageUrls,
        media: updatedMedia,
        createdAt: c.createdAt,
        amendments: c.amendments,
      ));
    }
  }

  // ── chronicConditions ─────────────────────────────────────────────────────
  var conditionsChanged = false;
  final updatedConditions = <ChronicCondition>[];
  for (final cc in record.chronicConditions) {
    final (updatedDocs, pending) = await _migrateDescriptors(
      cc.documents,
      storageDir,
      mediaClient,
      mediaCipher,
    );
    toDelete.addAll(pending);
    if (pending.isEmpty) {
      updatedConditions.add(cc);
    } else {
      conditionsChanged = true;
      updatedConditions.add(cc.copyWith(documents: updatedDocs));
    }
  }

  // ── top-level PatientDocuments ────────────────────────────────────────────
  var docsChanged = false;
  final updatedPatientDocs = <PatientDocument>[];
  for (final doc in record.documents) {
    final (updatedDescriptors, pending) = await _migrateDescriptors(
      [doc.media],
      storageDir,
      mediaClient,
      mediaCipher,
    );
    toDelete.addAll(pending);
    if (pending.isEmpty) {
      updatedPatientDocs.add(doc);
    } else {
      docsChanged = true;
      updatedPatientDocs.add(doc.copyWithMedia(updatedDescriptors.first));
    }
  }

  if (!consultsChanged && !conditionsChanged && !docsChanged) {
    return (record, const <String>[]);
  }

  return (
    record.copyWith(
      consultations: consultsChanged ? updatedConsults : null,
      chronicConditions: conditionsChanged ? updatedConditions : null,
      documents: docsChanged ? updatedPatientDocs : null,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    ),
    toDelete,
  );
}

/// For each descriptor in [descriptors] with url == null:
///   1. Mint an access URL via [mediaClient.requestAccess].
///   2. Fetch the opaque ciphertext.
///   3. Decrypt in RAM and verify [MediaDescriptor.contentHash].
///   4. Flush the ciphertext to a local file.
///   5. Return the updated descriptor (url: file://).
///
/// Returns (updatedDescriptors, uuidsToDelete). Descriptors whose download
/// or integrity check fails are returned unchanged (url: null) and are NOT
/// added to uuidsToDelete — they will be retried on the next call.
Future<(List<MediaDescriptor>, List<String>)> _migrateDescriptors(
  List<MediaDescriptor> descriptors,
  Directory storageDir,
  MediaClient mediaClient,
  MediaCipher mediaCipher,
) async {
  if (descriptors.every((d) => d.url != null)) {
    return (descriptors, const <String>[]);
  }

  var changed = false;
  final toDelete = <String>[];
  final updated = <MediaDescriptor>[];

  for (final d in descriptors) {
    if (d.url != null) {
      updated.add(d);
      continue;
    }
    try {
      final grant = await mediaClient.requestAccess(d.uuid);
      final ciphertext = await mediaClient.fetchCiphertext(grant.url);

      // Decrypt in RAM to verify integrity — throws MediaIntegrityError on
      // SHA-256 mismatch. Plaintext is discarded; only ciphertext is kept.
      final contentKeyBytes = base64.decode(d.contentKey);
      await mediaCipher.decrypt(
        ciphertext,
        contentKeyBytes,
        expectedHash: d.contentHash,
      );

      // Write ciphertext (not plaintext) — consistent with patient_record_screen
      // which stores encrypted bytes at file:// and decrypts at read time.
      final ext = _extFromMime(d.mime);
      final localFile = File('${storageDir.path}/media_${d.uuid}$ext');
      await localFile.writeAsBytes(ciphertext, flush: true);

      updated.add(MediaDescriptor(
        uuid: d.uuid,
        contentKey: d.contentKey,
        contentHash: d.contentHash,
        mime: d.mime,
        sizeBytes: d.sizeBytes,
        addedAt: d.addedAt,
        alg: d.alg,
        url: 'file://${localFile.path}',
        durationMs: d.durationMs,
      ));
      toDelete.add(d.uuid);
      changed = true;
    } catch (_) {
      // Network / integrity failure: keep url: null → retried on next call.
      updated.add(d);
    }
  }

  return (changed ? updated : descriptors, toDelete);
}

String _extFromMime(String mime) => switch (mime) {
      'image/jpeg' => '.jpg',
      'image/png' => '.png',
      'image/gif' => '.gif',
      'image/webp' => '.webp',
      'video/mp4' => '.mp4',
      'audio/mpeg' => '.mp3',
      'audio/aac' => '.aac',
      'audio/ogg' => '.ogg',
      'audio/wav' => '.wav',
      'application/pdf' => '.pdf',
      _ => '.bin',
    };
