import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart' show sha256;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
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
    this.backendUrl,
    this.onWillPauseForPicker,
    this.onTreatmentStatusChanged,
    this.onMediaAttached,
    this.onRemoveConsultationMedia,
    this.onAddCondition,
    this.onUpdateCondition,
    this.onRemoveCondition,
    this.onAddDocument,
    this.onRemoveDocument,
  });

  final MedicalRecord record;
  final PatientAccount account;
  final VoidCallback onShowQr;

  /// Backend base URL for media upload/download (#117). Null disables the
  /// attach button (read-only mode or no connectivity config).
  final String? backendUrl;

  /// Called just before image_picker opens the camera/gallery so the root
  /// lifecycle observer can suppress the automatic lock-on-resume (#117).
  final VoidCallback? onWillPauseForPicker;

  /// Called when the patient closes a treatment.
  /// Args: (id, 'completed' | 'discontinued', endedAt ISO date).
  final void Function(String id, String status, String endedAt)?
      onTreatmentStatusChanged;

  /// Called when the patient attaches a new image to a consultation (#117).
  /// Args: (consultationId, descriptor). Caller persists the record update.
  final Future<void> Function(String consultationId, MediaDescriptor)?
      onMediaAttached;

  /// Called when the patient removes a media item from a consultation.
  /// Args: (consultationId, descriptor). Caller removes it from the record.
  final Future<void> Function(String consultationId, MediaDescriptor)?
      onRemoveConsultationMedia;

  /// Called when the patient adds a new chronic condition (#115).
  /// Caller persists the record update.
  final Future<void> Function(ChronicCondition)? onAddCondition;

  /// Called when a document is added to condition at [index] (#115).
  /// Args: (index in chronicConditions, updated condition with new doc appended).
  final Future<void> Function(int index, ChronicCondition)? onUpdateCondition;

  /// Called when the patient deletes a chronic condition at [index].
  final Future<void> Function(int index)? onRemoveCondition;

  /// Called when the patient adds a new administrative document (#116).
  final Future<void> Function(PatientDocument)? onAddDocument;

  /// Called when the patient removes an administrative document (#116).
  final Future<void> Function(PatientDocument)? onRemoveDocument;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.primary50,
        body: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverOverlapAbsorber(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: PatientHeroAppBar(
                record: record,
                account: account,
                showAllergie: false,
                collapsedTitle: 'Mon Dossier',
                expandedHeight: 238,
                stretch: false,
                bottom: TabBar(
                  labelColor: AppColors.white,
                  unselectedLabelColor: AppColors.white.withAlpha(140),
                  indicatorColor: AppColors.white,
                  indicatorWeight: 2,
                  tabs: const [
                    Tab(text: 'Suivi'),
                    Tab(text: 'Antécédents'),
                    Tab(text: 'Profil médical'),
                  ],
                ),
                actions: const [
                  Padding(
                    padding: EdgeInsets.only(right: AppSpacing.sm),
                    child: _SyncChip(),
                  ),
                ],
              ),
            ),
          ],
          body: TabBarView(
            children: [
              _SuiviTab(
                record: record,
                onTreatmentStatusChanged: onTreatmentStatusChanged,
                backendUrl: backendUrl,
                onWillPauseForPicker: onWillPauseForPicker,
                onMediaAttached: onMediaAttached,
                onRemoveConsultationMedia: onRemoveConsultationMedia,
              ),
              _AntecedintsTab(
                record: record,
                backendUrl: backendUrl,
                onAddCondition: onAddCondition,
                onUpdateCondition: onUpdateCondition,
                onRemoveCondition: onRemoveCondition,
                onWillPauseForPicker: onWillPauseForPicker,
              ),
              _ProfilTab(
                record: record,
                backendUrl: backendUrl,
                onWillPauseForPicker: onWillPauseForPicker,
                onAddDocument: onAddDocument,
                onRemoveDocument: onRemoveDocument,
              ),
            ],
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: onShowQr,
          icon: const Icon(Symbols.qr_code_rounded),
          label: const Text('Partager mon dossier'),
        ),
      ),
    );
  }
}

// ─── Tab: Suivi (traitements + consultations) ─────────────────────────────────

class _SuiviTab extends StatelessWidget {
  const _SuiviTab({
    required this.record,
    this.onTreatmentStatusChanged,
    this.backendUrl,
    this.onWillPauseForPicker,
    this.onMediaAttached,
    this.onRemoveConsultationMedia,
  });

  final MedicalRecord record;
  final void Function(String, String, String)? onTreatmentStatusChanged;
  final String? backendUrl;
  final VoidCallback? onWillPauseForPicker;
  final Future<void> Function(String, MediaDescriptor)? onMediaAttached;
  final Future<void> Function(String, MediaDescriptor)?
      onRemoveConsultationMedia;

  @override
  Widget build(BuildContext context) {
    final isEmpty = record.medications.isEmpty &&
        record.treatments.isEmpty &&
        record.consultations.isEmpty;
    return _TabScrollView(
      children: isEmpty
          ? [
              const _EmptyTabPlaceholder(
                icon: Symbols.medical_information_rounded,
                message: 'Aucun suivi médical enregistré',
              ),
            ]
          : [
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
                _ConsultationsSection(
                  consultations: record.consultations,
                  backendUrl: backendUrl,
                  onWillPauseForPicker: onWillPauseForPicker,
                  onMediaAttached: onMediaAttached,
                  onRemoveMedia: onRemoveConsultationMedia,
                ),
            ],
    );
  }
}

// ─── Tab: Antécédents (conditions chroniques) ────────────────────────────────

class _AntecedintsTab extends StatelessWidget {
  const _AntecedintsTab({
    required this.record,
    this.backendUrl,
    this.onAddCondition,
    this.onUpdateCondition,
    this.onRemoveCondition,
    this.onWillPauseForPicker,
  });

  final MedicalRecord record;
  final String? backendUrl;
  final Future<void> Function(ChronicCondition)? onAddCondition;
  final Future<void> Function(int, ChronicCondition)? onUpdateCondition;
  final Future<void> Function(int)? onRemoveCondition;
  final VoidCallback? onWillPauseForPicker;

  @override
  Widget build(BuildContext context) {
    return _TabScrollView(
      children: [
        _ConditionsSection(
          conditions: record.chronicConditions,
          backendUrl: backendUrl,
          onAddCondition: onAddCondition,
          onUpdateCondition: onUpdateCondition,
          onRemoveCondition: onRemoveCondition,
          onWillPauseForPicker: onWillPauseForPicker,
        ),
      ],
    );
  }
}

// ─── Tab: Profil médical (documents admin + données médicales + allergies) ────

class _ProfilTab extends StatelessWidget {
  const _ProfilTab({
    required this.record,
    this.backendUrl,
    this.onWillPauseForPicker,
    this.onAddDocument,
    this.onRemoveDocument,
  });

  final MedicalRecord record;
  final String? backendUrl;
  final VoidCallback? onWillPauseForPicker;
  final Future<void> Function(PatientDocument)? onAddDocument;
  final Future<void> Function(PatientDocument)? onRemoveDocument;

