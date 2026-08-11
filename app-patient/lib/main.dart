// HealthTech — patient app entry point.
//
// CRYPTO BOUNDARY: NO cipher code in Dart. AES-256-GCM / PBKDF2 / master-key
// generation all happen in the shared Rust crypto-core via flutter_rust_bridge.
// Dart holds only what the UI renders.
//
// Auth flow:
//   SplashScreen → probeState()
//     absent     → OnboardingScreen → PinScreen(create) → load data → MainShell
//     present    → PinScreen(verify) → load data → MainShell
//     invalidated → recovery stub (#12)
//
//   On app pause → lock (show PinScreen again on resume).

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'src/cloud/backend_client.dart'
    show BackendClient, BackendUnavailable, BlobNotFound;
import 'src/cloud/media_client.dart';
import 'src/design/app_theme.dart';
import 'src/doctor/scan_service.dart';
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

const String _kBackendBaseUrl = 'https://api.healthtech.ci';
const String _kPinKey = 'patient_pin';
const String _kLastSyncKey = 'last_sync_at';
const String _kAutoShareMediaKey = 'auto_share_media';
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
      title: 'HealthTech',
      theme: AppTheme.light,
      debugShowCheckedModeBanner: false,
      home: const _AppRoot(),
    );
  }
}

// ── Phase FSM ─────────────────────────────────────────────────────────────────

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
  bool _autoShareMedia = false;

  final _masterKey = const MasterKeyService();
  late final PatientAccountStore _accountStore;
  late final MedicalRecordStore _recordStore;

  @override
  void initState() {
    super.initState();
    _accountStore = const PatientAccountStore(
      crypto: FrbCryptoCore(),
      blobStore: FileSealedBlobStore(fileName: 'patient_account.sealed'),
    );
    _recordStore = MedicalRecordStore(
      crypto: const FrbCryptoCore(),
      client: BackendClient(_kBackendBaseUrl),
      localStore: const FileSealedBlobStore(fileName: 'medical_record.sealed'),
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
          // Account might not exist if onboarding was interrupted before it completed.
          if (!await _accountStore.exists()) {
            if (!mounted) return;
            setState(() => _phase = _Phase.onboarding);
            return;
          }
          final pin = await _storage.read(key: _kPinKey);
          _biometricEnabled = await _biometricService.isEnabled();
          _lastSyncedAt = await _storage.read(key: _kLastSyncKey);
          _autoShareMedia =
              await _storage.read(key: _kAutoShareMediaKey) == 'true';
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
          // Read local first — always safe (canonical, file:// URLs intact).
          final local =
              await _recordStore.read(handle, _account!.anonymousUuid);
          // Best-effort cloud merge: catches doctor notes written after the
          // patient closed QR early (before _onQrClosed could pull them).
          // Dev (XOR-0x5A): cloud read always succeeds.
          // Prod (AES-GCM): DecryptError if session blob still live → ignore.
          var merged = local;
          try {
            final cloud = await _recordStore.read(
              handle,
              _account!.anonymousUuid,
              forceCloud: true,
            );
            merged = _mergeSessionIntoLocal(local, cloud);
            if (!identical(merged, local)) {
              // Persist merged record so next restart reads it locally.
              try {
                await _recordStore.write(
                    merged, handle, _account!.anonymousUuid);
              } on BackendUnavailable {
                // Local cache already updated by _recordStore.read above.
              }
            }
          } on BackendUnavailable {
            // Offline — local record is authoritative.
          } catch (_) {
            // Prod: DecryptError or other issue — local record is fine.
          }
          _record = merged;
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

  // Merges doctor additions (new consultations / treatment changes) from the
  // session blob into the patient's local record, without touching media URLs.
  // The session blob's URLs are all null (sanitised by AccessTokenService) —
  // [local] is always used as the base to preserve file:// references.
  MedicalRecord _mergeSessionIntoLocal(
    MedicalRecord local,
    MedicalRecord session,
  ) {
    final localIds = {for (final c in local.consultations) c.id};
    final newConsults =
        session.consultations.where((c) => !localIds.contains(c.id)).toList();

    final localTreatMap = {for (final t in local.treatments) t.id: t};
    final mergedTreatments = local.treatments.map((t) {
      final s = session.treatments.where((x) => x.id == t.id).firstOrNull;
      return s == null ? t : t.copyWith(status: s.status, endedAt: s.endedAt);
    }).toList()
      ..addAll(
        session.treatments.where((t) => !localTreatMap.containsKey(t.id)),
      );

    if (newConsults.isEmpty &&
        !session.treatments.any((t) => !localTreatMap.containsKey(t.id))) {
      return local;
    }
    return local.copyWith(
      consultations: [...local.consultations, ...newConsults],
      treatments: mergedTreatments,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> _onQrClosed() async {
    final savedRecord = _record;
    if (savedRecord == null || _account == null) return;
    final handle = await _masterKey.unsealForUse();
    try {
      // Try to pick up doctor additions from the session blob.
      // Base is always savedRecord to preserve file:// media URLs —
      // the session blob has null URLs (sanitised for the doctor).
      // In dev (XOR-0x5A key-agnostic): decrypt succeeds → merge applied.
      // In prod (AES-GCM): decrypt throws with wrong key → fallback to local.
      var toWrite = savedRecord;
      try {
        final fromCloud = await _recordStore.read(
          handle,
          _account!.anonymousUuid,
          forceCloud: true,
        );
        toWrite = _mergeSessionIntoLocal(savedRecord, fromCloud);
      } on BackendUnavailable {
        // Offline — write savedRecord back as-is.
      } catch (_) {
        // Prod decrypt error → write savedRecord back as-is.
      }
      if (!identical(toWrite, savedRecord) && mounted) {
        setState(() => _record = toWrite);
      }
      // Restore canonical master-key blob on the backend.
      try {
        await _recordStore.write(toWrite, handle, _account!.anonymousUuid);
        final now = DateTime.now().toUtc().toIso8601String();
        await _storage.write(key: _kLastSyncKey, value: now);
        if (mounted) setState(() => _lastSyncedAt = now);
      } on BackendUnavailable {
        // Offline — local record intact; cloud sync will restore on next connect.
      }
    } finally {
      await _masterKey.wipeHandle(handle);
    }
  }

  Future<void> _onAutoShareMediaChanged(bool value) async {
    setState(() => _autoShareMedia = value);
    await _storage.write(
      key: _kAutoShareMediaKey,
      value: value ? 'true' : 'false',
    );
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
        // local write succeeded; cloud sync will retry
      }
    } finally {
      await _masterKey.wipeHandle(handle);
    }
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
      // Best-effort cloud deletion (ignore network errors)
      final uuid = _account?.anonymousUuid;
      if (uuid != null) {
        try {
          await BackendClient(_kBackendBaseUrl).delete(uuid);
        } on BackendUnavailable {
          // Offline — local data still cleared
        } on BlobNotFound {
          // Already gone from server
        }
      }
      // Erase local blobs
      await _recordStore.deleteLocal();
      // Erase all secure storage (PIN, biometric flag, last sync)
      await _storage.deleteAll();
    } finally {
      // Always reset FSM to onboarding, regardless of cloud/local errors
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

  // ── Controllers ──────────────────────────────────────────────────────────────

  DefaultQrController _buildQrController() => DefaultQrController(
        masterKey: _masterKey,
        accountStore: _accountStore,
        tokenService: AccessTokenService(
          crypto: const FrbCryptoCore(),
          recordStore: _recordStore,
          client: BackendClient(_kBackendBaseUrl),
          mediaClient: MediaClient(_kBackendBaseUrl),
        ),
        backendUrl: _kBackendBaseUrl,
      );

  ScanService _buildScanService() => ScanService(
        crypto: const FrbCryptoCore(),
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
      _Phase.onboarding => OnboardingScreen(onComplete: _onOnboardingDone),
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
          autoShareMedia: _autoShareMedia,
          onAutoShareMediaChanged: _onAutoShareMediaChanged,
          onAddDocument: (doc) => _onUpdateRecord(
            _record!.copyWith(
              documents: [..._record!.documents, doc],
              updatedAt: DateTime.now().toUtc().toIso8601String(),
            ),
          ),
          onRemoveDocument: (doc) => _onUpdateRecord(
            _record!.copyWith(
              documents:
                  _record!.documents.where((d) => d.id != doc.id).toList(),
              updatedAt: DateTime.now().toUtc().toIso8601String(),
            ),
          ),
        ),
      _Phase.invalidated => _InvalidatedScreen(
          error: _loadError,
          onReset: () async {
            await _storage.deleteAll();
            if (mounted) setState(() => _phase = _Phase.onboarding);
          },
        ),
    };
  }
}

// ── Helper screens ────────────────────────────────────────────────────────────

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
  const _InvalidatedScreen({this.error, this.onReset});
  final String? error;
  final Future<void> Function()? onReset;

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
                'Accès non disponible',
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                error ??
                    'La clé de chiffrement est inaccessible. '
                        'Vous pouvez recréer un nouveau profil — '
                        'les données précédentes ne seront pas récupérables.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              if (onReset != null) ...[
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: onReset,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary700,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 14),
                  ),
                  child: const Text('Recréer mon profil'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
