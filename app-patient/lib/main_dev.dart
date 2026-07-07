// DEV-ONLY entry point — substitutes FrbCryptoCore (requires FRB codegen)
// with a pure-Dart XOR stub so the full UI can be run on a local emulator
// without generating the flutter_rust_bridge bindings.
//
// Usage:  flutter run --target lib/main_dev.dart -d emulator-5554
//
// WARNING: _DevCryptoCore is NOT cryptographically secure. It XORs plaintext
// with 0x5A — it exists only to exercise the UI wiring. Never ship this target.
//
// Everything else (KeystoreChannel, BackendClient, real screens) is production
// code pointed at the local dev stack (http://10.0.2.2:8081).

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'src/cloud/backend_client.dart';
import 'src/doctor/consultation_edit_service.dart';
import 'src/doctor/offline_upload_queue.dart';
import 'src/doctor/scan_service.dart';
import 'src/qr/access_token.dart';
import 'src/record/medical_record.dart';
import 'src/record/medical_record_store.dart';
import 'src/rust/crypto_core_bindings.dart';
import 'src/secure/keystore_channel.dart';
import 'src/secure/master_key_service.dart';
import 'src/secure/patient_account.dart';
import 'src/secure/sealed_blob_store.dart';
import 'src/ui/onboarding_screen.dart';
import 'src/ui/qr_screen.dart';
import 'src/ui/scan_screen.dart';

// Android emulator reaches the host via 10.0.2.2; every other platform
// (macOS desktop, iOS simulator, web) uses localhost directly.
final String _kBackendBaseUrl = Platform.isAndroid
    ? 'http://10.0.2.2:8081'
    : 'http://localhost:8081';

void main() {
  runApp(PatientApp(masterKey: _devMasterKeyService()));
}

MasterKeyService _devMasterKeyService() => const MasterKeyService(
      cryptoCore: _DevCryptoCore(),
      keystore: _DevKeystoreChannel(),
      blobStore: FileSealedBlobStore(fileName: 'dev_master_key.sealed'),
    );

// ─── Dev keystore stub — identity seal, no hardware required ─────────────────

/// Simulates the Android Keystore seal/unseal on emulator/host where TEE is
/// unavailable. The "sealed blob" IS the clear key (no wrapping) — suitable
/// only for UI wiring in dev, never for production.
class _DevKeystoreChannel extends KeystoreChannel {
  const _DevKeystoreChannel() : super();

  @override
  Future<Uint8List> seal(Uint8List clearKey) async => clearKey;

  @override
  Future<Uint8List> unseal(Uint8List sealedBlob) async => sealedBlob;

  @override
  Future<bool> exists() async => true;

  @override
  Future<void> clear() async {}
}

// ─── XOR stub — UI wiring only, no cryptographic guarantees ──────────────────

class _DevHandle implements MasterKeyHandle {
  const _DevHandle();
}

class _DevCryptoCore implements CryptoCore {
  const _DevCryptoCore();

  static const int _xor = 0x5A;

  Uint8List _xorBytes(List<int> bytes) =>
      Uint8List.fromList(bytes.map((b) => b ^ _xor).toList());

  @override
  Future<MasterKeyHandle> generateMasterKey() async => const _DevHandle();

  @override
  Future<Uint8List> exportSealable(MasterKeyHandle handle) async =>
      Uint8List(32); // 32 zero bytes — sealed by the real Keystore KEK

  @override
  Future<MasterKeyHandle> handleFromUnsealed(Uint8List clearBytes) async =>
      const _DevHandle();

  @override
  Future<void> wipe(MasterKeyHandle handle) async {}

  @override
  Future<Uint8List> encryptRecord(
    MasterKeyHandle handle,
    Uint8List plaintext,
  ) async =>
      _xorBytes(plaintext);

  @override
  Future<Uint8List> decryptRecord(
    MasterKeyHandle handle,
    Uint8List ciphertext,
  ) async =>
      _xorBytes(ciphertext);

  @override
  Future<Uint8List> sealRecoveryEnvelope(
    Uint8List masterKeyClear,
    Uint8List secret,
    int iterations,
  ) async =>
      Uint8List(32);

  @override
  Future<MasterKeyHandle> openRecoveryEnvelope(
    Uint8List secret,
    Uint8List envelopeBytes,
  ) async =>
      const _DevHandle();

  @override
  Future<Uint8List> normalizeRecoveryAnswers(List<String> answers) async =>
      Uint8List.fromList(answers.join('\x1f').codeUnits);
}

// ─── App shell (mirrors main.dart, dev deps only) ────────────────────────────

