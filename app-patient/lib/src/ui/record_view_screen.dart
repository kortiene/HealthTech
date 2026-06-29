// Medical record viewer with doctor edit entry point (issues #17–#19).
//
// #17: Displays the decrypted [MedicalRecord] in RAM only.
// #18: Adds "Ajouter une note / ordonnance" (opens [ConsultationEditScreen];
//      merged record + re-encrypted blob stored in RAM-only [ConsultationSession]).
// #19: Adds "Terminer" AppBar action + 15-min idle [Timer] — on either trigger,
//      [SessionEndService.terminate] PUTs the pending blob (if edited) then
//      wipes the session (session key + blob bytes). No plaintext, key, or PII
//      is ever written to any storage layer.

import 'dart:async';

import 'package:flutter/material.dart';

import '../cloud/backend_client.dart';
import '../doctor/consultation_edit_service.dart';
import '../doctor/consultation_session.dart';
import '../doctor/session_end_service.dart';
import '../qr/access_token.dart';
import '../record/medical_record.dart';
import '../rust/crypto_core_bindings.dart';
import 'consultation_edit_screen.dart';

/// Viewer for a decrypted [MedicalRecord] with a doctor edit entry point.
///
/// [payload] is held for the session key lifecycle and wiped in [dispose].
/// [record] is rendered in RAM and never written to disk. Inject [editService]
/// and [endService] in tests; production defaults to [FrbCryptoCore]-backed
/// re-encryption and a [BackendClient]-backed upload.
class RecordViewScreen extends StatefulWidget {
  RecordViewScreen({
    super.key,
    required this.record,
    required this.payload,
    ConsultationEditService? editService,
    SessionEndService? endService,
  })  : editService = editService ??
            ConsultationEditService(crypto: const FrbCryptoCore()),
        endService = endService ??
            SessionEndService(client: BackendClient(payload.backendUrl));

  final MedicalRecord record;
  final QrPayload payload;
  final ConsultationEditService editService;
  final SessionEndService endService;

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

  @override
  void initState() {
    super.initState();
    _resetIdleTimer();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _session.wipe();
    super.dispose();
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
      await widget.endService.terminate(_session);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on BackendUnavailable {
      if (!mounted) return;
      // Session is already wiped in SessionEndService.terminate's finally.
      // Inform the doctor before closing — ScaffoldMessenger survives the pop.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Synchro échouée — les modifications n'ont pas été sauvegardées.",
          ),
          duration: Duration(seconds: 5),
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
