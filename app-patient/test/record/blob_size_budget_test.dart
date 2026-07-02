// Blob-size budget guard (issue #27, G3) — the DETERMINISTIC network-term gate.
//
// The scan→display 3 s target (PRD §5) decomposes into CPU terms (timed
// elsewhere) plus a network transfer term. CI cannot reproduce a real 3G radio,
// so instead of a flaky wall-clock assertion we bound the transferred
// (compressed + encrypted) blob to PerfBudget.maxCompressedBlobBytes — the
// largest blob whose *modelled* transfer time over the reference 3G profile
// keeps the whole pipeline within budget (see docs/perf/decryption-budget.md).
//
// This test drives a worst-case ~500 Kio synthetic record through the REAL
// MedicalRecordStore.write path (RecordSizeGuard → gzip compress → encrypt →
// persist/PUT) and asserts the produced blob fits the ceiling. It catches a
// schema bloat (#15), a lost/broken compression step (#24), or any change that
// blows the transferred size past the modelled 3G budget.
//
// It complements — does NOT replace — the plaintext ≤ 500 Kio RecordSizeGuard
// (record_size_guard_test.dart): that bounds decrypt/deserialize work, this
// bounds transfer time.
//
// CRYPTO HONESTY: FakeCryptoCore XORs (length-preserving), so the captured blob
// length equals gzip(plaintext).length. The real AES-256-GCM path adds a fixed
// 28-byte overhead (nonce+tag); we add PerfBudget.aesGcmOverheadBytes back so
// the assertion reflects the true on-the-wire size. Fixtures are synthetic,
// non-nominative filler — no real PII, and nothing is written to disk.

import 'dart:io' show GZipCodec;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_patient/src/cloud/backend_client.dart';
import 'package:app_patient/src/record/medical_record.dart';
import 'package:app_patient/src/record/medical_record_store.dart';
import 'package:app_patient/src/record/perf_budget.dart';
import 'package:app_patient/src/record/record_size_guard.dart';
import 'package:app_patient/src/rust/crypto_core_bindings.dart';
import 'package:app_patient/src/secure/sealed_blob_store.dart';

// ─── Fakes (XOR, length-preserving — mirrors the shared test convention) ───────

class _FakeMasterKeyHandle implements MasterKeyHandle {
  const _FakeMasterKeyHandle();
}

class _FakeCryptoCore implements CryptoCore {
  const _FakeCryptoCore();
  static const _xor = 0x5A;

  Uint8List _xorBytes(Uint8List data) =>
      Uint8List.fromList(data.map((b) => b ^ _xor).toList());

  @override
  Future<MasterKeyHandle> generateMasterKey() async =>
      const _FakeMasterKeyHandle();
  @override
  Future<Uint8List> exportSealable(MasterKeyHandle handle) async =>
      Uint8List(32);
  @override
  Future<MasterKeyHandle> handleFromUnsealed(Uint8List clearBytes) async =>
      const _FakeMasterKeyHandle();
  @override
  Future<void> wipe(MasterKeyHandle handle) async {}
  @override
  Future<Uint8List> encryptRecord(
    MasterKeyHandle handle,
    Uint8List plaintext,
  ) async =>
      _xorBytes(plaintext);
  @override
  Future<Uint8List> decryptRecord(
    MasterKeyHandle handle,
    Uint8List ciphertext,
  ) async =>
      _xorBytes(ciphertext);
  @override
  Future<Uint8List> sealRecoveryEnvelope(
    Uint8List masterKeyClear,
    Uint8List secret,
    int iterations,
  ) async =>
      Uint8List(32);
  @override
  Future<MasterKeyHandle> openRecoveryEnvelope(
    Uint8List secret,
    Uint8List envelopeBytes,
  ) async =>
      const _FakeMasterKeyHandle();
  @override
  Future<Uint8List> normalizeRecoveryAnswers(List<String> answers) async =>
      Uint8List.fromList(answers.join('\x1f').codeUnits);
}

// ─── Worst-case fixture: a realistic ~500 Kio synthetic record ─────────────────

const _uuid = '00000000-0000-4000-8000-000000000027';
const _base = 'http://backend.test';

