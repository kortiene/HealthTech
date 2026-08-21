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

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_io.dart'
    show ExternalLibrary;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'src/cloud/backend_client.dart'
    show BackendClient, BackendUnavailable, BlobNotFound;
import 'src/cloud/media_client.dart';
import 'src/cloud/network_retry.dart';
import 'src/design/app_theme.dart';
import 'src/doctor/scan_service.dart';
import 'src/qr/access_token.dart';
import 'src/qr/media_migration.dart';
import 'src/record/media_cipher.dart';
import 'src/record/medical_record.dart';
import 'src/record/medical_record_store.dart';
import 'src/rust/crypto_core_bindings.dart';
import 'src/rust/frb_generated.dart';
import 'src/secure/biometric_service.dart';
import 'src/secure/keystore_channel.dart';
import 'src/secure/master_key_service.dart';
import 'src/secure/patient_account.dart';
import 'src/secure/sealed_blob_store.dart';
import 'src/ui/auth/pin_screen.dart';
import 'src/ui/main_shell.dart';
import 'src/ui/onboarding_screen.dart';
import 'src/ui/splash_screen.dart';

const String _kBackendBaseUrl =
    'https://healthtech-api.staging.go.incubtek.com';
const String _kPinKey = 'patient_pin';
const String _kLastSyncKey = 'last_sync_at';
const String _kAutoShareMediaKey = 'auto_share_media';
const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // On iOS crypto-core is a static library linked into the app binary —
  // symbols are already in the process, so DynamicLibrary.open() would fail.
  // Use ExternalLibrary.process() to tell FRB to look up symbols via dlsym.
  if (Platform.isIOS) {
    await RustLib.init(
        externalLibrary: ExternalLibrary.process(iKnowHowToUseIt: true));
  } else {
    await RustLib.init();
  }
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
  final _crypto = const FrbCryptoCore();
  late final PatientAccountStore _accountStore;
  late final MedicalRecordStore _recordStore;
  late final MediaClient _mediaClient;
  final _mediaCipher = const MediaCipher(FrbCryptoCore());

  // Session key kept in RAM after QR close so the home sync button can retry
  // decryption if the doctor writes notes after the patient leaves QR screen.
  // No expiry timer — the key lives until a new QR session is generated or
  // the app process is killed (swipe from recents / phone restart). This
  // matches the master key's own lifetime and avoids arbitrary cutoffs that
  // break real consultations longer than any fixed duration.
  Uint8List? _pendingSessionKey;
  bool _isSyncing = false;

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
    _mediaClient = MediaClient(
      _kBackendBaseUrl,
      retry: const NetworkRetry(maxAttempts: 3, baseDelayMs: 500),
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
            // Download url:null media that the doctor uploaded (#152).
            final (downloaded, toDelete) = await downloadPendingMedia(
              merged,
              _mediaClient,
              _mediaCipher,
            );
            merged = downloaded;
            if (!identical(merged, local)) {
              // Persist merged record so next restart reads it locally.
              try {
                await _recordStore.write(
                  merged,
                  handle,
                  _account!.anonymousUuid,
                );
              } on BackendUnavailable {
                // Local write succeeded; cloud sync will retry.
              }
              // Delete from backend only after local persistence (#152).
              for (final uuid in toDelete) {
                try {
                  await _mediaClient.deleteMedia(uuid);
                } catch (_) {
                  // Best-effort — backend retention policy (#114) cleans up.
                }
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

  // Merges doctor additions (new consultations / treatment changes / amendments /
  // ordonnance line statuses) from the session blob into the patient's local
  // record, without touching media URLs.
  // The session blob's URLs are all null (sanitised by AccessTokenService) —
  // [local] is always used as the base to preserve file:// references.
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
    // Doctor amendments are append-only: session will have a longer list.
    // Ordonnance line statuses: take the session value when it differs from local.
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
        final sessionOrd =
            sessionC.ordonnances.where((o) => o.id == localOrd.id).firstOrNull;
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
        media: localC.media, // always keep local URLs — session has null
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

  void _wipePendingSession() {
    _pendingSessionKey?.fillRange(0, _pendingSessionKey!.length, 0);
    _pendingSessionKey = null;
  }

  // Core cloud sync: downloads from backend, decrypts with sessionKey (or
  // master key if null), merges doctor additions into local record, restores
  // master-key blob on backend. Returns true when local record was updated.
  // Does NOT wipe sessionKey — caller manages its lifecycle.
  // onSessionExpired: called when cloud decryption fails AND sessionKey is
  // null — signals the caller that a re-scan is needed.
  Future<bool> _syncFromCloud({
    Uint8List? sessionKey,
    void Function()? onSessionExpired,
  }) async {
    final savedRecord = _record;
    if (savedRecord == null || _account == null) return false;
    final handle = await _masterKey.unsealForUse();
    try {
      var toWrite = savedRecord;
      final toDelete = <String>[];
      bool gotNewData = false;
      bool readFromCloud = false;
      try {
        MasterKeyHandle? sessionHandle;
        if (sessionKey != null) {
          sessionHandle = await _crypto.handleFromUnsealed(sessionKey);
        }
        try {
          final fromCloud = await _recordStore.read(
            sessionHandle ?? handle,
            _account!.anonymousUuid,
            forceCloud: true,
          );
          readFromCloud = true;
          final merged = _mergeSessionIntoLocal(savedRecord, fromCloud);
          gotNewData = !identical(merged, savedRecord);
          toWrite = merged;
          // Download url:null media that the doctor uploaded (#152).
          final (downloaded, pending) = await downloadPendingMedia(
            toWrite,
            _mediaClient,
            _mediaCipher,
          );
          toWrite = downloaded;
          toDelete.addAll(pending);
        } finally {
          if (sessionHandle != null) await _crypto.wipe(sessionHandle);
        }
      } on BackendUnavailable {
        // Offline — skip write-back below.
      } catch (e, st) {
        // DecryptError or JSON parse failure — fall back to local record.
        // Do NOT write to the backend: the cloud blob may be the doctor's
        // K_session blob that we simply cannot decrypt yet (wrong/missing key).
        // Overwriting it would permanently destroy the doctor's notes.
        debugPrint('[sync] cloud read failed: $e\n$st');
        // No session key in RAM → app was restarted mid-consultation. Notify
        // the caller so it can ask the patient to re-scan the QR.
        if (sessionKey == null) onSessionExpired?.call();
      }
      if (!identical(toWrite, savedRecord) && mounted) {
        setState(() => _record = toWrite);
      }
      // Restore canonical master-key blob on the backend only when the cloud
      // read succeeded. Skipping when readFromCloud=false preserves any doctor
      // session blob that this sync could not decrypt.
      if (readFromCloud) {
        try {
          await _recordStore.write(toWrite, handle, _account!.anonymousUuid);
          final now = DateTime.now().toUtc().toIso8601String();
          await _storage.write(key: _kLastSyncKey, value: now);
          if (mounted) setState(() => _lastSyncedAt = now);
        } on BackendUnavailable {
          // Offline — local record intact; cloud sync will restore on next connect.
        }
      }
      for (final uuid in toDelete) {
        try {
          await _mediaClient.deleteMedia(uuid);
        } catch (_) {
          // Best-effort — backend retention policy (#114) cleans up.
        }
      }
      return gotNewData;
    } finally {
      await _masterKey.wipeHandle(handle);
    }
  }

  // Called by QrScreen (via MainShell) when the patient closes the QR screen.
  // sessionKey: copy of K_session made before dispose() wipes it. Non-null
  // even when the display countdown reached zero — the key bytes are preserved
  // in QrScreen until dispose() (fix #170 bug 1).
  Future<void> _onQrClosed(Uint8List? sessionKey) async {
    // Store the session key so the home sync button can decrypt the doctor's
    // blob regardless of how long the consultation lasts. No expiry timer —
    // the key lives until a new QR session is started or the process is killed.
    if (sessionKey != null) {
      _wipePendingSession();
      _pendingSessionKey = Uint8List.fromList(sessionKey);
      sessionKey.fillRange(0, sessionKey.length, 0);
    }
    if (mounted) setState(() => _isSyncing = true);
    try {
      // Do not wipe after gotData=true: the doctor may make a second change
      // during the same consultation and the patient must be able to sync again.
      await _syncFromCloud(sessionKey: _pendingSessionKey);
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  // Home screen "Récupérer les notes" button handler.
  // Uses the pending session key (RAM-only, no expiry) to decrypt the doctor's
  // session blob. Key is cleared only when a new QR session is generated.
  Future<void> _onHomeSync() async {
    if (_isSyncing || _record == null || _account == null) return;
    if (mounted) setState(() => _isSyncing = true);
    try {
      // Do not wipe after gotData=true: the doctor may make a second change
      // during the same consultation and the patient must be able to sync again.
      await _syncFromCloud(
        sessionKey: _pendingSessionKey,
        onSessionExpired: () {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Session expirée — re-scannez le QR du médecin pour récupérer les nouvelles notes.',
              ),
              duration: Duration(seconds: 7),
            ),
          );
        },
      );
    } finally {
      if (mounted) setState(() => _isSyncing = false);
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
          onHomeSync: _onHomeSync,
          isSyncing: _isSyncing,
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
