import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../design/app_theme.dart';
import '../record/medical_record.dart';
import '../secure/biometric_service.dart';
import '../secure/patient_account.dart';
import 'auth/pin_screen.dart';
import 'widgets/hero_app_bar.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.record,
    required this.account,
    required this.onLock,
    this.onUpdateRecord,
    this.storedPin,
    this.onChangePin,
    this.biometricService,
    this.biometricEnabled = false,
  });

  final MedicalRecord record;
  final PatientAccount account;
  final VoidCallback onLock;
  final Future<void> Function(MedicalRecord)? onUpdateRecord;
  final String? storedPin;
  final Future<void> Function(String newPin)? onChangePin;
  final BiometricService? biometricService;
  final bool biometricEnabled;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _biometrics;
  bool _autoSync = false;

  @override
  void initState() {
    super.initState();
    _biometrics = widget.biometricEnabled;
  }

  static String _maskCmu(String cmu) {
    if (cmu.length <= 4) return '••••';
    final visible = cmu.substring(cmu.length - 4);
    return '••••••••$visible';
  }

  static String _maskPhone(String phone) {
    if (phone.length <= 4) return '••••';
    final visible = phone.substring(phone.length - 4);
    return '••••$visible';
  }

  static String _formatDate(String isoDate) {
    try {
      final d = DateTime.parse(isoDate);
      const months = [
        '',
        'jan.',
        'fév.',
        'mars',
        'avr.',
        'mai',
        'juin',
        'juil.',
        'août',
        'sep.',
        'oct.',
        'nov.',
        'déc.'
      ];
      return '${d.day} ${months[d.month]} ${d.year}';
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary50,
      body: CustomScrollView(
        slivers: [
          PatientHeroAppBar(
            record: widget.record,
            account: widget.account,
            collapsedTitle: 'Paramètres',
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // ── Identité ──────────────────────────────────────────────
                _Section(
                  title: 'Identité',
                  children: [
                    _SettingsTile(
                      icon: Symbols.badge_rounded,
                      iconBg: AppColors.primary100,
                      iconColor: AppColors.primary700,
                      title: 'Numéro CMU',
                      trailing: Text(
                        _maskCmu(widget.account.cmuNumber),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                              color: AppColors.neutral500,
                            ),
                      ),
                    ),
                    _SettingsTile(
                      icon: Symbols.phone_rounded,
                      iconBg: AppColors.primary100,
                      iconColor: AppColors.primary700,
                      title: 'Téléphone',
                      trailing: Text(
                        _maskPhone(widget.account.phone),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                              color: AppColors.neutral500,
                            ),
                      ),
                    ),
                    _SettingsTile(
                      icon: Symbols.calendar_month_rounded,
                      iconBg: AppColors.primary100,
                      iconColor: AppColors.primary700,
                      title: 'Compte créé le',
                      trailing: Text(
                        _formatDate(widget.account.createdAt),
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.neutral500),
                      ),
                    ),
                    _SettingsTile(
                      icon: Symbols.person_edit_rounded,
                      iconBg: AppColors.primary100,
                      iconColor: AppColors.primary700,
                      title: 'Modifier mon profil médical',
                      subtitle: 'Prénom · Âge · Sexe · Groupe sanguin',
                      onTap: widget.onUpdateRecord != null
                          ? () => _showEditProfile(context)
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // ── Sécurité ──────────────────────────────────────────────
                _Section(
                  title: 'Sécurité',
                  children: [
                    _SettingsTile(
                      icon: Symbols.fingerprint_rounded,
                      iconBg: AppColors.primary100,
                      iconColor: AppColors.primary700,
                      title: 'Déverrouillage biométrique',
                      subtitle: 'Empreinte ou reconnaissance faciale',
                      trailing: Switch.adaptive(
                        value: _biometrics,
                        onChanged: _onBiometricChanged,
                        activeColor: AppColors.primary700,
                      ),
                    ),
                    _SettingsTile(
                      icon: Symbols.lock_rounded,
                      iconBg: AppColors.primary100,
                      iconColor: AppColors.primary700,
                      title: 'Changer mon code PIN',
                      onTap: () => _showPinChange(context),
                    ),
                    _SettingsTile(
                      icon: Symbols.lock_open_rounded,
                      iconBg: AppColors.accent100,
                      iconColor: AppColors.accent700,
                      title: 'Verrouiller l\'application',
                      subtitle: 'Exige le code PIN au prochain accès',
                      onTap: widget.onLock,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // ── Sauvegarde ────────────────────────────────────────────
                _Section(
                  title: 'Sauvegarde & synchronisation',
                  children: [
                    _SettingsTile(
                      icon: Symbols.cloud_sync_rounded,
                      iconBg: AppColors.primary100,
                      iconColor: AppColors.primary700,
                      title: 'Synchronisation automatique',
                      subtitle: 'Chiffrement de bout en bout · Zero-knowledge',
                      trailing: Switch.adaptive(
                        value: _autoSync,
                        onChanged: (v) => setState(() => _autoSync = v),
                        activeColor: AppColors.primary700,
                      ),
                    ),
                    _SettingsTile(
                      icon: Symbols.backup_rounded,
                      iconBg: AppColors.primary100,
                      iconColor: AppColors.primary700,
                      title: 'Sauvegarder maintenant',
                      onTap: () => _showNotImplemented(context),
                    ),
                    _SettingsTile(
                      icon: Symbols.cloud_off_rounded,
                      iconBg: AppColors.neutral100,
                      iconColor: AppColors.neutral500,
                      title: 'Dernière sauvegarde',
                      trailing: Text(
                        'Jamais',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.neutral500),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // ── Conformité ────────────────────────────────────────────
                _Section(
                  title: 'Sécurité & conformité',
                  children: [
                    const _SettingsTile(
                      icon: Symbols.shield_rounded,
                      iconBg: AppColors.primary100,
                      iconColor: AppColors.primary700,
                      title: 'Chiffrement AES-256-GCM',
                      subtitle: 'Clé maîtresse dans le keystore sécurisé',
                      trailing: _GreenBadge(label: 'Actif'),
                    ),
                    const _SettingsTile(
                      icon: Symbols.verified_rounded,
                      iconBg: AppColors.primary100,
                      iconColor: AppColors.primary700,
                      title: 'Conformité ARTCI',
                      trailing: _GreenBadge(label: 'Certifié'),
                    ),
                    _SettingsTile(
                      icon: Symbols.policy_rounded,
                      iconBg: AppColors.primary100,
                      iconColor: AppColors.primary700,
                      title: 'Politique de confidentialité',
                      onTap: () => _showNotImplemented(context),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),

                // ── Zone danger ───────────────────────────────────────────
                const _DangerZone(),
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditProfile(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
      ),
      builder: (_) => _EditProfileSheet(
        demographics: widget.record.demographics,
        allergies: widget.record.allergies,
        onSave: (newDemo, newAllergies) async {
          final updated = widget.record.copyWith(
            demographics: newDemo,
            allergies: newAllergies,
            updatedAt: DateTime.now().toUtc().toIso8601String(),
          );
          await widget.onUpdateRecord!(updated);
        },
      ),
    );
  }

  void _showPinChange(BuildContext context) {
    if (widget.storedPin == null || widget.onChangePin == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Changement de PIN non disponible')));
      return;
    }
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => PinScreen(
          mode: PinMode.verify,
          storedPin: widget.storedPin,
          onSuccess: (_) {
            Navigator.of(context, rootNavigator: true).pushReplacement(
              MaterialPageRoute<void>(
                builder: (_) => PinScreen(
                  mode: PinMode.create,
                  onSuccess: (newPin) async {
                    await widget.onChangePin!(newPin);
                    if (context.mounted) {
                      Navigator.of(context, rootNavigator: true).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Code PIN modifié avec succès')));
                    }
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _onBiometricChanged(bool value) async {
    final svc = widget.biometricService;
    if (svc == null) return;
    if (value) {
      final available = await svc.isAvailable();
      if (!available) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Biométrie non disponible sur cet appareil')));
        }
        return;
      }
      final ok =
          await svc.authenticate('Activer le déverrouillage biométrique');
      if (!ok) return;
      await svc.setEnabled(true);
    } else {
      await svc.setEnabled(false);
    }
    if (mounted) setState(() => _biometrics = value);
  }

  void _showNotImplemented(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fonctionnalité disponible prochainement')),
    );
  }
}

// ─── Section container ────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
          child: Text(
            title.toUpperCase(),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.neutral500,
                  letterSpacing: 1.0,
                  fontSize: 11,
                ),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.neutral200),
          ),
          child: Column(
            children: List.generate(children.length, (i) {
              final isLast = i == children.length - 1;
              return Column(
                children: [
                  children[i],
                  if (!isLast)
                    const Divider(
                      height: 1,
                      indent: 56,
                      color: AppColors.neutral100,
                    ),
                ],
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ─── Settings tile ────────────────────────────────────────────────────────────

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconBg,
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        child: Icon(icon, size: 20, color: iconColor),
      ),
      title: Text(title, style: Theme.of(context).textTheme.bodyLarge),
      subtitle: subtitle != null
          ? Text(subtitle!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.neutral500))
          : null,
      trailing: trailing ??
          (onTap != null
              ? const Icon(Icons.chevron_right,
                  color: AppColors.neutral200, size: 20)
              : null),
      onTap: onTap,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 2),
    );
  }
}

// ─── Small green badge ────────────────────────────────────────────────────────

class _GreenBadge extends StatelessWidget {
  const _GreenBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.success.withAlpha(20),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.success,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

// ─── Danger zone ─────────────────────────────────────────────────────────────

class _DangerZone extends StatelessWidget {
  const _DangerZone();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.sm),
          child: Text(
            'ZONE DANGEREUSE',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppColors.error.withAlpha(180),
                  letterSpacing: 1.0,
                  fontSize: 11,
                ),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.error.withAlpha(60)),
          ),
          child: ListTile(
            leading: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.error.withAlpha(15),
                borderRadius: BorderRadius.circular(AppRadii.sm),
              ),
              child: const Icon(Symbols.delete_forever_rounded,
                  size: 20, color: AppColors.error),
            ),
            title: Text(
              'Supprimer mon compte',
              style: Theme.of(context)
                  .textTheme
                  .bodyLarge
                  ?.copyWith(color: AppColors.error),
            ),
            subtitle: Text(
              'Efface toutes les données chiffrées · Irréversible',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppColors.error.withAlpha(160)),
            ),
            trailing: Icon(Icons.chevron_right,
                color: AppColors.error.withAlpha(120), size: 20),
            onTap: () => _confirmDelete(context),
            contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: 2),
          ),
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer le compte ?'),
        content: const Text(
          'Cette action supprime définitivement toutes vos données chiffrées. '
          'Votre dossier médical ne pourra pas être récupéré.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text('Suppression disponible prochainement')),
              );
            },
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
  }
}

// ─── Profile edit bottom sheet ────────────────────────────────────────────────

class _EditProfileSheet extends StatefulWidget {
  const _EditProfileSheet({
    required this.demographics,
    required this.allergies,
    required this.onSave,
  });

  final Demographics demographics;
  final List<Allergy> allergies;
  final Future<void> Function(Demographics, List<Allergy>) onSave;

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _birthYearCtrl;
  late final TextEditingController _newSubstanceCtrl;
  String? _sex;
  String? _bloodType;
  bool _saving = false;
  late List<Allergy> _allergies;
  bool _addingAllergy = false;
  String _newSeverity = 'mild';

  static const _bloodTypes = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  static const _severityLabels = {
    'mild': 'Légère',
    'moderate': 'Modérée',
    'severe': 'Sévère'
  };
  static const _severityColors = {
    'mild': AppColors.warning,
    'moderate': AppColors.allergy,
    'severe': AppColors.error,
  };

  @override
  void initState() {
    super.initState();
    final d = widget.demographics;
    _nameCtrl = TextEditingController(text: d.givenName ?? '');
    _birthYearCtrl = TextEditingController(
        text: d.birthYear != null ? '${d.birthYear}' : '');
    _newSubstanceCtrl = TextEditingController();
    _sex = d.sex;
    _bloodType = d.bloodType;
    _allergies = List.of(widget.allergies);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _birthYearCtrl.dispose();
    _newSubstanceCtrl.dispose();
    super.dispose();
  }

  void _confirmAddAllergy() {
    final substance = _newSubstanceCtrl.text.trim();
    if (substance.isEmpty) return;
    setState(() {
      _allergies.add(Allergy(
        substance: substance,
        severity: _newSeverity,
        notedAt: DateTime.now().toIso8601String().substring(0, 10),
      ));
      _newSubstanceCtrl.clear();
      _newSeverity = 'mild';
      _addingAllergy = false;
    });
  }

  Future<void> _save() async {
    final yearText = _birthYearCtrl.text.trim();
    final birthYear = yearText.isEmpty ? null : int.tryParse(yearText);

    final newDemo = Demographics(
      givenName: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      birthYear: birthYear,
      sex: _sex,
      bloodType: _bloodType,
    );

    setState(() => _saving = true);
    try {
      await widget.onSave(newDemo, List.unmodifiable(_allergies));
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la sauvegarde')),
        );
      }
    }
  }

  @override
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final viewInsets = MediaQuery.viewInsetsOf(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.9;

    // Plus de DraggableScrollableSheet ni d'Expanded : ces deux widgets
    // combinés créaient un conflit de contraintes de largeur (infinite
    // width) qui remontait jusqu'aux boutons. Ce pattern — ConstrainedBox
    // (plafond de hauteur) + Padding (compensation clavier) +
    // SingleChildScrollView + Column(mainAxisSize.min) — est le plus
    // simple et le plus robuste pour un bottom sheet à contenu variable.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── drag handle (décoratif, non fonctionnel) ──────────────
              Center(
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.neutral200,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                ),
              ),
              Text('Profil médical', style: tt.titleMedium),
              const SizedBox(height: AppSpacing.md),

              // Prénom
              _label(tt, 'Prénom'),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  hintText: 'Votre prénom',
                  prefixIcon: Icon(Symbols.person_rounded),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: AppSpacing.md),

              // Année de naissance
              _label(tt, 'Année de naissance'),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _birthYearCtrl,
                decoration: const InputDecoration(
                  hintText: 'ex: 1990',
                  prefixIcon: Icon(Symbols.cake_rounded),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: AppSpacing.md),

              // Sexe
              _label(tt, 'Sexe'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  for (final e in const [
                    ('M', 'Homme'),
                    ('F', 'Femme'),
                    ('O', 'Autre'),
                  ])
                    ChoiceChip(
                      label: Text(e.$2),
                      selected: _sex == e.$1,
                      onSelected: (_) =>
                          setState(() => _sex = _sex == e.$1 ? null : e.$1),
                      selectedColor: AppColors.primary700,
                      labelStyle: tt.labelLarge?.copyWith(
                        color: _sex == e.$1 ? AppColors.white : null,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              // Groupe sanguin
              _label(tt, 'Groupe sanguin'),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: _bloodTypes.map((bt) {
                  final sel = _bloodType == bt;
                  return ChoiceChip(
                    label: Text(bt),
                    selected: sel,
                    onSelected: (_) =>
                        setState(() => _bloodType = sel ? null : bt),
                    selectedColor: AppColors.primary700,
                    labelStyle: tt.labelLarge?.copyWith(
                      color: sel ? AppColors.white : null,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: AppSpacing.md),

              // ── Allergies ────────────────────────────────────────────
              Row(
                children: [
                  Expanded(child: _label(tt, 'Allergies')),
                  if (!_addingAllergy)
                    TextButton.icon(
                      onPressed: () => setState(() => _addingAllergy = true),
                      icon: const Icon(Symbols.add_circle_rounded, size: 18),
                      label: const Text('Ajouter'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary700,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),

              if (_allergies.isEmpty && !_addingAllergy)
                Text(
                  'Aucune allergie enregistrée',
                  style: tt.bodyMedium?.copyWith(
                      color: AppColors.neutral500, fontStyle: FontStyle.italic),
                ),

              for (final a in _allergies)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: _AllergyRow(
                    allergy: a,
                    severityLabels: _severityLabels,
                    severityColors: _severityColors,
                    tt: tt,
                    onDelete: () => setState(() => _allergies.remove(a)),
                  ),
                ),

              if (_addingAllergy)
                _AllergyForm(
                  controller: _newSubstanceCtrl,
                  severity: _newSeverity,
                  severityLabels: _severityLabels,
                  severityColors: _severityColors,
                  tt: tt,
                  onSeverityChanged: (v) => setState(() => _newSeverity = v),
                  onConfirm: _confirmAddAllergy,
                  onCancel: () => setState(() {
                    _addingAllergy = false;
                    _newSubstanceCtrl.clear();
                    _newSeverity = 'mild';
                  }),
                ),

              const SizedBox(height: AppSpacing.xl),

              FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary700,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.white),
                      )
                    : const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _label(TextTheme tt, String text) => Text(
        text,
        style: tt.labelLarge
            ?.copyWith(color: AppColors.neutral500, letterSpacing: 0.5),
      );
}

// ── Allergie item (widget propre = pas de closure dans ListView) ─────────────

class _AllergyRow extends StatelessWidget {
  const _AllergyRow({
    required this.allergy,
    required this.severityLabels,
    required this.severityColors,
    required this.tt,
    required this.onDelete,
  });
  final Allergy allergy;
  final Map<String, String> severityLabels;
  final Map<String, Color> severityColors;
  final TextTheme tt;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final col = severityColors[allergy.severity] ?? AppColors.allergy;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: col.withAlpha(18),
        border: Border.all(color: col.withAlpha(60)),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        child: Row(
          children: [
            Icon(Symbols.warning_rounded, size: 16, color: col),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(allergy.substance,
                      style:
                          tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                  Text(
                    severityLabels[allergy.severity] ?? allergy.severity,
                    style: tt.bodySmall?.copyWith(color: col),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Symbols.delete_rounded, size: 18),
              color: AppColors.neutral500,
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Formulaire ajout allergie ─────────────────────────────────────────────────

class _AllergyForm extends StatelessWidget {
  const _AllergyForm({
    required this.controller,
    required this.severity,
    required this.severityLabels,
    required this.severityColors,
    required this.tt,
    required this.onSeverityChanged,
    required this.onConfirm,
    required this.onCancel,
  });
  final TextEditingController controller;
  final String severity;
  final Map<String, String> severityLabels;
  final Map<String, Color> severityColors;
  final TextTheme tt;
  final ValueChanged<String> onSeverityChanged;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.neutral200),
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'Substance allergène (ex: Pénicilline)',
                prefixIcon: Icon(Symbols.warning_rounded),
              ),
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Sévérité',
                style: tt.bodySmall?.copyWith(color: AppColors.neutral500)),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final e in severityLabels.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: severity == e.key,
                    onSelected: (_) => onSeverityChanged(e.key),
                    selectedColor: severityColors[e.key]?.withAlpha(40),
                    checkmarkColor: severityColors[e.key],
                    labelStyle: tt.labelLarge?.copyWith(
                      color: severity == e.key ? severityColors[e.key] : null,
                      fontWeight: severity == e.key ? FontWeight.w600 : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              spacing: AppSpacing.sm,
              children: [
                TextButton(
                  onPressed: onCancel,
                  child: const Text('Annuler'),
                ),
                FilledButton(
                  onPressed: onConfirm,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary700,
                  ),
                  child: const Text('Ajouter'),
                ),
              ],
            )
          ],
        ),
      ),
    );
  }
}
