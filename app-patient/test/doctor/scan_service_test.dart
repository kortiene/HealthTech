// Unit tests for ScanService (issue #17 — QR scan → RAM-only decrypt).
//
// Verified properties:
//   - parseQr: fresh QR string → valid QrPayload returned.
//   - parseQr: expired QR string → ExpiredQrCode thrown.
//   - parseQr: malformed input → Exception thrown.
//   - fetchAndDecrypt: valid payload + blob → correct MedicalRecord.
//   - fetchAndDecrypt: issues GET /blob/{uuid} (never PUT).
//   - fetchAndDecrypt: wipes the Rust handle after success.
//   - fetchAndDecrypt: wipes the Rust handle after DecryptError.
//   - fetchAndDecrypt: propagates BlobNotFound on 404.
//   - fetchAndDecrypt: propagates BackendUnavailable on 5xx.
//   - ZK: fetchAndDecrypt never issues PUT (read-only cloud operation).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_patient/src/cloud/backend_client.dart';
import 'package:app_patient/src/doctor/scan_service.dart';
import 'package:app_patient/src/qr/access_token.dart';
import 'package:app_patient/src/record/medical_record.dart';
import 'package:app_patient/src/rust/crypto_core_bindings.dart';

// ─── Fakes ────────────────────────────────────────────────────────────────────

class _FakeMasterKeyHandle implements MasterKeyHandle {
  const _FakeMasterKeyHandle();
}

/// XOR-based fake — deterministic, invertible (encrypt == decrypt == XOR 0x5A).
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

/// [CryptoCore] that counts [wipe] calls and can simulate a [DecryptError].
class _TrackingCryptoCore implements CryptoCore {
  _TrackingCryptoCore({this.failDecrypt = false});

  final bool failDecrypt;
  var wipeCount = 0;

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
  Future<void> wipe(MasterKeyHandle handle) async {
    wipeCount++;
  }

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
  ) async {
    if (failDecrypt) throw const DecryptError();
    return _xorBytes(ciphertext);
  }

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

const _uuid = '00000000-0000-4000-8000-000000000001';
const _base = 'http://backend.test';

const _fakeRecord = MedicalRecord(
  patientId: _uuid,
  createdAt: '2025-01-01T00:00:00Z',
  updatedAt: '2025-01-01T00:00:00Z',
);

/// XOR-encoded session blob for [_fakeRecord].
///
/// The fake crypto XORs with 0x5A regardless of the key, so this is the
/// "ciphertext" that decrypts back to [_fakeRecord].
Uint8List _fakeBlob() {
  final json = Uint8List.fromList(
    utf8.encode(jsonEncode(_fakeRecord.toJson())),
  );
  return Uint8List.fromList(json.map((b) => b ^ 0x5A).toList());
}

QrPayload _freshPayload() => QrPayload(
      uuid: _uuid,
      backendUrl: _base,
      sessionKey: Uint8List(32),
      expiresAt: DateTime.now().add(const Duration(seconds: 120)),
    );

QrPayload _expiredPayload() => QrPayload(
      uuid: _uuid,
      backendUrl: _base,
      sessionKey: Uint8List(32),
      expiresAt: DateTime.now().subtract(const Duration(seconds: 1)),
    );

ScanService _svc(CryptoCore crypto, http.Client httpClient) => ScanService(
      crypto: crypto,
      client: BackendClient(_base, httpClient: httpClient),
    );

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('ScanService.parseQr', () {
    test('returns valid payload for a fresh QR string', () {
      final payload = _freshPayload();
      final result = ScanService.parseQr(payload.toQrString());
      expect(result.uuid, _uuid);
      expect(result.isExpired, isFalse);
    });

    test('throws ExpiredQrCode for an expired QR string', () {
      expect(
        () => ScanService.parseQr(_expiredPayload().toQrString()),
        throwsA(isA<ExpiredQrCode>()),
      );
    });

    test('throws Exception for malformed (non-JSON) input', () {
      expect(
        () => ScanService.parseQr('not-valid-json'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('ScanService.fetchAndDecrypt', () {
    test('returns correct MedicalRecord from session blob', () async {
      final svc = _svc(
        const _FakeCryptoCore(),
        MockClient((_) async => http.Response.bytes(_fakeBlob(), 200)),
      );
      final record = await svc.fetchAndDecrypt(_freshPayload());
      expect(record.patientId, _uuid);
    });

    test('issues GET /blob/{uuid} to fetch the session blob', () async {
      final gets = <String>[];
      final svc = _svc(
        const _FakeCryptoCore(),
        MockClient((req) async {
          if (req.method == 'GET') gets.add(req.url.path);
          return http.Response.bytes(_fakeBlob(), 200);
        }),
      );
      await svc.fetchAndDecrypt(_freshPayload());
      expect(gets, hasLength(1));
      expect(gets.first, '/blob/$_uuid');
    });

    test('wipes the Rust handle after successful decryption', () async {
      final crypto = _TrackingCryptoCore();
      final svc = _svc(
        crypto,
        MockClient((_) async => http.Response.bytes(_fakeBlob(), 200)),
      );
      await svc.fetchAndDecrypt(_freshPayload());
      expect(crypto.wipeCount, 1);
    });

    test('wipes the Rust handle even when decryptRecord throws', () async {
      final crypto = _TrackingCryptoCore(failDecrypt: true);
      final svc = _svc(
        crypto,
        MockClient((_) async => http.Response.bytes(Uint8List(64), 200)),
      );
      await expectLater(
        svc.fetchAndDecrypt(_freshPayload()),
        throwsA(isA<DecryptError>()),
      );
      expect(crypto.wipeCount, 1);
    });

    test('propagates BlobNotFound when server returns 404', () async {
      final svc = _svc(
        const _FakeCryptoCore(),
        MockClient((_) async => http.Response('not found', 404)),
      );
      await expectLater(
        svc.fetchAndDecrypt(_freshPayload()),
        throwsA(isA<BlobNotFound>()),
      );
    });

    test('propagates BackendUnavailable when server returns 5xx', () async {
      final svc = _svc(
        const _FakeCryptoCore(),
        MockClient((_) async => http.Response('error', 503)),
      );
      await expectLater(
        svc.fetchAndDecrypt(_freshPayload()),
        throwsA(isA<BackendUnavailable>()),
      );
    });

    test('ZK: fetchAndDecrypt issues only GET, no PUT', () async {
      final puts = <String>[];
      final svc = _svc(
        const _FakeCryptoCore(),
        MockClient((req) async {
          if (req.method == 'PUT') puts.add(req.url.path);
          return http.Response.bytes(_fakeBlob(), 200);
        }),
      );
      await svc.fetchAndDecrypt(_freshPayload());
      expect(puts, isEmpty);
    });
  });
}