  bool get _hasStableData {
    final d = record.demographics;
    return d.bloodType != null ||
        d.heightCm != null ||
        d.weightKg != null ||
        d.bmi != null ||
        d.birthYear != null ||
        d.sex != null;
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty =
        record.allergies.isEmpty && !_hasStableData && record.documents.isEmpty;
    return _TabScrollView(
      children: isEmpty
          ? [
              const _EmptyTabPlaceholder(
                icon: Symbols.health_and_safety_rounded,
                message: 'Aucune donnée médicale enregistrée',
              ),
            ]
          : [
              _DocumentsSection(
                documents: record.documents,
                backendUrl: backendUrl,
                onWillPauseForPicker: onWillPauseForPicker,
                onAddDocument: onAddDocument,
                onRemoveDocument: onRemoveDocument,
              ),
              const SizedBox(height: AppSpacing.md),
              if (_hasStableData) ...[
                _MedicalStatsSection(demographics: record.demographics),
                const SizedBox(height: AppSpacing.md),
              ],
              if (record.allergies.isNotEmpty)
                _AllergySection(allergies: record.allergies),
            ],
    );
  }
}

// ─── Documents administratifs (#116) ─────────────────────────────────────────

class _DocumentsSection extends StatelessWidget {
  const _DocumentsSection({
    required this.documents,
    this.backendUrl,
    this.onWillPauseForPicker,
    this.onAddDocument,
    this.onRemoveDocument,
  });

  final List<PatientDocument> documents;
  final String? backendUrl;
  final VoidCallback? onWillPauseForPicker;
  final Future<void> Function(PatientDocument)? onAddDocument;
  final Future<void> Function(PatientDocument)? onRemoveDocument;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: _SectionHeader(
                  icon: Symbols.folder_shared_rounded,
                  title: 'Mes documents',
                ),
              ),
              if (onAddDocument != null)
                TextButton.icon(
                  onPressed: () => _showAddDocumentSheet(
                    context,
                    onAdd: onAddDocument!,
                    onWillPauseForPicker: onWillPauseForPicker,
                  ),
                  icon: const Icon(Symbols.add_rounded, size: 18),
                  label: const Text('Ajouter'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primary700,
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: 0),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
          if (documents.isEmpty)
            Padding(
              padding: const EdgeInsets.only(
                  top: AppSpacing.sm, bottom: AppSpacing.xs),
              child: Text(
                'Aucun document ajouté',
                style: tt.bodyMedium?.copyWith(color: AppColors.neutral500),
              ),
            )
          else
            ...documents.map(
              (doc) => _DocumentRow(
                document: doc,
                onRemove: onRemoveDocument != null
                    ? () => onRemoveDocument!(doc)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({required this.document, this.onRemove});

  final PatientDocument document;
  final VoidCallback? onRemove;

  IconData _icon() => switch (document.type) {
        DocumentType.cmuCard => Symbols.badge_rounded,
        DocumentType.insuranceCard => Symbols.health_and_safety_rounded,
        DocumentType.other => Symbols.description_rounded,
      };

  void _viewDocument(BuildContext context) {
    if (document.media.url == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _DocumentViewerPage(descriptor: document.media),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final hasMedia = document.media.url != null;
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 0, vertical: AppSpacing.xs),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.primary100,
          borderRadius: BorderRadius.circular(AppRadii.sm),
        ),
        child: Icon(_icon(), size: 18, color: AppColors.primary700),
      ),
      title: Text(document.label,
          style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
      subtitle: Text(document.type.label,
          style: tt.bodySmall?.copyWith(color: AppColors.neutral500)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasMedia)
            IconButton(
              icon: const Icon(Symbols.open_in_full_rounded, size: 20),
              color: AppColors.primary700,
              tooltip: 'Voir',
              onPressed: () => _viewDocument(context),
            ),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Symbols.delete_rounded, size: 20),
              color: AppColors.error,
              tooltip: 'Supprimer',
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}

void _showAddDocumentSheet(
  BuildContext context, {
  required Future<void> Function(PatientDocument) onAdd,
  VoidCallback? onWillPauseForPicker,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
    ),
    builder: (ctx) => _AddDocumentSheet(
      onAdd: onAdd,
      onWillPauseForPicker: onWillPauseForPicker,
    ),
  );
}

class _AddDocumentSheet extends StatefulWidget {
  const _AddDocumentSheet({required this.onAdd, this.onWillPauseForPicker});

  final Future<void> Function(PatientDocument) onAdd;
  final VoidCallback? onWillPauseForPicker;

  @override
  State<_AddDocumentSheet> createState() => _AddDocumentSheetState();
}

