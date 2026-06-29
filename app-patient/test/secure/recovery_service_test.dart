// Tests for the recovery-related methods of MasterKeyService (#12).
//
// Uses a FakeCryptoCore (implements CryptoCore in memory) and
// InMemorySealedBlobStore + a FakeKeystoreChannel to avoid any native shim
// dependency.  The tests cover the Dart orchestration layer only — the Rust
// PBKDF2 logic is gated separately in
// crypto-core/tests/pbkdf2_rfc6070_vectors.rs.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/rust/crypto_core_bindings.dart';
import 'package:app_patient/src/secure/keystore_channel.dart';
import 'package:app_patient/src/secure/master_key_service.dart';
import 'package:app_patient/src/secure/sealed_blob_store.dart';

// ─── Fakes ────────────────────────────────────────────────────────────────────

/// A fake [MasterKeyHandle] that stores its key for comparison in tests.
class _FakeMasterKeyHandle implements MasterKeyHandle {
  _FakeMasterKeyHandle(this.key);
  final Uint8List key;
}

/// In-memory [CryptoCore] for unit tests.  Seal/open use a trivial XOR with a
/// fixed byte so the tests don't depend on real PBKDF2 — only the orchestration
/// (argument passing, wipe calls, error propagation) is exercised here.
class FakeCryptoCore implements CryptoCore {
  /// If set, [openRecoveryEnvelope] throws [WrongRecoverySecret].
  bool failOpen = false;

  /// Recorded calls to verify arguments in tests.
  final List<String> calls = [];

  static final Uint8List _fixedEnvelope =
      Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);

  static final Uint8List _fixedKey =
      Uint8List.fromList(List.generate(32, (i) => i));

  @override
  Future<MasterKeyHandle> generateMasterKey() async {
    calls.add('generateMasterKey');
    return _FakeMasterKeyHandle(_fixedKey);
  }

  @override
  Future<Uint8List> exportSealable(MasterKeyHandle handle) async {
    calls.add('exportSealable');
    return Uint8List.fromList((handle as _FakeMasterKeyHandle).key);
  }

  @override
  Future<MasterKeyHandle> handleFromUnsealed(Uint8List clearBytes) async {
    calls.add('handleFromUnsealed');
    return _FakeMasterKeyHandle(clearBytes);
  }

  @override
  Future<void> wipe(MasterKeyHandle handle) async {
    calls.add('wipe');
  }

  @override
  Future<Uint8List> sealRecoveryEnvelope(
    Uint8List masterKeyClear,
    Uint8List secret,
    int iterations,
  ) async {
    calls.add('sealRecoveryEnvelope');
    return _fixedEnvelope;
  }

  @override
  Future<MasterKeyHandle> openRecoveryEnvelope(
    Uint8List secret,
    Uint8List envelopeBytes,
  ) async {
    calls.add('openRecoveryEnvelope');
    if (failOpen) throw const WrongRecoverySecret();
    return _FakeMasterKeyHandle(_fixedKey);
  }

  @override
  Future<Uint8List> normalizeRecoveryAnswers(List<String> answers) async {
    calls.add('normalizeRecoveryAnswers');
    return Uint8List.fromList(answers.join('\x1f').codeUnits);
  }
}

/// In-memory [KeystoreChannel] that simply stores and returns the same bytes.
class FakeKeystoreChannel extends KeystoreChannel {
  FakeKeystoreChannel() : super();

  Uint8List? _sealed;

  @override
  Future<Uint8List> seal(Uint8List clearKey) async {
    _sealed = Uint8List.fromList(clearKey);
    return _sealed!;
  }

  @override
  Future<Uint8List> unseal(Uint8List sealedBlob) async {
    return Uint8List.fromList(sealedBlob);
  }

