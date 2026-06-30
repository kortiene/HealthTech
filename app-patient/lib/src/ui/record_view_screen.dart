// Medical record viewer with doctor edit entry point (issues #17–#19, #22).
//
// #17: Displays the decrypted [MedicalRecord] in RAM only.
// #18: Adds "Ajouter une note / ordonnance" (opens [ConsultationEditScreen];
//      merged record + re-encrypted blob stored in RAM-only [ConsultationSession]).
// #19: Adds "Terminer" AppBar action + 15-min idle [Timer] — on either trigger,
//      [SessionEndService.terminate] PUTs the pending blob (if edited) then
//      wipes the session (session key + blob bytes). No plaintext, key, or PII
//      is ever written to any storage layer.
// #22: Surfaces the offline queue: a "N en attente" badge, a manual
//      "Synchroniser" action that drains via [SyncService], and an OPPORTUNISTIC
//      drain after an end-of-session PUT (a success proves the network is back).
//      The drain never touches the (wiped) session key — only opaque queued bytes.

import 'dart:async';

import 'package:flutter/material.dart';

import '../cloud/backend_client.dart';
import '../doctor/consultation_edit_service.dart';
import '../doctor/consultation_session.dart';
import '../doctor/offline_upload_queue.dart';
import '../doctor/session_end_service.dart';
import '../doctor/sqlcipher_upload_queue.dart';
import '../doctor/sync_service.dart';
import '../qr/access_token.dart';
import '../record/medical_record.dart';
import '../rust/crypto_core_bindings.dart';
import 'consultation_edit_screen.dart';

/// Viewer for a decrypted [MedicalRecord] with a doctor edit entry point.
///
/// [payload] is held for the session key lifecycle and wiped in [dispose].
/// [record] is rendered in RAM and never written to disk. Inject [editService],
/// [endService] and [syncService] in tests; production defaults wire a shared
/// [SqlCipherUploadQueue] behind both the end-of-session enqueue and the #22
/// drain, plus [FrbCryptoCore]-backed re-encryption and a [BackendClient].
class RecordViewScreen extends StatefulWidget {
  factory RecordViewScreen({
    Key? key,
    required MedicalRecord record,
    required QrPayload payload,
    ConsultationEditService? editService,
    SessionEndService? endService,
    SyncService? syncService,
    OfflineUploadQueue? queue,
  }) {
    // Share ONE queue between the end-of-session enqueue and the #22 drain, so a
    // freshly-queued blob and any backlog drain through the same durable store.
    final sharedQueue = queue ?? SqlCipherUploadQueue();
    final client = BackendClient(payload.backendUrl);
    return RecordViewScreen._(
      key: key,
      record: record,
      payload: payload,
      editService:
          editService ?? ConsultationEditService(crypto: const FrbCryptoCore()),
      endService:
          endService ?? SessionEndService(client: client, queue: sharedQueue),
      syncService:
          syncService ?? SyncService(client: client, queue: sharedQueue),
    );
  }

  const RecordViewScreen._({
    super.key,
    required this.record,
    required this.payload,
    required this.editService,
    required this.endService,
    required this.syncService,
  });

  final MedicalRecord record;
  final QrPayload payload;
  final ConsultationEditService editService;
  final SessionEndService endService;
  final SyncService syncService;

  @override
  State<RecordViewScreen> createState() => _RecordViewScreenState();
}

class _RecordViewScreenState extends State<RecordViewScreen> {
  late final ConsultationSession _session = ConsultationSession(
    payload: widget.payload,
    record: widget.record,
  );