class _AddDocumentSheetState extends State<_AddDocumentSheet> {
  final _labelCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  DocumentType _type = DocumentType.cmuCard;
  MediaDescriptor? _photoDescriptor;
  _UploadStatus _photoStatus = _UploadStatus.idle;
  String? _photoError;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _labelCtrl.text = _type.label;
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    super.dispose();
  }

  void _onTypeChanged(DocumentType? t) {
    if (t == null) return;
    setState(() {
      _type = t;
      if (t != DocumentType.other) _labelCtrl.text = t.label;
    });
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    XFile? picked;
    try {
      setState(() {
        _photoStatus = _UploadStatus.picking;
        _photoError = null;
      });
      widget.onWillPauseForPicker?.call();
      picked = await picker.pickImage(
          source: source, imageQuality: 60, maxWidth: 1280);
    } catch (e) {
      if (mounted) {
        setState(() {
          _photoStatus = _UploadStatus.error;
          _photoError = 'Accès refusé ou appareil indisponible : $e';
        });
      }
      return;
    }
    if (picked == null) {
      if (mounted) setState(() => _photoStatus = _UploadStatus.idle);
      return;
    }
    setState(() => _photoStatus = _UploadStatus.uploading);
    try {
      final bytes = await picked.readAsBytes();
      // Dev stub: XOR 0x5A — NOT a cipher. TODO(#102): replace with MediaCipher(FrbCryptoCore).encrypt().
      final cipher = Uint8List(bytes.length);
      for (var i = 0; i < bytes.length; i++) {
        cipher[i] = bytes[i] ^ 0x5A;
      }
      final uuid = _genUuid();
      final hash = sha256.convert(bytes).toString();
      final dir = await getApplicationDocumentsDirectory();
      final localFile = File('${dir.path}/media_$uuid.jpg');
      await localFile.writeAsBytes(cipher, flush: true);
      final descriptor = MediaDescriptor(
        uuid: uuid,
        contentKey: base64Encode(Uint8List(32)), // stub — TODO(#102)
        contentHash: hash,
        mime: 'image/jpeg',
        sizeBytes: bytes.length,
        addedAt: DateTime.now().toUtc().toIso8601String(),
        url: 'file://${localFile.path}',
      );
      if (mounted) {
        setState(() {
          _photoDescriptor = descriptor;
          _photoStatus = _UploadStatus.idle;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _photoStatus = _UploadStatus.error;
          _photoError = e.toString();
        });
      }
    }
  }

  void _showPhotoPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.neutral200,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AppColors.primary700),
              title: const Text('Prendre une photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.primary700),
              title: const Text('Depuis la galerie'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_photoDescriptor == null) return;
    setState(() => _saving = true);
    try {
      final doc = PatientDocument(
        id: _genUuid(),
        type: _type,
        label: _labelCtrl.text.trim(),
        media: _photoDescriptor!,
        addedAt: DateTime.now().toUtc().toIso8601String(),
      );
      await widget.onAdd(doc);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.neutral200,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Ajouter un document',
                style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: AppSpacing.md),
            // Type selector
            SegmentedButton<DocumentType>(
              segments: const [
                ButtonSegment(
                    value: DocumentType.cmuCard,
                    label: Text('CMU'),
                    icon: Icon(Symbols.badge_rounded)),
                ButtonSegment(
                    value: DocumentType.insuranceCard,
                    label: Text('Assurance'),
                    icon: Icon(Symbols.health_and_safety_rounded)),
                ButtonSegment(
                    value: DocumentType.other,
                    label: Text('Autre'),
                    icon: Icon(Symbols.description_rounded)),
              ],
              selected: {_type},
              onSelectionChanged: (s) => _onTypeChanged(s.firstOrNull),
            ),
            const SizedBox(height: AppSpacing.md),
            // Label field (free-text for "other", pre-filled for known types)
            TextFormField(
              controller: _labelCtrl,
              decoration: const InputDecoration(labelText: 'Libellé'),
              readOnly: _type != DocumentType.other,
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requis' : null,
            ),
            const SizedBox(height: AppSpacing.md),
            // Photo picker
            OutlinedButton.icon(
              onPressed: _photoStatus == _UploadStatus.picking ||
                      _photoStatus == _UploadStatus.uploading
                  ? null
                  : () => _showPhotoPicker(context),
              icon: _photoStatus == _UploadStatus.picking ||
                      _photoStatus == _UploadStatus.uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(_photoDescriptor != null
                      ? Symbols.check_circle_rounded
                      : Symbols.photo_camera_rounded),
              label: Text(_photoDescriptor != null
                  ? 'Photo ajoutée — changer'
                  : 'Ajouter une photo'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _photoDescriptor != null
                    ? AppColors.success
                    : AppColors.primary700,
              ),
            ),
            if (_photoError != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(_photoError!,
                  style: tt.bodySmall?.copyWith(color: AppColors.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            FilledButton(
              onPressed: (_saving || _photoDescriptor == null) ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Données médicales stables (onglet Profil médical) ───────────────────────

class _MedicalStatsSection extends StatelessWidget {
  const _MedicalStatsSection({required this.demographics});
  final Demographics demographics;

  String _bmiCategory(double bmi) {
    if (bmi < 18.5) return 'Insuffisance pondérale';
    if (bmi < 25.0) return 'Normal';
    if (bmi < 30.0) return 'Surpoids';
    return 'Obésité';
  }

  @override
  Widget build(BuildContext context) {
    final d = demographics;
    final rows = <_StatRowData>[];

    if (d.bloodType != null) {
      rows.add(_StatRowData(
        icon: Symbols.water_drop_rounded,
        iconColor: AppColors.error,
        iconBg: AppColors.errorBg,
        label: 'Groupe sanguin',
        value: d.bloodType!,
      ));
    }
    if (d.birthYear != null) {
      rows.add(_StatRowData(
        icon: Symbols.cake_rounded,
        iconColor: AppColors.primary700,
        iconBg: AppColors.primary100,
        label: 'Âge',
        value: '${DateTime.now().year - d.birthYear!} ans',
      ));
    }
    if (d.sex != null) {
      rows.add(_StatRowData(
        icon: Symbols.person_rounded,
        iconColor: AppColors.primary700,
        iconBg: AppColors.primary100,
        label: 'Sexe',
        value: d.sex == 'M'
            ? 'Homme'
            : d.sex == 'F'
                ? 'Femme'
                : d.sex!,
      ));
    }
    if (d.heightCm != null) {
      rows.add(_StatRowData(
        icon: Symbols.height_rounded,
        iconColor: AppColors.primary700,
        iconBg: AppColors.primary100,
        label: 'Taille',
        value: '${d.heightCm} cm',
      ));
    }
    if (d.weightKg != null) {
      final kg = d.weightKg!;
      rows.add(_StatRowData(
        icon: Symbols.monitor_weight_rounded,
        iconColor: AppColors.primary700,
        iconBg: AppColors.primary100,
        label: 'Poids',
        value:
            '${kg == kg.roundToDouble() ? kg.toInt() : kg.toStringAsFixed(1)} kg',
      ));
    }
    if (d.bmi != null) {
      rows.add(_StatRowData(
        icon: Symbols.calculate_rounded,
        iconColor: AppColors.accent700,
        iconBg: AppColors.accent100,
        label: 'IMC',
        value: '${d.bmi!.toStringAsFixed(1)} · ${_bmiCategory(d.bmi!)}',
      ));
    }

    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            icon: Symbols.medical_information_rounded,
            title: 'Données médicales',
          ),
          ...rows.map((r) => _StatRow(data: r)),
        ],
      ),
    );
  }
}

class _StatRowData {
  const _StatRowData({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String label;
  final String value;
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.data});
  final _StatRowData data;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: data.iconBg,
              borderRadius: BorderRadius.circular(AppRadii.sm),
            ),
            child: Icon(data.icon, size: 16, color: data.iconColor),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              data.label,
              style: tt.bodyMedium?.copyWith(color: AppColors.neutral500),
            ),
          ),
          Text(
            data.value,
            style: tt.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

// ─── Tab scroll view (NestedScrollView-aware) ────────────────────────────────

class _TabScrollView extends StatelessWidget {
  const _TabScrollView({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (ctx) => CustomScrollView(
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(ctx),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              100,
            ),
            sliver: SliverList(
              delegate: SliverChildListDelegate(children),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Empty tab placeholder ────────────────────────────────────────────────────

class _EmptyTabPlaceholder extends StatelessWidget {
  const _EmptyTabPlaceholder({
    required this.icon,
    required this.message,
  });

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.neutral200),
          const SizedBox(height: AppSpacing.md),
          Text(
            message,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: AppColors.neutral500),
            textAlign: TextAlign.center,
          ),
        ],
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

// ─── Severity helpers (#138) ──────────────────────────────────────────────────

String _severityLabel(int s) => switch (s) {
      1 => 'Légère',
      2 => 'Modérée',
      3 => 'Importante',
      4 => 'Sévère',
      _ => 'Critique',
    };

Color _severityColor(int s) => switch (s) {
      1 => AppColors.success,
      2 => const Color(0xFF84CC16),
      3 => AppColors.warning,
      4 => const Color(0xFFF97316),
      _ => AppColors.error,
    };

class _SeverityDots extends StatelessWidget {
  const _SeverityDots(this.severity);
  final int severity;

  @override
  Widget build(BuildContext context) {
    final color = _severityColor(severity);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 1; i <= 5; i++)
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(right: 2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i <= severity ? color : AppColors.neutral200,
            ),
          ),
        const SizedBox(width: 4),
        Text(
          _severityLabel(severity),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─── Add condition sheet (#115) ───────────────────────────────────────────────

void _showAddConditionSheet(
  BuildContext context, {
  required Future<void> Function(ChronicCondition) onAdd,
  VoidCallback? onWillPauseForPicker,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
    ),
    builder: (ctx) => _AddConditionSheet(
      onAdd: onAdd,
      onWillPauseForPicker: onWillPauseForPicker,
    ),
  );
}

class _AddConditionSheet extends StatefulWidget {
  const _AddConditionSheet({
    required this.onAdd,
    this.onWillPauseForPicker,
  });

  final Future<void> Function(ChronicCondition) onAdd;
  final VoidCallback? onWillPauseForPicker;

  @override
  State<_AddConditionSheet> createState() => _AddConditionSheetState();
}

class _AddConditionSheetState extends State<_AddConditionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _icdCtrl = TextEditingController();
  final _sinceCtrl = TextEditingController();

  MediaDescriptor? _photoDescriptor;
  _UploadStatus _photoStatus = _UploadStatus.idle;
  String? _photoError;
  bool _saving = false;
  int _severity = 1;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _icdCtrl.dispose();
    _sinceCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    XFile? picked;
    try {
      setState(() {
        _photoStatus = _UploadStatus.picking;
        _photoError = null;
      });
      widget.onWillPauseForPicker?.call();
      picked = await picker.pickImage(
          source: source, imageQuality: 60, maxWidth: 1280);
    } catch (e) {
      if (mounted) {
        setState(() {
          _photoStatus = _UploadStatus.error;
          _photoError = 'Accès refusé ou appareil indisponible : $e';
        });
      }
      return;
    }
    if (picked == null) {
      if (mounted) setState(() => _photoStatus = _UploadStatus.idle);
      return;
    }
    setState(() => _photoStatus = _UploadStatus.uploading);
    try {
      final bytes = await picked.readAsBytes();
      // Dev stub: XOR 0x5A — NOT a cipher. TODO(#102): replace with MediaCipher(FrbCryptoCore).encrypt().
      final cipher = Uint8List(bytes.length);
      for (var i = 0; i < bytes.length; i++) {
        cipher[i] = bytes[i] ^ 0x5A;
      }
      final uuid = _genUuid();
      final hash = sha256.convert(bytes).toString();
      final dir = await getApplicationDocumentsDirectory();
      final localFile = File('${dir.path}/media_$uuid.jpg');
      await localFile.writeAsBytes(cipher, flush: true);
      final descriptor = MediaDescriptor(
        uuid: uuid,
        contentKey: base64Encode(Uint8List(32)), // stub — TODO(#102)
        contentHash: hash,
        mime: 'image/jpeg',
        sizeBytes: bytes.length,
        addedAt: DateTime.now().toUtc().toIso8601String(),
        url: 'file://${localFile.path}',
      );
      if (mounted) {
        setState(() {
          _photoDescriptor = descriptor;
          _photoStatus = _UploadStatus.idle;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _photoStatus = _UploadStatus.error;
          _photoError = e.toString();
        });
      }
    }
  }

  void _showPhotoPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.neutral200,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AppColors.primary700),
              title: const Text('Prendre une photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.primary700),
              title: const Text('Depuis la galerie'),
              onTap: () {
                Navigator.pop(ctx);
                _pickPhoto(ImageSource.gallery);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final condition = ChronicCondition(
        name: _nameCtrl.text.trim(),
        icd10: _icdCtrl.text.trim().isEmpty ? null : _icdCtrl.text.trim(),
        since: _sinceCtrl.text.trim().isEmpty ? null : _sinceCtrl.text.trim(),
        documents: [if (_photoDescriptor != null) _photoDescriptor!],
        severity: _severity,
        addedAt: DateTime.now().toUtc().toIso8601String(),
      );
      await widget.onAdd(condition);
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.72,
      maxChildSize: 0.92,
      minChildSize: 0.4,
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
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.primary100,
                  borderRadius: BorderRadius.circular(AppRadii.sm),
                ),
                child: const Icon(Symbols.history_rounded,
                    color: AppColors.primary700, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Text('Ajouter une pathologie', style: tt.titleSmall),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, color: AppColors.neutral500),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Fermer',
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Nom *',
                    style:
                        tt.labelMedium?.copyWith(color: AppColors.neutral500)),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  controller: _nameCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Ex. Diabète de type 2',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requis' : null,
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Code ICD-10 (optionnel)',
                    style:
                        tt.labelMedium?.copyWith(color: AppColors.neutral500)),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  controller: _icdCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    hintText: 'Ex. E11',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Depuis (année, optionnel)',
                    style:
                        tt.labelMedium?.copyWith(color: AppColors.neutral500)),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  controller: _sinceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Ex. 2020',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                // ── Sévérité (#138) ─────────────────────────────────────────
                Row(
                  children: [
                    Text(
                      'Sévérité',
                      style:
                          tt.labelMedium?.copyWith(color: AppColors.neutral500),
                    ),
                    const Spacer(),
                    _SeverityDots(_severity),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                SliderTheme(
                  data: SliderThemeData(
                    thumbColor: _severityColor(_severity),
                    activeTrackColor: _severityColor(_severity),
                    inactiveTrackColor: AppColors.neutral200,
                    overlayColor:
                        _severityColor(_severity).withValues(alpha: 0.15),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: _severity.toDouble(),
                    min: 1,
                    max: 5,
                    divisions: 4,
                    onChanged: (v) => setState(() => _severity = v.round()),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                // ── Justificatif photo ──────────────────────────────────────
                if (_photoDescriptor != null) ...[
                  Row(
                    children: [
                      const Icon(Symbols.attach_file_rounded,
                          size: 14, color: AppColors.primary700),
                      const SizedBox(width: 4),
                      Text('Justificatif joint',
                          style: tt.bodySmall
                              ?.copyWith(color: AppColors.primary700)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() {
                          _photoDescriptor = null;
                          _photoStatus = _UploadStatus.idle;
                          _photoError = null;
                        }),
                        child: const Text('Supprimer'),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _DecryptedImageTile(
                    media: _photoDescriptor!,
                    backendUrl: '',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ] else ...[
                  if (_photoStatus == _UploadStatus.error &&
                      _photoError != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Text(_photoError!,
                          style:
                              tt.bodySmall?.copyWith(color: AppColors.allergy)),
                    ),
                  OutlinedButton.icon(
                    onPressed: _photoStatus == _UploadStatus.idle ||
                            _photoStatus == _UploadStatus.error
                        ? () => _showPhotoPicker(context)
                        : null,
                    icon: _photoStatus == _UploadStatus.uploading ||
                            _photoStatus == _UploadStatus.picking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppColors.primary700),
                          )
                        : const Icon(Icons.add_photo_alternate_rounded),
                    label: Text(
                      _photoStatus == _UploadStatus.uploading
                          ? 'Enregistrement…'
                          : _photoStatus == _UploadStatus.picking
                              ? 'Sélection…'
                              : '+ Ajouter un justificatif (optionnel)',
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary700,
                      side: const BorderSide(color: AppColors.primary100),
                      minimumSize: const Size(double.infinity, 44),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                ],
                // ── Enregistrer ─────────────────────────────────────────────
                FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    backgroundColor: AppColors.primary700,
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
        ],
      ),
    );
  }
}

// ─── Condition detail sheet (#115) ────────────────────────────────────────────

void _showConditionDetailSheet(
  BuildContext context, {
  required ChronicCondition condition,
  String? backendUrl,
  VoidCallback? onWillPauseForPicker,
  Future<void> Function(MediaDescriptor)? onAddDocument,
  Future<void> Function(MediaDescriptor)? onRemoveDocument,
  Future<void> Function(int)? onSeverityChanged,
  Future<void> Function()? onRemoveCondition,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
    ),
    builder: (_) => _ConditionDetailSheet(
      condition: condition,
      backendUrl: backendUrl,
      onWillPauseForPicker: onWillPauseForPicker,
      onAddDocument: onAddDocument,
      onRemoveDocument: onRemoveDocument,
      onSeverityChanged: onSeverityChanged,
      onRemoveCondition: onRemoveCondition,
    ),
  );
}

class _ConditionDetailSheet extends StatefulWidget {
  const _ConditionDetailSheet({
    required this.condition,
    this.backendUrl,
    this.onWillPauseForPicker,
    this.onAddDocument,
    this.onRemoveDocument,
    this.onSeverityChanged,
    this.onRemoveCondition,
  });

  final ChronicCondition condition;
  final String? backendUrl;
  final VoidCallback? onWillPauseForPicker;

  /// Called after saving a new document to disk. Caller persists the record.
  final Future<void> Function(MediaDescriptor)? onAddDocument;

  /// Called when the patient deletes a persisted document. Caller removes it
  /// from the record and persists. Null = delete button hidden.
  final Future<void> Function(MediaDescriptor)? onRemoveDocument;

  /// Called when the patient changes the severity slider. Null = read-only.
  final Future<void> Function(int)? onSeverityChanged;

  /// Called when the patient confirms deletion of this condition. Null = no delete button.
  final Future<void> Function()? onRemoveCondition;

  @override
  State<_ConditionDetailSheet> createState() => _ConditionDetailSheetState();
}

class _ConditionDetailSheetState extends State<_ConditionDetailSheet> {
  _UploadStatus _uploadStatus = _UploadStatus.idle;
  String? _uploadError;
  late int _severity;

  // Optimistic: descriptors added this session, not yet in widget.condition.documents
  final List<MediaDescriptor> _localDocs = [];
  // Optimistic: UUIDs removed this session, pending parent record update
  final Set<String> _removedUuids = {};

  @override
  void initState() {
    super.initState();
    _severity = widget.condition.severity ?? 1;
  }

  List<MediaDescriptor> get _allDocs => [
        ...widget.condition.documents
            .where((d) => !_removedUuids.contains(d.uuid)),
        ..._localDocs,
      ];

  Future<void> _handleDeleteDoc(MediaDescriptor desc) async {
    // Local-only doc (added this session) — just remove from local list.
    if (_localDocs.remove(desc)) {
      setState(() {});
      return;
    }
    // Persisted doc — optimistic UI removal + delegate to parent.
    setState(() => _removedUuids.add(desc.uuid));
    await widget.onRemoveDocument?.call(desc);
  }

  Future<void> _pickAndAttach(ImageSource source) async {
    final picker = ImagePicker();
    XFile? picked;
    try {
      setState(() {
        _uploadStatus = _UploadStatus.picking;
        _uploadError = null;
      });
      widget.onWillPauseForPicker?.call();
      picked = await picker.pickImage(
          source: source, imageQuality: 60, maxWidth: 1280);
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadStatus = _UploadStatus.error;
          _uploadError = 'Accès refusé ou appareil indisponible : $e';
        });
      }
      return;
    }
    if (picked == null) {
      if (mounted) setState(() => _uploadStatus = _UploadStatus.idle);
      return;
    }
    setState(() => _uploadStatus = _UploadStatus.uploading);
    try {
      final bytes = await picked.readAsBytes();
      // Dev stub: XOR 0x5A — NOT a cipher. TODO(#102): replace with MediaCipher(FrbCryptoCore).encrypt().
      final cipher = Uint8List(bytes.length);
      for (var i = 0; i < bytes.length; i++) {
        cipher[i] = bytes[i] ^ 0x5A;
      }
      final uuid = _genUuid();
      final hash = sha256.convert(bytes).toString();
      final dir = await getApplicationDocumentsDirectory();
      final localFile = File('${dir.path}/media_$uuid.jpg');
      await localFile.writeAsBytes(cipher, flush: true);
      final descriptor = MediaDescriptor(
        uuid: uuid,
        contentKey: base64Encode(Uint8List(32)), // stub — TODO(#102)
        contentHash: hash,
        mime: 'image/jpeg',
        sizeBytes: bytes.length,
        addedAt: DateTime.now().toUtc().toIso8601String(),
        url: 'file://${localFile.path}',
      );
      if (mounted) {
        setState(() {
          _localDocs.add(descriptor);
          _uploadStatus = _UploadStatus.idle;
        });
      }
      await widget.onAddDocument?.call(descriptor);
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadStatus = _UploadStatus.error;
          _uploadError = e.toString();
        });
      }
    }
  }

  void _showSourcePicker(BuildContext ctx) {
    showModalBottomSheet<void>(
      context: ctx,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
      ),
      builder: (inner) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.neutral200,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AppColors.primary700),
              title: const Text('Prendre une photo'),
              onTap: () {
                Navigator.pop(inner);
                _pickAndAttach(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.primary700),
              title: const Text('Depuis la galerie'),
              onTap: () {
                Navigator.pop(inner);
                _pickAndAttach(ImageSource.gallery);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final docs = _allDocs;
    final canAttach = widget.onAddDocument != null;
    final icd = widget.condition.icd10;
    final since = widget.condition.since;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.5,
      maxChildSize: 0.92,
      minChildSize: 0.3,
      builder: (_, scrollCtrl) => ListView(
        controller: scrollCtrl,
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
        children: [
          // Handle
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
          // Header
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
                child: const Icon(Symbols.history_rounded,
                    color: AppColors.primary700, size: 24),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.condition.name,
                        style: tt.titleSmall
                            ?.copyWith(color: AppColors.primary700)),
                    if (since != null && since.isNotEmpty)
                      Text('Depuis $since', style: tt.bodyMedium),
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
          // ICD-10
          if (icd != null && icd.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.primary100,
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'ICD-10 ',
                        style:
                            tt.bodySmall?.copyWith(color: AppColors.neutral500),
                      ),
                      Text(
                        icd,
                        style: tt.bodySmall?.copyWith(
                          color: AppColors.primary700,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          // Sévérité (#138)
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Text('Sévérité',
                  style: tt.labelLarge?.copyWith(color: AppColors.neutral500)),
              const Spacer(),
              _SeverityDots(_severity),
            ],
          ),
          if (widget.onSeverityChanged != null) ...[
            const SizedBox(height: AppSpacing.xs),
            SliderTheme(
              data: SliderThemeData(
                thumbColor: _severityColor(_severity),
                activeTrackColor: _severityColor(_severity),
                inactiveTrackColor: AppColors.neutral200,
                overlayColor: _severityColor(_severity).withValues(alpha: 0.15),
                trackHeight: 4,
              ),
              child: Slider(
                value: _severity.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                onChanged: (v) => setState(() => _severity = v.round()),
                onChangeEnd: (v) => widget.onSeverityChanged!(v.round()),
              ),
            ),
          ],
          // Justificatifs
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              const Icon(Symbols.attach_file_rounded,
                  size: 16, color: AppColors.neutral500),
              const SizedBox(width: 6),
              Text(
                docs.isEmpty
                    ? 'Justificatifs'
                    : 'Justificatifs (${docs.length})',
                style: tt.labelLarge
                    ?.copyWith(color: AppColors.neutral500, letterSpacing: 0.5),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          if (docs.isNotEmpty) ...[
            _ImageStrip(
              images: docs,
              backendUrl: widget.backendUrl ?? '',
              onDelete: (canAttach || widget.onRemoveDocument != null)
                  ? _handleDeleteDoc
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
          ] else if (!canAttach)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Text(
                'Aucun justificatif joint.',
                style: tt.bodySmall?.copyWith(color: AppColors.neutral500),
              ),
            ),
          if (canAttach) ...[
            if (_uploadStatus == _UploadStatus.error &&
                _uploadError != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  _uploadError!,
                  style: tt.bodySmall?.copyWith(color: AppColors.allergy),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            OutlinedButton.icon(
              onPressed: _uploadStatus == _UploadStatus.idle ||
                      _uploadStatus == _UploadStatus.error
                  ? () => _showSourcePicker(context)
                  : null,
              icon: _uploadStatus == _UploadStatus.uploading ||
                      _uploadStatus == _UploadStatus.picking
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary700),
                    )
                  : const Icon(Icons.add_photo_alternate_rounded),
              label: Text(
                _uploadStatus == _UploadStatus.uploading
                    ? 'Enregistrement…'
                    : _uploadStatus == _UploadStatus.picking
                        ? 'Sélection…'
                        : '+ Ajouter un justificatif',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary700,
                side: const BorderSide(color: AppColors.primary100),
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
          ],
          // ── Supprimer la pathologie ──────────────────────────────────────
          if (widget.onRemoveCondition != null) ...[
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.xs),
            TextButton.icon(
              onPressed: () async {
                final nav = Navigator.of(context);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Supprimer cette pathologie ?'),
                    content: Text(
                      'La pathologie « ${widget.condition.name} » '
                      'sera retirée de votre dossier.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(false),
                        child: const Text('Annuler'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(true),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.error,
                        ),
                        child: const Text('Supprimer'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && mounted) {
                  await widget.onRemoveCondition!();
                  nav.pop();
                }
              },
              icon: const Icon(Icons.delete_outline_rounded,
                  color: AppColors.error, size: 18),
              label: const Text('Supprimer cette pathologie'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.error,
                minimumSize: const Size(double.infinity, 44),
              ),
            ),
          ],
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

// ─── Antécédents (#115) ───────────────────────────────────────────────────────

class _ConditionsSection extends StatefulWidget {
  const _ConditionsSection({
    required this.conditions,
    this.backendUrl,
    this.onAddCondition,
    this.onUpdateCondition,
    this.onRemoveCondition,
    this.onWillPauseForPicker,
  });

  final List<ChronicCondition> conditions;
  final String? backendUrl;
  final Future<void> Function(ChronicCondition)? onAddCondition;
  final Future<void> Function(int index, ChronicCondition)? onUpdateCondition;
  final Future<void> Function(int index)? onRemoveCondition;
  final VoidCallback? onWillPauseForPicker;

  @override
  State<_ConditionsSection> createState() => _ConditionsSectionState();
}

class _ConditionsSectionState extends State<_ConditionsSection> {
  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return _sectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Custom header row with optional "+ Ajouter" button
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary100,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                  child: const Icon(Symbols.history_rounded,
                      size: 20, color: AppColors.primary700),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text('Antécédents', style: tt.titleSmall),
                if (widget.conditions.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary100,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Text(
                      '${widget.conditions.length}',
                      style: tt.bodySmall?.copyWith(
                        color: AppColors.primary700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (widget.onAddCondition != null)
                  OutlinedButton.icon(
                    onPressed: () => _showAddConditionSheet(
                      context,
                      onAdd: widget.onAddCondition!,
                      onWillPauseForPicker: widget.onWillPauseForPicker,
                    ),
                    icon: const Icon(Icons.add, size: 13),
                    label: const Text('Ajouter'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary700,
                      side: const BorderSide(color: AppColors.primary100),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: const TextStyle(fontSize: 12),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ),
          if (widget.conditions.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                'Aucune pathologie chronique renseignée.',
                style: tt.bodySmall?.copyWith(color: AppColors.neutral500),
              ),
            )
          else
            ...(() {
              // Sort by addedAt descending (newest first). Conditions without
              // addedAt (pre-#138) sort to the bottom.
              final conditions = widget.conditions;
              final sortedIdx = List.generate(conditions.length, (i) => i)
                ..sort(
                  (a, b) => (conditions[b].addedAt ?? '')
                      .compareTo(conditions[a].addedAt ?? ''),
                );
              return sortedIdx.map((i) {
                final c = conditions[i];
                return _ConditionRow(
                  condition: c,
                  onTap: () => _showConditionDetailSheet(
                    context,
                    condition: c,
                    backendUrl: widget.backendUrl,
                    onWillPauseForPicker: widget.onWillPauseForPicker,
                    // Callbacks read widget.conditions[i] at call time, NOT
                    // the stale `c` from build(). State.widget is always
                    // updated by Flutter on parent rebuild (didUpdateWidget),
                    // so these closures are never stale even if the bottom
                    // sheet stays open across parent rebuilds.
                    onAddDocument: widget.onUpdateCondition != null
                        ? (descriptor) => widget.onUpdateCondition!(
                            i, widget.conditions[i].copyWithDocument(descriptor))
                        : null,
                    onRemoveDocument: widget.onUpdateCondition != null
                        ? (descriptor) => widget.onUpdateCondition!(
                              i,
                              widget.conditions[i].copyWith(
                                documents: widget.conditions[i]
                                    .documents
                                    .where((d) => d.uuid != descriptor.uuid)
                                    .toList(),
                              ),
                            )
                        : null,
                    onSeverityChanged: widget.onUpdateCondition != null
                        ? (sev) => widget.onUpdateCondition!(
                            i, widget.conditions[i].copyWith(severity: sev))
                        : null,
                    onRemoveCondition: widget.onRemoveCondition != null
                        ? () => widget.onRemoveCondition!(i)
                        : null,
                  ),
                );
              }).toList();
            })()
        ],
      ),
    );
  }
}

class _ConditionRow extends StatelessWidget {
  const _ConditionRow({required this.condition, this.onTap});
  final ChronicCondition condition;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final icd = condition.icd10;
    final docCount = condition.documents.length;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: AppColors.primary50,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        border: const Border(
          left: BorderSide(color: AppColors.primary500, width: 3),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadii.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadii.sm),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm + 2),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        condition.name,
                        style:
                            tt.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                      ),
                      if (condition.since != null &&
                          condition.since!.isNotEmpty)
                        Text(
                          'Depuis ${condition.since}',
                          style: tt.bodySmall
                              ?.copyWith(color: AppColors.neutral500),
                        ),
                      if (condition.severity != null) ...[
                        const SizedBox(height: 3),
                        _SeverityDots(condition.severity!),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                if (docCount > 0) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.neutral200,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Symbols.attach_file_rounded,
                            size: 10, color: AppColors.neutral500),
                        const SizedBox(width: 2),
                        Text(
                          '$docCount',
                          style: tt.bodySmall?.copyWith(
                              color: AppColors.neutral500,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                ],
                if (icd != null && icd.isNotEmpty) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                  const SizedBox(width: AppSpacing.xs),
                ],
                if (onTap != null)
                  const Icon(Icons.chevron_right,
                      size: 16, color: AppColors.neutral500),
              ],
            ),
          ),
        ),
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
  const _ConsultationsSection({
    required this.consultations,
    this.backendUrl,
    this.onWillPauseForPicker,
    this.onMediaAttached,
    this.onRemoveMedia,
  });

  final List<Consultation> consultations;
  final String? backendUrl;
  final VoidCallback? onWillPauseForPicker;
  final Future<void> Function(String consultationId, MediaDescriptor)?
      onMediaAttached;
  final Future<void> Function(String consultationId, MediaDescriptor)?
      onRemoveMedia;

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
              onTap: () => _showConsultationSheet(
                context,
                sorted[i],
                backendUrl: backendUrl,
                onWillPauseForPicker: onWillPauseForPicker,
                onMediaAttached: onMediaAttached,
                onRemoveMedia: onRemoveMedia,
              ),
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

