// Onboarding screen — encrypted account creation (issue #13 / US-1.1).
//
// Flow:
//  1. Consent step  — display CGU / privacy policy (#7), require explicit tap.
//  2. Identity step — CMU number + phone number inputs.
//  3. Creating      — master key generated (#11), identity encrypted (#10),
//                     stored locally.  NO network call occurs during this flow;
//                     the server never sees CMU or phone in clear.
//
// SECURITY: CMU and phone are Ivorian PII.  They are passed directly to
// PatientAccountStore.write(), which encrypts them with AES-256-GCM before
// touching any storage.  They are never logged, never passed to the backend,
// and never appear in Dart debug output.

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../design/app_theme.dart';
import '../legal/consent_model.dart';
import '../rust/crypto_core_bindings.dart';
import '../secure/keystore_channel.dart';
import '../secure/master_key_service.dart';
import '../secure/patient_account.dart';
import '../secure/sealed_blob_store.dart';

String _generateUuidV4() {
  final rng = DateTime.now().microsecondsSinceEpoch;
  final b = List<int>.generate(16, (i) => (rng >> (i * 3)) & 0xFF);
  b[6] = (b[6] & 0x0F) | 0x40;
  b[8] = (b[8] & 0x3F) | 0x80;
  String hex(int v) => v.toRadixString(16).padLeft(2, '0');
  return '${hex(b[0])}${hex(b[1])}${hex(b[2])}${hex(b[3])}-'
      '${hex(b[4])}${hex(b[5])}-'
      '${hex(b[6])}${hex(b[7])}-'
      '${hex(b[8])}${hex(b[9])}-'
      '${hex(b[10])}${hex(b[11])}${hex(b[12])}${hex(b[13])}${hex(b[14])}${hex(b[15])}';
}

/// Controller for [OnboardingScreen] — encapsulates all non-UI logic.
class OnboardingController {
  OnboardingController({
    MasterKeyService? masterKey,
    PatientAccountStore? accountStore,
    String Function()? uuidFactory,
    String Function()? nowFactory,
  })  : _masterKey = masterKey ?? const MasterKeyService(),
        _accountStore = accountStore ??
            const PatientAccountStore(
              crypto: FrbCryptoCore(),
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

  Future<void> createAccount({
    required String cmuNumber,
    required String phone,
    required ConsentRecord consent,
  }) async {
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
      await _masterKey.wipeHandle(handle);
    }
  }

  Future<bool> get accountExists => _accountStore.exists();
}

// ─── Widget ───────────────────────────────────────────────────────────────────

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({
    super.key,
    required this.onComplete,
    this.controller,
  });

  final VoidCallback onComplete;
  final OnboardingController? controller;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Step { consent, identity, creating }

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

  void _onConsentAccepted() => setState(() => _step = _Step.identity);

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
      await _ctrl.createAccount(cmuNumber: cmu, phone: phone, consent: consent);
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
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: switch (_step) {
            _Step.consent => _ConsentStep(
                key: const ValueKey('consent'),
                onAccepted: _onConsentAccepted,
              ),
            _Step.identity => _IdentityStep(
                key: const ValueKey('identity'),
                cmuController: _cmuController,
                phoneController: _phoneController,
                error: _error,
                onSubmit: _onIdentitySubmit,
                onBack: () => setState(() => _step = _Step.consent),
              ),
            _Step.creating => const _CreatingStep(key: ValueKey('creating')),
          },
        ),
      ),
    );
  }
}

// ─── Steps ────────────────────────────────────────────────────────────────────

