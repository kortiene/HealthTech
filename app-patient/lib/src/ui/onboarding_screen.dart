// Onboarding screen — encrypted account creation (issue #13 / US-1.1).
//
// Flow:
//  1. Consent step  — display CGU / privacy policy (#7), require explicit tap.
//  2. Identity step — CMU number + phone number inputs.
//  3. Account creation — master key generated (#11), identity encrypted (#10),
//                        stored locally.  NO network call occurs during this
//                        flow; the server never sees CMU or phone in clear.
//
// SECURITY: CMU and phone are Ivorian PII.  They are passed directly to
// PatientAccountStore.write(), which encrypts them with AES-256-GCM before
// touching any storage.  They are never logged, never passed to the backend,
// and never appear in Dart debug output.

import 'package:flutter/material.dart';

import '../legal/consent_model.dart';
import '../rust/crypto_core_bindings.dart';
import '../secure/keystore_channel.dart';
import '../secure/master_key_service.dart';
import '../secure/patient_account.dart';
import '../secure/sealed_blob_store.dart';

/// Generates a random UUID v4 using the platform clock as entropy source.
///
/// The UUID is an anonymous correlation handle (not a secret): it identifies
/// the patient's slot on the backend without linking to CMU or phone.
String _generateUuidV4() {
  final rng = DateTime.now().microsecondsSinceEpoch;
  final b = List<int>.generate(16, (i) => (rng >> (i * 3)) & 0xFF);
  b[6] = (b[6] & 0x0F) | 0x40; // version 4
  b[8] = (b[8] & 0x3F) | 0x80; // variant RFC 4122
  String hex(int v) => v.toRadixString(16).padLeft(2, '0');
  return '${hex(b[0])}${hex(b[1])}${hex(b[2])}${hex(b[3])}-'
      '${hex(b[4])}${hex(b[5])}-'
      '${hex(b[6])}${hex(b[7])}-'
      '${hex(b[8])}${hex(b[9])}-'
      '${hex(b[10])}${hex(b[11])}${hex(b[12])}${hex(b[13])}${hex(b[14])}${hex(b[15])}';
}

/// Controller for [OnboardingScreen] — encapsulates all non-UI logic.
///
/// Extracted so unit tests can drive the flow with injected fakes without
/// rendering the full Flutter widget tree.
class OnboardingController {
  OnboardingController({
    MasterKeyService? masterKey,
    PatientAccountStore? accountStore,
    String Function()? uuidFactory,
    String Function()? nowFactory,
  })  : _masterKey = masterKey ?? const MasterKeyService(),
        _accountStore = accountStore ??
            PatientAccountStore(
              crypto: const FrbCryptoCore(),
              blobStore: FileSealedBlobStore(
                fileName: 'patient_account.sealed',
              ),
            ),
        _uuidFactory = uuidFactory ?? _generateUuidV4,
        _nowFactory =
            nowFactory ?? (() => DateTime.now().toUtc().toIso8601String());

  final MasterKeyService _masterKey;
  final PatientAccountStore _accountStore;
  final String Function() _uuidFactory;
  final String Function() _nowFactory;

  /// Create the encrypted patient account from [cmuNumber] and [phone].
  ///
  /// Generates the master key (idempotent), unseals it for a single
  /// encrypt call, then wipes the clear handle.  The [cmuNumber] and [phone]
  /// values are consumed by this call and must not be retained by the caller.
  ///
  /// Throws [KeystoreUnavailable] or [KeyInvalidated] on hardware failure.
  Future<void> createAccount({
    required String cmuNumber,
    required String phone,
    required ConsentRecord consent,
  }) async {
    // Idempotent key generation — no-op if the key already exists.
    await _masterKey.ensureMasterKey();

    final handle = await _masterKey.unsealForUse();
    try {
      final account = PatientAccount(
        anonymousUuid: _uuidFactory(),
        cmuNumber: cmuNumber,
        phone: phone,
        consent: consent,
        createdAt: _nowFactory(),
      );
      await _accountStore.write(account, handle);
    } finally {
      // Wipe the clear key even if encryption throws.
      await _masterKey.wipeHandle(handle);
    }
  }

  /// Whether a patient account already exists on this device.
  Future<bool> get accountExists => _accountStore.exists();
}

// ─── Widget ───────────────────────────────────────────────────────────────────

