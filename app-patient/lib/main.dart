// HealthTech — patient app entry point (skeleton).
//
// ADR 0001 (Flutter patient app) + ADR 0006 (offline storage & keys).
//
// CRYPTO BOUNDARY: there is NO cipher code in Dart. AES-256-GCM / PBKDF2 /
// master-key generation all happen in the shared Rust crypto-core, reached
// ONLY through flutter_rust_bridge. Dart holds just what the UI renders.
//
// This file is a compiling stub. The feature work is tracked by:
//   #11 keygen      — master key generated in Rust core, sealed in Android
//                     Keystore (StrongBox/TEE) via the Kotlin MethodChannel shim.
//   #13 onboarding  — first-run flow, recovery passphrase/security questions.
//   #16 QR          — generate (qr_flutter, 120 s TTL) + scan (mobile_scanner).
//   #14 backup      — SQLCipher local mirror + pending-upload queue; recovery.

import 'package:flutter/material.dart';

void main() {
  runApp(const PatientApp());
}

class PatientApp extends StatelessWidget {
  const PatientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HealthTech Patient',
      theme: ThemeData(useMaterial3: true),
      home: const _HomeStub(),
    );
  }
}

/// Placeholder home screen.
///
/// TODO(#13): replace with the real onboarding / record-view flow.
class _HomeStub extends StatelessWidget {
  const _HomeStub();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HealthTech')),
      body: const Center(
        // TODO(#11): generate_master_key via CryptoCore (Rust/FRB) + seal in Keystore.
        // TODO(#16): patient QR (generate w/ 120 s TTL, scan w/ mobile_scanner).
        // TODO(#14): open SQLCipher mirror (DB key unsealed in-memory only).
        child: Text('HealthTech patient app — skeleton (issue #2)'),
      ),
    );
  }
}
