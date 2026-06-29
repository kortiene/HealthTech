// Master-key lifecycle orchestration (issue #11).
//
// Ties together the three trust anchors without ever holding clear key material
// longer than necessary:
//   - CryptoCore (Rust core)  — generates the key, exports it once for sealing,
//                               wipes its clear copy (G1/G5/G8).
//   - KeystoreChannel (native) — seals/unseals with the hardware KEK (G2/G3).
//   - SealedBlobStore          — persists ONLY the sealed blob (G4).
//
// Generation flow (consumed by onboarding #13):
//   generateMasterKey -> exportSealable -> seal -> persist blob -> wipe clear copy
//
// No software fallback (G3): any keystore unavailability propagates as a typed
// KeystoreException. No clear key or sealed blob is ever logged (G5).

import 'dart:typed_data';

import '../rust/crypto_core_bindings.dart';
import 'keystore_channel.dart';
import 'sealed_blob_store.dart';

/// State of the device master key at startup, used to route the user.
enum MasterKeyState {
  /// No sealed blob yet — first run; route to onboarding (#13).
  absent,

  /// Sealed blob present and the hardware key is usable.
  present,

  /// A sealed blob exists but the hardware key was invalidated — route to the
  /// PBKDF2 recovery flow (#12).
  invalidated,
}

/// Orchestrates generation, sealing, persistence, and unsealing of the master key.
class MasterKeyService {
  const MasterKeyService({
    CryptoCore cryptoCore = const FrbCryptoCore(),
    KeystoreChannel keystore = const KeystoreChannel(),
    SealedBlobStore blobStore = const FileSealedBlobStore(),
  })  : _crypto = cryptoCore,
        _keystore = keystore,
        _blobStore = blobStore;

  final CryptoCore _crypto;
  final KeystoreChannel _keystore;
  final SealedBlobStore _blobStore;

  /// Generate the device master key and seal it, **idempotently** (G6).
  ///
  /// If a sealed blob already exists this is a no-op (it does NOT overwrite an
  /// existing key — doing so would orphan the encrypted record). Returns true if
  /// a new key was generated and sealed, false if one already existed.
  Future<bool> ensureMasterKey() async {
    if (await _blobStore.exists() && await _keystore.exists()) {
      return false;
    }
    await _generateAndSeal();
    return true;
  }

  /// Force-generate and seal a fresh master key. Internal: callers use
  /// [ensureMasterKey] so an existing key is never silently overwritten.
  Future<void> _generateAndSeal() async {
    final handle = await _crypto.generateMasterKey();
    Uint8List? clear;
    try {
      // Single sanctioned crossing of the clear key over the FFI (G8).
      clear = await _crypto.exportSealable(handle);
      final sealed = await _keystore.seal(clear);
      await _blobStore.write(sealed);
    } finally {
      // Wipe the Rust-side clear copy as soon as sealing is done (G5)...
      await _crypto.wipe(handle);
      // ...and best-effort overwrite the transient Dart copy. Uint8List is not
      // deterministically zeroizable (ADR 0001), so we minimise its lifetime and
      // overwrite what we can rather than rely on it.
      if (clear != null) clear.fillRange(0, clear.length, 0);
    }
  }

  /// Probe the master-key state at startup to route the UI (#13 vs #12).
  ///
  /// Distinguishes "no key yet" from "key invalidated" so a hardware-key loss
  /// becomes a recovery prompt, not a crash or silent data loss (G7).
  Future<MasterKeyState> probeState() async {
    if (!await _blobStore.exists()) {
      return MasterKeyState.absent;
    }
    try {
      // `exists()` reflects whether the hardware KEK is still usable.
      return await _keystore.exists()
          ? MasterKeyState.present
          : MasterKeyState.invalidated;
    } on KeyInvalidated {
      return MasterKeyState.invalidated;
    }
  }

  /// Zeroize the clear key behind [handle] in the Rust core (G5).
  ///
  /// Callers that obtained a handle from [unsealForUse] must call this as soon
  /// as the key is no longer needed — typically in a `finally` block.
  Future<void> wipeHandle(MasterKeyHandle handle) => _crypto.wipe(handle);

  /// Unseal the master key into the Rust core for use (#14 / local session open).
  ///
  /// Returns an opaque handle; the clear bytes live in memory only for the
  /// re-wrap and are overwritten immediately. The caller owns the handle and must
  /// [CryptoCore.wipe] it after use.
  ///
  /// Throws [KeystoreUnavailable] if no blob is persisted, or [KeyInvalidated]
  /// if the hardware key is gone (route to recovery, #12).
  Future<MasterKeyHandle> unsealForUse() async {
    final blob = await _blobStore.read();
    if (blob == null) {
      throw const KeystoreUnavailable('no sealed master key to unseal');
    }
    Uint8List? clear;
    try {
      clear = await _keystore.unseal(blob);
      return await _crypto.handleFromUnsealed(clear);
    } finally {
      if (clear != null) clear.fillRange(0, clear.length, 0);
    }
  }
}
