// QR code consultation access screen (issue #16 / #118).
//
// The patient first picks a sharing mode ([_ModeSelectorView]):
//   - "Lecture seule"  → QrMode.readOnly  — doctor can read, not write back.
//   - "Consultation"   → QrMode.readWrite — doctor can read and add a note.
//
// The selected mode is forwarded to [QrController.generate], which embeds the
// write token in the QR payload only for readWrite sessions. The session key and
// write token are held in RAM only and wiped on [dispose] / expiry.
//
// [QrScreen.autoMode] bypasses the mode selector — inject in widget tests to
// get the loading/QR/error states without interacting with the selector.

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../design/app_theme.dart';
import '../qr/access_token.dart';
import '../record/medical_record.dart';

class QrScreen extends StatefulWidget {
  const QrScreen({
    super.key,
    required this.controller,
    this.record,
    this.autoMode,
    this.autoShareMedia = false,
  });

  final QrController controller;

  /// The patient's current record — used to detect pending local media so a
  /// consent dialog is shown before QR generation. Optional: when null the
  /// dialog is skipped and no media flush is attempted.
  final MedicalRecord? record;

  /// Skips the mode selector and generates immediately with this mode.
  /// Intended for widget tests only.
  final QrMode? autoMode;

  /// When true, justificatifs are always shared without asking consent.
  /// Controlled by the "Partage automatique" toggle in Settings.
  final bool autoShareMedia;

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> {
  QrPayload? _payload;
  String? _error;
  bool _generating = false;
  String _loadingMessage = 'Génération du code…';
  Timer? _countdownTimer;
  int _remainingSeconds = 0;
  QrMode? _selectedMode; // null = mode-selector phase

  @override
  void initState() {
    super.initState();
    if (widget.autoMode != null) {
      Future.microtask(() => _generate(widget.autoMode!));
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _payload?.wipe();
    super.dispose();
  }

  // Collects all media across the record (local file:// AND backend url:null), grouped for UI.
  List<_SelectableMedia> _collectAllMedia(MedicalRecord record) {
    final result = <_SelectableMedia>[];
    for (final c in record.consultations) {
      for (final d in c.media) {
        result.add(_SelectableMedia(
          descriptor: d,
          groupLabel: 'Consultations',
          itemLabel: _fmtMediaItem(d.mime, d.addedAt),
        ));
      }
    }
    for (final cc in record.chronicConditions) {
      for (final d in cc.documents) {
        result.add(_SelectableMedia(
          descriptor: d,
          groupLabel: cc.name,
          itemLabel: _fmtMediaItem(d.mime, d.addedAt),
        ));
      }
    }
    for (final doc in record.documents) {
      result.add(_SelectableMedia(
        descriptor: doc.media,
        groupLabel: 'Documents administratifs',
        itemLabel: doc.label.isNotEmpty ? doc.label : doc.type.label,
      ));
    }
    return result;
  }

  static String _fmtMediaItem(String mime, String addedAt) {
    final type = mime.startsWith('image/')
        ? 'Photo'
        : mime.startsWith('audio/')
            ? 'Audio'
            : 'Document';
    try {
      final d = DateTime.parse(addedAt).toLocal();
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
      return '$type · ${d.day} ${months[d.month]} ${d.year}';
    } catch (_) {
      return type;
    }
  }

  Future<Set<String>?> _showMediaSelectionSheet(List<_SelectableMedia> media) =>
      showModalBottomSheet<Set<String>>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        shape: const RoundedRectangleBorder(
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
        ),
        builder: (ctx) => _MediaSelectionSheet(media: media),
      );

  // Fallback dialog after upload failure: returns true = retry without media.
  Future<bool?> _askFallbackWithoutMedia() => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Envoi impossible'),
          content: const Text(
            'Les justificatifs n\'ont pas pu être envoyés. '
            'Générer le code sans eux ?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Continuer sans'),
            ),
          ],
        ),
      );

  Future<void> _generate(QrMode mode) async {
    final rec = widget.record;
    Set<String> selectedUuids = const {};
    if (rec != null) {
      final allMedia = _collectAllMedia(rec);
      if (allMedia.isNotEmpty) {
        if (widget.autoShareMedia) {
          // Patient configured auto-share — select all without showing sheet.
          selectedUuids = allMedia.map((m) => m.descriptor.uuid).toSet();
        } else {
          final result = await _showMediaSelectionSheet(allMedia);
          if (!mounted) return;
          if (result == null) return; // sheet dismissed — stay on mode selector
          selectedUuids = result;
        }
      }
    }
    await _doGenerate(mode, selectedMediaUuids: selectedUuids);
  }

  Future<void> _doGenerate(
    QrMode mode, {
    Set<String> selectedMediaUuids = const {},
  }) async {
    _countdownTimer?.cancel();
    setState(() {
      _generating = true;
      _error = null;
      _payload?.wipe();
      _payload = null;
      _remainingSeconds = 0;
      _selectedMode = mode;
      _loadingMessage = selectedMediaUuids.isNotEmpty
          ? 'Envoi des justificatifs…'
          : 'Génération du code…';
    });
    try {
      final p = await widget.controller.generate(
        mode: mode,
        selectedMediaUuids: selectedMediaUuids,
      );
      if (!mounted) {
        p.wipe();
        return;
      }
      final secs = p.expiresAt.difference(DateTime.now()).inSeconds;
      setState(() {
        _payload = p;
        _generating = false;
        _loadingMessage = 'Génération du code…';
        _remainingSeconds = secs > 0 ? secs : 0;
      });
      if (secs > 0) _startCountdown();
    } catch (e) {
      if (!mounted) return;
      if (selectedMediaUuids.isNotEmpty) {
        // Upload failed — offer to continue without the media.
        final fallback = await _askFallbackWithoutMedia();
        if (!mounted) return;
        if (fallback == true) {
          await _doGenerate(mode, selectedMediaUuids: const {});
          return;
        }
      }
      setState(() {
        _error = e.toString();
        _generating = false;
        _loadingMessage = 'Génération du code…';
      });
    }
  }

  // Copy session key bytes before popping so the caller can decrypt the
  // doctor's session blob BEFORE dispose() zeroes _payload.sessionKey.
  // Returns null when the session already expired.
  void _popWithKey() {
    final p = _payload;
    final keyCopy = (p != null && !p.isExpired)
        ? Uint8List.fromList(p.sessionKey)
        : null;
    Navigator.pop(context, keyCopy);
  }

  void _startCountdown() {
    _countdownTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;
        } else {
          _countdownTimer?.cancel();
          _payload?.wipe();
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    // PopScope(canPop: false) intercepts the system back gesture so we can
    // pass the session key copy to the caller before dispose() wipes it.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _popWithKey();
      },
      child: Scaffold(
        backgroundColor: AppColors.primary900,
        appBar: AppBar(
          backgroundColor: AppColors.primary900,
          foregroundColor: AppColors.white,
          elevation: 0,
          title: const Text(
            'Accès consultation',
            style:
                TextStyle(color: AppColors.white, fontWeight: FontWeight.w600),
          ),
          leading: IconButton(
            icon:
                const Icon(Symbols.arrow_back_rounded, color: AppColors.white),
            onPressed: _popWithKey,
          ),
        ),
        body: SafeArea(child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_selectedMode == null) {
      return _ModeSelectorView(onSelect: _generate);
    }
    if (_generating) return _LoadingView(message: _loadingMessage);
    if (_error != null) {
      return _ErrorView(
        message: _error!,
        onRetry: () => _generate(_selectedMode!),
      );
    }
    final p = _payload;
    if (p == null) return const _LoadingView(message: 'Génération du code…');
    if (_remainingSeconds == 0) {
      return _ExpiredView(onRegenerate: () => _generate(_selectedMode!));
    }
    return _QrView(
      qrData: p.toQrString(),
      remainingSeconds: _remainingSeconds,
      readOnly: p.isReadOnly,
    );
  }
}