class _ConsentStep extends StatelessWidget {
  const _ConsentStep({super.key, required this.onAccepted});
  final VoidCallback onAccepted;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xl),
          Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: AppColors.primary100,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Symbols.health_and_safety_rounded,
              size: 40,
              color: AppColors.primary700,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Bienvenue sur\nHealthTech',
            style: tt.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppColors.primary900,
              height: 1.15,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Votre dossier médical sécurisé,\ntoujours avec vous.',
            style: tt.bodyLarge?.copyWith(color: AppColors.neutral700),
          ),
          const SizedBox(height: AppSpacing.xl),
          _TrustCard(),
          const Spacer(),
          Text(
            'En continuant, vous acceptez nos Conditions Générales d\'Utilisation '
            'et la Politique de Confidentialité (v$consentBundleVersion).',
            style: tt.bodySmall?.copyWith(color: AppColors.neutral500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            key: const Key('consent_accept'),
            onPressed: onAccepted,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary700,
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.md),
              ),
            ),
            child: const Text('Créer mon compte', style: TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }
}

class _TrustCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final items = [
      (Symbols.lock_rounded, 'Chiffrement AES-256-GCM', 'Données protégées sur l\'appareil'),
      (Symbols.visibility_off_rounded, 'Zéro connaissance', 'Le serveur ne voit jamais vos données'),
      (Symbols.verified_rounded, 'Conforme ARTCI', 'Loi ivoirienne n°2013-450'),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary50,
        borderRadius: BorderRadius.circular(AppRadii.lg),
        border: Border.all(color: AppColors.primary100),
      ),
      child: Column(
        children: items.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary100,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: Icon(item.$1, size: 18, color: AppColors.primary700),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.$2,
                        style: tt.titleSmall?.copyWith(
                          color: AppColors.primary900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        item.$3,
                        style: tt.bodySmall?.copyWith(color: AppColors.neutral700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _IdentityStep extends StatelessWidget {
  const _IdentityStep({
    super.key,
    required this.cmuController,
    required this.phoneController,
    required this.error,
    required this.onSubmit,
    required this.onBack,
  });

  final TextEditingController cmuController;
  final TextEditingController phoneController;
  final String? error;
  final VoidCallback onSubmit;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          child: Row(
            children: [
              IconButton(
                onPressed: onBack,
                icon: const Icon(Symbols.arrow_back_rounded),
                color: AppColors.neutral700,
              ),
              Text('Vos identifiants', style: tt.titleLarge),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.primary50,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.primary100),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Symbols.shield_rounded,
                        size: 16,
                        color: AppColors.primary700,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Ces informations sont chiffrées sur votre appareil et '
                          'ne sont jamais transmises en clair.',
                          style: tt.bodySmall?.copyWith(
                            color: AppColors.primary900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                TextFormField(
                  key: const Key('cmu_field'),
                  controller: cmuController,
                  decoration: InputDecoration(
                    labelText: 'Numéro CMU',
                    hintText: 'CMU-2025-XXXXXX',
                    prefixIcon: const Icon(Symbols.badge_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                  ),
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.next,
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: AppSpacing.md),
                TextFormField(
                  key: const Key('phone_field'),
                  controller: phoneController,
                  decoration: InputDecoration(
                    labelText: 'Numéro de téléphone',
                    hintText: '+225 07 00 00 00 00',
                    prefixIcon: const Icon(Symbols.phone_rounded),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                  ),
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => onSubmit(),
                ),
                if (error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.allergyBg,
                      borderRadius: BorderRadius.circular(AppRadii.sm),
                    ),
                    child: Row(
                      children: [
                        const Icon(Symbols.error_rounded,
                            size: 16, color: AppColors.allergy),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            error!,
                            style: tt.bodySmall
                                ?.copyWith(color: AppColors.allergy),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  key: const Key('create_account'),
                  onPressed: onSubmit,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary700,
                    padding:
                        const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.md),
                    ),
                  ),
                  child: const Text(
                    'Créer mon compte',
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CreatingStep extends StatelessWidget {
  const _CreatingStep({super.key});

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 64,
              height: 64,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppColors.primary700,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Création du compte…',
              style: tt.titleLarge?.copyWith(color: AppColors.primary900),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Génération des clés de chiffrement\net sécurisation de votre dossier.',
              style: tt.bodyMedium?.copyWith(color: AppColors.neutral700),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
