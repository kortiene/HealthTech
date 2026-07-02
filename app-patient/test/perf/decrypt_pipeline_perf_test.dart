// In-process decrypt-pipeline timing test (issue #27, G2/G4).
//
// Times the CPU-bound tail of the scan→display flow — the part CI can measure
// deterministically — through REAL production code:
//
//   QR parse (ScanService.parseQr, trivial) +
//   MedicalRecordStore.read  →  decrypt  →  decodeIfCompressed (gzip)
//                            →  jsonDecode  →  MedicalRecord.fromJson
//
// WHY MedicalRecordStore.read and not ScanService.fetchAndDecrypt:
// the transfer-size model (docs/perf/decryption-budget.md) budgets a *gzip
// decompress* stage, because the transferred blob is compressed (#24). That
// decrypt→decompress→deserialize chain lives in MedicalRecordStore.read. The
// doctor-side ScanService.fetchAndDecrypt path does NOT decompress today — its
// session blob is written uncompressed by AccessTokenService (access_token.dart),
// so it exercises no gzip stage. Compressing the session path is an OPTIMISATION
// (out of scope for #27, which is measure+gate — see the spec Non-Goals and
// Risk #7); we measure the pipeline that actually performs every budgeted CPU
// stage, and flag the session-path gap as follow-up in the budget doc.
//
// The network term is EXCLUDED (the blob is pre-seeded in the local cache, so
// read resolves with zero HTTP). Real AES-256-GCM decrypt CPU is covered by
// crypto-core/tests/decrypt_perf_regression.rs; here the crypto is the shared
// XOR fake, so this effectively bounds gzip-decompress + JSON-deserialize on a
// worst-case (~500 Kio) record.
//
// The assertion is a GENEROUS, order-of-magnitude guard (PerfBudget
// .pipelineCpuBudgetMs), warmed-up and median-of-N to damp JIT/GC noise, so it
// catches a real regression (an accidental O(n²), a lost fast path) without
// flaking on shared-runner jitter. Synthetic data only; nothing hits disk.

import 'dart:io' show GZipCodec;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_patient/src/cloud/backend_client.dart';
import 'package:app_patient/src/doctor/scan_service.dart';
import 'package:app_patient/src/qr/access_token.dart';
import 'package:app_patient/src/record/medical_record.dart';
import 'package:app_patient/src/record/medical_record_store.dart';
import 'package:app_patient/src/record/perf_budget.dart';
import 'package:app_patient/src/record/record_size_guard.dart';
import 'package:app_patient/src/rust/crypto_core_bindings.dart';
import 'package:app_patient/src/secure/sealed_blob_store.dart';

// ─── XOR fake crypto (length-preserving; mirrors the shared test convention) ───

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

const _uuid = '00000000-0000-4000-8000-000000000027';
const _base = 'http://backend.test';

/// A worst-case ~500 Kio record so the decompress + deserialize work is maximal.
MedicalRecord _worstCaseRecord() {
  final consultations = <Consultation>[];
  var index = 0;

  MedicalRecord build() => MedicalRecord(
        patientId: _uuid,
        demographics: const Demographics(givenName: 'Awa', birthYear: 1990),
        consultations: List.unmodifiable(consultations),
        createdAt: '2020-01-01T09:00:00Z',
        updatedAt: '2026-06-30T09:00:00Z',
      );

  const targetBytes = maxPlaintextBytes - 8192; // ~492 Kio, no truncation
  while (RecordSizeGuard.measure(build()) < targetBytes) {
    consultations.add(
      Consultation(
        id: 'consult-${index.toString().padLeft(5, '0')}',
        date: '2024-01-01',
        practitionerRef: 'practitioner-${index % 40}',
        summary: 'Séance n°$index — Consultation de suivi, état stable, '
            'poursuite du traitement. Observation ${index * 7} consignée. ',
      ),
    );
    index++;
  }
  return build();
}

/// The compressed, encrypted blob exactly as MedicalRecordStore.write produces:
/// XOR(gzip(plaintext)). This is the transferred form the size guard bounds.
Uint8List _compressedBlob(MedicalRecord record) {
  final plaintext = Uint8List.fromList(record.toUtf8Bytes());
  final compressed = Uint8List.fromList(GZipCodec().encode(plaintext));
  return Uint8List.fromList(compressed.map((b) => b ^ 0x5A).toList());
}

QrPayload _freshPayload() => QrPayload(
      uuid: _uuid,
      backendUrl: _base,
      sessionKey: Uint8List(32),
      expiresAt: DateTime.now().add(const Duration(seconds: 120)),
    );

void main() {
  test(
    'CPU chain (parse→decrypt→decompress→deserialize) median < pipelineCpuBudgetMs',
    () async {
      final record = _worstCaseRecord();
      final blob = _compressedBlob(record);
      final qr = _freshPayload().toQrString();

      // Pre-seed the local cache so read resolves with ZERO network — the
      // decrypt→decompress→deserialize chain runs entirely in-process.
      final store = MedicalRecordStore(
        crypto: const _FakeCryptoCore(),
        client: BackendClient(
          _base,
          // Any HTTP call would be a bug (local cache must hit); fail loudly.
          httpClient: MockClient((_) async => http.Response('unexpected', 500)),
        ),
        localStore: InMemorySealedBlobStore(blob),
      );

      Future<void> once() async {
        // Doctor entrypoint (trivial CPU) + the full decrypt/decompress/parse.
        final payload = ScanService.parseQr(qr);
        expect(payload.uuid, _uuid);
        final decoded = await store.read(const _FakeMasterKeyHandle(), _uuid);
        // Touch the result so nothing is optimised away.
        expect(decoded.patientId, _uuid);
      }

      // Warm-up (JIT/allocator) — not measured.
      for (var i = 0; i < 3; i++) {
        await once();
      }

      // Measure median-of-N.
      const iterations = 9;
      final samples = <int>[];
      for (var i = 0; i < iterations; i++) {
        final sw = Stopwatch()..start();
        await once();
        sw.stop();
        samples.add(sw.elapsedMicroseconds);
      }
      samples.sort();
      final medianMs = samples[samples.length ~/ 2] / 1000.0;

      expect(
        medianMs,
        lessThan(PerfBudget.pipelineCpuBudgetMs),
        reason: 'in-process parse→decrypt→decompress→deserialize median '
            '${medianMs.toStringAsFixed(1)} ms exceeds the '
            '${PerfBudget.pipelineCpuBudgetMs} ms CPU-chain guard. This is an '
            'order-of-magnitude regression on the scan→display hot path — see '
            'docs/perf/decryption-budget.md.',
      );
    },
  );
}
