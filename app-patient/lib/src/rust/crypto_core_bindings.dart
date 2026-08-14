// flutter_rust_bridge facade for crypto-core (ADR 0001 / ADR 0003).
//
// This file defines the *stable, hand-written seam* the rest of the app codes
// against (`CryptoCore`, `MasterKeyHandle`), plus the FRB-backed implementation
// (`FrbCryptoCore`) that delegates to the generated bindings in api.dart.
// Coding against the interface keeps the master-key flow unit-testable with a
// fake core (injected via _DevCryptoCore in main_dev.dart ONLY — never main.dart).
//
// The FFI surface is intentionally tiny (ADR 0003): clients call only the
// audited high-level functions. NO cipher logic ever lives in Dart, and the
// clear key never crosses this boundary except through `exportSealable`, whose
// only caller is the immediate hardware-sealing step (issue #11, G8).
//
// The Rust API + wire format are FROZEN by #10 — codegen must mirror it exactly,
// never reinterpret it: encryptRecord returns `nonce(12) || ciphertext || tag(16)`
// (28-byte overhead), and decryptRecord surfaces a single coarse error (no oracle)
// and never returns plaintext on a bad key/tag/blob. See crypto-core/README.md and
// docs/security/crypto-core-review.md.

import 'dart:typed_data';

import 'api.dart' as frb_api;
import 'api.dart' show sealRecovery, openRecovery, normalizeAnswers;

/// Opaque Dart-side reference to a master key that lives **inside the Rust core**.
///
/// Dart never holds the clear key behind this handle; it only passes the handle
/// back across the FFI for [CryptoCore.exportSealable] (sealing) and
/// [CryptoCore.wipe] (zeroize). The concrete subclass is [_FrbHandle].
abstract class MasterKeyHandle {}

/// The single cryptography entry point for the patient app (ADR 0003).
///
/// Mirrors the Rust `crypto-core` master-key surface (issue #11). Implementations
/// must never fall back to Dart-side crypto.
abstract class CryptoCore {
  /// Generate a fresh 256-bit master key inside the Rust core (OS CSPRNG).
  ///
  /// The clear key stays in Rust; only an opaque [MasterKeyHandle] is returned.
  Future<MasterKeyHandle> generateMasterKey();

  /// Export the clear key bytes **for immediate hardware sealing only** (G8).
  ///
  /// This is the one sanctioned point where the clear key crosses the FFI. The
  /// caller must pass the result straight to the Keystore shim and never persist,
  /// log, or transmit it.
  Future<Uint8List> exportSealable(MasterKeyHandle handle);

  /// Re-wrap clear bytes that hardware has just unsealed back into a handle (#14).
  Future<MasterKeyHandle> handleFromUnsealed(Uint8List clearBytes);

  /// Zeroize the clear key behind [handle] inside the Rust core (G5).
  Future<void> wipe(MasterKeyHandle handle);

  /// Encrypt [plaintext] with the key behind [handle] (AES-256-GCM, #10).
  ///
  /// Returns `nonce(12) || ciphertext || tag(16)`. Wire format matches
  /// the Rust `encrypt_record` function (28-byte overhead). The clear key
  /// never leaves the Rust core.
  Future<Uint8List> encryptRecord(MasterKeyHandle handle, Uint8List plaintext);

  /// Decrypt a blob from [encryptRecord] (#10).
  ///
  /// Throws [DecryptError] on a bad tag, wrong key, or corrupted blob.
  Future<Uint8List> decryptRecord(MasterKeyHandle handle, Uint8List ciphertext);

  /// Seal the master key under a PBKDF2-derived recovery key (#12, G2).
  ///
  /// [masterKeyClear] is the 32-byte clear key (immediately wiped after).
  /// [secret] is the passphrase or normalized cultural answers.
  /// [iterations] is the PBKDF2 iteration count (clamped to floor internally).
  /// Returns the self-describing recovery envelope bytes.
  Future<Uint8List> sealRecoveryEnvelope(
    Uint8List masterKeyClear,
    Uint8List secret,
    int iterations,
  );

  /// Open a recovery envelope, returning a [MasterKeyHandle] (#12, G1).
  ///
  /// [secret] is the passphrase or normalized answers (must match what was
  /// used to seal). Throws [WrongRecoverySecret] on bad secret or corrupted
  /// envelope (coarse error, no oracle).
  Future<MasterKeyHandle> openRecoveryEnvelope(
    Uint8List secret,
    Uint8List envelopeBytes,
  );

