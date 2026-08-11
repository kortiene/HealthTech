import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../design/app_theme.dart';
import '../../record/medical_record.dart';
import '../../secure/patient_account.dart';

/// Hero SliverAppBar partagé entre Accueil, Mon Dossier et Paramètres.
/// Se condense en AppBar standard au scroll (titre + actions).
class PatientHeroAppBar extends StatelessWidget {
  const PatientHeroAppBar({
    super.key,
    required this.record,
    required this.collapsedTitle,
    this.account,
    this.showGreeting = false,
    this.actions,
    this.expandedHeight = 220,
    this.showAllergie = true,
    this.bottom,
    this.stretch = true,
  });

  final MedicalRecord record;
  final PatientAccount? account;
  final String collapsedTitle;
  final bool showGreeting;
  final List<Widget>? actions;
  final double expandedHeight;
  final bool showAllergie;
  final PreferredSizeWidget? bottom;
  final bool stretch;

  String get _greeting {
    final h = TimeOfDay.now().hour;
    if (h < 12) return 'Bonjour';
    if (h < 18) return 'Bon après-midi';
    return 'Bonsoir';
  }

  String get _name => record.demographics.givenName ?? 'Patient';

  @override
  Widget build(BuildContext context) {
    final displayName = showGreeting ? '$_greeting, $_name' : _name;

    return SliverAppBar(
      expandedHeight: expandedHeight,
      pinned: true,
      stretch: stretch,
      backgroundColor: AppColors.primary900,
      foregroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0.5,
      shadowColor: AppColors.primary900,
      title: Text(
        collapsedTitle,
        style: Theme.of(context)
            .textTheme
            .titleLarge
            ?.copyWith(color: AppColors.white),
      ),
      actions: actions,
      bottom: bottom,
      flexibleSpace: FlexibleSpaceBar(
        stretchModes:
            stretch ? const [StretchMode.zoomBackground] : const [],
        background: _HeroBackground(
          record: record,
          account: account,
          displayName: displayName,
          showAllergie: showAllergie,
          bottomInset: bottom?.preferredSize.height ?? 0,
        ),
      ),
    );
  }
}

class _HeroBackground extends StatelessWidget {
  const _HeroBackground({
    required this.record,
    required this.displayName,
    this.account,
    required this.showAllergie,
    this.bottomInset = 0,
  });

  final MedicalRecord record;
  final PatientAccount? account;
  final String displayName;
  final bool showAllergie;
  final double bottomInset;

  String get _name => record.demographics.givenName ?? 'Patient';

  String get _subtitle {
    final parts = <String>[];
    final birthYear = record.demographics.birthYear;
    if (birthYear != null) {
      final age = DateTime.now().year - birthYear;
      parts.add('$age ans');
    }
    final sex = record.demographics.sex;
    if (sex == 'M') parts.add('Homme');
    if (sex == 'F') parts.add('Femme');
    return parts.join(' · ');
  }

  List<Allergy> get _severeAllergies =>
      record.allergies.where((a) => a.severity == 'severe').toList();

  String get _allergyChipLabel {
    if (record.allergies.length == 1) return record.allergies.first.substance;
    return '${record.allergies.length} allergies';
  }

