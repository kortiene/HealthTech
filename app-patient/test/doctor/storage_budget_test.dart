// Unit tests for StorageBudget (issue #29 — Livrable D).
//
// StorageBudget is the single source of truth for the app's local disk footprint
// on a constrained device (persona Awa, Infinix 32 Go quasi saturé, PRD §2/§4).
// These tests ARE the budget's integrity anchor — any deliberate change to a
// constant must update this file (same discipline as blob_size_budget_test.dart
// and ux_budget_test.dart).
//
// HONESTY: these are generous anti-regression guards, not a substitute for
// on-device field validation on the Infinix reference device — that proof is a
// human activity (docs/ux/low-end-validation-protocol.md).
//
// Run:  flutter test test/doctor/storage_budget_test.dart

import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/doctor/storage_budget.dart';
import 'package:app_patient/src/record/medical_record.dart';
import 'package:app_patient/src/record/perf_budget.dart';

// ─── Fixture helpers ────────────────────────────────────────────────────────

const _baseRecord = MedicalRecord(
  patientId: 'budget-test-id',
  createdAt: '2025-01-01T00:00:00Z',
  updatedAt: '2025-01-01T00:00:00Z',
);

MedicalRecord _recordWith(List<Consultation> consultations) =>
    _baseRecord.copyWith(consultations: consultations);

