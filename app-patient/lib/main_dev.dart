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
// code pointed at the local dev stack.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'src/cloud/backend_client.dart'
    show BackendClient, BackendUnavailable, BlobNotFound;
import 'src/design/app_theme.dart';
import 'src/doctor/scan_service.dart';
// import 'src/legal/consent_model.dart' -- used transitively by OnboardingController;
import 'src/qr/access_token.dart';
import 'src/record/medical_record.dart';
import 'src/record/medical_record_store.dart';
import 'src/rust/crypto_core_bindings.dart';
import 'src/secure/biometric_service.dart';
import 'src/secure/keystore_channel.dart';
import 'src/secure/master_key_service.dart';
import 'src/secure/patient_account.dart';
import 'src/secure/sealed_blob_store.dart';
import 'src/ui/auth/pin_screen.dart';
import 'src/ui/main_shell.dart';
import 'src/ui/onboarding_screen.dart';
import 'src/ui/splash_screen.dart';

// Android emulator reaches the host via 10.0.2.2; every other platform uses
// localhost. This is for API calls from the Flutter app itself.
final String _kBackendBaseUrl =
    Platform.isAndroid ? 'http://10.0.2.2:8081' : 'http://localhost:8081';

// The URL embedded in the QR code must be reachable from the doctor's
// browser — always localhost when the backend runs on the dev machine.
const String _kQrBackendUrl = 'http://localhost:8081';

const String _kPinKey = 'patient_pin';
const String _kLastSyncKey = 'last_sync_at';
const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

void main() {
  runApp(const PatientApp());
}

class PatientApp extends StatelessWidget {
  const PatientApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HealthTech [DEV]',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: const _AppRoot(),
    );
  }
}

// ─── Dev keystore stub — identity seal, no hardware required ─────────────────

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
      Uint8List(32);

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

// ─── Phase FSM (mirrors main.dart, dev deps injected) ───────────────────────

enum _Phase {
  splash,
  probing,
  onboarding,
  pinCreate,
  locked,
  loading,
  home,
  invalidated
}

class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> with WidgetsBindingObserver {
  _Phase _phase = _Phase.splash;
  MedicalRecord? _record;
  PatientAccount? _account;
  String? _storedPin;
  bool _didPause = false;
  bool _suppressNextLock = false;
  String? _loadError;
  final _biometricService = BiometricService();
  bool _biometricEnabled = false;
  String? _lastSyncedAt;

  static const _masterKey = MasterKeyService(
    cryptoCore: _DevCryptoCore(),
    keystore: _DevKeystoreChannel(),
    blobStore: FileSealedBlobStore(fileName: 'dev_master_key.sealed'),
  );

  static const _accountStore = PatientAccountStore(
    crypto: _DevCryptoCore(),
    blobStore: FileSealedBlobStore(fileName: 'dev_patient_account.sealed'),
  );

  late final MedicalRecordStore _recordStore;

  @override
  void initState() {
    super.initState();
    _recordStore = MedicalRecordStore(
      crypto: const _DevCryptoCore(),
      client: BackendClient(_kBackendBaseUrl),
      localStore:
          const FileSealedBlobStore(fileName: 'dev_medical_record.sealed'),
    );
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _didPause = true;
    if (state == AppLifecycleState.resumed &&
        _didPause &&
        _phase == _Phase.home) {
      _didPause = false;
      if (_suppressNextLock) {
        _suppressNextLock = false;
        return; // Paused by image_picker — don't lock.
      }
      setState(() => _phase = _Phase.locked);
    }
  }

  void _onWillPauseForPicker() => _suppressNextLock = true;

  // ── Transitions ─────────────────────────────────────────────────────────────

  void _onSplashDone() {
    setState(() => _phase = _Phase.probing);
    _probe();
  }

