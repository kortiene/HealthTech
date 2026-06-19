// Android Keystore (StrongBox/TEE) platform-channel shim — Dart side (stub).
//
// ADR 0001 + ADR 0006: the patient master key is generated inside the Rust
// crypto-core, then SEALED in the Android Keystore. Flutter plugins do not
// expose `setIsStrongBoxBacked` / TEE fallback, so a MANDATORY, security-
// critical Kotlin MethodChannel shim does the sealing. That Kotlin code is
// NOT written yet.
//
// `flutter_secure_storage` is used ONLY for non-critical items, never for the
// master key (ADR 0001).
//
// TODO(#11): implement the Kotlin shim
//   (KeyGenParameterSpec + setIsStrongBoxBacked(true) -> TEE fallback,
//    non-exportable) and the corresponding native iOS Keychain shim.

import 'package:flutter/services.dart';

/// Dart handle to the native key-sealing shim.
///
/// Every method is a stub that throws until the native side lands (#11) — it
/// must NOT silently degrade to a software key.
class KeystoreChannel {
  // Declared ahead of first use: the stub methods below will route through this
  // channel once the Kotlin/iOS shim lands (#11). Kept now so the API surface is
  // stable. `ignore` is scoped to this single intentional case, not the package.
  // ignore: unused_field
  static const MethodChannel _channel = MethodChannel('healthtech/keystore');

  const KeystoreChannel();

  /// Seal the Rust-produced master-key blob in hardware (StrongBox/TEE).
  /// TODO(#11): call the Kotlin `setIsStrongBoxBacked` path with TEE fallback.
  Future<void> sealMasterKey(Uint8List wrappedKey) {
    throw UnimplementedError('Keystore seal shim — TODO(#11)');
  }

  /// Unseal the wrapped SQLCipher DB key into memory (never to disk).
  /// TODO(#14): used to open the SQLCipher mirror; key stays in-memory only.
  Future<Uint8List> unsealDbKey() {
    throw UnimplementedError('Keystore unseal shim — TODO(#14)');
  }
}