class PatientApp extends StatelessWidget {
  const PatientApp({super.key, required this.masterKey});

  final MasterKeyService masterKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HealthTech [DEV]',
      theme: ThemeData(useMaterial3: true),
      home: _RootRouter(masterKey: masterKey),
    );
  }
}

class _RootRouter extends StatefulWidget {
  const _RootRouter({required this.masterKey});

  final MasterKeyService masterKey;

  @override
  State<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends State<_RootRouter> {
  late Future<MasterKeyState> _stateFuture;

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
          return Scaffold(body: Center(child: Text('[DEV] Erreur — $msg')));
        }
        return switch (snap.data!) {
          MasterKeyState.absent => OnboardingScreen(
              onComplete: () => setState(() {
                _stateFuture = widget.masterKey.probeState();
              }),
              controller: OnboardingController(
                masterKey: widget.masterKey,
                accountStore: const PatientAccountStore(
                  crypto: _DevCryptoCore(),
                  blobStore: FileSealedBlobStore(
                    fileName: 'dev_patient_account.sealed',
                  ),
                ),
              ),
            ),
          MasterKeyState.present => _HomeScreen(masterKey: widget.masterKey),
          MasterKeyState.invalidated => const Scaffold(
              body: Center(child: Text('[DEV] Clé invalidée')),
            ),
        };
      },
    );
  }
}

// Seeds an empty MedicalRecord on first generate() if none exists yet, then
// delegates to DefaultQrController. Needed because onboarding only creates the
// patient account; the medical record is written separately (issue #15/#16).
class _DevQrController implements QrController {
  _DevQrController({
    required MasterKeyService masterKey,
    required PatientAccountStore accountStore,
    required MedicalRecordStore recordStore,
    required AccessTokenService tokenService,
    required String backendUrl,
  })  : _inner = DefaultQrController(
          masterKey: masterKey,
          accountStore: accountStore,
          tokenService: tokenService,
          backendUrl: backendUrl,
        ),
        _masterKey = masterKey,
        _accountStore = accountStore,
        _recordStore = recordStore;

  final DefaultQrController _inner;
  final MasterKeyService _masterKey;
  final PatientAccountStore _accountStore;
  final MedicalRecordStore _recordStore;

  @override
  Future<QrPayload> generate() async {
    if (!await _recordStore.exists()) {
      await _seedEmptyRecord();
    }
    return _inner.generate();
  }

  Future<void> _seedEmptyRecord() async {
    final handle = await _masterKey.unsealForUse();
    try {
      final account = await _accountStore.read(handle);
      final now = DateTime.now().toUtc().toIso8601String();
      final record = MedicalRecord(
        patientId: account.anonymousUuid,
        createdAt: now,
        updatedAt: now,
      );
      await _recordStore.write(record, handle, account.anonymousUuid);
    } finally {
      await _masterKey.wipeHandle(handle);
    }
  }
}

class _HomeScreen extends StatelessWidget {
  const _HomeScreen({required this.masterKey});

  final MasterKeyService masterKey;

  _DevQrController _buildController() => _DevQrController(
        masterKey: masterKey,
        accountStore: const PatientAccountStore(
          crypto: _DevCryptoCore(),
          blobStore: FileSealedBlobStore(
            fileName: 'dev_patient_account.sealed',
          ),
        ),
        recordStore: MedicalRecordStore(
          crypto: const _DevCryptoCore(),
          client: BackendClient(_kBackendBaseUrl),
          localStore: const FileSealedBlobStore(
            fileName: 'dev_medical_record.sealed',
          ),
        ),
        tokenService: AccessTokenService(
          crypto: const _DevCryptoCore(),
          recordStore: MedicalRecordStore(
            crypto: const _DevCryptoCore(),
            client: BackendClient(_kBackendBaseUrl),
            localStore: const FileSealedBlobStore(
              fileName: 'dev_medical_record.sealed',
            ),
          ),
          client: BackendClient(_kBackendBaseUrl),
        ),
        backendUrl: _kBackendBaseUrl,
      );

  ScanService _buildScanService() => ScanService(
        crypto: const _DevCryptoCore(),
        client: BackendClient(_kBackendBaseUrl),
      );

  ConsultationEditService _buildEditService() =>
      ConsultationEditService(crypto: const _DevCryptoCore());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HealthTech [DEV]')),
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
                  builder: (_) => ScanScreen(
                        service: _buildScanService(),
                        editService: _buildEditService(),
                        // SQLCipher is Android-only; use in-memory queue on
                        // macOS/desktop so the session still works without it.
                        queue: Platform.isAndroid
                            ? null
                            : InMemoryUploadQueue(),
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
