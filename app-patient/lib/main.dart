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
import 'src/ui/onboarding_screen.dart';

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
      home: _RootRouter(masterKey: masterKey),
    );
  }
}

/// Start-up router: probes the master-key state and navigates accordingly.
class _RootRouter extends StatefulWidget {
  const _RootRouter({required this.masterKey});

  final MasterKeyService masterKey;

  @override
  State<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<_RootRouter> {
  late final Future<MasterKeyState> _stateFuture;

  @override
  void initState() {
    super.initState();
    _stateFuture = widget.masterKey.probeState();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<MasterKeyState>(
      future: _stateFuture,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (snap.hasError) {
          final err = snap.error;
          final msg = err is KeystoreException ? err.message : err.toString();
          return Scaffold(
            body: Center(
              child: Text('Erreur démarrage — $msg'),
            ),
          );
        }
        return switch (snap.data!) {
          // First run: show the onboarding flow (#13).
          MasterKeyState.absent => OnboardingScreen(
              onComplete: () => setState(() {
                _stateFuture = widget.masterKey.probeState();
              }),
            ),
          // Key present: route to the main app screen.
          // TODO(#16): replace stub with QR + record screen.
          MasterKeyState.present => const Scaffold(
              body: Center(child: Text('HealthTech — dossier médical')),
            ),
          // Key invalidated: route to PBKDF2 recovery (#12).
          // TODO(#12): replace stub with RecoveryScreen.
          MasterKeyState.invalidated => const Scaffold(
              body: Center(child: Text('Clé invalidée — récupération (#12)')),
            ),
        };
      },
    );
  }
}