// ─── Shared helpers ───────────────────────────────────────────────────────────

String _genUuid() {
  final rng = Random.secure();
  final b = List.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0F) | 0x40;
  b[8] = (b[8] & 0x3F) | 0x80;
  String h(int v) => v.toRadixString(16).padLeft(2, '0');
  return '${h(b[0])}${h(b[1])}${h(b[2])}${h(b[3])}-'
      '${h(b[4])}${h(b[5])}-${h(b[6])}${h(b[7])}-'
      '${h(b[8])}${h(b[9])}-'
      '${h(b[10])}${h(b[11])}${h(b[12])}${h(b[13])}${h(b[14])}${h(b[15])}';
}

// ─── Consultation detail sheet ────────────────────────────────────────────────

void _showConsultationSheet(
  BuildContext context,
  Consultation consultation, {
  String? backendUrl,
  VoidCallback? onWillPauseForPicker,
  Future<void> Function(String consultationId, MediaDescriptor)?
      onMediaAttached,
  Future<void> Function(String consultationId, MediaDescriptor)? onRemoveMedia,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
    ),
    builder: (_) => _ConsultationSheet(
      consultation: consultation,
      backendUrl: backendUrl,
      onWillPauseForPicker: onWillPauseForPicker,
      onMediaAttached: onMediaAttached,
      onRemoveMedia: onRemoveMedia,
    ),
  );
}

