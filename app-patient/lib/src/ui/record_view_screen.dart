// Medical record viewer with doctor edit entry point (issues #17, #18).
//
// Displays the decrypted [MedicalRecord] in RAM only.  #18 adds an "Ajouter une
// note / ordonnance" action that opens [ConsultationEditScreen]; on save the
// merged record + re-encrypted blob are stored on a RAM-only [ConsultationSession]
// (the single source of truth threaded to the #19 upload/wipe flow) and the
// appended consultation is shown immediately.  On [dispose] the session is wiped
// (session key + pending blob) — this marks the end of the doctor-side session.
// No field of the record is ever written to any storage layer.

import 'package:flutter/material.dart';

import '../doctor/consultation_edit_service.dart';
import '../doctor/consultation_session.dart';
import '../qr/access_token.dart';
import '../record/medical_record.dart';
import '../rust/crypto_core_bindings.dart';
import 'consultation_edit_screen.dart';

/// Viewer for a decrypted [MedicalRecord] with a doctor edit entry point.
///
/// [payload] is held for the session key lifecycle and wiped in [dispose].
/// [record] is rendered in RAM and never written to disk. Inject [editService]
/// in tests; production defaults to [FrbCryptoCore]-backed re-encryption.
class RecordViewScreen extends StatefulWidget {
  RecordViewScreen({
    super.key,
    required this.record,
    required this.payload,
    ConsultationEditService? editService,
  }) : editService = editService ??
            ConsultationEditService(crypto: const FrbCryptoCore());

  final MedicalRecord record;
  final QrPayload payload;
  final ConsultationEditService editService;

  @override
  State<RecordViewScreen> createState() => _RecordViewScreenState();
}

class _RecordViewScreenState extends State<RecordViewScreen> {
  late final ConsultationSession _session = ConsultationSession(
    payload: widget.payload,
    record: widget.record,
  );

  @override
  void dispose() {
    _session.wipe();
    super.dispose();
  }

  Future<void> _openEditScreen() async {
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
    setState(() => _session.applyMerge(result.record, result.blob));
  }

  @override
  Widget build(BuildContext context) {
    final r = _session.current;
    return Scaffold(
      appBar: AppBar(title: const Text('Dossier médical')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openEditScreen,
        icon: const Icon(Icons.note_add),
        label: const Text('Ajouter une note / ordonnance'),
      ),
      body: ListView(
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
                    (a) => _InfoRow(label: a.substance, value: a.severity),
                  )
                  .toList(),
            ),
          if (r.chronicConditions.isNotEmpty)
            _SectionCard(
              title: 'Pathologies chroniques',
              children: r.chronicConditions
                  .map((c) => _InfoRow(label: c.name, value: c.icd10 ?? ''))
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
                      value: c.prescription == null || c.prescription!.isEmpty
                          ? c.summary
                          : '${c.summary}\n${c.prescription}',
                    ),
                  )
                  .toList(),
            ),
        ],
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