  Timer? _idleTimer;
  bool _terminating = false;
  bool _syncing = false;
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _resetIdleTimer();
    _refreshPendingCount();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _session.wipe();
    super.dispose();
  }

  Future<void> _refreshPendingCount() async {
    final count = await widget.syncService.queueCount();
    if (!mounted) return;
    setState(() => _pendingCount = count);
  }

  /// Manual "Synchroniser" or opportunistic drain. Never throws to the UI; a
  /// [SyncSummary] is reported and the badge refreshed. Conflicts / persistent
  /// failures are surfaced (never silently dropped).
  Future<void> _syncNow() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final summary = await widget.syncService.drain();
      if (!mounted) return;
      setState(() => _pendingCount = summary.remaining);
      if (summary.conflicts > 0 || summary.persistentFailures > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Synchro incomplète — éléments en conflit ou en échec persistant. '
              'Action requise.',
            ),
            duration: Duration(seconds: 6),
          ),
        );
      } else if (summary.synced > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${summary.synced} consultation(s) synchronisée(s).'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(const Duration(minutes: 15), _terminateSession);
  }

  Future<void> _terminateSession() async {
    if (_terminating || !mounted) return;
    _idleTimer?.cancel();
    setState(() => _terminating = true);
    try {
      final outcome = await widget.endService.terminate(_session);
      if (!mounted) return;
      // #21: an offline session is VALIDATED — the encrypted blob is safely
      // queued and will sync later (#22). Reassure the doctor; never an error.
      if (outcome == SessionEndOutcome.queued) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Consultation enregistrée hors-ligne — synchro à la reconnexion.',
            ),
            duration: Duration(seconds: 5),
          ),
        );
      } else if (outcome == SessionEndOutcome.uploaded) {
        // #22: a successful end-of-session PUT proves the network is back — drain
        // any backlog opportunistically (fire-and-forget; never blocks the pop).
        unawaited(widget.syncService.drain());
      }
      Navigator.of(context).pop();
    } on OfflineQueueUnavailable {
      if (!mounted) return;
      // Session is already wiped in SessionEndService.terminate's finally.
      // Both the upload AND the local queue failed — the only path that can
      // still lose the edit. Alert the doctor loudly before closing.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Échec d'enregistrement local — les modifications n'ont pas pu "
            'être sauvegardées.',
          ),
          duration: Duration(seconds: 8),
        ),
      );
      Navigator.of(context).pop();
    }
  }

  Future<void> _openEditScreen() async {
    _resetIdleTimer();
    final result = await Navigator.of(context).push<ConsultationEditResult>(
      MaterialPageRoute<ConsultationEditResult>(
        builder: (_) => ConsultationEditScreen(
          record: _session.current,
          payload: _session.payload,
          service: widget.editService,
        ),
      ),
    );
    if (result == null || !mounted) return;
    _resetIdleTimer();
    setState(() => _session.applyMerge(result.record, result.blob));
  }

  @override
  Widget build(BuildContext context) {
    final r = _session.current;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dossier médical'),
        actions: [
          // #22: "N en attente" badge + manual drain. Tooltip carries the count;
          // the badge shows it so the doctor knows work is queued (never lost).
          if (_pendingCount > 0)
            IconButton(
              tooltip: '$_pendingCount en attente — synchroniser',
              onPressed: (_syncing || _terminating) ? null : _syncNow,
              icon: Badge(
                label: Text('$_pendingCount'),
                child: _syncing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
              ),
            ),
          TextButton.icon(
            onPressed: _terminating ? null : _terminateSession,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('Terminer'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _terminating ? null : _openEditScreen,
        icon: const Icon(Icons.note_add),
        label: const Text('Ajouter une note / ordonnance'),
      ),
      body: Listener(
        onPointerDown: (_) => _resetIdleTimer(),
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SectionCard(
                  title: 'Informations',
                  children: _demographicsRows(r.demographics),
                ),
                if (r.allergies.isNotEmpty)
                  _SectionCard(
                    title: 'Allergies',
                    children: r.allergies
                        .map(
                          (a) =>
                              _InfoRow(label: a.substance, value: a.severity),
                        )
                        .toList(),
                  ),
                if (r.chronicConditions.isNotEmpty)
                  _SectionCard(
                    title: 'Pathologies chroniques',
                    children: r.chronicConditions
                        .map(
                          (c) => _InfoRow(label: c.name, value: c.icd10 ?? ''),
                        )
                        .toList(),
                  ),
                if (r.medications.isNotEmpty)
                  _SectionCard(
                    title: 'Médicaments',
                    children: r.medications
                        .map(
                          (m) => _InfoRow(
                            label: m.name,
                            value: '${m.dose} · ${m.frequency}',
                          ),
                        )
                        .toList(),
                  ),
                if (r.consultations.isNotEmpty)
                  _SectionCard(
                    title: 'Consultations',
                    children: r.consultations
                        .map(
                          (c) => _InfoRow(
                            label: c.date,
                            value: c.prescription == null ||
                                    c.prescription!.isEmpty
                                ? c.summary
                                : '${c.summary}\n${c.prescription}',
                          ),
                        )
                        .toList(),
                  ),
              ],
            ),
            if (_terminating)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black26,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _demographicsRows(Demographics d) => [
        if (d.givenName != null) _InfoRow(label: 'Prénom', value: d.givenName!),
        if (d.birthYear != null)
          _InfoRow(label: 'Année naissance', value: '${d.birthYear}'),
        if (d.sex != null) _InfoRow(label: 'Sexe', value: d.sex!),
        if (d.bloodType != null)
          _InfoRow(label: 'Groupe sanguin', value: d.bloodType!),
      ];
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const Divider(),
            ...children,
          ],
        ),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(flex: 3, child: Text(value)),
        ],
      ),
    );
  }
}
