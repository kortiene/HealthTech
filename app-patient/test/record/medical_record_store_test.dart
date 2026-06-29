// Tests for MedicalRecordStore (issue #14 — zero-knowledge cloud backup).
//
// Uses FakeCryptoCore (XOR obfuscation), MockClient (in-memory HTTP), and
// InMemorySealedBlobStore. No real network calls, no native crypto.
//
// Key properties verified:
//   - ZK: cloud-transmitted blob does not contain plaintext medical data.
//   - Round-trip: write → read returns the identical MedicalRecord.
//   - Local-first: read resolves from local cache without any HTTP call.
//   - Cloud fallback: missing local → GET from cloud → cached locally.
//   - Resilience: PUT failure leaves a valid local copy (offline-safe).
//   - Error propagation: BlobNotFound / BackendUnavailable surfaced cleanly.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_patient/src/cloud/backend_client.dart';
import 'package:app_patient/src/record/medical_record.dart';
import 'package:app_patient/src/record/medical_record_store.dart';
import 'package:app_patient/src/rust/crypto_core_bindings.dart';
import 'package:app_patient/src/secure/sealed_blob_store.dart';

// ─── Fakes ────────────────────────────────────────────────────────────────────

class _FakeMasterKeyHandle implements MasterKeyHandle {
  const _FakeMasterKeyHandle();
}

/// XOR-based fake — deterministic, invertible (encrypt == decrypt).
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

// ─── Helpers ─────────────────────────────────────────────────────────────────

const _handle = _FakeMasterKeyHandle();
const _crypto = _FakeCryptoCore();
const _uuid = '00000000-0000-4000-8000-000000000001';
const _base = 'http://backend.test';

MedicalRecord _fakeRecord() => const MedicalRecord(
      patientId: '00000000-0000-4000-8000-000000000001',
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
    );

/// Build a store backed by a [MockClient] that always responds [statusCode].
MedicalRecordStore _storeWithStatus(
  int statusCode,
  InMemorySealedBlobStore local, {
  Uint8List? getBody,
}) {
  return MedicalRecordStore(
    crypto: _crypto,
    client: BackendClient(
      _base,
      httpClient: MockClient((req) async {
        if (req.method == 'GET' && getBody != null) {
          return http.Response.bytes(getBody, 200);
        }
        return http.Response('', statusCode);
      }),
    ),
    localStore: local,
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('MedicalRecordStore.write', () {
    test('local blob is persisted after write', () async {
      final local = InMemorySealedBlobStore();
      final store = _storeWithStatus(201, local);

      await store.write(_fakeRecord(), _handle, _uuid);

      expect(await local.exists(), isTrue);
    });

    test('exists() returns true after write', () async {
      final local = InMemorySealedBlobStore();
      final store = _storeWithStatus(201, local);

      expect(await store.exists(), isFalse);
      await store.write(_fakeRecord(), _handle, _uuid);
      expect(await store.exists(), isTrue);
    });

    test('ZK: cloud blob does not contain plaintext medical data', () async {
      // Marker must not appear in any wire-level representation.
      const marker = 'blood-type:O-NEG';
      const record = MedicalRecord(
        patientId: _uuid,
        demographics: Demographics(bloodType: marker),
        createdAt: '2025-01-01T00:00:00Z',
        updatedAt: '2025-01-01T00:00:00Z',
      );

      Uint8List? sentBlob;
      final store = MedicalRecordStore(
        crypto: _crypto,
        client: BackendClient(
          _base,
          httpClient: MockClient((req) async {
            sentBlob = req.bodyBytes;
            return http.Response('', 201);
          }),
        ),
        localStore: InMemorySealedBlobStore(),
      );

      await store.write(record, _handle, _uuid);

      expect(sentBlob, isNotNull);
      final blobString = utf8.decode(sentBlob!, allowMalformed: true);
      expect(
        blobString,
        isNot(contains(marker)),
        reason: 'plaintext medical data must not appear in cloud blob',
      );
    });

    test('cloud PUT fails → BackendUnavailable, local still persisted',
        () async {
      final local = InMemorySealedBlobStore();
      final store = _storeWithStatus(503, local);

      await expectLater(
        store.write(_fakeRecord(), _handle, _uuid),
        throwsA(isA<BackendUnavailable>()),
      );
      // Local write happened before the failed PUT.
      expect(await local.exists(), isTrue);
    });

    test('cloud PUT returns 200 (overwrite) → completes', () async {
      final store = _storeWithStatus(200, InMemorySealedBlobStore());
      await expectLater(
        store.write(_fakeRecord(), _handle, _uuid),
        completes,
      );
    });
  });

  group('MedicalRecordStore.read', () {
    test('round-trip: write then read returns identical record', () async {
      final local = InMemorySealedBlobStore();
      final store = _storeWithStatus(201, local);
      final original = _fakeRecord();

      await store.write(original, _handle, _uuid);
      final restored = await store.read(_handle, _uuid);

      expect(restored, equals(original));
    });

    test('local-first: read resolves from local without any HTTP call',
        () async {
      final local = InMemorySealedBlobStore();
      // Seed local with an already-encrypted blob.
      final plaintext = Uint8List.fromList(
        jsonEncode(_fakeRecord().toJson()).codeUnits,
      );
      final blob = Uint8List.fromList(
        plaintext.map((b) => b ^ 0x5A).toList(),
      );
      await local.write(blob);

      int httpCalls = 0;
      final store = MedicalRecordStore(
        crypto: _crypto,
        client: BackendClient(
          _base,
          httpClient: MockClient((_) async {
            httpCalls++;
            return http.Response('', 500);
          }),
        ),
        localStore: local,
      );

      final record = await store.read(_handle, _uuid);

      expect(httpCalls, 0, reason: 'must not call HTTP when local exists');
      expect(record.patientId, _fakeRecord().patientId);
    });

    test('cloud fallback: no local → GET from cloud → cached', () async {
      final original = _fakeRecord();
      final plaintext = Uint8List.fromList(
        jsonEncode(original.toJson()).codeUnits,
      );
      final blob = Uint8List.fromList(
        plaintext.map((b) => b ^ 0x5A).toList(),
      );

      final local = InMemorySealedBlobStore();
      final store = _storeWithStatus(200, local, getBody: blob);

      final record = await store.read(_handle, _uuid);

      expect(record, equals(original));
      // Cloud blob was cached locally.
      expect(await local.exists(), isTrue);
    });

    test('no local + cloud 404 → throws BlobNotFound', () async {
      final store = _storeWithStatus(404, InMemorySealedBlobStore());
      expect(
        () => store.read(_handle, _uuid),
        throwsA(isA<BlobNotFound>()),
      );
    });

    test('no local + cloud 503 → throws BackendUnavailable', () async {
      final store = _storeWithStatus(503, InMemorySealedBlobStore());
      expect(
        () => store.read(_handle, _uuid),
        throwsA(isA<BackendUnavailable>()),
      );
    });
  });
}
