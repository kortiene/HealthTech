// Biometric unlock service — UI layer only.
//
// Security note: biometric authentication at this layer is purely an identity
// confirmation gate before showing the app UI. It does NOT unseal the master
// key; that remains in the Android Keystore/TEE via KeystoreSealer. The
// biometric_enabled flag stored here is a non-critical preference — an attacker
// who can bypass the OS biometric prompt already has full device access.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class BiometricService {
  BiometricService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  final FlutterSecureStorage _storage;
  static const _kKey = 'biometric_enabled';
  final _auth = LocalAuthentication();

  Future<bool> isAvailable() async {
    final can = await _auth.canCheckBiometrics;
    final supported = await _auth.isDeviceSupported();
    return can && supported;
  }

  Future<bool> isEnabled() async =>
      (await _storage.read(key: _kKey)) == 'true';

  Future<bool> authenticate(String reason) async {
    try {
      return await _auth.authenticate(
        localizedReason: reason,
        options:
            const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
      );
    } catch (_) {
      return false;
    }
  }

  Future<void> setEnabled(bool v) async {
    if (v) {
      await _storage.write(key: _kKey, value: 'true');
    } else {
      await _storage.delete(key: _kKey);
    }
  }
}