class _ConsultationSheet extends StatefulWidget {
  const _ConsultationSheet({
    required this.consultation,
    this.backendUrl,
    this.onWillPauseForPicker,
    this.onMediaAttached,
    this.onRemoveMedia,
  });

  final Consultation consultation;
  final String? backendUrl;
  final VoidCallback? onWillPauseForPicker;
  final Future<void> Function(String consultationId, MediaDescriptor)?
      onMediaAttached;

  /// Called when the patient removes a media item from a consultation.
  final Future<void> Function(String consultationId, MediaDescriptor)?
      onRemoveMedia;

  @override
  State<_ConsultationSheet> createState() => _ConsultationSheetState();
}

enum _UploadStatus { idle, picking, uploading, error }

class _ConsultationSheetState extends State<_ConsultationSheet> {
  _UploadStatus _uploadStatus = _UploadStatus.idle;
  String? _uploadError;

  // Optimistic: descriptors added this session, not yet in widget.consultation.media
  final List<MediaDescriptor> _localMedia = [];
  // Optimistic: UUIDs removed this session, pending parent record update
  final Set<String> _removedMediaUuids = {};

  List<MediaDescriptor> get _allImages => [
        ...widget.consultation.media.where(
          (m) =>
              m.mime.startsWith('image/') &&
              !_removedMediaUuids.contains(m.uuid),
        ),
        ..._localMedia,
      ];

