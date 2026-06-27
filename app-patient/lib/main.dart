// HealthTech — patient app entry point (skeleton).
//
// ADR 0001 (Flutter patient app) + ADR 0006 (offline storage & keys).
//
// CRYPTO BOUNDARY: there is NO cipher code in Dart. AES-256-GCM / PBKDF2 /
// master-key generation all happen in the shared Rust crypto-core, reached
// ONLY through flutter_rust_bridge. Dart holds just what the UI renders.
//
// #11 wires the master-key LIFECYCLE (generate in Rust core -> seal in the
// Android Keystore StrongBox/TEE via the Kotlin MethodChannel shim -> persist
// only the sealed blob). This file does the minimal STARTUP ROUTING off that
// lifecycle; the onboarding/record UI itself is #13.
//   #13 onboarding  — first-run flow, recovery passphrase/security questions.
//   #16 QR          — generate (qr_flutter, 120 s TTL) + scan (mobile_scanner).
//   #14 backup      — SQLCipher local mirror + pending-upload queue; recovery.

import 'package:flutter/material.dart';

import 'src/secure/keystore_channel.dart';
import 'src/secure/master_key_service.dart';

void main() {
  runApp(const PatientApp());
}

class PatientApp extends StatelessWidget {
  const PatientApp({super.key, this.masterKey = const MasterKeyService()});

  /// Injectable so widget tests can supply a fake-backed service.
  final MasterKeyService masterKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HealthTech Patient',
      theme: ThemeData(useMaterial3: true),
      home: _HomeStub(masterKey: masterKey),
    );
  }
}

/// Placeholder home screen that performs the #11 startup routing decision.
///
/// It probes the master-key state and shows which path the real UI (#13 onboarding
/// vs #12 recovery) would take. The actual screens are out of scope for #11.
class _HomeStub extends StatelessWidget {
  const _HomeStub({required this.masterKey});

  final MasterKeyService masterKey;

  Future<String> _route() async {
    try {
      switch (await masterKey.probeState()) {
        case MasterKeyState.absent:
          return 'No master key yet → onboarding (#13): generate + seal in Keystore.';
        case MasterKeyState.present:
          return 'Master key sealed in hardware → open record.';
        case MasterKeyState.invalidated:
          return 'Hardware key invalidated → recovery (#12, PBKDF2).';
      }
    } on KeystoreException catch (e) {
      // No silent software fallback (G3): surface the failure honestly.
      return 'Keystore unavailable — ${e.message}. (No software fallback by design.)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HealthTech')),
      body: Center(
        child: FutureBuilder<String>(
          future: _route(),
          builder: (context, snap) {
            // TODO(#16): patient QR (generate w/ 120 s TTL, scan w/ mobile_scanner).
            // TODO(#14): open SQLCipher mirror (DB key unsealed in-memory only).
            final status = snap.data ?? 'Checking device key…';
            return Text('HealthTech patient app — $status');
          },
        ),
      ),
    );
  }
}