// ── Media selection data ──────────────────────────────────────────────────────

class _SelectableMedia {
  const _SelectableMedia({
    required this.descriptor,
    required this.groupLabel,
    required this.itemLabel,
  });
  final MediaDescriptor descriptor;
  final String groupLabel;
  final String itemLabel;
}

// ── Mode selector ─────────────────────────────────────────────────────────────

class _ModeSelectorView extends StatelessWidget {
  const _ModeSelectorView({required this.onSelect});
  final void Function(QrMode) onSelect;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Mode de partage',
            style: TextStyle(
              color: AppColors.white,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choisissez ce que votre médecin pourra faire avec votre dossier.',
            style: TextStyle(
              color: AppColors.white.withAlpha(153),
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          _ModeCard(
            icon: Symbols.visibility_rounded,
            title: 'Lecture seule',
            subtitle:
                'Le médecin consulte votre dossier sans pouvoir y ajouter de note.',
            onTap: () => onSelect(QrMode.readOnly),
          ),
          const SizedBox(height: 16),
          _ModeCard(
            icon: Symbols.edit_note_rounded,
            title: 'Consultation',
            subtitle:
                'Le médecin peut lire votre dossier et y ajouter une note de consultation.',
            onTap: () => onSelect(QrMode.readWrite),
          ),
        ],
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.white.withAlpha(15),
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        splashColor: AppColors.primary500.withAlpha(40),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary500.withAlpha(30),
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: Icon(icon, color: AppColors.primary500, size: 22),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: AppColors.white.withAlpha(153),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Symbols.chevron_right_rounded,
                color: AppColors.white.withAlpha(100),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── States ────────────────────────────────────────────────────────────────────

class _LoadingView extends StatelessWidget {
  const _LoadingView({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primary500,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            message,
            style: TextStyle(
              color: AppColors.white.withAlpha(180),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _QrView extends StatelessWidget {
  const _QrView({
    required this.qrData,
    required this.remainingSeconds,
    required this.readOnly,
  });

  final String qrData;
  final int remainingSeconds;
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final isUrgent = remainingSeconds <= 30;
    // Scrollable so the QR + mode badge + countdown fit on small viewports.
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Mode badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: readOnly
                            ? AppColors.white.withAlpha(20)
                            : AppColors.primary500.withAlpha(30),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        border: Border.all(
                          color: readOnly
                              ? AppColors.white.withAlpha(60)
                              : AppColors.primary500.withAlpha(80),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            readOnly
                                ? Symbols.visibility_rounded
                                : Symbols.edit_note_rounded,
                            size: 14,
                            color: readOnly
                                ? AppColors.white.withAlpha(180)
                                : AppColors.primary500,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            readOnly ? 'Lecture seule' : 'Consultation',
                            style: TextStyle(
                              color: readOnly
                                  ? AppColors.white.withAlpha(180)
                                  : AppColors.primary500,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Présentez ce code à votre médecin',
                      style: TextStyle(
                        color: AppColors.white.withAlpha(180),
                        fontSize: 14,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withAlpha(80),
                            blurRadius: 32,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        size: 260,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: Color(0xFF003D39),
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF003D39),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    _CountdownRing(seconds: remainingSeconds, urgent: isUrgent),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.white.withAlpha(15),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Symbols.shield_rounded,
                            size: 14,
                            color: AppColors.primary500,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Valable 120 s — Partagez uniquement avec votre médecin',
                            style: TextStyle(
                              color: AppColors.white.withAlpha(153),
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CountdownRing extends StatelessWidget {
  const _CountdownRing({required this.seconds, required this.urgent});

  final int seconds;
  final bool urgent;

  @override
  Widget build(BuildContext context) {
    final color = urgent ? AppColors.allergy : AppColors.primary500;
    final progress = (seconds / 120).clamp(0.0, 1.0);

    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 80,
          height: 80,
          child: CircularProgressIndicator(
            value: progress,
            strokeWidth: 4,
            backgroundColor: AppColors.white.withAlpha(25),
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$seconds',
              style: TextStyle(
                color: color,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              's',
              style: TextStyle(
                color: color.withAlpha(180),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ExpiredView extends StatelessWidget {
  const _ExpiredView({required this.onRegenerate});

  final VoidCallback onRegenerate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.white.withAlpha(15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Symbols.timer_off_rounded,
                size: 40,
                color: AppColors.white.withAlpha(153),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Code expiré',
              style: TextStyle(
                color: AppColors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Pour la sécurité, chaque code n\'est valable que 120 secondes.',
              style: TextStyle(
                color: AppColors.white.withAlpha(153),
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: onRegenerate,
              icon: const Icon(Symbols.refresh_rounded),
              label: const Text('Régénérer'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary500,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.error_rounded,
              size: 56,
              color: AppColors.allergy.withAlpha(200),
            ),
            const SizedBox(height: 24),
            const Text(
              'Impossible de générer le code',
              style: TextStyle(
                color: AppColors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              style: TextStyle(
                color: AppColors.white.withAlpha(120),
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Symbols.refresh_rounded, color: AppColors.white),
              label: const Text(
                'Réessayer',
                style: TextStyle(color: AppColors.white),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.white.withAlpha(80)),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Media selection bottom sheet (#143) ───────────────────────────────────────

class _MediaSelectionSheet extends StatefulWidget {
  const _MediaSelectionSheet({required this.media});
  final List<_SelectableMedia> media;

  @override
  State<_MediaSelectionSheet> createState() => _MediaSelectionSheetState();
}

class _MediaSelectionSheetState extends State<_MediaSelectionSheet> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    // Pre-select all by default.
    _selected = widget.media.map((m) => m.descriptor.uuid).toSet();
  }

  void _toggleAll(bool select) {
    setState(() {
      _selected =
          select ? widget.media.map((m) => m.descriptor.uuid).toSet() : {};
    });
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    // Build ordered group map preserving insertion order.
    final groups = <String, List<_SelectableMedia>>{};
    for (final m in widget.media) {
      (groups[m.groupLabel] ??= []).add(m);
    }

    final allSelected = _selected.length == widget.media.length;
    final noneSelected = _selected.isEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollCtrl) => Column(
        children: [
          // Drag handle
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.neutral200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Partager avec le médecin',
                    style:
                        tt.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  icon: const Icon(Symbols.close_rounded),
                  tooltip: 'Annuler',
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
          ),
          // Select all / none
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                TextButton(
                  onPressed: allSelected ? null : () => _toggleAll(true),
                  child: const Text('Tout sélectionner'),
                ),
                TextButton(
                  onPressed: noneSelected ? null : () => _toggleAll(false),
                  child: const Text('Tout désélectionner'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Scrollable list grouped by source
          Expanded(
            child: ListView(
              controller: scrollCtrl,
              children: [
                for (final groupLabel in groups.keys) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                    child: Text(
                      groupLabel,
                      style: tt.labelMedium?.copyWith(
                        color: AppColors.primary700,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  for (final m in groups[groupLabel]!)
                    CheckboxListTile(
                      value: _selected.contains(m.descriptor.uuid),
                      onChanged: (v) => setState(() {
                        if (v ?? false) {
                          _selected.add(m.descriptor.uuid);
                        } else {
                          _selected.remove(m.descriptor.uuid);
                        }
                      }),
                      title: Text(m.itemLabel, style: tt.bodyMedium),
                      subtitle: Text(
                        '${(m.descriptor.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                        style:
                            tt.bodySmall?.copyWith(color: AppColors.neutral500),
                      ),
                      activeColor: AppColors.primary700,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 12),
                    ),
                ],
                const SizedBox(height: 16),
              ],
            ),
          ),
          // Confirm button — always enabled; empty set = QR without attachments
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, _selected),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary700,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                ),
                child: Text(
                  _selected.isEmpty
                      ? 'Générer le QR sans pièces jointes'
                      : 'Partager ${_selected.length} fichier${_selected.length > 1 ? 's' : ''}',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
