import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../design/app_theme.dart';
import '../record/medical_record.dart';
import '../secure/patient_account.dart';
import 'widgets/hero_app_bar.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    super.key,
    required this.record,
    required this.account,
    required this.onShowQr,
    required this.onScan,
    this.lastSyncedAt,
  });

  final MedicalRecord record;
  final PatientAccount account;
  final VoidCallback onShowQr;
  final VoidCallback onScan;
  final String? lastSyncedAt;

  Consultation? get _lastConsultation {
    if (record.consultations.isEmpty) return null;
    final indexed = List<MapEntry<int, Consultation>>.generate(
      record.consultations.length,
      (i) => MapEntry(i, record.consultations[i]));
    indexed.sort((a, b) {
      final cmp = b.value.date.compareTo(a.value.date);
      return cmp != 0 ? cmp : b.key - a.key;
    });
    return indexed.first.value;
  }

  @override
  Widget build(BuildContext context) {
    final last = _lastConsultation;

    return Scaffold(
      backgroundColor: AppColors.primary50,
      body: CustomScrollView(
        slivers: [
          PatientHeroAppBar(
            record: record,
            account: account,
            collapsedTitle: 'Accueil',
            showGreeting: true,
          ),
          SliverPadding(
            padding: const EdgeInsets.all(AppSpacing.md),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _PrimaryAction(onTap: onShowQr),
                const SizedBox(height: AppSpacing.md),
                if (last != null) ...[
                  _LastConsultationCard(consultation: last),
                  const SizedBox(height: AppSpacing.md),
                ],
                _SecondaryAction(onTap: onScan),
                const SizedBox(height: AppSpacing.md),
                _BackupStatusCard(
                  lastBackupAt: lastSyncedAt != null
                      ? DateTime.tryParse(lastSyncedAt!)?.toLocal()
                      : null,
                ),
                const SizedBox(height: AppSpacing.xl),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Primary action — QR code ─────────────────────────────────────────────────

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Partager mon dossier médical — générer un QR code',
      child: Material(
        color: AppColors.primary700,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.md),
          splashColor: Colors.white.withAlpha(30),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(25),
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: const Icon(Symbols.qr_code_rounded,
                      color: Colors.white, size: 28),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Partager mon dossier',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(color: AppColors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Générez un QR sécurisé à présenter au médecin',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppColors.white.withAlpha(180)),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Symbols.arrow_forward_ios_rounded,
                  color: AppColors.white.withAlpha(200),
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Last consultation card ───────────────────────────────────────────────────

class _LastConsultationCard extends StatelessWidget {
  const _LastConsultationCard({required this.consultation});
  final Consultation consultation;

  String _formatDate(DateTime d) {
    const months = [
      '', 'jan.', 'fév.', 'mars', 'avr.', 'mai', 'juin',
      'juil.', 'août', 'sep.', 'oct.', 'nov.', 'déc.'
    ];
    return '${d.day} ${months[d.month]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    DateTime? date;
    try {
      date = DateTime.parse(consultation.date);
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.neutral200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Symbols.event_note_rounded,
                  size: 16, color: AppColors.primary700),
              const SizedBox(width: 6),
              Text('Dernière consultation',
                  style: tt.labelLarge?.copyWith(color: AppColors.primary700)),
              const Spacer(),
              if (date != null) Text(_formatDate(date), style: tt.bodySmall),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(consultation.practitionerRef, style: tt.titleSmall),
          const SizedBox(height: 2),
          Text(
            consultation.summary,
            style: tt.bodyMedium,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── Secondary action — scanner ───────────────────────────────────────────────

class _SecondaryAction extends StatelessWidget {
  const _SecondaryAction({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.md),
            border: Border.all(color: AppColors.neutral200),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.accent100,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: const Icon(Symbols.qr_code_scanner_rounded,
                    color: AppColors.accent700, size: 24),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Interface médecin',
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text('Scanner le QR d\'un patient',
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                ),
              ),
              const Icon(Symbols.chevron_right_rounded,
                  color: AppColors.neutral500),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Backup status card ───────────────────────────────────────────────────────

class _BackupStatusCard extends StatelessWidget {
  const _BackupStatusCard({this.lastBackupAt});
  final DateTime? lastBackupAt;

  String _label() {
    if (lastBackupAt == null) return 'Aucune sauvegarde';
    final diff = DateTime.now().difference(lastBackupAt!);
    if (diff.inMinutes < 60) return 'Sauvegardé il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Sauvegardé il y a ${diff.inHours} h';
    return 'Sauvegardé il y a ${diff.inDays} jour(s)';
  }

  @override
  Widget build(BuildContext context) {
    final ok = lastBackupAt != null;
    final color = ok ? AppColors.success : AppColors.neutral500;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.neutral200),
      ),
      child: Row(
        children: [
          Icon(
            ok ? Symbols.cloud_done_rounded : Symbols.cloud_off_rounded,
            size: 18,
            color: color,
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(_label(),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: color)),
        ],
      ),
    );
  }
}
