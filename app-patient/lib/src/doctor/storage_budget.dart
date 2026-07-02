// Local storage budget — low-end-device anti-regression source of truth (issue #29).
//
// The product explicitly targets constrained hardware: the "Awa" persona owns an
// Infinix 32 Go phone that is "souvent saturé" (PRD §2), and the reliability KPI
// demands "100 % des consultations sans perte de données" (PRD §1). On a nearly
// full device local writes can fail; the offline queue (#21) and its WAL must
// degrade cleanly and NEVER grow unbounded on disk.
//
// This file is the SINGLE SOURCE OF TRUTH for the numeric bound on the app's
// LOCAL disk footprint — the analogue of PerfBudget (#27) and UxBudget (#28). It
// turns the "smartphone d'entrée de gamme" constraint into checkable invariants:
//
//   * a per-entry ceiling on the queued ciphertext ([maxQueueEntryBytes], which
//     mirrors PerfBudget.maxCompressedBlobBytes — Dart cannot read that Rust-free
//     constant across files without coupling, so it is re-stated and kept equal);
//   * a ceiling on the number of pending queue entries before the UI must alert
//     ([maxPendingQueueEntries]); together these bound the queue's disk footprint
//     ([maxQueueFootprintBytes]);
//   * the "no heavy image on the device" invariant (#23): the record embeds only a
//     small, off-device MEDIA DESCRIPTOR (anonymous UUID + content key), NEVER the
//     image bytes and NEVER a baked-in data: URI.
//
// It is documented in full (reference profile citation, derivation, the "never
// bypass crypto to save space" rule) in docs/ux/low-end-device-profile.md — keep
// the two in sync (enforced by scripts/check-lowend-docs.sh / `just lowend-check`).
//
// HONESTY: these are GENEROUS anti-regression guards, not a substitute for the
// on-device field validation of the acceptance criterion (deux parcours validés
// sur appareil Infinix réel), which remains a HUMAN activity — see the protocol
// docs/ux/low-end-validation-protocol.md. This introduces NO crypto, protocol,
// blob-format or data-model change.

import '../record/medical_record.dart';

/// Local storage-footprint budget for the offline path on a low-end device (#29).
abstract final class StorageBudget {
  // ── Per-entry ceiling ──────────────────────────────────────────────────────

  /// Largest transferred (compressed + encrypted) blob, in bytes, that a single
  /// offline-queue entry may hold. MIRRORS `PerfBudget.maxCompressedBlobBytes`
  /// (128 Kio, #27): the enqueued ciphertext is exactly the blob that would have
  /// been PUT, so the perf size ceiling is also the queue's per-entry ceiling.
  /// Kept EQUAL to `PerfBudget.maxCompressedBlobBytes` by the guard-rail.
  static const int maxQueueEntryBytes = 131072; // 128 Kio

  // ── Queue-length ceiling ────────────────────────────────────────────────────

  /// Maximum number of PENDING offline uploads before the UI must warn the doctor
  /// that a backlog is accumulating on a possibly-saturated device. This is a
  /// conservative anti-regression guard, NOT a hard limiter (an item is NEVER
  /// silently purged — no-loss KPI, #22): crossing it signals "sync soon / free
  /// space", it does not drop data.
  ///
  /// Derivation: on a 32 Go device driven to its "quasi saturé" target (< 500 Mo
  /// free, cf. the profile), a doctor validating consultations offline rarely
  /// queues more than a handful before reconnecting. 64 entries gives generous
  /// headroom while bounding the queue's disk footprint to [maxQueueFootprintBytes]
  /// (~8 Mio) — trivial against 500 Mo. Value to confirm from a first field pass
  /// (Risk #6) — same prudence as `MAX_CONSULTATION_STEPS` (#28).
  static const int maxPendingQueueEntries = 64;

  /// Upper bound on the offline queue's on-disk footprint (ciphertext only, WAL
  /// and SQLCipher page overhead excluded): `maxPendingQueueEntries ×
  /// maxQueueEntryBytes`. A generous ceiling that stays negligible against the
  /// residual free space of the reference device.
  static const int maxQueueFootprintBytes =
      maxPendingQueueEntries * maxQueueEntryBytes; // 8 Mio

  // ── Invariant helpers (asserted by the host-only guard-rail, tests phase) ────

  /// Whether a single queued ciphertext of [byteLength] respects the per-entry
  /// ceiling. A blob larger than [maxQueueEntryBytes] means an upstream size
  /// guard (record ≤ 500 Kio, #15; compressed blob ≤ 128 Kio, #27) has regressed.
  static bool entryWithinBudget(int byteLength) =>
      byteLength <= maxQueueEntryBytes;

  /// Whether [pendingCount] is within the alert ceiling. `false` ⇒ the UI should
  /// surface a "synchronisez / libérez de l'espace" prompt; data is still kept.
  static bool queueLengthWithinBudget(int pendingCount) =>
      pendingCount <= maxPendingQueueEntries;

  /// The "no heavy image on the device" invariant (#23, PRD §4): a record persisted
  /// or queued locally must NOT embed image bytes — only off-device pointers.
  ///
  /// Returns `true` when every consultation carries images exclusively as
  /// off-device references:
  ///   - [MediaDescriptor]s (anonymous UUID + content key, bytes live server-side),
  ///     which are pointers by construction, and
  ///   - legacy [Consultation.imageUrls] that are plain ephemeral links, NEVER
  ///     `data:` URIs (a `data:` URI would inline the image bytes on the device).
  static bool recordCarriesNoHeavyMedia(MedicalRecord record) {
    for (final consultation in record.consultations) {
      for (final url in consultation.imageUrls) {
        if (_isInlineDataUri(url)) return false;
      }
    }
    return true;
  }

  /// True for a `data:` URI (case-insensitive), which would embed the image bytes
  /// directly in the record instead of pointing at an off-device blob.
  static bool _isInlineDataUri(String url) =>
      url.trimLeft().toLowerCase().startsWith('data:');
}
