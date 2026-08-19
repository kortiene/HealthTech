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
    this.onEditProfile,
    this.onSync,
    this.isSyncing = false,
  });

  final MedicalRecord record;
  final PatientAccount account;
  final VoidCallback onShowQr;
  final VoidCallback onScan;
  final String? lastSyncedAt;
  final VoidCallback? onEditProfile;
  final VoidCallback? onSync;
  final bool isSyncing;

  bool get _isProfileEmpty =>
      (record.demographics.givenName ?? '').trim().isEmpty;

  List<Treatment> get _activeTreatments =>
      record.treatments.where((t) => t.status == 'active').toList();

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
                if (_isProfileEmpty && onEditProfile != null) ...[
                  _OnboardingCard(onTap: onEditProfile!),
                  const SizedBox(height: AppSpacing.md),
                ],
                _PrimaryAction(onTap: onShowQr),
                const SizedBox(height: AppSpacing.md),
                if (last != null) ...[
                  _LastConsultationCard(consultation: last),
                  const SizedBox(height: AppSpacing.md),
                ],
                if (_activeTreatments.isNotEmpty) ...[
                  _ActiveTreatmentsCard(treatments: _activeTreatments),
                  const SizedBox(height: AppSpacing.md),
                ],
                // Interface médecin masquée — non nécessaire ici pour l'instant.
                // _SecondaryAction(onTap: onScan),
                // const SizedBox(height: AppSpacing.md),
                _BackupStatusCard(
                  lastBackupAt: lastSyncedAt != null
                      ? DateTime.tryParse(lastSyncedAt!)?.toLocal()
                      : null,
                  onSync: onSync,
                  isSyncing: isSyncing,
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

// ── Onboarding — profil vide ─────────────────────────────────────────────────

class _OnboardingCard extends StatelessWidget {
  const _OnboardingCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Material(
      color: AppColors.primary100,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary700.withAlpha(20),
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: const Icon(Symbols.assignment_ind_rounded,
                    color: AppColors.primary700, size: 24),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Complétez votre profil médical',
                      style:
                          tt.titleSmall?.copyWith(color: AppColors.primary900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Ajoutez vos informations pour que votre médecin puisse prendre en charge votre dossier.',
                      style:
                          tt.bodyMedium?.copyWith(color: AppColors.primary700),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              const Icon(Symbols.arrow_forward_ios_rounded,
                  size: 16, color: AppColors.primary700),
            ],
          ),
        ),
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

// ── Active treatments badge card (#144) ──────────────────────────────────────

class _ActiveTreatmentsCard extends StatelessWidget {
  const _ActiveTreatmentsCard({required this.treatments});
  final List<Treatment> treatments;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    const maxShown = 3;
    final shown = treatments.take(maxShown).toList();
    final overflow = treatments.length - maxShown;

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
              const Icon(Symbols.medical_services_rounded,
                  size: 16, color: AppColors.primary700),
              const SizedBox(width: 6),
              Text('Traitements en cours',
                  style: tt.labelLarge?.copyWith(color: AppColors.primary700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary100,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  '${treatments.length}',
                  style: tt.bodySmall?.copyWith(
                      color: AppColors.primary700, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          ...shown.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 8, top: 1),
                    decoration: const BoxDecoration(
                      color: AppColors.primary500,
                      shape: BoxShape.circle,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      t.diagnosis,
                      style: tt.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (overflow > 0)
            Text(
              '+ $overflow autre${overflow > 1 ? 's' : ''}',
              style: tt.bodySmall?.copyWith(color: AppColors.neutral500),
            ),
        ],
      ),
    );
  }
}

// ── Secondary action — scanner (masqué pour l'instant, voir _showScan) ──────

// ── Backup status card ───────────────────────────────────────────────────────

class _BackupStatusCard extends StatelessWidget {
  const _BackupStatusCard({
    this.lastBackupAt,
    this.onSync,
    this.isSyncing = false,
  });
  final DateTime? lastBackupAt;
  final VoidCallback? onSync;
  final bool isSyncing;

  String _label() {
    if (isSyncing) return 'Synchronisation…';
    if (lastBackupAt == null) return 'Aucune sauvegarde';
    final diff = DateTime.now().difference(lastBackupAt!);
    if (diff.inMinutes < 1) return 'Synchronisé à l\'instant';
    if (diff.inMinutes < 60) return 'Synchronisé il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'Synchronisé il y a ${diff.inHours} h';
    return 'Synchronisé il y a ${diff.inDays} jour(s)';
  }

  @override
  Widget build(BuildContext context) {
    final ok = lastBackupAt != null;
    final color = isSyncing
        ? AppColors.primary500
        : ok
            ? AppColors.success
            : AppColors.neutral500;
    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.md,
        right: onSync != null ? AppSpacing.xs : AppSpacing.md,
        top: AppSpacing.sm,
        bottom: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.neutral200),
      ),
      child: Row(
        children: [
          if (isSyncing)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: AppColors.primary500,
              ),
            )
          else
            Icon(
              ok ? Symbols.cloud_done_rounded : Symbols.cloud_off_rounded,
              size: 18,
              color: color,
            ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              _label(),
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: color),
            ),
          ),
          if (onSync != null)
            IconButton(
              onPressed: isSyncing ? null : onSync,
              icon: const Icon(Symbols.sync_rounded, size: 18),
              padding: const EdgeInsets.all(AppSpacing.sm),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              color: AppColors.primary500,
              disabledColor: AppColors.neutral500,
              tooltip: 'Récupérer les notes du médecin',
            ),
        ],
      ),
    );
  }
}
