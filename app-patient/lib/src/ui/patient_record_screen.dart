import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:path_provider/path_provider.dart';

import '../cloud/media_client.dart';
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
    this.onTreatmentStatusChanged,
  });

  final MedicalRecord record;
  final PatientAccount account;
  final VoidCallback onShowQr;

  /// Called when the patient closes a treatment.
  /// Args: (id, 'completed' | 'discontinued', endedAt ISO date).
  final void Function(String id, String status, String endedAt)?
      onTreatmentStatusChanged;

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
                if (record.treatments.isNotEmpty) ...[
                  _TreatmentsSection(
                    record: record,
                    onTreatmentStatusChanged: onTreatmentStatusChanged,
                  ),
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
                        if (consultation.prescription != null ||
                            consultation.ordonnances.isNotEmpty) ...[
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
          if (consultation.ordonnances.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                const Icon(Symbols.receipt_long_rounded,
                    size: 16, color: AppColors.primary700),
                const SizedBox(width: 6),
                Text(
                  consultation.ordonnances.length == 1
                      ? 'Ordonnance'
                      : 'Ordonnances (${consultation.ordonnances.length})',
                  style: tt.labelLarge?.copyWith(
                      color: AppColors.neutral500, letterSpacing: 0.5),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ...consultation.ordonnances
                .map((o) => _OrdonnanceBlock(ordonnance: o)),
          ] else if (consultation.prescription != null) ...[
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
          // ── Voice notes (#120) ──────────────────────────────────────────────
          for (final m in consultation.media)
            if (m.mime.startsWith('audio/')) ...[
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  const Icon(Icons.mic_rounded,
                      size: 16, color: AppColors.neutral500),
                  const SizedBox(width: 6),
                  Text('Note vocale',
                      style: tt.labelLarge?.copyWith(
                          color: AppColors.neutral500, letterSpacing: 0.5)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _VoiceNoteTile(
                media: m,
                practitionerRef: consultation.practitionerRef,
              ),
            ],
        ],
      ),
    );
  }
}

// ── Traitements (#121) ───────────────────────────────────────────────────────

typedef _TreatmentStatusCallback = void Function(
    String id, String status, String endedAt);

class _TreatmentsSection extends StatelessWidget {
  const _TreatmentsSection({
    required this.record,
    this.onTreatmentStatusChanged,
  });

  final MedicalRecord record;
  final _TreatmentStatusCallback? onTreatmentStatusChanged;

  @override
  Widget build(BuildContext context) {
    final indexed = record.treatments.asMap().entries.toList()
      ..sort((a, b) {
        final da = DateTime.tryParse(a.value.startedAt) ?? DateTime(0);
        final db = DateTime.tryParse(b.value.startedAt) ?? DateTime(0);
        final cmp = db.compareTo(da);
        return cmp != 0 ? cmp : b.key.compareTo(a.key);
      });
    final sorted = indexed.map((e) => e.value).toList();
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Symbols.medical_services_rounded,
            title: 'Traitements',
            badge: '${record.treatments.length}',
          ),
          ...sorted.map((t) {
            final linked = record.consultations
                .expand(
                  (c) => c.ordonnances
                      .where((o) => o.treatmentId == t.id)
                      .map((o) => (consultation: c, ordonnance: o)),
                )
                .toList()
              ..sort(
                  (a, b) => a.consultation.date.compareTo(b.consultation.date));
            return _TreatmentCard(
              treatment: t,
              linked: linked,
              defaultExpanded: sorted.length == 1,
              onClose: t.status == 'active' && onTreatmentStatusChanged != null
                  ? (status) {
                      final endedAt =
                          DateTime.now().toIso8601String().substring(0, 10);
                      onTreatmentStatusChanged!(t.id, status, endedAt);
                    }
                  : null,
            );
          }),
        ],
      ),
    );
  }
}

class _TreatmentCard extends StatefulWidget {
  const _TreatmentCard({
    required this.treatment,
    required this.linked,
    required this.defaultExpanded,
    this.onClose,
  });

  final Treatment treatment;
  final List<({Consultation consultation, Ordonnance ordonnance})> linked;
  final bool defaultExpanded;
  final void Function(String status)? onClose;

  @override
  State<_TreatmentCard> createState() => _TreatmentCardState();
}

