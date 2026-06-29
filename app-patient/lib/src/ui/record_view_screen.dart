// Read-only medical record viewer (issue #17 — US-2.1).
//
// Displays the decrypted [MedicalRecord] in RAM only.  On [dispose], the
// [QrPayload.wipe] is called to overwrite the session key bytes — this marks
// the end of the doctor-side consultation session.  No field of [record] is
// ever written to any storage layer.

import 'package:flutter/material.dart';

import '../qr/access_token.dart';
import '../record/medical_record.dart';

/// Read-only viewer for a decrypted [MedicalRecord].
///
/// [payload] is held for the session key lifecycle and wiped in [dispose].
/// [record] is rendered in RAM and never written to disk.
class RecordViewScreen extends StatefulWidget {
  const RecordViewScreen({
    super.key,
    required this.record,
    required this.payload,
  });

  final MedicalRecord record;
  final QrPayload payload;

  @override
  State<RecordViewScreen> createState() => _RecordViewScreenState();
}

class _RecordViewScreenState extends State<RecordViewScreen> {
  @override
  void dispose() {
    widget.payload.wipe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.record;
    return Scaffold(
      appBar: AppBar(title: const Text('Dossier médical')),
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
