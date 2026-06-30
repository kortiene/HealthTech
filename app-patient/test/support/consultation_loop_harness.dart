// Shared test support for the consultation loop (issue #20).
//
// Factors the fakes that the doctor-flow unit tests (#16–#19) each duplicate
// today — a deterministic XOR `CryptoCore`, a fake master-key handle, and a
// synthetic reference [MedicalRecord] — plus a NEW stateful in-memory blob
// backend, into one reusable module. The end-to-end test wires the REAL #16–#19
// services around these fakes; nothing here re-implements production logic.
//
// CRYPTO HONESTY: [FakeCryptoCore] is XOR 0x5A (encrypt == decrypt, regardless
// of the key). It proves the WIRING of the loop (the same session key circulates
// patient↔doctor and the round-trip is byte-exact) — it does NOT validate
// AES-256-GCM, the `nonce(12)||ct||tag(16)` format, GCM authentication, or
// "wrong key" rejection. Real cryptography is covered by the crypto-core NIST
// vectors (#10) and, in time, by a device-backed e2e (follow-up). No plaintext,
// key, or PII is ever logged or written to disk by anything in this module.

import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_patient/src/cloud/backend_client.dart';
import 'package:app_patient/src/record/medical_record.dart';
import 'package:app_patient/src/record/medical_record_store.dart';
import 'package:app_patient/src/rust/crypto_core_bindings.dart';
import 'package:app_patient/src/secure/sealed_blob_store.dart';

/// Anonymous patient UUID used across the loop (never correlated with CMU/phone).
const String kPatientUuid = '00000000-0000-4000-8000-000000000020';

/// The single byte the [FakeCryptoCore] XORs with — opaque, invertible.
const int kFakeXor = 0x5A;

/// XOR [bytes] with [kFakeXor] — the fake's encrypt/decrypt transform.
Uint8List fakeXor(List<int> bytes) =>
    Uint8List.fromList(bytes.map((b) => b ^ kFakeXor).toList());

/// Opaque Dart-side master-key handle stand-in (no real key behind it).
class FakeMasterKeyHandle implements MasterKeyHandle {
  const FakeMasterKeyHandle();
}

/// XOR-based fake crypto core — deterministic and invertible.
///
/// `decrypt(encrypt(x, k)) == x` for ANY key bytes, which is exactly what the
/// e2e needs to prove the loop's wiring (see the crypto-honesty note above).
class FakeCryptoCore implements CryptoCore {
  const FakeCryptoCore();

  @override
  Future<MasterKeyHandle> generateMasterKey() async =>
      const FakeMasterKeyHandle();

  @override
  Future<Uint8List> exportSealable(MasterKeyHandle handle) async =>
      Uint8List(32);

  @override
  Future<MasterKeyHandle> handleFromUnsealed(Uint8List clearBytes) async =>
      const FakeMasterKeyHandle();

  @override
  Future<void> wipe(MasterKeyHandle handle) async {}

  @override
  Future<Uint8List> encryptRecord(
    MasterKeyHandle handle,
    Uint8List plaintext,
  ) async =>
      fakeXor(plaintext);

  @override
  Future<Uint8List> decryptRecord(
    MasterKeyHandle handle,
    Uint8List ciphertext,
  ) async =>
      fakeXor(ciphertext);

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
      const FakeMasterKeyHandle();

  @override
  Future<Uint8List> normalizeRecoveryAnswers(List<String> answers) async =>
      Uint8List.fromList(answers.join('\x1f').codeUnits);
}

/// Stateful in-memory zero-knowledge blob backend (the server side of ADR 0004).
///
/// Wraps a `Map<String, Uint8List>` behind a `package:http` [MockClient]:
///   - `PUT /blob/{uuid}` stores a COPY of the body, returns 201 (or 503 when
///     [failPut] is set — used to exercise the end-of-session failure path);
///   - `GET /blob/{uuid}` returns the stored bytes (200) or 404 when absent.
///
/// It never inspects, logs, or decodes the bodies — they are opaque ciphertext.
/// [blobs], [putCount], [getCount] and [putCountByUuid] are exposed for
/// flow-level assertions.
///
/// [failPut] is MUTABLE so the #22 drain tests can simulate the NETWORK COMING
/// BACK: start with `failPut: true` (session-end queues offline), flip it to
/// `false`, fire a [SyncService] drain, and assert the queue empties with no
/// duplicate PUT ([putCountByUuid] stays 1 per UUID).
class FakeBlobBackend {
  FakeBlobBackend({this.failPut = false});

  /// When true, every PUT returns 503 without storing — simulates a sync outage.
  /// Flip to false mid-test to simulate the network returning.
  bool failPut;

  /// The opaque ciphertext store, keyed by anonymous UUID.
  final Map<String, Uint8List> blobs = {};

  int putCount = 0;
  int getCount = 0;

  /// PUT count per UUID — proves idempotence (a re-PUT after a crash between
  /// `put` and `remove` re-uses the same UUID and leaves one final blob).
  final Map<String, int> putCountByUuid = {};

  /// An [http.Client] that routes PUT/GET /blob/{uuid} to this in-memory store.
  http.Client get client => MockClient(_handle);

  Future<http.Response> _handle(http.Request request) async {
    final uuid = request.url.pathSegments.last;
    switch (request.method) {
      case 'PUT':
        putCount++;
        putCountByUuid.update(uuid, (n) => n + 1, ifAbsent: () => 1);
        if (failPut) return http.Response('unavailable', 503);
        blobs[uuid] = Uint8List.fromList(request.bodyBytes);
        return http.Response('', 201);
      case 'GET':
        getCount++;
        final blob = blobs[uuid];
        if (blob == null) return http.Response('not found', 404);
        return http.Response.bytes(blob, 200);
      default:
        return http.Response('method not allowed', 405);
    }
  }
}

/// A synthetic patient record — 1 prior consultation + 1 allergy, no real PII
/// (the "Awa" persona from the PRD). Small, well under the 500 Kio budget.
MedicalRecord referenceRecord() => const MedicalRecord(
      patientId: kPatientUuid,
      demographics: Demographics(givenName: 'Awa', birthYear: 1990, sex: 'F'),
      allergies: [
        Allergy(
          substance: 'Pénicilline',
          severity: 'severe',
          notedAt: '2024-03-10',
        ),
      ],
      consultations: [
        Consultation(
          id: 'consult-initial-0001',
          date: '2025-11-02',
          practitionerRef: 'practitioner-initial',
          summary: 'Bilan initial — RAS',
        ),
      ],
      createdAt: '2025-11-02T09:00:00Z',
      updatedAt: '2025-11-02T09:00:00Z',
    );

/// A [MedicalRecordStore] whose local cache already holds [seed] (master-key
/// encrypted), so `read` resolves the reference record without any cloud call —
/// feeding [AccessTokenService.generate] the patient's record on the host.
MedicalRecordStore seededRecordStore({
  required FakeBlobBackend backend,
  required MedicalRecord seed,
  required String baseUrl,
}) {
  final local = InMemorySealedBlobStore(fakeXor(seed.toUtf8Bytes()));
  return MedicalRecordStore(
    crypto: const FakeCryptoCore(),
    client: BackendClient(baseUrl, httpClient: backend.client),
    localStore: local,
  );
}
