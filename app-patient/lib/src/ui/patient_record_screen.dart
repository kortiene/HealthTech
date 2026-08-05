import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../design/app_theme.dart';
import '../record/medical_record.dart';
import '../secure/patient_account.dart';
import 'widgets/hero_app_bar.dart';

class PatientRecordScreen extends StatelessWidget {
  const PatientRecordScreen({
    super.key,
    required this.record,
    required this.account,
    required this.onShowQr,
  });

  final MedicalRecord record;
  final PatientAccount account;
  final VoidCallback onShowQr;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary50,
      body: CustomScrollView(
        slivers: [
          PatientHeroAppBar(
            record: record,
            account: account,
            showAllergie: false,
            collapsedTitle: 'Mon Dossier',
            actions: const [
              Padding(
                padding: EdgeInsets.only(right: AppSpacing.sm),
                child: _SyncChip(),
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.md, AppSpacing.md, AppSpacing.md, 0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // if (record.demographics.heightCm != null ||
                //     record.demographics.weightKg != null) ...[
                //   _DemographicsSection(demographics: record.demographics),
                //   const SizedBox(height: AppSpacing.md),
                // ],
                if (record.allergies.isNotEmpty) ...[
                  _AllergySection(allergies: record.allergies),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (record.chronicConditions.isNotEmpty) ...[
                  _ConditionsSection(conditions: record.chronicConditions),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (record.medications.isNotEmpty) ...[
                  _MedicationsSection(medications: record.medications),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (record.consultations.isNotEmpty)
                  _ConsultationsSection(consultations: record.consultations),
                const SizedBox(height: 100),
              ]),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onShowQr,
        icon: const Icon(Symbols.qr_code_rounded),
        label: const Text('Partager mon dossier'),
      ),
    );
  }
}

// ─── Sync chip (dark hero variant) ───────────────────────────────────────────

class _SyncChip extends StatelessWidget {
  const _SyncChip();

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(
        Symbols.cloud_off_rounded,
        size: 13,
        color: AppColors.white.withAlpha(120),
      ),
      label: const Text('Jamais'),
      backgroundColor: AppColors.white.withAlpha(20),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppColors.white.withAlpha(200),
            fontSize: 11,
          ),
      side: BorderSide.none,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }
}

// ─── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    this.iconColor = AppColors.primary700,
    this.iconBg = AppColors.primary100,
    this.badge,
  });

  final IconData icon;
  final String title;
  final Color iconColor;
  final Color iconBg;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(icon, size: 20, color: iconColor),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          if (badge != null) ...[
            const SizedBox(width: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Text(
                badge!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: iconColor,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

Widget _sectionCard({required Widget child}) {
  return Container(
    width: double.infinity,
    padding: const EdgeInsets.all(AppSpacing.md),
    decoration: BoxDecoration(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(AppRadii.md),
      border: Border.all(color: AppColors.neutral200),
    ),
    child: child,
  );
}

// ─── Helper — BMI label ───────────────────────────────────────────────────────

String _bmiLabel(double bmi) {
  if (bmi < 18.5) return 'Insuffisance pondérale';
  if (bmi < 25.0) return 'Poids normal';
  if (bmi < 30.0) return 'Surpoids';
  return 'Obésité';
}

// ─── Demographics (height / weight / BMI) ─────────────────────────────────────

class _DemographicsSection extends StatelessWidget {
  const _DemographicsSection({required this.demographics});
  final Demographics demographics;

  @override
  Widget build(BuildContext context) {
    final bmi = demographics.bmi;
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Symbols.monitor_heart_rounded,
            title: 'Mesures',
          ),
          if (demographics.heightCm != null)
            _InfoRow(
              label: 'Taille',
              value: '${demographics.heightCm} cm',
            ),
          if (demographics.weightKg != null)
            _InfoRow(
              label: 'Poids',
              value: '${demographics.weightKg} kg',
            ),
          if (bmi != null)
            _InfoRow(
              label: 'IMC',
              value: '${bmi.toStringAsFixed(1)} — ${_bmiLabel(bmi)}',
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: tt.bodyMedium?.copyWith(color: AppColors.neutral500),
            ),
          ),
          Text(
            value,
            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

// ─── Allergies ────────────────────────────────────────────────────────────────

class _AllergySection extends StatelessWidget {
  const _AllergySection({required this.allergies});
  final List<Allergy> allergies;

  @override
  Widget build(BuildContext context) {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Symbols.warning_rounded,
            title: 'Allergies',
            iconColor: AppColors.allergy,
            iconBg: AppColors.allergyBg,
          ),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: allergies.map((a) => _AllergyPill(allergy: a)).toList(),
          ),
        ],
      ),
    );
  }
}