  String _bodyLabel(Demographics d) {
    final parts = <String>[];
    if (d.heightCm != null) parts.add('${d.heightCm} cm');
    if (d.weightKg != null) {
      final kg = d.weightKg!;
      parts.add(
          '${kg == kg.roundToDouble() ? kg.toInt() : kg.toStringAsFixed(1)} kg');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.primary900, AppColors.primary700],
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
              AppSpacing.md, 56, AppSpacing.md, AppSpacing.md + bottomInset),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.white.withAlpha(20),
                      border: Border.all(
                          color: AppColors.white.withAlpha(60), width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _name.isNotEmpty ? _name[0].toUpperCase() : '?',
                      style: tt.headlineSmall?.copyWith(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: tt.headlineSmall?.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w700,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (_subtitle.isNotEmpty)
                          Text(
                            _subtitle,
                            style: tt.bodyMedium?.copyWith(
                                color: AppColors.white.withAlpha(180)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  if (record.demographics.bloodType != null)
                    HeroStat(
                      icon: Symbols.water_drop_rounded,
                      label: record.demographics.bloodType!,
                      highlight: true,
                    ),
                  if (record.demographics.heightCm != null ||
                      record.demographics.weightKg != null)
                    HeroStat(
                      icon: Symbols.monitor_weight_rounded,
                      label: _bodyLabel(record.demographics),
                    ),
                  if (record.demographics.bmi != null)
                    HeroStat(
                      icon: Symbols.calculate_rounded,
                      label:
                          'IMC ${record.demographics.bmi!.toStringAsFixed(1)}',
                    ),
                  if (account != null)
                    const HeroStat(
                      icon: Symbols.badge_rounded,
                      label: 'CMU ✓',
                      success: true,
                    ),
                  if (record.allergies.isNotEmpty && showAllergie)
                    HeroStat(
                      icon: Symbols.warning_rounded,
                      label: _allergyChipLabel,
                      warning: _severeAllergies.isNotEmpty,
                      onTap: () => _showAllergySheet(context, record.allergies),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showAllergySheet(BuildContext context, List<Allergy> allergies) {
  // Severe allergies first, then alphabetical.
  final sorted = [...allergies]..sort((a, b) {
      if (a.severity == 'severe' && b.severity != 'severe') return -1;
      if (b.severity == 'severe' && a.severity != 'severe') return 1;
      return a.substance.compareTo(b.substance);
    });
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
    ),
    builder: (_) => _AllergySheet(allergies: sorted),
  );
}

// ── Bottom sheet — toutes les allergies ───────────────────────────────────────

class _AllergySheet extends StatelessWidget {
  const _AllergySheet({required this.allergies});
  final List<Allergy> allergies;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final severeCount = allergies.where((a) => a.severity == 'severe').length;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.error.withAlpha(15),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: const Icon(Symbols.warning_rounded,
                      size: 20, color: AppColors.error),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Allergies',
                          style: tt.titleSmall
                              ?.copyWith(color: AppColors.neutral900)),
                      Text(
                        severeCount > 0
                            ? '${allergies.length} au total · $severeCount sévère(s)'
                            : '${allergies.length} substance(s) recensée(s)',
                        style:
                            tt.bodySmall?.copyWith(color: AppColors.neutral500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.neutral100),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final a in allergies)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(right: AppSpacing.sm),
                            decoration: BoxDecoration(
                              color: a.severity == 'severe'
                                  ? AppColors.error
                                  : AppColors.neutral500,
                              shape: BoxShape.circle,
                            ),
                          ),
                          Expanded(
                            child: Text(
                              a.substance,
                              style: tt.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          _SeverityBadge(severity: a.severity),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeverityBadge extends StatelessWidget {
  const _SeverityBadge({required this.severity});
  final String severity;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final String label;
    switch (severity) {
      case 'severe':
        bg = AppColors.error.withAlpha(15);
        fg = AppColors.error;
        label = 'Sévère';
      case 'moderate':
        bg = AppColors.warning.withAlpha(15);
        fg = AppColors.warning;
        label = 'Modérée';
      default:
        bg = AppColors.neutral100;
        fg = AppColors.neutral500;
        label = 'Légère';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Chip stat sur fond sombre du hero.
class HeroStat extends StatelessWidget {
  const HeroStat({
    super.key,
    required this.icon,
    required this.label,
    this.highlight = false,
    this.success = false,
    this.warning = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool highlight;
  final bool success;
  final bool warning;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;

    if (highlight) {
      bg = AppColors.error.withAlpha(40);
      fg = const Color(0xFFFF8A80);
    } else if (success) {
      bg = AppColors.success.withAlpha(40);
      fg = const Color(0xFF69F0AE);
    } else if (warning) {
      bg = AppColors.warning.withAlpha(40);
      fg = const Color(0xFFFFCC80);
    } else {
      bg = AppColors.white.withAlpha(20);
      fg = AppColors.white.withAlpha(220);
    }

    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.keyboard_arrow_down_rounded, size: 13, color: fg),
          ],
        ],
      ),
    );

    if (onTap != null) {
      return GestureDetector(onTap: onTap, child: chip);
    }
    return chip;
  }
}