  Future<void> _handleDeleteMedia(MediaDescriptor desc) async {
    if (_localMedia.remove(desc)) {
      setState(() {});
      return;
    }
    setState(() => _removedMediaUuids.add(desc.uuid));
    await widget.onRemoveMedia?.call(widget.consultation.id, desc);
  }

  static String _resolveAndroid(String url) =>
      Platform.isAndroid ? url.replaceFirst('localhost', '10.0.2.2') : url;

  Future<void> _pickAndAttach(ImageSource source) async {
    final picker = ImagePicker();
    XFile? picked;
    try {
      setState(() {
        _uploadStatus = _UploadStatus.picking;
        _uploadError = null;
      });
      // Notify root observer: the next pause/resume cycle is image_picker,
      // not a user-initiated app switch — do NOT lock.
      widget.onWillPauseForPicker?.call();
      picked = await picker.pickImage(
          source: source, imageQuality: 60, maxWidth: 1280);
    } catch (e) {
      // Surface picker errors (permission denied, camera unavailable, etc.)
      if (mounted) {
        setState(() {
          _uploadStatus = _UploadStatus.error;
          _uploadError = 'Accès refusé ou appareil indisponible : $e';
        });
      }
      return;
    }
    if (picked == null) {
      // User cancelled — silent reset.
      if (mounted) setState(() => _uploadStatus = _UploadStatus.idle);
      return;
    }
    setState(() => _uploadStatus = _UploadStatus.uploading);
    try {
      final bytes = await picked.readAsBytes();

      // Dev stub: XOR 0x5A "encrypt" — NOT a cipher.
      // TODO(#102): replace with MediaCipher(FrbCryptoCore).encrypt(bytes)
      final cipher = Uint8List(bytes.length);
      for (var i = 0; i < bytes.length; i++) {
        cipher[i] = bytes[i] ^ 0x5A;
      }

      final uuid = _genUuid();
      final hash = sha256.convert(bytes).toString();

      // Local-first: save encrypted bytes to app documents dir.
      // The image stays on-device until the patient shares via QR (TODO #22:
      // sync media bytes to backend as part of the QR/upload flow).
      final dir = await getApplicationDocumentsDirectory();
      final localFile = File('${dir.path}/media_$uuid.jpg');
      await localFile.writeAsBytes(cipher, flush: true);

      final descriptor = MediaDescriptor(
        uuid: uuid,
        // Stub: 32 zero bytes key — real key generated inside Rust (#102).
        contentKey: base64Encode(Uint8List(32)),
        contentHash: hash,
        mime: 'image/jpeg',
        sizeBytes: bytes.length,
        addedAt: DateTime.now().toUtc().toIso8601String(),
        // file:// URL → _DecryptedImageTile reads from disk, no network call.
        url: 'file://${localFile.path}',
      );

      if (mounted) {
        setState(() {
          _localMedia.add(descriptor);
          _uploadStatus = _UploadStatus.idle;
        });
      }

      await widget.onMediaAttached?.call(widget.consultation.id, descriptor);
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadStatus = _UploadStatus.error;
          _uploadError = e.toString();
        });
      }
    }
  }

  void _showSourcePicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.neutral200,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera_rounded,
                  color: AppColors.primary700),
              title: const Text('Prendre une photo'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndAttach(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_rounded,
                  color: AppColors.primary700),
              title: const Text('Depuis la galerie'),
              onTap: () {
                Navigator.pop(ctx);
                _pickAndAttach(ImageSource.gallery);
              },
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }

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
    final images = _allImages;
    final canAttach =
        widget.onMediaAttached != null && widget.backendUrl != null;

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
                    Text(_formatDate(widget.consultation.date),
                        style: tt.titleSmall
                            ?.copyWith(color: AppColors.primary700)),
                    Text(widget.consultation.practitionerRef,
                        style: tt.bodyMedium),
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
            child: Text(widget.consultation.summary, style: tt.bodyLarge),
          ),
          if (widget.consultation.ordonnances.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                const Icon(Symbols.receipt_long_rounded,
                    size: 16, color: AppColors.primary700),
                const SizedBox(width: 6),
                Text(
                  widget.consultation.ordonnances.length == 1
                      ? 'Ordonnance'
                      : 'Ordonnances (${widget.consultation.ordonnances.length})',
                  style: tt.labelLarge?.copyWith(
                      color: AppColors.neutral500, letterSpacing: 0.5),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            ...widget.consultation.ordonnances
                .map((o) => _OrdonnanceBlock(ordonnance: o)),
          ] else if (widget.consultation.prescription != null) ...[
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
              child: Text(widget.consultation.prescription!,
                  style: tt.bodyLarge?.copyWith(color: AppColors.primary900)),
            ),
          ],
          // ── Voice notes (#120) ──────────────────────────────────────────────
          for (final m in widget.consultation.media)
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
                practitionerRef: widget.consultation.practitionerRef,
              ),
            ],
          // ── Images / pièces jointes (#117) ─────────────────────────────────
          if (images.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                const Icon(Symbols.attach_file_rounded,
                    size: 16, color: AppColors.neutral500),
                const SizedBox(width: 6),
                Text(
                  images.length == 1
                      ? 'Pièce jointe'
                      : 'Pièces jointes (${images.length})',
                  style: tt.labelLarge?.copyWith(
                      color: AppColors.neutral500, letterSpacing: 0.5),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            _ImageStrip(
              images: images,
              backendUrl: _resolveAndroid(widget.backendUrl ?? ''),
              onDelete:
                  widget.onRemoveMedia != null ? _handleDeleteMedia : null,
            ),
          ],
          // ── Attach button ───────────────────────────────────────────────────
          if (canAttach) ...[
            const SizedBox(height: AppSpacing.lg),
            if (_uploadStatus == _UploadStatus.error &&
                _uploadError != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Text(
                  _uploadError!,
                  style: tt.bodySmall?.copyWith(color: AppColors.allergy),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
            OutlinedButton.icon(
              onPressed: _uploadStatus == _UploadStatus.idle ||
                      _uploadStatus == _UploadStatus.error
                  ? () => _showSourcePicker(context)
                  : null,
              icon: _uploadStatus == _UploadStatus.uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.primary700),
                    )
                  : const Icon(Icons.add_photo_alternate_rounded),
              label: Text(
                _uploadStatus == _UploadStatus.uploading
                    ? 'Envoi en cours…'
                    : _uploadStatus == _UploadStatus.picking
                        ? 'Sélection…'
                        : '+ Ajouter une pièce',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary700,
                side: const BorderSide(color: AppColors.primary100),
                minimumSize: const Size(double.infinity, 44),
              ),
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
            onTap:
                hasLinked ? () => setState(() => _expanded = !_expanded) : null,
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
                                const Icon(Symbols.check_circle_outline_rounded,
                                    size: 12, color: AppColors.neutral500),
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
                    padding: const EdgeInsets.fromLTRB(
                        AppSpacing.sm + 2, 0, AppSpacing.sm + 2, AppSpacing.sm),
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

// ── Image strip (#117) ────────────────────────────────────────────────────────

class _ImageStrip extends StatelessWidget {
  const _ImageStrip({
    required this.images,
    required this.backendUrl,
    this.onDelete,
  });

  final List<MediaDescriptor> images;
  final String backendUrl;

  /// Called when the user taps the delete button on a tile. Null = no button.
  final void Function(MediaDescriptor)? onDelete;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final img in images)
          _DecryptedImageTile(
            key: ValueKey(img.uuid),
            media: img,
            backendUrl: backendUrl,
            onDelete: onDelete != null ? () => onDelete!(img) : null,
          ),
      ],
    );
  }
}