/// Multi-step onboarding screen: consent → identity → account creation.
///
/// On completion [onComplete] is called; callers should navigate to the main
/// app screen.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onComplete,
    this.controller,
  });

  final VoidCallback onComplete;

  /// Injectable for tests; defaults to a production [OnboardingController]
  /// created in [State.initState].
  final OnboardingController? controller;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Step { consent, identity, creating, done }

class _OnboardingScreenState extends State<OnboardingScreen> {
  late final OnboardingController _ctrl;
  _Step _step = _Step.consent;
  final _cmuController = TextEditingController();
  final _phoneController = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? OnboardingController();
  }

  @override
  void dispose() {
    _cmuController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _onConsentAccepted() {
    setState(() => _step = _Step.identity);
  }

  Future<void> _onIdentitySubmit() async {
    final cmu = _cmuController.text.trim();
    final phone = _phoneController.text.trim();

    if (cmu.isEmpty || phone.isEmpty) {
      setState(() => _error = 'Veuillez remplir tous les champs.');
      return;
    }

    setState(() {
      _step = _Step.creating;
      _error = null;
    });

    try {
      final consent = ConsentRecord(
        version: consentBundleVersion,
        acceptedAt: DateTime.now().toUtc().toIso8601String(),
      );
      await _ctrl.createAccount(
        cmuNumber: cmu,
        phone: phone,
        consent: consent,
      );
      setState(() => _step = _Step.done);
      widget.onComplete();
    } on KeystoreUnavailable catch (e) {
      setState(() {
        _step = _Step.identity;
        _error = 'Trousseau indisponible : ${e.message}';
      });
    } catch (_) {
      setState(() {
        _step = _Step.identity;
        _error = 'Erreur lors de la création du compte. Réessayez.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Création de compte')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: switch (_step) {
            _Step.consent => _ConsentStep(onAccepted: _onConsentAccepted),
            _Step.identity => _IdentityStep(
                cmuController: _cmuController,
                phoneController: _phoneController,
                error: _error,
                onSubmit: _onIdentitySubmit,
              ),
            _Step.creating => const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Création du compte…'),
                  ],
                ),
              ),
            _Step.done => const Center(child: Text('Compte créé.')),
          },
        ),
      ),
    );
  }
}

// ─── Step sub-widgets ─────────────────────────────────────────────────────────

class _ConsentStep extends StatelessWidget {
  const _ConsentStep({required this.onAccepted});

  final VoidCallback onAccepted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Politique de confidentialité',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        const Expanded(
          child: SingleChildScrollView(
            child: Text(
              'HealthTech respecte votre vie privée conformément à la loi '
              'ivoirienne n°2013-450 et aux recommandations de l\'ARTCI.\n\n'
              'Vos données médicales sont chiffrées sur votre appareil avant '
              'tout transfert. Nous ne stockons jamais vos informations en '
              'clair.\n\n'
              'En appuyant sur « J\'accepte », vous consentez à l\'utilisation '
              'de l\'application selon les Conditions Générales d\'Utilisation '
              'et la Politique de Confidentialité (version $consentBundleVersion).',
            ),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('consent_accept'),
          onPressed: onAccepted,
          child: const Text("J'accepte"),
        ),
      ],
    );
  }
}

class _IdentityStep extends StatelessWidget {
  const _IdentityStep({
    required this.cmuController,
    required this.phoneController,
    required this.error,
    required this.onSubmit,
  });

  final TextEditingController cmuController;
  final TextEditingController phoneController;
  final String? error;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Vos identifiants',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'Ces informations sont chiffrées sur votre appareil et ne sont '
          'jamais transmises en clair.',
          style: TextStyle(fontSize: 13),
        ),
        const SizedBox(height: 24),
        TextFormField(
          key: const Key('cmu_field'),
          controller: cmuController,
          decoration: const InputDecoration(
            labelText: 'Numéro CMU',
            hintText: 'Ex : CMU-2025-XXXXXX',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.text,
          textInputAction: TextInputAction.next,
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: const Key('phone_field'),
          controller: phoneController,
          decoration: const InputDecoration(
            labelText: 'Numéro de téléphone',
            hintText: 'Ex : +225 07 00 00 00 00',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => onSubmit(),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          key: const Key('create_account'),
          onPressed: onSubmit,
          child: const Text('Créer mon compte'),
        ),
      ],
    );
  }
}