  Future<void> _probe() async {
    try {
      final keyState = await _masterKey.probeState();
      if (!mounted) return;
      switch (keyState) {
        case MasterKeyState.absent:
          setState(() => _phase = _Phase.onboarding);
        case MasterKeyState.present:
          if (!await _accountStore.exists()) {
            if (!mounted) return;
            setState(() => _phase = _Phase.onboarding);
            return;
          }
          final pin = await _storage.read(key: _kPinKey);
          _biometricEnabled = await _biometricService.isEnabled();
          _lastSyncedAt = await _storage.read(key: _kLastSyncKey);
          if (!mounted) return;
          if (pin != null && pin.isNotEmpty) {
            _storedPin = pin;
            setState(() => _phase = _Phase.locked);
          } else {
            setState(() => _phase = _Phase.pinCreate);
          }
        case MasterKeyState.invalidated:
          setState(() => _phase = _Phase.invalidated);
      }
    } on KeystoreException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.message;
        _phase = _Phase.invalidated;
      });
    }
  }

  void _onOnboardingDone() {
    setState(() => _phase = _Phase.pinCreate);
  }

  Future<void> _onPinCreated(String pin) async {
    await _storage.write(key: _kPinKey, value: pin);
    _storedPin = pin;
    await _loadAppData();
  }

  Future<void> _onPinVerified(String _) async {
    await _loadAppData();
  }

  Future<void> _loadAppData() async {
    setState(() {
      _phase = _Phase.loading;
      _loadError = null;
    });
    try {
      final handle = await _masterKey.unsealForUse();
      try {
        _account = await _accountStore.read(handle);
        if (await _recordStore.exists()) {
          // Cloud-first on startup: picks up doctor's session changes from
          // a prior QR scan without requiring another QR cycle.
          MedicalRecord? cloudRecord;
          try {
            cloudRecord = await _recordStore.read(
              handle,
              _account!.anonymousUuid,
              forceCloud: true,
            );
          } on BackendUnavailable {
            // Offline — fall back to local cache below.
          } catch (e, st) {
            // ignore: avoid_print
            print('[_loadAppData] cloud read ERROR: $e\n$st');
          }
          _record = cloudRecord ??
              await _recordStore.read(handle, _account!.anonymousUuid);
        } else {
          final now = DateTime.now().toUtc().toIso8601String();
          final empty = MedicalRecord(
            patientId: _account!.anonymousUuid,
            createdAt: now,
            updatedAt: now,
          );
          try {
            await _recordStore.write(empty, handle, _account!.anonymousUuid);
          } on BackendUnavailable {
            // Local write already succeeded; cloud sync will retry when available.
          }
          _record = empty;
        }
      } finally {
        await _masterKey.wipeHandle(handle);
      }
      if (!mounted) return;
      setState(() => _phase = _Phase.home);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e.toString();
        _phase = _Phase.locked;
      });
    }
  }

  void _onLock() {
    setState(() => _phase = _Phase.locked);
  }

  Future<void> _onChangePin(String newPin) async {
    await _storage.write(key: _kPinKey, value: newPin);
    _storedPin = newPin;
  }

  Future<void> _onManualSync() async {
    if (_record == null || _account == null) return;
    final handle = await _masterKey.unsealForUse();
    try {
      await _recordStore.write(_record!, handle, _account!.anonymousUuid);
      final now = DateTime.now().toUtc().toIso8601String();
      await _storage.write(key: _kLastSyncKey, value: now);
      if (mounted) setState(() => _lastSyncedAt = now);
    } finally {
      await _masterKey.wipeHandle(handle);
    }
  }

  Future<void> _onDeleteAccount() async {
    try {
      final uuid = _account?.anonymousUuid;
      if (uuid != null) {
        try {
          await BackendClient(_kBackendBaseUrl).delete(uuid);
        } on BackendUnavailable {
          // offline
        } on BlobNotFound {
          // already gone
        }
      }
      await _recordStore.deleteLocal();
      await _storage.deleteAll();
    } finally {
      if (mounted) {
        setState(() {
          _record = null;
          _account = null;
          _storedPin = null;
          _lastSyncedAt = null;
          _biometricEnabled = false;
          _phase = _Phase.onboarding;
        });
      }
    }
  }

  // Called when the patient closes the QR screen — re-fetches from the backend
  // so any consultation the doctor just wrote is immediately visible, then
  // re-encrypts with the master key to take back ownership from the session-key blob.
  Future<void> _onQrClosed() async {
    final handle = await _masterKey.unsealForUse();
    try {
      final updated = await _recordStore.read(
        handle,
        _account!.anonymousUuid,
        forceCloud: true,
      );
      // Update UI immediately — don't let a write failure block the display.
      if (mounted) setState(() => _record = updated);
      // Re-encrypt with master key — takes back ownership from session-key blob.
      try {
        await _recordStore.write(updated, handle, _account!.anonymousUuid);
        final now = DateTime.now().toUtc().toIso8601String();
        await _storage.write(key: _kLastSyncKey, value: now);
        if (mounted) setState(() => _lastSyncedAt = now);
      } on BackendUnavailable {
        // Offline — local write already happened inside write(); cloud retry later.
      }
    } on BackendUnavailable {
      // offline — keep existing record
    } catch (e, st) {
      // ignore: avoid_print
      print('[_onQrClosed] ERROR: $e\n$st');
    } finally {
      await _masterKey.wipeHandle(handle);
    }
  }

  Future<void> _onUpdateRecord(MedicalRecord record) async {
    setState(() => _record = record);
    final handle = await _masterKey.unsealForUse();
    try {
      try {
        await _recordStore.write(record, handle, _account!.anonymousUuid);
        final now = DateTime.now().toUtc().toIso8601String();
        await _storage.write(key: _kLastSyncKey, value: now);
        if (mounted) setState(() => _lastSyncedAt = now);
      } on BackendUnavailable {
        // local write succeeded; sync will retry when backend is available
      }
    } finally {
      await _masterKey.wipeHandle(handle);
    }
  }

  // ── Controllers ──────────────────────────────────────────────────────────────

  _DevQrController _buildQrController() => _DevQrController(
        masterKey: _masterKey,
        accountStore: _accountStore,
        recordStore: _recordStore,
        tokenService: AccessTokenService(
          crypto: const _DevCryptoCore(),
          recordStore: _recordStore,
          client: BackendClient(_kBackendBaseUrl),
        ),
        backendUrl: _kQrBackendUrl,
      );

  ScanService _buildScanService() => ScanService(
        crypto: const _DevCryptoCore(),
        client: BackendClient(_kBackendBaseUrl),
      );

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: KeyedSubtree(
        key: ValueKey(_phase),
        child: _buildPhase(),
      ),
    );
  }

  Widget _buildPhase() {
    return switch (_phase) {
      _Phase.splash => SplashScreen(onDone: _onSplashDone),
      _Phase.probing || _Phase.loading => const _LoadingScreen(),
      _Phase.onboarding => OnboardingScreen(
          onComplete: _onOnboardingDone,
          controller: OnboardingController(
            masterKey: _masterKey,
            accountStore: _accountStore,
          ),
        ),
      _Phase.pinCreate => PinScreen(
          mode: PinMode.create,
          onSuccess: _onPinCreated,
        ),
      _Phase.locked => PinScreen(
          mode: PinMode.verify,
          storedPin: _storedPin ?? '',
          onSuccess: _onPinVerified,
          onBiometric: _biometricEnabled
              ? () async {
                  final ok = await _biometricService
                      .authenticate('Déverrouiller HealthTech');
                  if (ok && mounted) await _onPinVerified('');
                }
              : null,
        ),
      _Phase.home => MainShell(
          record: _record!,
          account: _account!,
          qrController: _buildQrController(),
          scanService: _buildScanService(),
          onLock: _onLock,
          backendUrl: _kBackendBaseUrl,
          onWillPauseForPicker: _onWillPauseForPicker,
          onUpdateRecord: _onUpdateRecord,
          onQrClosed: _onQrClosed,
          storedPin: _storedPin,
          onChangePin: _onChangePin,
          biometricService: _biometricService,
          biometricEnabled: _biometricEnabled,
          lastSyncedAt: _lastSyncedAt,
          onManualSync: _onManualSync,
          onDeleteAccount: _onDeleteAccount,
        ),
      _Phase.invalidated => _InvalidatedScreen(error: _loadError),
    };
  }
}

