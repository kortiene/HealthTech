// Quick-edit consultation form (issue #18 — US-2.2, "formulaire d'édition rapide").
//
// The doctor adds a clinical note and/or a structured ordonnance during an open
// consultation session. On "Enregistrer" the form:
//   1. builds a [Prescription] from the dynamic drug lines,
//   2. calls the PURE [mergeConsultation] to APPEND a new consultation (and any
//      prescribed medications) without overwriting history,
//   3. re-encrypts the merged record IN RAM with the session key via
//      [ConsultationEditService.reEncrypt] (size budget enforced),
//   4. pops a [ConsultationEditResult] (merged record + pending blob) back to
//      [RecordViewScreen], which updates the in-RAM session.
//
// RAM hygiene: every [TextEditingController] is disposed in [dispose]; the
// plaintext the doctor types lives ONLY in controllers and the in-RAM record —
// nothing is written to disk or logged (PRD §4, zero-knowledge). The
// authoritative end-of-session wipe is #19.
//
// French UI strings, English identifiers.

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../doctor/consultation_edit_service.dart';
import '../doctor/consultation_merge.dart';
import '../qr/access_token.dart';
import '../record/medical_record.dart';
import '../record/prescription.dart';
import '../rust/crypto_core_bindings.dart';

/// Session-scoped placeholder practitioner reference.
///
/// There is no doctor identity/authentication in the codebase yet (spec Risk
/// #2). v1 uses this opaque placeholder; the real source (doctor login /
/// device-bound id) is deferred to a later issue.
// TODO(#18-followup): replace with an authenticated practitioner reference.
const String kUnverifiedPractitionerRef = 'practitioner-unverified';

/// Generate an RFC-4122 v4 UUID from the OS CSPRNG (spec Risk #5).
String generateSecureUuidV4() {
  final rng = Random.secure();
  final b = Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
  b[6] = (b[6] & 0x0F) | 0x40; // version 4
  b[8] = (b[8] & 0x3F) | 0x80; // variant RFC 4122
  String hex(int v) => v.toRadixString(16).padLeft(2, '0');
  return '${hex(b[0])}${hex(b[1])}${hex(b[2])}${hex(b[3])}-'
      '${hex(b[4])}${hex(b[5])}-'
      '${hex(b[6])}${hex(b[7])}-'
      '${hex(b[8])}${hex(b[9])}-'
      '${hex(b[10])}${hex(b[11])}${hex(b[12])}${hex(b[13])}${hex(b[14])}${hex(b[15])}';
}

/// Result returned by [ConsultationEditScreen] on a successful save.
///
/// Both fields are RAM-only: [record] is the merged in-RAM record and [blob] is
/// the session-key ciphertext (`nonce||ct||tag`) handed to the #19 upload flow.
class ConsultationEditResult {
  const ConsultationEditResult({required this.record, required this.blob});

  final MedicalRecord record;
  final Uint8List blob;
}

/// Quick-edit form for adding a consultation note and/or ordonnance.
class ConsultationEditScreen extends StatefulWidget {
  ConsultationEditScreen({
    super.key,
    required this.record,
    required this.payload,
    required this.service,
    this.practitionerRef = kUnverifiedPractitionerRef,
    String Function()? idFactory,
    DateTime Function()? clock,
  })  : idFactory = idFactory ?? generateSecureUuidV4,
        clock = clock ?? (() => DateTime.now().toUtc());

  /// The current in-RAM record to merge into (never mutated by this screen).
  final MedicalRecord record;

  /// Holds the ephemeral session key used for re-encryption.
  final QrPayload payload;

  final ConsultationEditService service;

  /// Opaque practitioner reference written to the appended consultation.
  final String practitionerRef;

  /// Injectable id source (default: OS CSPRNG UUID v4) — overridden in tests.
  final String Function() idFactory;

  /// Injectable clock (default: `DateTime.now().toUtc()`) — overridden in tests.
  final DateTime Function() clock;

  @override
  State<ConsultationEditScreen> createState() => _ConsultationEditScreenState();
}

class _ConsultationEditScreenState extends State<ConsultationEditScreen> {
  final TextEditingController _noteController = TextEditingController();
  final List<_LineControllers> _lines = [_LineControllers()];
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _noteController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _addLine() => setState(() => _lines.add(_LineControllers()));

  void _removeLine(int index) {
    setState(() {
      _lines.removeAt(index).dispose();
      if (_lines.isEmpty) _lines.add(_LineControllers());
    });
  }

  Prescription _buildPrescription() {
    return Prescription(
      lines: [
        for (final line in _lines)
          PrescriptionLine(
            drug: line.drug.text.trim(),
            dose: line.dose.text.trim(),
            frequency: line.frequency.text.trim(),
            durationDays: int.tryParse(line.duration.text.trim()),
          ),
      ],
    );
  }

  Future<void> _save() async {
    if (_saving) return;
    final summary = _noteController.text.trim();
    final prescription = _buildPrescription();
    if (summary.isEmpty && prescription.isEmpty) {
      setState(() => _error = 'Ajoutez une note ou une ordonnance.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    final now = widget.clock();
    final nowIso = now.toIso8601String();
    final date = nowIso.substring(0, 10); // yyyy-MM-dd
    final consultationId = widget.idFactory();

    try {
      final merged = mergeConsultation(
        widget.record,
        practitionerRef: widget.practitionerRef,
        date: date,
        summary: summary,
        prescription: prescription.isEmpty ? null : prescription,
        newConsultationId: consultationId,
        nowIso: nowIso,
      );
      final blob = await widget.service.reEncrypt(
        merged,
        widget.payload,
        newConsultationId: consultationId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(
        ConsultationEditResult(record: merged, blob: blob),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _errorMessage(e);
      });
    }
  }

  String _errorMessage(Object e) => switch (e) {
        RecordFullException() =>
          'Dossier plein — impossible d’ajouter la note.',
        CryptoCoreUnavailable() =>
          'Chiffrement indisponible — réessayez plus tard.',
        _ => 'Échec de l’enregistrement — réessayez.',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ajouter une note / ordonnance')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _noteController,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Note de consultation',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Ordonnance',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Divider(),
          for (var i = 0; i < _lines.length; i++)
            _PrescriptionLineRow(
              key: ValueKey(_lines[i]),
              controllers: _lines[i],
              onRemove: () => _removeLine(i),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _addLine,
              icon: const Icon(Icons.add),
              label: const Text('Ajouter un médicament'),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            label: const Text('Enregistrer'),
          ),
        ],
      ),
    );
  }
}

/// Bundles the four [TextEditingController]s for one prescription line.
class _LineControllers {
  final TextEditingController drug = TextEditingController();
  final TextEditingController dose = TextEditingController();
  final TextEditingController frequency = TextEditingController();
  final TextEditingController duration = TextEditingController();

  void dispose() {
    drug.dispose();
    dose.dispose();
    frequency.dispose();
    duration.dispose();
  }
}

class _PrescriptionLineRow extends StatelessWidget {
  const _PrescriptionLineRow({
    super.key,
    required this.controllers,
    required this.onRemove,
  });

  final _LineControllers controllers;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: controllers.drug,
                  decoration: const InputDecoration(labelText: 'Médicament'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: controllers.dose,
                  decoration: const InputDecoration(labelText: 'Dose'),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.remove_circle_outline),
                tooltip: 'Retirer',
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: controllers.frequency,
                  decoration: const InputDecoration(labelText: 'Fréquence'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: TextField(
                  controller: controllers.duration,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Durée (j)'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