const _bareConsultation = Consultation(
  id: 'c-bare',
  date: '2025-01-01',
  practitionerRef: 'dr-test',
  summary: 'RAS',
);

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  // ── Constant value guard-rails ────────────────────────────────────────────
  // A change to any constant is a deliberate policy decision and must also
  // update docs/ux/low-end-device-profile.md (enforced by just lowend-check).

  group('StorageBudget — constant values (anti-regression guard)', () {
    test('maxQueueEntryBytes is 131072 (128 Kio)', () {
      expect(StorageBudget.maxQueueEntryBytes, 131072);
    });

    test('maxPendingQueueEntries is 64', () {
      expect(StorageBudget.maxPendingQueueEntries, 64);
    });

    test(
        'maxQueueFootprintBytes == maxPendingQueueEntries × maxQueueEntryBytes',
        () {
      expect(
        StorageBudget.maxQueueFootprintBytes,
        StorageBudget.maxPendingQueueEntries * StorageBudget.maxQueueEntryBytes,
      );
      // Exact value for extra readability: 64 × 128 Kio = 8 Mio.
      expect(StorageBudget.maxQueueFootprintBytes, 8 * 1024 * 1024);
    });
  });

  // ── Cross-file mirror: maxQueueEntryBytes == PerfBudget.maxCompressedBlobBytes
  // The queued ciphertext IS the blob that would have been PUT. A divergence
  // here means the disk guard and the perf gate have drifted apart silently.

  group('StorageBudget — cross-file constant consistency', () {
    test(
        'maxQueueEntryBytes mirrors PerfBudget.maxCompressedBlobBytes '
        '(queued blob is the compressed+encrypted PUT body)', () {
      expect(
        StorageBudget.maxQueueEntryBytes,
        PerfBudget.maxCompressedBlobBytes,
        reason:
            'StorageBudget.maxQueueEntryBytes and PerfBudget.maxCompressedBlobBytes '
            'must stay equal — they bound the same object on two different code paths.',
      );
    });
  });

  // ── entryWithinBudget ─────────────────────────────────────────────────────

  group('StorageBudget.entryWithinBudget', () {
    test('0 bytes is within budget', () {
      expect(StorageBudget.entryWithinBudget(0), isTrue);
    });

    test('1 byte is within budget', () {
      expect(StorageBudget.entryWithinBudget(1), isTrue);
    });

    test('exactly at the ceiling (maxQueueEntryBytes) is within budget', () {
      expect(
        StorageBudget.entryWithinBudget(StorageBudget.maxQueueEntryBytes),
        isTrue,
      );
    });

    test('one byte over the ceiling is outside budget', () {
      expect(
        StorageBudget.entryWithinBudget(StorageBudget.maxQueueEntryBytes + 1),
        isFalse,
      );
    });

    test('a very large entry (512 Kio plaintext ceiling) is outside budget',
        () {
      // 500 Kio plaintext ceiling (PRD §4) compressed + encrypted would still
      // exceed maxQueueEntryBytes — the per-entry guard catches it first.
      expect(StorageBudget.entryWithinBudget(500 * 1024), isFalse);
    });
  });

  // ── queueLengthWithinBudget ───────────────────────────────────────────────

  group('StorageBudget.queueLengthWithinBudget', () {
    test('0 pending entries is within budget (empty queue)', () {
      expect(StorageBudget.queueLengthWithinBudget(0), isTrue);
    });

    test('1 pending entry is within budget', () {
      expect(StorageBudget.queueLengthWithinBudget(1), isTrue);
    });

    test('exactly at the ceiling (maxPendingQueueEntries) is within budget',
        () {
      expect(
        StorageBudget.queueLengthWithinBudget(
          StorageBudget.maxPendingQueueEntries,
        ),
        isTrue,
      );
    });

    test('one entry over the ceiling is outside budget', () {
      expect(
        StorageBudget.queueLengthWithinBudget(
          StorageBudget.maxPendingQueueEntries + 1,
        ),
        isFalse,
      );
    });

    test('a large count (1 000) is outside budget', () {
      expect(StorageBudget.queueLengthWithinBudget(1000), isFalse);
    });
  });

  // ── Device-relative policy guard ─────────────────────────────────────────
  // The "quasi saturé" reference device targets < 500 Mo of residual free
  // space (docs/ux/low-end-device-profile.md). The queue footprint must be
  // negligible against that floor — this test encodes the derivation claim
  // from the source comment of storage_budget.dart so it cannot silently drift.

  group('StorageBudget — device-relative policy guard (#29 A/D)', () {
    test(
        'maxQueueFootprintBytes is well below the 500 Mo residual free '
        'space floor of the reference Infinix device', () {
      const residualFreeSpaceFloor = 500 * 1024 * 1024; // 500 Mo in bytes
      expect(
        StorageBudget.maxQueueFootprintBytes,
        lessThan(residualFreeSpaceFloor),
        reason:
            'maxQueueFootprintBytes (${StorageBudget.maxQueueFootprintBytes} B) '
            'must remain negligible against the 500 Mo free-space floor '
            '(docs/ux/low-end-device-profile.md, #29 G5)',
      );
    });
  });

  // ── recordCarriesNoHeavyMedia ─────────────────────────────────────────────
  // Invariant: records persisted or queued locally must NOT embed image bytes
  // — only off-device pointers (MediaDescriptor or ephemeral URL strings).
  // A `data:` URI inlines image bytes on the patient device, violating #23.

  group('StorageBudget.recordCarriesNoHeavyMedia — no consultations', () {
    test('empty record (no consultations) passes', () {
      expect(StorageBudget.recordCarriesNoHeavyMedia(_baseRecord), isTrue);
    });
  });

  group('StorageBudget.recordCarriesNoHeavyMedia — safe imageUrls', () {
    test('consultation with no imageUrls passes', () {
      expect(
        StorageBudget.recordCarriesNoHeavyMedia(
          _recordWith([_bareConsultation]),
        ),
        isTrue,
      );
    });

    test('consultation with a plain HTTPS image URL passes', () {
      expect(
        StorageBudget.recordCarriesNoHeavyMedia(
          _recordWith([
            const Consultation(
              id: 'c-https',
              date: '2025-01-01',
              practitionerRef: 'dr-test',
              summary: 'Radiographie',
              imageUrls: [
                'https://media.test/img/00000000-0000-4000-8000-000000000001',
              ],
            ),
          ]),
        ),
        isTrue,
      );
    });

    test('MediaDescriptor-only consultation passes (bytes live server-side)',
        () {
      expect(
        StorageBudget.recordCarriesNoHeavyMedia(
          _recordWith([
            Consultation(
              id: 'c-descriptor',
              date: '2025-01-01',
              practitionerRef: 'dr-test',
              summary: 'Scan off-device',
              media: [
                MediaDescriptor(
                  uuid: '00000000-0000-4000-8000-000000000001',
                  contentKey: 'YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWE=',
                  contentHash: 'a' * 64, // synthetic hex
                  mime: 'image/jpeg',
                  sizeBytes: 2 * 1024 * 1024,
                  addedAt: '2025-01-01T00:00:00Z',
                ),
              ],
            ),
          ]),
        ),
        isTrue,
      );
    });

    test('empty string imageUrl passes (empty string is not a data: URI)', () {
      expect(
        StorageBudget.recordCarriesNoHeavyMedia(
          _recordWith([
            const Consultation(
              id: 'c-empty-url',
              date: '2025-01-01',
              practitionerRef: 'dr-test',
              summary: 'Test vide',
              imageUrls: [''],
            ),
          ]),
        ),
        isTrue,
        reason: 'empty string does not start with "data:" — '
            'passes the no-heavy-media invariant',
      );
    });

    test('multiple consultations with only safe URLs all pass', () {
      expect(
        StorageBudget.recordCarriesNoHeavyMedia(
          _recordWith([
            const Consultation(
              id: 'c-multi-a',
              date: '2025-01-01',
              practitionerRef: 'dr-test',
              summary: 'Bilan',
            ),
            const Consultation(
              id: 'c-multi-b',
              date: '2025-06-01',
              practitionerRef: 'dr-test',
              summary: 'Suivi',
              imageUrls: [
                'https://media.test/img/00000000-0000-4000-8000-000000000002',
              ],
            ),
          ]),
        ),
        isTrue,
      );
    });
  });

  group('StorageBudget.recordCarriesNoHeavyMedia — data: URI detection', () {
    test('data: URI (JPEG) fails — inline bytes on device', () {
      expect(
        StorageBudget.recordCarriesNoHeavyMedia(
          _recordWith([
            const Consultation(
              id: 'c-data-jpeg',
              date: '2025-01-01',
              practitionerRef: 'dr-test',
              summary: 'Radiographie',
              imageUrls: ['data:image/jpeg;base64,/9j/4AAQSkZJRgAB'],
            ),
          ]),
        ),
        isFalse,
      );
    });

    test('data: URI detection is case-insensitive ("DATA:" prefix fails)', () {
      expect(
        StorageBudget.recordCarriesNoHeavyMedia(
          _recordWith([
            const Consultation(
              id: 'c-data-upper',
              date: '2025-01-01',
              practitionerRef: 'dr-test',
              summary: 'Test',
              imageUrls: ['DATA:image/png;base64,iVBORw0KGgo='],
            ),
          ]),
        ),
        isFalse,
      );
    });

    test('data: URI with leading whitespace fails (trimLeft applied)', () {
      expect(
        StorageBudget.recordCarriesNoHeavyMedia(
          _recordWith([
            const Consultation(
              id: 'c-data-ws',
              date: '2025-01-01',
              practitionerRef: 'dr-test',
              summary: 'Test',
              imageUrls: ['   data:image/jpeg;base64,abc123'],
            ),
          ]),
        ),
        isFalse,
      );
    });

    test('any one data: URI among safe URLs fails (short-circuit)', () {
      expect(
        StorageBudget.recordCarriesNoHeavyMedia(
          _recordWith([
            const Consultation(
              id: 'c-mixed',
              date: '2025-01-01',
              practitionerRef: 'dr-test',
              summary: 'Mixed',
              imageUrls: [
                'https://media.test/img/safe-1',
                'data:image/jpeg;base64,INLINE_BYTES',
                'https://media.test/img/safe-2',
              ],
            ),
          ]),
        ),
        isFalse,
      );
    });

    test(
        'consultation with a safe MediaDescriptor AND a data: URI in imageUrls '
        'fails — data: URI overrides the safe descriptor (#23)', () {
      // A MediaDescriptor is always safe (bytes live server-side). But if the
      // same consultation also carries a data: URI in imageUrls, the invariant
      // must still fail — the inline bytes would be on the device.
      expect(
        StorageBudget.recordCarriesNoHeavyMedia(
          _recordWith([
            Consultation(
              id: 'c-mixed-descriptor-and-data',
              date: '2025-01-01',
              practitionerRef: 'dr-test',
              summary: 'Mixed contenu',
              media: [
                MediaDescriptor(
                  uuid: '00000000-0000-4000-8000-000000000002',
                  contentKey: 'YWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWFhYWE=',
                  contentHash: 'b' * 64,
                  mime: 'image/jpeg',
                  sizeBytes: 2 * 1024 * 1024,
                  addedAt: '2025-01-01T00:00:00Z',
                ),
              ],
              imageUrls: ['data:image/jpeg;base64,INLINE_BYTES'],
            ),
          ]),
        ),
        isFalse,
        reason: 'a data: URI in imageUrls fails even when a safe '
            'MediaDescriptor is also present (#23 — no inline bytes on device)',
      );
    });

    test(
        'data: URI in any consultation fails even if others are clean '
        '(multi-consultation check)', () {
      expect(
        StorageBudget.recordCarriesNoHeavyMedia(
          _recordWith([
            // First consultation is clean.
            const Consultation(
              id: 'c-clean',
              date: '2025-01-01',
              practitionerRef: 'dr-test',
              summary: 'Bilan initial',
            ),
            // Second consultation embeds bytes.
            const Consultation(
              id: 'c-dirty',
              date: '2025-06-01',
              practitionerRef: 'dr-test',
              summary: 'Radio',
              imageUrls: ['data:image/png;base64,INLINE'],
            ),
          ]),
        ),
        isFalse,
      );
    });
  });
}