// Fetches + XOR-0x5A decrypts one image and displays it as a tappable thumbnail.
// Dev stub — TODO(#102): replace XOR with MediaCipher(FrbCryptoCore).decrypt().
class _DecryptedImageTile extends StatefulWidget {
  const _DecryptedImageTile({
    super.key,
    required this.media,
    required this.backendUrl,
    this.onDelete,
  });

  final MediaDescriptor media;
  final String backendUrl;

  /// Called when the patient taps the ✕ badge. Null = no badge shown.
  final VoidCallback? onDelete;

  @override
  State<_DecryptedImageTile> createState() => _DecryptedImageTileState();
}

class _DecryptedImageTileState extends State<_DecryptedImageTile> {
  Uint8List? _bytes;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Uint8List ciphertext;
      final url = widget.media.url;
      if (url != null && url.startsWith('file://')) {
        // Local-first: read encrypted bytes from app documents dir.
        ciphertext = await File(url.replaceFirst('file://', '')).readAsBytes();
      } else if (url != null) {
        // Backend direct URL (legacy dev path — no /access roundtrip).
        ciphertext = await MediaClient('').fetchCiphertext(url);
      } else {
        // Prod path: mint an ephemeral access URL then fetch ciphertext.
        final client = MediaClient(widget.backendUrl);
        final grant = await client.requestAccess(widget.media.uuid);
        ciphertext = await client.fetchCiphertext(grant.url);
      }
      // XOR 0x5A dev stub decrypt — NOT a cipher.
      // TODO(#102): replace with MediaCipher(FrbCryptoCore).decrypt()
      final plain = Uint8List(ciphertext.length);
      for (var i = 0; i < ciphertext.length; i++) {
        plain[i] = ciphertext[i] ^ 0x5A;
      }
      if (mounted) {
        setState(() {
          _bytes = plain;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.sm),
            child: Material(
              color: AppColors.neutral100,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadii.sm),
                onTap: _bytes != null
                    ? () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                _ImageFullScreenPage(bytes: _bytes!),
                          ),
                        )
                    : null,
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary700),
                      )
                    : _error != null
                        ? const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.broken_image_rounded,
                                    color: AppColors.neutral500, size: 28),
                                SizedBox(height: 4),
                                Text(
                                  'Erreur',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: AppColors.neutral500,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Image.memory(_bytes!, fit: BoxFit.cover),
              ),
            ),
          ),
          if (widget.onDelete != null)
            Positioned(
              top: 4,
              right: 4,
              child: GestureDetector(
                onTap: widget.onDelete,
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: Colors.black.withAlpha(160),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, size: 13, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// Loads, XOR-decrypts (stub — TODO #102), and displays a document full-screen.
class _DocumentViewerPage extends StatefulWidget {
  const _DocumentViewerPage({required this.descriptor});
  final MediaDescriptor descriptor;

  @override
  State<_DocumentViewerPage> createState() => _DocumentViewerPageState();
}

class _DocumentViewerPageState extends State<_DocumentViewerPage> {
  Uint8List? _bytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final url = widget.descriptor.url;
    if (url == null) {
      setState(() => _error = 'Document non disponible localement');
      return;
    }
    try {
      final ciphertext =
          await File(url.replaceFirst('file://', '')).readAsBytes();
      // Dev stub: XOR 0x5A — NOT a cipher. TODO(#102): replace with FrbCryptoCore decrypt.
      final plain = Uint8List(ciphertext.length);
      for (var i = 0; i < ciphertext.length; i++) {
        plain[i] = ciphertext[i] ^ 0x5A;
      }
      if (mounted) setState(() => _bytes = plain);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _error != null
          ? Center(
              child: Text(_error!,
                  style: const TextStyle(color: Colors.white),
                  textAlign: TextAlign.center))
          : _bytes != null
              ? InteractiveViewer(child: Center(child: Image.memory(_bytes!)))
              : const Center(
                  child: CircularProgressIndicator(color: Colors.white)),
    );
  }
}

class _ImageFullScreenPage extends StatelessWidget {
  const _ImageFullScreenPage({required this.bytes});
  final Uint8List bytes;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: InteractiveViewer(
        child: Center(child: Image.memory(bytes)),
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