/// A pool of realistic (French) consultation-summary fragments. Rotated with a
/// per-consultation index so the fixture has the STRUCTURED repetition of a real
/// medical record (repeated field names + similar phrasing) — which gzip
/// compresses ~80 %+, as #24 assumes — rather than incompressible random noise
/// (which would make the ceiling trivially unreachable) or a single repeated
/// string (which would compress to almost nothing and make the guard toothless).
const List<String> _summaryFragments = [
  'Consultation de suivi. Tension artérielle 12/8, fréquence cardiaque 74 bpm. ',
  'Patient afébrile, état général conservé. Auscultation cardio-pulmonaire sans particularité. ',
  'Poursuite du traitement en cours, bonne tolérance rapportée, aucun effet indésirable signalé. ',
  'Renouvellement de l\'ordonnance pour trois mois. Contrôle biologique programmé. ',
  'Douleurs abdominales modérées en amélioration. Palpation souple, pas de défense. ',
  'Bilan lipidique dans les normes. Recommandations hygiéno-diététiques rappelées au patient. ',
  'Vaccination à jour. Rappel prévu selon le calendrier vaccinal en vigueur. ',
  'Symptômes respiratoires bénins, évolution favorable sous traitement symptomatique. ',
];

/// Deterministic pseudo-random value in [0, mod) from a seed — gives per-entry
/// unique measurement values without any real RNG (reproducible fixture).
int _pseudo(int seed, int mod) => ((seed * 2654435761) & 0x7fffffff) % mod;

/// Builds a [MedicalRecord] whose serialised JSON is just under the 500 Kio
/// plaintext limit (so RecordSizeGuard.truncate leaves it intact), with realistic
/// structure and per-entry variation.
MedicalRecord _worstCaseRecord() {
  final consultations = <Consultation>[];
  var index = 0;

  MedicalRecord build() => MedicalRecord(
        patientId: _uuid,
        demographics: const Demographics(
          givenName: 'Awa',
          birthYear: 1990,
          sex: 'F',
          bloodType: 'O-',
        ),
        allergies: const [
          Allergy(
            substance: 'Pénicilline',
            severity: 'severe',
            notedAt: '2024-03-10',
          ),
        ],
        consultations: List.unmodifiable(consultations),
        createdAt: '2020-01-01T09:00:00Z',
        updatedAt: '2026-06-30T09:00:00Z',
      );

  // Grow the record consultation-by-consultation until it sits just under the
  // plaintext limit, staying safely below truncation (< maxPlaintextBytes).
  const targetBytes = maxPlaintextBytes - 8192; // ~492 Kio, no truncation
  while (RecordSizeGuard.measure(build()) < targetBytes) {
    final year = 2020 + (index % 6);
    final month = (index % 12) + 1;
    final day = (index % 28) + 1;
    final frag = _summaryFragments[index % _summaryFragments.length];
    consultations.add(
      Consultation(
        // Per-entry variation (unique id/date/index + a deterministic
        // pseudo-random measurement token) so the fixture is neither a single
        // repeated string (which would compress to almost nothing and make the
        // guard toothless) nor incompressible noise. The phrasing pool + the
        // token together yield a realistic ~10 % gzip ratio (~48 Kio on-wire for
        // a ~500 Kio record) — the structured repetition of a real medical
        // record with per-visit unique values, comfortably under the ceiling.
        id: 'consult-${index.toString().padLeft(5, '0')}',
        date: '$year-${month.toString().padLeft(2, '0')}-'
            '${day.toString().padLeft(2, '0')}',
        practitionerRef:
            'practitioner-${(index % 40).toString().padLeft(3, '0')}',
        summary: 'Séance n°$index — $frag'
            'Constantes: TA ${90 + _pseudo(index, 60)}/'
            '${50 + _pseudo(index + 1, 40)}, FC ${55 + _pseudo(index + 2, 45)}, '
            'SpO2 ${94 + _pseudo(index + 3, 6)}%, T ${360 + _pseudo(index + 4, 25)}. '
            'Réf. laboratoire ${_pseudo(index, 900000) + 100000}-'
            '${_pseudo(index + 7, 900000) + 100000}. ',
      ),
    );
    index++;
  }
  return build();
}