class _TreatmentCardState extends State<_TreatmentCard> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.defaultExpanded;
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return AppColors.neutral500;
      case 'discontinued':
        return AppColors.allergy;
      default:
        return AppColors.primary700;
    }
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'completed':
        return 'Terminé';
      case 'discontinued':
        return 'Arrêté';
      default:
        return 'En cours';
    }
  }

  static String _fmtDate(String isoDate) {
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

  Future<void> _showCloseSheet(BuildContext context) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
      ),
      builder: (_) =>
          _CloseTreatmentSheet(diagnosis: widget.treatment.diagnosis),
    );
    if (result != null) widget.onClose!(result);
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final color = _statusColor(widget.treatment.status);
    final isActive = widget.treatment.status == 'active';
    final hasLinked = widget.linked.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: isActive ? AppColors.primary50 : AppColors.neutral100,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border(
          left: BorderSide(
            color: isActive ? AppColors.primary500 : AppColors.neutral200,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header — tappable pour replier/déplier si des ordonnances sont liées
          InkWell(
            onTap: hasLinked
                ? () => setState(() => _expanded = !_expanded)
                : null,
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.sm + 2,
                  AppSpacing.sm + 2, AppSpacing.xs, AppSpacing.sm + 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.treatment.diagnosis,
                          style: tt.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          [
                            if (widget.treatment.doctorRef != null)
                              widget.treatment.doctorRef!,
                            'depuis le ${_fmtDate(widget.treatment.startedAt)}',
                            if (widget.treatment.endedAt != null)
                              "jusqu'au ${_fmtDate(widget.treatment.endedAt!)}",
                          ].join(' · '),
                          style: tt.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: color.withAlpha(20),
                              borderRadius:
                                  BorderRadius.circular(AppRadii.pill),
                            ),
                            child: Text(
                              _statusLabel(widget.treatment.status),
                              style: tt.bodySmall?.copyWith(
                                  color: color, fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (hasLinked) ...[
                            const SizedBox(width: 4),
                            AnimatedRotation(
                              turns: _expanded ? 0.5 : 0,
                              duration: const Duration(milliseconds: 200),
                              child: const Icon(
                                Symbols.keyboard_arrow_down_rounded,
                                size: 18,
                                color: AppColors.neutral500,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (isActive && widget.onClose != null) ...[
                        const SizedBox(height: 6),
                        GestureDetector(
                          onTap: () => _showCloseSheet(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.neutral200,
                              borderRadius:
                                  BorderRadius.circular(AppRadii.pill),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                    Symbols.check_circle_outline_rounded,
                                    size: 12,
                                    color: AppColors.neutral500),
                                const SizedBox(width: 4),
                                Text(
                                  'Clore',
                                  style: tt.bodySmall?.copyWith(
                                      color: AppColors.neutral500,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
          // Ordonnances liées — expand/collapse animé
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: (_expanded && hasLinked)
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(AppSpacing.sm + 2, 0,
                        AppSpacing.sm + 2, AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Symbols.receipt_long_rounded,
                                size: 12, color: AppColors.neutral500),
                            const SizedBox(width: 4),
                            Text(
                              'Ordonnances liées (${widget.linked.length})',
                              style: tt.bodySmall?.copyWith(
                                  color: AppColors.neutral500,
                                  fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        ...widget.linked.map(
                          (pair) => Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: Container(
                              decoration: BoxDecoration(
                                color: AppColors.white,
                                borderRadius:
                                    BorderRadius.circular(AppRadii.sm),
                                border: Border.all(color: AppColors.neutral200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                        AppSpacing.sm,
                                        AppSpacing.xs,
                                        AppSpacing.sm,
                                        0),
                                    child: Text(
                                      _fmtDate(pair.consultation.date),
                                      style: tt.labelMedium?.copyWith(
                                          color: AppColors.primary700,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  ...pair.ordonnance.lines
                                      .map((l) => _OrdonnanceLineCard(line: l)),
                                  if (pair.ordonnance.lines.isEmpty)
                                    Padding(
                                      padding:
                                          const EdgeInsets.all(AppSpacing.sm),
                                      child: Text(
                                        'Ordonnance vide',
                                        style: tt.bodySmall?.copyWith(
                                            color: AppColors.neutral500),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _CloseTreatmentSheet extends StatelessWidget {
  const _CloseTreatmentSheet({required this.diagnosis});
  final String diagnosis;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.neutral200,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Clore ce traitement', style: tt.titleSmall),
            const SizedBox(height: 2),
            Text(diagnosis,
                style: tt.bodyMedium?.copyWith(color: AppColors.neutral500)),
            const SizedBox(height: AppSpacing.md),
            _CloseOption(
              icon: Symbols.check_circle_rounded,
              label: 'Traitement terminé',
              subtitle: 'Guérison ou fin normale du traitement',
              color: AppColors.primary700,
              onTap: () => Navigator.of(context).pop('completed'),
            ),
            const SizedBox(height: AppSpacing.sm),
            _CloseOption(
              icon: Symbols.cancel_rounded,
              label: 'Traitement arrêté',
              subtitle: "Arrêt sur décision médicale ou personnelle",
              color: AppColors.allergy,
              onTap: () => Navigator.of(context).pop('discontinued'),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Annuler'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CloseOption extends StatelessWidget {
  const _CloseOption({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Material(
      color: AppColors.neutral100,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: tt.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text(subtitle, style: tt.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Ordonnance block (#121) ───────────────────────────────────────────────────

class _OrdonnanceBlock extends StatelessWidget {
  const _OrdonnanceBlock({required this.ordonnance});
  final Ordonnance ordonnance;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primary50,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: AppColors.primary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ordonnance.label != null && ordonnance.label!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm, AppSpacing.sm, AppSpacing.sm, 0),
              child: Text(
                ordonnance.label!,
                style: tt.labelLarge?.copyWith(
                    color: AppColors.primary700, fontWeight: FontWeight.w600),
              ),
            ),
          ...ordonnance.lines.map(
            (l) => _OrdonnanceLineCard(line: l),
          ),
          if (ordonnance.lines.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: Text('Ordonnance vide',
                  style: tt.bodySmall?.copyWith(color: AppColors.neutral500)),
            ),
        ],
      ),
    );
  }
}

class _OrdonnanceLineCard extends StatelessWidget {
  const _OrdonnanceLineCard({required this.line});
  final OrdonnanceLine line;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final details = [
      if (line.dose != null) line.dose!,
      if (line.frequency != null) line.frequency!,
      if (line.durationDays != null) '${line.durationDays} j',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      child: Row(
        children: [
          const Icon(Symbols.medication_rounded,
              size: 18, color: AppColors.primary700),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(line.medication,
                    style: tt.titleSmall?.copyWith(fontSize: 14)),
                if (details.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(details, style: tt.bodySmall),
                ],
                if (line.notes != null) ...[
                  const SizedBox(height: 1),
                  Text(line.notes!,
                      style:
                          tt.bodySmall?.copyWith(color: AppColors.neutral500)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Voice note player tile ────────────────────────────────────────────────────
//
// Dev: fetches ciphertext via MediaClient.requestAccess → fetchCiphertext,
// XOR 0x5A decrypts in Dart (stub only — NOT a cipher), plays via audioplayers
// (Android MediaPlayer — no ExoPlayer, no guava, builds offline).
// Prod: TODO(#17) — decryption delegated to WASM crypto-core.

enum _PlayerStatus { idle, loading, ready, error }

class _VoiceNoteTile extends StatefulWidget {
  const _VoiceNoteTile({
    required this.media,
    required this.practitionerRef,
  });

  final MediaDescriptor media;
  final String practitionerRef;

  @override
  State<_VoiceNoteTile> createState() => _VoiceNoteTileState();
}

class _VoiceNoteTileState extends State<_VoiceNoteTile> {
  final _player = AudioPlayer();
  _PlayerStatus _status = _PlayerStatus.idle;
  String? _errorMessage;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  // Stored after first download so replay never re-fetches from the network.
  String? _localPath;

  @override
  void initState() {
    super.initState();
    _player.onPositionChanged.listen((p) {
      if (mounted) setState(() => _position = p);
    });
    _player.onDurationChanged.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _player.onPlayerStateChanged.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  // On Android the QR URL uses localhost (host machine) but the emulator
  // reaches the host via 10.0.2.2.
  String _resolveUrl(String url) {
    if (Platform.isAndroid) return url.replaceFirst('localhost', '10.0.2.2');
    return url;
  }

  String _fmt(Duration d) {
    final min = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  Future<void> _prepare() async {
    final rawUrl = widget.media.url ?? '';
    if (rawUrl.isEmpty) {
      setState(() {
        _status = _PlayerStatus.error;
        _errorMessage = 'URL manquante — re-scannez le QR.';
      });
      return;
    }
    setState(() => _status = _PlayerStatus.loading);
    try {
      final uri = Uri.parse(_resolveUrl(rawUrl));
      final baseUrl = '${uri.scheme}://${uri.host}:${uri.port}';
      final client = MediaClient(baseUrl);

      // POST /media/{uuid}/access → ephemeral URL → ciphertext bytes
      final grant = await client.requestAccess(widget.media.uuid);
      final ciphertext = await client.fetchCiphertext(grant.url);

      // XOR 0x5A dev stub decrypt — NOT a cipher; replaced by WASM in prod (#17).
      final plain = Uint8List(ciphertext.length);
      for (var i = 0; i < ciphertext.length; i++) {
        plain[i] = ciphertext[i] ^ 0x5A;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${widget.media.uuid}.webm');
      await file.writeAsBytes(plain, flush: true);
      _localPath = file.path;
      await _player.setSourceDeviceFile(file.path);
      if (mounted) setState(() => _status = _PlayerStatus.ready);
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _PlayerStatus.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _togglePlay() async {
    try {
      if (_status == _PlayerStatus.idle || _status == _PlayerStatus.error) {
        await _prepare();
        if (_status == _PlayerStatus.ready) await _player.resume();
        return;
      }
      if (_player.state == PlayerState.playing) {
        await _player.pause();
        return;
      }
      // After completion: seek(zero) + resume() hangs on audioplayers —
      // re-play the source directly to avoid the 30 s TimeoutException.
      if (_player.state == PlayerState.completed && _localPath != null) {
        setState(() => _position = Duration.zero);
        await _player.play(DeviceFileSource(_localPath!));
        return;
      }
      await _player.resume();
    } on TimeoutException {
      // audioplayers platform-channel timeout: reset so the user can retry.
      if (mounted) {
        setState(() {
          _status = _PlayerStatus.idle;
          _localPath = null;
          _position = Duration.zero;
          _duration = Duration.zero;
          _errorMessage = 'Délai expiré — appuyez à nouveau pour recharger.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = _PlayerStatus.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final isPlaying = _player.state == PlayerState.playing;
    final isCompleted = _player.state == PlayerState.completed;
    final knownDuration = widget.media.durationMs != null
        ? Duration(milliseconds: widget.media.durationMs!)
        : null;
    final duration = _duration > Duration.zero
        ? _duration
        : (knownDuration ?? Duration.zero);
    final progress = duration.inMilliseconds > 0
        ? (_position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    IconData icon;
    if (_status == _PlayerStatus.loading) {
      icon = Icons.hourglass_empty_rounded;
    } else if (isCompleted) {
      icon = Icons.replay_rounded;
    } else if (isPlaying) {
      icon = Icons.pause_rounded;
    } else {
      icon = Icons.play_arrow_rounded;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.neutral100,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: Border.all(color: AppColors.neutral200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dr. ${widget.practitionerRef}',
            style: tt.labelMedium?.copyWith(color: AppColors.neutral500),
          ),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              IconButton(
                onPressed:
                    _status == _PlayerStatus.loading ? null : _togglePlay,
                icon: Icon(icon, size: 32, color: AppColors.primary700),
                tooltip: isPlaying ? 'Pause' : 'Lecture',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value:
                            _status == _PlayerStatus.loading ? null : progress,
                        minHeight: 4,
                        backgroundColor: AppColors.neutral200,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                            AppColors.primary700),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _status == _PlayerStatus.loading
                          ? 'Chargement…'
                          : duration > Duration.zero
                              ? '${_fmt(_position)} / ${_fmt(duration)}'
                              : '',
                      style:
                          tt.labelSmall?.copyWith(color: AppColors.neutral500),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_status == _PlayerStatus.error && _errorMessage != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _errorMessage!,
              style: tt.labelSmall?.copyWith(color: AppColors.accent700),
            ),
          ],
        ],
      ),
    );
  }
}
