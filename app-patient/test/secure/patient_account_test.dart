// Tests for PatientAccount model + PatientAccountStore (issue #13).
//
// Uses FakeCryptoCore (XOR obfuscation — not real AES) and
// InMemorySealedBlobStore to keep tests host-only and fast.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/rust/crypto_core_bindings.dart';
import 'package:app_patient/src/legal/consent_model.dart';
import 'package:app_patient/src/secure/patient_account.dart';
import 'package:app_patient/src/secure/sealed_blob_store.dart';

// ─── Fakes ────────────────────────────────────────────────────────────────────

class _FakeMasterKeyHandle implements MasterKeyHandle {
  const _FakeMasterKeyHandle();
}

/// Trivial XOR-based fake: not AES, but tests the orchestration layer only.
class _FakeCryptoCore implements CryptoCore {
  const _FakeCryptoCore();

  static const _xorByte = 0x5A;

  Uint8List _xor(Uint8List data) =>
      Uint8List.fromList(data.map((b) => b ^ _xorByte).toList());

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
      _xor(plaintext);

  @override
  Future<Uint8List> decryptRecord(
    MasterKeyHandle handle,
    Uint8List ciphertext,
  ) async =>
      _xor(ciphertext);

  @override
  Future<Uint8List> sealRecoveryEnvelope(
    Uint8List masterKeyClear,
    Uint8List secret,
    int iterations,
  ) async =>
      _xor(masterKeyClear);

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

PatientAccount _fakeAccount() => const PatientAccount(
      anonymousUuid: '00000000-0000-4000-8000-000000000001',
      cmuNumber: 'CMU-2025-TEST01',
      phone: '+225 07 00 00 00 01',
      consent: ConsentRecord(
        version: consentBundleVersion,
        acceptedAt: '2025-01-01T00:00:00Z',
      ),
      createdAt: '2025-01-01T00:00:00Z',
    );

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  const crypto = _FakeCryptoCore();
  const handle = _FakeMasterKeyHandle();

  group('PatientAccount serialization', () {
    test('round-trips through JSON', () {
      final account = _fakeAccount();
      final json = account.toJson();
      final restored = PatientAccount.fromJson(json);
      expect(restored, equals(account));
    });

    test('equality: same fields → equal', () {
      expect(_fakeAccount(), equals(_fakeAccount()));
    });

    test('equality: different CMU → not equal', () {
      final a = _fakeAccount();
      final b = PatientAccount(
        anonymousUuid: a.anonymousUuid,
        cmuNumber: 'CMU-DIFFERENT',
        phone: a.phone,
        consent: a.consent,
        createdAt: a.createdAt,
      );
      expect(a, isNot(equals(b)));
    });

    test('toJson includes all fields', () {
      final json = _fakeAccount().toJson();
      expect(
        json.keys,
        containsAll(['uuid', 'cmu', 'phone', 'consent', 'created_at']),
      );
    });
  });

  group('PatientAccountStore', () {
    test('write + read round-trip returns same account', () async {
      final store = InMemorySealedBlobStore();
      final accountStore = PatientAccountStore(
        crypto: crypto,
        blobStore: store,
      );
      final account = _fakeAccount();

      await accountStore.write(account, handle);
      final restored = await accountStore.read(handle);

      expect(restored, equals(account));
    });

    test('exists returns false before write', () async {
      final store = InMemorySealedBlobStore();
      final accountStore = PatientAccountStore(
        crypto: crypto,
        blobStore: store,
      );
      expect(await accountStore.exists(), isFalse);
    });

    test('exists returns true after write', () async {
      final store = InMemorySealedBlobStore();
      final accountStore = PatientAccountStore(
        crypto: crypto,
        blobStore: store,
      );
      await accountStore.write(_fakeAccount(), handle);
      expect(await accountStore.exists(), isTrue);
    });

    test('read with empty store throws AccountNotFound', () async {
      final store = InMemorySealedBlobStore();
      final accountStore = PatientAccountStore(
        crypto: crypto,
        blobStore: store,
      );
      expect(
        () => accountStore.read(handle),
        throwsA(isA<AccountNotFound>()),
      );
    });

    test('encrypted blob does not contain plaintext CMU', () async {
      final store = InMemorySealedBlobStore();
      final accountStore = PatientAccountStore(
        crypto: crypto,
        blobStore: store,
      );
      await accountStore.write(_fakeAccount(), handle);
      final blob = await store.read();

      final blobString = utf8.decode(blob!, allowMalformed: true);
      expect(
        blobString,
        isNot(contains('CMU-2025-TEST01')),
        reason: 'CMU must not appear in clear in the stored blob',
      );
      expect(
        blobString,
        isNot(contains('+225 07 00 00 00 01')),
        reason: 'phone must not appear in clear in the stored blob',
      );
    });
  });

  group('AccountNotFound', () {
    test('toString is non-empty', () {
      expect(const AccountNotFound().toString(), isNotEmpty);
    });

    test('is an Exception', () {
      expect(const AccountNotFound(), isA<Exception>());
    });
  });
}