void main() {
  group('Compressed-blob size budget (issue #27, G3)', () {
    test('worst-case ~500 Kio record → real write-path blob ≤ ceiling',
        () async {
      final record = _worstCaseRecord();

      // Sanity: the fixture is genuinely a worst case — near, but under, the
      // 500 Kio plaintext limit (so it is NOT truncated before compression).
      final plaintextBytes = RecordSizeGuard.measure(record);
      expect(
        plaintextBytes,
        lessThan(maxPlaintextBytes),
        reason: 'fixture must not be truncated by RecordSizeGuard',
      );
      expect(
        plaintextBytes,
        greaterThan(maxPlaintextBytes ~/ 2),
        reason: 'fixture must exercise a realistic worst case (> 250 Kio)',
      );

      // Drive the REAL write path and capture the transferred blob.
      Uint8List? sentBlob;
      final store = MedicalRecordStore(
        crypto: const _FakeCryptoCore(),
        client: BackendClient(
          _base,
          httpClient: MockClient((req) async {
            if (req.method == 'PUT') sentBlob = req.bodyBytes;
            return http.Response('', 201);
          }),
        ),
        localStore: InMemorySealedBlobStore(),
      );

      await store.write(record, const _FakeMasterKeyHandle(), _uuid);

      expect(sentBlob, isNotNull, reason: 'write must PUT a blob');

      // XOR is length-preserving, so the captured length equals gzip(plaintext).
      // Add back the real AES-256-GCM overhead (nonce+tag) so the assertion is
      // the true on-the-wire size the 3G model bounds.
      final onWireBytes = sentBlob!.length + PerfBudget.aesGcmOverheadBytes;

      expect(
        onWireBytes,
        lessThanOrEqualTo(PerfBudget.maxCompressedBlobBytes),
        reason: 'transferred blob ($onWireBytes B) exceeds the 3G size ceiling '
            '(${PerfBudget.maxCompressedBlobBytes} B). A schema/compression '
            'regression would push scan→display past the 3 s budget on 3G — '
            'see docs/perf/decryption-budget.md.',
      );

      // Compression must actually be doing work (guards against a lost gzip
      // step, which would blow the transfer time out even under the ceiling).
      expect(
        sentBlob!.length,
        lessThan(plaintextBytes ~/ 2),
        reason:
            'blob must be materially smaller than plaintext (compression on)',
      );
    });

    test('a lost-compression regression would breach the ceiling', () {
      // Explicit anti-regression rationale: an UNcompressed worst-case blob
      // (what a dropped gzip step in #24 would transmit) blows the ceiling.
      final record = _worstCaseRecord();
      final rawPlaintext = Uint8List.fromList(record.toUtf8Bytes());
      expect(
        rawPlaintext.length + PerfBudget.aesGcmOverheadBytes,
        greaterThan(PerfBudget.maxCompressedBlobBytes),
        reason:
            'sanity: uncompressed transfer must exceed the ceiling, proving '
            'the guard would catch a lost compression step',
      );
      // And the compressed form is what keeps it under.
      final compressed = Uint8List.fromList(GZipCodec().encode(rawPlaintext));
      expect(
        compressed.length + PerfBudget.aesGcmOverheadBytes,
        lessThanOrEqualTo(PerfBudget.maxCompressedBlobBytes),
      );
    });
  });

  group('Budget-model self-consistency (issue #27, testing plan #5)', () {
    test('modelled transfer at the ceiling matches the documented ~1.4 s', () {
      final t =
          PerfBudget.modelledTransferMs(PerfBudget.maxCompressedBlobBytes);
      // 131072 * 8 / 750000 ≈ 1398 ms.
      expect(t, closeTo(1398, 5));
    });

    test('at the guard ceilings the modelled total still fits under 3 s', () {
      final total = PerfBudget.modelledTotalAtCeilingsMs(
          PerfBudget.maxCompressedBlobBytes);
      expect(
        total,
        lessThanOrEqualTo(PerfBudget.totalBudgetMs.toDouble()),
        reason: 'even at every generous CPU guard ceiling, conn+transfer+'
            'decrypt+pipeline+render must stay within the 3 s NFR',
      );
    });

    test('the size ceiling leaves a genuine safety margin under 3 s', () {
      // At the guard ceilings we must still clear the 3 s cap by a real margin
      // (not merely tie it) — headroom absorbs runner/link variance.
      final total = PerfBudget.modelledTotalAtCeilingsMs(
          PerfBudget.maxCompressedBlobBytes);
      final margin = PerfBudget.totalBudgetMs - total;
      expect(margin, greaterThan(0));
    });
  });

  // ── Cross-language constant sync canaries (Dart ↔ Rust) ────────────────────
  //
  // Rust cannot read Dart. These tests assert the EXACT numeric values of
  // PerfBudget constants that are documented as mirrors of constants in
  // crypto-core/tests/decrypt_perf_regression.rs (and vice-versa). A failure
  // here means the two sides have drifted and both must be updated together:
  //   * DECRYPT_BUDGET_MS (Rust)      ↔  PerfBudget.decryptBudgetMs (Dart)
  //   * MAX_BLOB_BYTES   (Rust)       ↔  PerfBudget.maxCompressedBlobBytes (Dart)
  //   * OVERHEAD_LEN     (crypto-core) ↔  PerfBudget.aesGcmOverheadBytes (Dart)
  //
  // The Rust side has matching compile-time `const _: () = assert!(...)` guards
  // in decrypt_perf_regression.rs that also fire on drift.

  group('Cross-language constant sync canaries (Dart ↔ Rust mirrors)', () {
    test(
        'decryptBudgetMs == 100 '
        '(mirrors DECRYPT_BUDGET_MS in decrypt_perf_regression.rs)', () {
      expect(
        PerfBudget.decryptBudgetMs,
        equals(100),
        reason: 'PerfBudget.decryptBudgetMs must stay equal to '
            'DECRYPT_BUDGET_MS (100) in '
            'crypto-core/tests/decrypt_perf_regression.rs — '
            'update both when changing either',
      );
    });

    test(
        'maxCompressedBlobBytes == 131072 '
        '(mirrors MAX_BLOB_BYTES in decrypt_perf_regression.rs)', () {
      expect(
        PerfBudget.maxCompressedBlobBytes,
        equals(131072),
        reason: 'PerfBudget.maxCompressedBlobBytes must stay equal to '
            'MAX_BLOB_BYTES (131072) in '
            'crypto-core/tests/decrypt_perf_regression.rs — '
            'update both when changing either',
      );
    });

    test(
        'aesGcmOverheadBytes == 28 '
        '(mirrors OVERHEAD_LEN = NONCE_LEN(12) + TAG_LEN(16) in crypto-core)',
        () {
      expect(
        PerfBudget.aesGcmOverheadBytes,
        equals(28),
        reason: 'PerfBudget.aesGcmOverheadBytes must equal OVERHEAD_LEN '
            '(NONCE_LEN=12 + TAG_LEN=16 = 28) in crypto-core/src/lib.rs — '
            'wire-format contract frozen by #10',
      );
    });

    test('safetyReserveMs is positive (not accidentally zeroed)', () {
      expect(
        PerfBudget.safetyReserveMs,
        greaterThan(0),
        reason: 'safety reserve must be positive; zero would mean no margin '
            'for runner/device/link variance',
      );
    });
  });

  group('PerfBudget.modelledTransferMs — edge cases', () {
    test('zero bytes → 0.0 ms transfer time', () {
      expect(PerfBudget.modelledTransferMs(0), equals(0.0));
    });

    test('formula: bytes × 8 × 1000 / goodput_bps', () {
      // 8000 bytes × 8 bits/byte = 64 000 bits.
      // 64 000 / 750 000 bit/s × 1000 ms/s ≈ 85.333 ms.
      const bytes = 8000;
      const expected = bytes * 8 * 1000 / PerfBudget.stable3gGoodputBitsPerSec;
      expect(PerfBudget.modelledTransferMs(bytes), closeTo(expected, 0.001));
    });
  });
}