// ─── QrController that seeds an empty record on first generate() ─────────────

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
  Future<QrPayload> generate({QrMode mode = QrMode.readWrite}) async {
    if (!await _recordStore.exists()) {
      await _seedEmptyRecord();
    }
    return _inner.generate(mode: mode);
  }

  Future<void> _seedEmptyRecord() async {
    final handle = await _masterKey.unsealForUse();
    try {
      final account = await _accountStore.read(handle);
      final now = DateTime.now().toUtc().toIso8601String();
      await _recordStore.write(
        MedicalRecord(
          patientId: account.anonymousUuid,
          createdAt: now,
          updatedAt: now,
        ),
        handle,
        account.anonymousUuid,
      );
    } finally {
      await _masterKey.wipeHandle(handle);
    }
  }
}

// ─── Helper screens ───────────────────────────────────────────────────────────

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.white,
      body: Center(
        child: CircularProgressIndicator(color: AppColors.primary700),
      ),
    );
  }
}

class _InvalidatedScreen extends StatelessWidget {
  const _InvalidatedScreen({this.error});
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outlined,
                  size: 64, color: AppColors.neutral500),
              const SizedBox(height: 24),
              Text(
                'Clé de chiffrement invalidée',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                error ??
                    '[DEV] Supprimez les fichiers .sealed dans le répertoire '
                        'de données de l\'application pour réinitialiser.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