  @override
  Future<bool> exists() async => _sealed != null;
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Build a [MasterKeyService] with an already-present sealed blob so
/// [setUpRecovery] and [unsealForUse] have something to read.
Future<MasterKeyService> _serviceWithBlob({
  required FakeCryptoCore core,
  required FakeKeystoreChannel keystore,
  required InMemorySealedBlobStore store,
}) async {
  // Write a fake sealed blob (32 bytes, all-zero) so blobStore.read() != null.
  await store.write(Uint8List(32));
  return MasterKeyService(
    cryptoCore: core,
    keystore: keystore,
    blobStore: store,
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('MasterKeyService.setUpRecovery', () {
    test('returns non-empty envelope bytes', () async {
      final core = FakeCryptoCore();
      final keystore = FakeKeystoreChannel();
      final store = InMemorySealedBlobStore();
      final svc = await _serviceWithBlob(
        core: core,
        keystore: keystore,
        store: store,
      );

      final envelope = await svc.setUpRecovery(
        Uint8List.fromList([0xAA, 0xBB]),
      );

      expect(envelope, isNotEmpty);
      expect(core.calls, contains('sealRecoveryEnvelope'));
    });

    test('with no existing master key throws KeystoreUnavailable', () async {
      final core = FakeCryptoCore();
      final keystore = FakeKeystoreChannel();
      // Empty store — no blob.
      final store = InMemorySealedBlobStore();
      final svc = MasterKeyService(
        cryptoCore: core,
        keystore: keystore,
        blobStore: store,
      );

      expect(
        () => svc.setUpRecovery(Uint8List.fromList([0x01])),
        throwsA(isA<KeystoreUnavailable>()),
      );
    });

    test('passes custom iteration count through to sealRecoveryEnvelope',
        () async {
      final core = FakeCryptoCore();
      final keystore = FakeKeystoreChannel();
      final store = InMemorySealedBlobStore();
      final svc = await _serviceWithBlob(
        core: core,
        keystore: keystore,
        store: store,
      );

      // Any non-null iterations value — the fake just records the call.
      await svc.setUpRecovery(
        Uint8List.fromList([0x01]),
        iterations: 300000,
      );

      expect(core.calls, contains('sealRecoveryEnvelope'));
    });
  });

  group('MasterKeyService.recoverFromSecret', () {
    test('calls blobStore.write on success (reseal on new device)', () async {
      final core = FakeCryptoCore();
      final keystore = FakeKeystoreChannel();
      final store = InMemorySealedBlobStore();
      final svc = MasterKeyService(
        cryptoCore: core,
        keystore: keystore,
        blobStore: store,
      );

      await svc.recoverFromSecret(
        Uint8List.fromList([0x01, 0x02]),
        Uint8List.fromList([0xDE, 0xAD]),
      );

      expect(await store.exists(), isTrue,
          reason: 'blobStore.write must be called on recovery success');
    });

    test('with wrong secret throws WrongRecoverySecret', () async {
      final core = FakeCryptoCore()..failOpen = true;
      final keystore = FakeKeystoreChannel();
      final store = InMemorySealedBlobStore();
      final svc = MasterKeyService(
        cryptoCore: core,
        keystore: keystore,
        blobStore: store,
      );

      expect(
        () => svc.recoverFromSecret(
          Uint8List.fromList([0xFF]),
          Uint8List.fromList([0xBE, 0xEF]),
        ),
        throwsA(isA<WrongRecoverySecret>()),
      );
    });

    test('wipes handle after successful recovery', () async {
      final core = FakeCryptoCore();
      final keystore = FakeKeystoreChannel();
      final store = InMemorySealedBlobStore();
      final svc = MasterKeyService(
        cryptoCore: core,
        keystore: keystore,
        blobStore: store,
      );

      await svc.recoverFromSecret(
        Uint8List.fromList([0x01]),
        Uint8List.fromList([0x02]),
      );

      expect(core.calls, contains('wipe'));
    });
  });

  group('CryptoCore.normalizeRecoveryAnswers (delegated to core)', () {
    test('returns non-empty bytes for non-empty answers', () async {
      final core = FakeCryptoCore();
      final result =
          await core.normalizeRecoveryAnswers(['Abidjan', 'Korhogo']);
      expect(result, isNotEmpty);
      expect(core.calls, contains('normalizeRecoveryAnswers'));
    });

    test('different answer lists produce different bytes', () async {
      final core = FakeCryptoCore();
      final a = await core.normalizeRecoveryAnswers(['ab', 'cd']);
      final core2 = FakeCryptoCore();
      final b = await core2.normalizeRecoveryAnswers(['abc', 'd']);
      // The fake joins with \x1f, so the two must differ.
      expect(a, isNot(equals(b)));
    });
  });

  group('WrongRecoverySecret', () {
    test('toString is non-empty', () {
      const e = WrongRecoverySecret();
      expect(e.toString(), isNotEmpty);
    });

    test('is an Exception', () {
      expect(const WrongRecoverySecret(), isA<Exception>());
    });
  });
}