class _AllergyPill extends StatelessWidget {
  const _AllergyPill({required this.allergy});
  final Allergy allergy;

  @override
  Widget build(BuildContext context) {
    final isSevere = allergy.severity == 'severe';
    final color = isSevere ? AppColors.allergy : AppColors.accent700;
    final bg = isSevere ? AppColors.allergyBg : AppColors.accent100;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: color.withAlpha(60)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSevere ? Symbols.warning_rounded : Symbols.info_rounded,
            size: 13,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            allergy.substance,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: color.withAlpha(20),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              allergy.severity,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Pathologies ──────────────────────────────────────────────────────────────

class _ConditionsSection extends StatelessWidget {
  const _ConditionsSection({required this.conditions});
  final List<ChronicCondition> conditions;

  @override
  Widget build(BuildContext context) {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Symbols.history_rounded,
            title: 'Pathologies chroniques',
            badge: '${conditions.length}',
          ),
          ...conditions.map((c) => _ConditionRow(condition: c)),
        ],
      ),
    );
  }
}

class _ConditionRow extends StatelessWidget {
  const _ConditionRow({required this.condition});
  final ChronicCondition condition;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final icd = condition.icd10;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: AppColors.primary50,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: const Border(
          left: BorderSide(color: AppColors.primary500, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(condition.name,
                style: tt.bodyLarge?.copyWith(fontWeight: FontWeight.w500)),
          ),
          if (icd != null && icd.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppColors.primary100,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Text(
                icd,
                style: tt.bodySmall?.copyWith(
                  color: AppColors.primary700,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Médicaments ─────────────────────────────────────────────────────────────

class _MedicationsSection extends StatelessWidget {
  const _MedicationsSection({required this.medications});
  final List<Medication> medications;

  @override
  Widget build(BuildContext context) {
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Symbols.medication_rounded,
            title: 'Médicaments en cours',
            badge: '${medications.length}',
          ),
          ...medications.map((m) => _MedicationCard(medication: m)),
        ],
      ),
    );
  }
}

class _MedicationCard extends StatelessWidget {
  const _MedicationCard({required this.medication});
  final Medication medication;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.neutral100,
        borderRadius: BorderRadius.circular(AppRadii.sm),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(AppRadii.sm),
              boxShadow: [
                BoxShadow(
                  color: AppColors.neutral900.withAlpha(10),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: const Icon(Symbols.medication_rounded,
                color: AppColors.primary700, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(medication.name,
                    style: tt.titleSmall?.copyWith(fontSize: 14)),
                const SizedBox(height: 1),
                Text('${medication.dose} · ${medication.frequency}',
                    style: tt.bodySmall),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary100,
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Text(
              medication.dose,
              style: tt.bodySmall?.copyWith(
                  color: AppColors.primary700, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Consultations (timeline) ─────────────────────────────────────────────────

class _ConsultationsSection extends StatelessWidget {
  const _ConsultationsSection({required this.consultations});
  final List<Consultation> consultations;

  @override
  Widget build(BuildContext context) {
    final indexed = List<MapEntry<int, Consultation>>.generate(
        consultations.length, (i) => MapEntry(i, consultations[i]));
    indexed.sort((a, b) {
      final cmp = b.value.date.compareTo(a.value.date);
      return cmp != 0 ? cmp : b.key - a.key;
    });
    final sorted = indexed.map((e) => e.value).toList();
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Symbols.event_note_rounded,
            title: 'Consultations',
            badge: '${sorted.length}',
          ),
          ...List.generate(
            sorted.length,
            (i) => _TimelineEntry(
              consultation: sorted[i],
              isLast: i == sorted.length - 1,
              onTap: () => _showConsultationSheet(context, sorted[i]),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineEntry extends StatelessWidget {
  const _TimelineEntry({
    required this.consultation,
    required this.isLast,
    required this.onTap,
  });

  final Consultation consultation;
  final bool isLast;
  final VoidCallback onTap;

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
        'déc.',
      ];
      return '${d.day} ${months[d.month]} ${d.year}';
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary700,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: Container(width: 2, color: AppColors.primary100),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.md),
              child: Material(
                color: AppColors.neutral100,
                borderRadius: BorderRadius.circular(AppRadii.sm),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.sm + 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _formatDate(consultation.date),
                                style: tt.labelLarge?.copyWith(
                                    color: AppColors.primary700,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                            Text(consultation.practitionerRef,
                                style: tt.bodySmall),
                            const SizedBox(width: 4),
                            const Icon(Icons.chevron_right,
                                size: 16, color: AppColors.neutral500),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(consultation.summary,
                            style: tt.bodyMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                        if (consultation.prescription != null) ...[
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              const Icon(Symbols.receipt_long_rounded,
                                  size: 12, color: AppColors.primary700),
                              const SizedBox(width: 4),
                              Text('Ordonnance',
                                  style: tt.bodySmall?.copyWith(
                                      color: AppColors.primary700,
                                      fontWeight: FontWeight.w500)),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Consultation detail sheet ────────────────────────────────────────────────

void _showConsultationSheet(BuildContext context, Consultation consultation) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
    ),
    builder: (_) => _ConsultationSheet(consultation: consultation),
  );
}

class _ConsultationSheet extends StatelessWidget {
  const _ConsultationSheet({required this.consultation});
  final Consultation consultation;

  static String _formatDate(String isoDate) {
    try {
      final d = DateTime.parse(isoDate);
      const months = [
        '',
        'janvier',
        'février',
        'mars',
        'avril',
        'mai',
        'juin',
        'juillet',
        'août',
        'septembre',
        'octobre',
        'novembre',
        'décembre',
      ];
      return '${d.day} ${months[d.month]} ${d.year}';
    } catch (_) {
      return isoDate;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.92,
      minChildSize: 0.3,
      builder: (_, scrollCtrl) => ListView(
        controller: scrollCtrl,
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.primary100,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: const Icon(Symbols.event_note_rounded,
                    color: AppColors.primary700, size: 24),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_formatDate(consultation.date),
                        style: tt.titleSmall
                            ?.copyWith(color: AppColors.primary700)),
                    Text(consultation.practitionerRef, style: tt.bodyMedium),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.neutral500),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Fermer',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text('Compte-rendu',
              style: tt.labelLarge
                  ?.copyWith(color: AppColors.neutral500, letterSpacing: 0.5)),
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.neutral100,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Text(consultation.summary, style: tt.bodyLarge),
          ),
          if (consultation.prescription != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                const Icon(Symbols.receipt_long_rounded,
                    size: 16, color: AppColors.primary700),
                const SizedBox(width: 6),
                Text('Ordonnance',
                    style: tt.labelLarge?.copyWith(
                        color: AppColors.neutral500, letterSpacing: 0.5)),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.primary50,
                borderRadius: BorderRadius.circular(AppRadii.sm),
                border: Border.all(color: AppColors.primary100),
              ),
              child: Text(consultation.prescription!,
                  style: tt.bodyLarge?.copyWith(color: AppColors.primary900)),
            ),
          ],
        ],
      ),
    );
  }
}
