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
import 'src/cloud/media_client.dart';
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
  bool _autoShareMedia = false;

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
          // XOR-0x5A stub: cloud read always succeeds regardless of key.
          var merged = local;
          try {
            final cloud = await _recordStore.read(
              handle,
              _account!.anonymousUuid,
              forceCloud: true,
            );
            merged = _mergeSessionIntoLocal(local, cloud);
            if (!identical(merged, local)) {
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

  MedicalRecord _mergeSessionIntoLocal(
    MedicalRecord local,
    MedicalRecord session,
  ) {
    // ── new consultations ────────────────────────────────────────────────────
    final localIds = {for (final c in local.consultations) c.id};
    final newConsults =
        session.consultations.where((c) => !localIds.contains(c.id)).toList();

    // ── treatments ───────────────────────────────────────────────────────────
    final localTreatMap = {for (final t in local.treatments) t.id: t};
    final mergedTreatments = local.treatments.map((t) {
      final s = session.treatments.where((x) => x.id == t.id).firstOrNull;
      return s == null ? t : t.copyWith(status: s.status, endedAt: s.endedAt);
    }).toList()
      ..addAll(
        session.treatments.where((t) => !localTreatMap.containsKey(t.id)),
      );

    // ── allergies ────────────────────────────────────────────────────────────
    final localAllergyKeys = {
      for (final a in local.allergies) a.substance.toLowerCase(),
    };
    final newAllergies = session.allergies
        .where((a) => !localAllergyKeys.contains(a.substance.toLowerCase()))
        .toList();

    // ── conditions ───────────────────────────────────────────────────────────
    final localConditionKeys = {
      for (final c in local.chronicConditions) c.name.toLowerCase(),
    };
    final newConditions = session.chronicConditions
        .where((c) => !localConditionKeys.contains(c.name.toLowerCase()))
        .toList();

    // ── amendments + ordonnance line statuses on existing consultations (#144)
    final sessionById = {for (final c in session.consultations) c.id: c};
    var existingChanged = false;
    final mergedConsults = local.consultations.map((localC) {
      final sessionC = sessionById[localC.id];
      if (sessionC == null) return localC;

      // amendments: pick up any that the doctor appended
      final newAmendments =
          sessionC.amendments.length > localC.amendments.length
              ? sessionC.amendments.sublist(localC.amendments.length)
              : <ConsultationAmendment>[];

      // ordonnance line statuses
      var ordsChanged = false;
      final mergedOrdonnances = localC.ordonnances.map((localOrd) {
        final sessionOrd = sessionC.ordonnances
            .where((o) => o.id == localOrd.id)
            .firstOrNull;
        if (sessionOrd == null) return localOrd;
        var lineChanged = false;
        final mergedLines = List<OrdonnanceLine>.generate(
          localOrd.lines.length,
          (i) {
            if (i >= sessionOrd.lines.length) return localOrd.lines[i];
            final sLine = sessionOrd.lines[i];
            final lLine = localOrd.lines[i];
            if (sLine.status != null && sLine.status != lLine.status) {
              lineChanged = true;
              return OrdonnanceLine(
                medication: lLine.medication,
                dose: lLine.dose,
                frequency: lLine.frequency,
                durationDays: lLine.durationDays,
                notes: lLine.notes,
                status: sLine.status,
              );
            }
            return lLine;
          },
        );
        if (!lineChanged) return localOrd;
        ordsChanged = true;
        return Ordonnance(
          id: localOrd.id,
          treatmentId: localOrd.treatmentId,
          label: localOrd.label,
          createdAt: localOrd.createdAt,
          lines: mergedLines,
        );
      }).toList();

      if (newAmendments.isEmpty && !ordsChanged) return localC;
      existingChanged = true;
      return Consultation(
        id: localC.id,
        date: localC.date,
        practitionerRef: localC.practitionerRef,
        summary: localC.summary,
        prescription: localC.prescription,
        ordonnances: mergedOrdonnances,
        imageUrls: localC.imageUrls,
        media: localC.media,
        createdAt: localC.createdAt,
        amendments: [...localC.amendments, ...newAmendments],
      );
    }).toList();

    // ── early return ─────────────────────────────────────────────────────────
    if (newConsults.isEmpty &&
        !session.treatments.any((t) => !localTreatMap.containsKey(t.id)) &&
        newAllergies.isEmpty &&
        newConditions.isEmpty &&
        !existingChanged) {
      return local;
    }
    return local.copyWith(
      consultations: [...mergedConsults, ...newConsults],
      treatments: mergedTreatments,
      allergies: [...local.allergies, ...newAllergies],
      chronicConditions: [...local.chronicConditions, ...newConditions],
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
  }

  Future<void> _onQrClosed() async {
    final savedRecord = _record;
    if (savedRecord == null || _account == null) return;
    final handle = await _masterKey.unsealForUse();
    try {
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
      try {
        await _recordStore.write(toWrite, handle, _account!.anonymousUuid);
        final now = DateTime.now().toUtc().toIso8601String();
        await _storage.write(key: _kLastSyncKey, value: now);
        if (mounted) setState(() => _lastSyncedAt = now);
      } on BackendUnavailable {
        // Offline — local record intact.
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
          mediaClient: MediaClient(_kBackendBaseUrl),
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
  Future<QrPayload> generate({
    QrMode mode = QrMode.readWrite,
    bool shareMedia = false,
  }) async {
    if (!await _recordStore.exists()) {
      await _seedEmptyRecord();
    }
    return _inner.generate(mode: mode, shareMedia: shareMedia);
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
