// Tests for QrPayload and AccessTokenService (issue #16 — QR access token).
//
// Verified properties:
//   - QrPayload round-trip: toQrString / fromQrString restores all fields.
//   - Expiry: isExpired is false immediately, true after the TTL.
//   - Version: QR string always embeds v=1.
//   - Session key encoding: base64url-encoded in the QR string.
//   - Wipe: wipe() zeros all session key bytes in place.
//   - AccessTokenService.generate: 32-byte session key, non-expired, PUT sent.
//   - AccessTokenService.generate: BackendUnavailable propagates when the
//     session blob PUT fails (no QrPayload is issued without a stored blob).
//   - ZK: local blob unchanged after generate() — session blob goes to cloud.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_patient/src/cloud/backend_client.dart';
import 'package:app_patient/src/qr/access_token.dart';
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
      patientId: _uuid,
      createdAt: '2025-01-01T00:00:00Z',
      updatedAt: '2025-01-01T00:00:00Z',
    );

QrPayload _freshPayload() => QrPayload(
      uuid: _uuid,
      backendUrl: _base,
      sessionKey: Uint8List.fromList(List.filled(32, 0xAB)),
      expiresAt: DateTime.now().add(const Duration(seconds: 120)),
    );

/// Pre-populates a [MedicalRecordStore] with a fake record and returns the
/// store and its backing local blob store.
Future<(MedicalRecordStore, InMemorySealedBlobStore)> _buildStore() async {
  final local = InMemorySealedBlobStore();
  final store = MedicalRecordStore(
    crypto: _crypto,
    client: BackendClient(
      _base,
      httpClient: MockClient((_) async => http.Response('', 201)),
    ),
    localStore: local,
  );
  await store.write(_fakeRecord(), _handle, _uuid);
  return (store, local);
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('QrPayload', () {
    test('isExpired: false when expiry is in the future', () {
      expect(_freshPayload().isExpired, isFalse);
    });

    test('isExpired: true when expiry is in the past', () {
      final p = QrPayload(
        uuid: _uuid,
        backendUrl: _base,
        sessionKey: Uint8List(32),
        expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
      );
      expect(p.isExpired, isTrue);
    });

    test('round-trip: toQrString / fromQrString restores all fields', () {
      final original = _freshPayload();
      final restored = QrPayload.fromQrString(original.toQrString());

      expect(restored.uuid, original.uuid);
      expect(restored.backendUrl, original.backendUrl);
      expect(restored.sessionKey, original.sessionKey);
      // Expiry round-trips through Unix seconds — compare at second precision.
      expect(
        restored.expiresAt.millisecondsSinceEpoch ~/ 1000,
        original.expiresAt.millisecondsSinceEpoch ~/ 1000,
      );
    });

    test('toQrString embeds version 1', () {
      final map =
          jsonDecode(_freshPayload().toQrString()) as Map<String, Object?>;
      expect(map['v'], 1);
    });

    test('toQrString encodes expiry as Unix seconds', () {
      final p = _freshPayload();
      final map = jsonDecode(p.toQrString()) as Map<String, Object?>;
      final expected = p.expiresAt.millisecondsSinceEpoch ~/ 1000;
      expect(map['exp'], expected);
    });

    test('toQrString encodes session key as base64url', () {
      final p = _freshPayload();
      final map = jsonDecode(p.toQrString()) as Map<String, Object?>;
      final decoded = base64Url.decode(map['key'] as String);
      expect(decoded, p.sessionKey);
    });

    test('wipe zeros all session key bytes', () {
      final p = _freshPayload();
      p.wipe();
      expect(p.sessionKey, everyElement(0));
    });
  });

  group('AccessTokenService.generate', () {
    test('payload has a 32-byte session key', () async {
      final (store, _) = await _buildStore();
      final svc = AccessTokenService(
        crypto: _crypto,
        recordStore: store,
        client: BackendClient(
          _base,
          httpClient: MockClient((_) async => http.Response('', 201)),
        ),
      );
      final payload = await svc.generate(_uuid, _handle, _base);
      expect(payload.sessionKey, hasLength(32));
    });

    test('payload is not expired immediately', () async {
      final (store, _) = await _buildStore();
      final svc = AccessTokenService(
        crypto: _crypto,
        recordStore: store,
        client: BackendClient(
          _base,
          httpClient: MockClient((_) async => http.Response('', 201)),
        ),
      );
      final payload = await svc.generate(_uuid, _handle, _base);
      expect(payload.isExpired, isFalse);
    });

    test('generate uploads session blob via PUT to /blob/{uuid}', () async {
      final (store, _) = await _buildStore();
      final puts = <http.Request>[];
      final svc = AccessTokenService(
        crypto: _crypto,
        recordStore: store,
        client: BackendClient(
          _base,
          httpClient: MockClient((req) async {
            if (req.method == 'PUT') puts.add(req);
            return http.Response('', 201);
          }),
        ),
      );
      await svc.generate(_uuid, _handle, _base);
      expect(puts, hasLength(1));
      expect(puts.first.url.path, '/blob/$_uuid');
    });

    test('throws BackendUnavailable when the session blob PUT fails', () async {
      final (store, _) = await _buildStore();
      final svc = AccessTokenService(
        crypto: _crypto,
        recordStore: store,
        client: BackendClient(
          _base,
          httpClient: MockClient((_) async => http.Response('', 503)),
        ),
      );
      await expectLater(
        svc.generate(_uuid, _handle, _base),
        throwsA(isA<BackendUnavailable>()),
      );
    });

    test('ZK: local blob unchanged — session blob goes to cloud only',
        () async {
      final (store, local) = await _buildStore();
      final blobBefore = await local.read();
      final svc = AccessTokenService(
        crypto: _crypto,
        recordStore: store,
        client: BackendClient(
          _base,
          httpClient: MockClient((_) async => http.Response('', 201)),
        ),
      );
      await svc.generate(_uuid, _handle, _base);
      final blobAfter = await local.read();
      expect(blobAfter, equals(blobBefore));
    });
  });
}
