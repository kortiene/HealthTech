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

import 'src/cloud/backend_client.dart';
import 'src/doctor/scan_service.dart';
import 'src/qr/access_token.dart';
import 'src/record/medical_record_store.dart';
import 'src/rust/crypto_core_bindings.dart';
import 'src/secure/keystore_channel.dart';
import 'src/secure/master_key_service.dart';
import 'src/secure/patient_account.dart';
import 'src/secure/sealed_blob_store.dart';
import 'src/ui/onboarding_screen.dart';
import 'src/ui/qr_screen.dart';
import 'src/ui/scan_screen.dart';

/// Backend base URL — production sovereign endpoint (ADR 0004 / ARTCI hosting).
const String _kBackendBaseUrl = 'https://api.healthtech.ci';

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
          // Key present: route to the home screen (#16 QR access).
          MasterKeyState.present => _HomeScreen(masterKey: widget.masterKey),
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

/// Home screen shown when the master key is ready.
///
/// Provides a button to generate a QR access token (#16) for the current
/// consultation session.  All dependencies are created on demand so the
/// production crypto stack is only reached when the user initiates a session.
class _HomeScreen extends StatelessWidget {
  const _HomeScreen({required this.masterKey});

  final MasterKeyService masterKey;

  DefaultQrController _buildController() {
    return DefaultQrController(
      masterKey: masterKey,
      accountStore: const PatientAccountStore(
        crypto: FrbCryptoCore(),
        blobStore: FileSealedBlobStore(
          fileName: 'patient_account.sealed',
        ),
      ),
      tokenService: AccessTokenService(
        crypto: const FrbCryptoCore(),
        recordStore: MedicalRecordStore(
          crypto: const FrbCryptoCore(),
          client: BackendClient(_kBackendBaseUrl),
          localStore: const FileSealedBlobStore(
            fileName: 'medical_record.sealed',
          ),
        ),
        client: BackendClient(_kBackendBaseUrl),
      ),
      backendUrl: _kBackendBaseUrl,
    );
  }

  ScanService _buildScanService() => ScanService(
        crypto: const FrbCryptoCore(),
        client: BackendClient(_kBackendBaseUrl),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HealthTech')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.qr_code),
              label: const Text('Partager mon dossier'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => QrScreen(controller: _buildController()),
                ),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scanner (médecin)'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ScanScreen(service: _buildScanService()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