  /// Normalize and concatenate security-question answers (G6).
  ///
  /// Delegates to the Rust normalize_recovery_answers function for determinism.
  Future<Uint8List> normalizeRecoveryAnswers(List<String> answers);
}

/// Raised when [CryptoCore.decryptRecord] detects a bad tag, wrong key,
/// or corrupted blob.  Deliberately coarse — no decryption oracle.
class DecryptError implements Exception {
  const DecryptError();

  @override
  String toString() =>
      'decryption failed: bad key, tag mismatch, or corrupted blob';
}

/// Raised when a recovery envelope cannot be opened — wrong secret, corrupted
/// envelope, or a tampered blob.  The error is deliberately coarse (no oracle):
/// it does not distinguish the failure cause (wrong passphrase vs. bad bytes).
///
/// This is the Dart-side mirror of `CryptoError::Decrypt` on the recovery path
/// (#12, THR-05). "Envelope not found" is a separate concern handled above this
/// layer (typed separately by the caller).
class WrongRecoverySecret implements Exception {
  const WrongRecoverySecret();

  @override
  String toString() => 'recovery failed: wrong secret or corrupted envelope';
}

// ── FRB adapter ───────────────────────────────────────────────────────────────

/// Private adapter: wraps the FRB-generated [frb_api.CryptoHandle] opaque type
/// (which lives in Rust RAM) behind the [MasterKeyHandle] interface that the
/// rest of the app codes against.
class _FrbHandle extends MasterKeyHandle {
  _FrbHandle(this._handle);
  final frb_api.CryptoHandle _handle;
}

/// [CryptoCore] backed by the generated `flutter_rust_bridge` bindings (#102).
///
/// Delegates every call to `crypto-core` Rust functions via the generated
/// api.dart surface. The native library must be initialized with
/// `await RustLib.init()` in `main()` before any method is called.
///
/// Error translation:
///   - Rust decrypt/recovery errors (coarse String) → [DecryptError] / [WrongRecoverySecret].
///   - All other Rust errors propagate as-is (FRB throws an Exception with the message).
class FrbCryptoCore implements CryptoCore {
  const FrbCryptoCore();

  @override
  Future<MasterKeyHandle> generateMasterKey() async {
    final h = await frb_api.CryptoHandle.generate();
    return _FrbHandle(h);
  }

  @override
  Future<Uint8List> exportSealable(MasterKeyHandle handle) =>
      (handle as _FrbHandle)._handle.exportSealable();

  @override
  Future<MasterKeyHandle> handleFromUnsealed(Uint8List clearBytes) async {
    final h = await frb_api.CryptoHandle.fromClearBytes(bytes: clearBytes);
    return _FrbHandle(h);
  }

  @override
  Future<void> wipe(MasterKeyHandle handle) =>
      (handle as _FrbHandle)._handle.wipe();

  @override
  Future<Uint8List> encryptRecord(
    MasterKeyHandle handle,
    Uint8List plaintext,
  ) =>
      (handle as _FrbHandle)._handle.encryptRecord(plaintext: plaintext);

  @override
  Future<Uint8List> decryptRecord(
    MasterKeyHandle handle,
    Uint8List ciphertext,
  ) async {
    try {
      return await (handle as _FrbHandle)._handle.decryptRecord(blob: ciphertext);
    } catch (_) {
      throw const DecryptError();
    }
  }

  @override
  Future<Uint8List> sealRecoveryEnvelope(
    Uint8List masterKeyClear,
    Uint8List secret,
    int iterations,
  ) =>
      sealRecovery(
        masterKeyClear: masterKeyClear,
        secret: secret,
        iterations: iterations,
      );

  @override
  Future<MasterKeyHandle> openRecoveryEnvelope(
    Uint8List secret,
    Uint8List envelopeBytes,
  ) async {
    try {
      final h = await openRecovery(secret: secret, envelope: envelopeBytes);
      return _FrbHandle(h);
    } catch (_) {
      throw const WrongRecoverySecret();
    }
  }

  @override
  Future<Uint8List> normalizeRecoveryAnswers(List<String> answers) =>
      normalizeAnswers(answers: answers);
}
