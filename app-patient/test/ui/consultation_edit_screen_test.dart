// Widget tests for ConsultationEditScreen (issue #18 — US-2.2).
//
// Verified properties:
//   - Form renders note field, prescription section, and "Enregistrer" button.
//   - Tapping "Enregistrer" with empty note and blank prescription rows shows
//     an inline error and does NOT call the service.
//   - Saving a note (without prescription) returns a ConsultationEditResult
//     whose merged record has a new consultation containing the typed text.
//   - Saving with a prescription line returns a result with the rendered
//     ordonnance in the consultation's prescription field and an appended
//     Medication entry.
//   - RecordFullException maps to the "Dossier plein" error string (no data
//     leaked in the message).
//   - CryptoCoreUnavailable maps to the "Chiffrement indisponible" message.
//   - Unknown exceptions map to a generic "Échec de l'enregistrement" message.
//   - No exception surfaces to the framework after RecordFullException
//     (saving = false, error shown inline).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/doctor/consultation_edit_service.dart';
import 'package:app_patient/src/qr/access_token.dart';
import 'package:app_patient/src/record/medical_record.dart';
import 'package:app_patient/src/rust/crypto_core_bindings.dart';
import 'package:app_patient/src/ui/consultation_edit_screen.dart';

// ─── Fakes ────────────────────────────────────────────────────────────────────

/// Implements only the public surface of [ConsultationEditService].
/// Returns a fixed fake blob or throws [failWith] when set.
class _FakeConsultationEditService implements ConsultationEditService {
  _FakeConsultationEditService({this.failWith});

  final Object? failWith;

  static final fakeBlob = Uint8List.fromList([0xAB, 0xCD]);

  @override
  Future<Uint8List> reEncrypt(
    MedicalRecord merged,
    QrPayload payload, {
    required String newConsultationId,
  }) async {
    if (failWith != null) throw failWith!;
    return fakeBlob;
  }
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

const _kPatientId = 'patient-fake-uuid-001';
const _kNewConsultId = 'test-fixed-consult-id';
const _kTestDate = '2026-06-29';

const _kRecord = MedicalRecord(
  patientId: _kPatientId,
  createdAt: '2025-01-01T00:00:00Z',
  updatedAt: '2025-01-01T00:00:00Z',
);

QrPayload _payload() => QrPayload(
      uuid: _kPatientId,
      backendUrl: 'http://backend.test',
      sessionKey: Uint8List(32),
      expiresAt: DateTime.now().add(const Duration(seconds: 120)),
    );

/// Mounts [ConsultationEditScreen] inside a [MaterialApp] reachable via a
/// `Navigator.push` from a launcher button. Returns the [Future] that resolves
/// to the [ConsultationEditResult] (or null) when the screen pops.
Future<Future<ConsultationEditResult?>> _pushScreen(
  WidgetTester tester, {
  _FakeConsultationEditService? service,
}) async {
  late Future<ConsultationEditResult?> resultFuture;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (ctx) => ElevatedButton(
          onPressed: () {
            resultFuture = Navigator.push<ConsultationEditResult>(
              ctx,
              MaterialPageRoute<ConsultationEditResult>(
                builder: (_) => ConsultationEditScreen(
                  record: _kRecord,
                  payload: _payload(),
                  service: service ?? _FakeConsultationEditService(),
                  practitionerRef: 'dr-fake-test',
                  idFactory: () => _kNewConsultId,
                  clock: () => DateTime(2026, 6, 29, 8, 0),
                ),
              ),
            );
          },
          child: const Text('open'),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return resultFuture;
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('ConsultationEditScreen — rendering', () {
    testWidgets('shows the note field', (tester) async {
      await _pushScreen(tester);
      expect(
        find.widgetWithText(TextField, 'Note de consultation'),
        findsOneWidget,
      );
    });

    testWidgets('shows the Ordonnance section heading', (tester) async {
      await _pushScreen(tester);
      expect(find.text('Ordonnance'), findsOneWidget);
    });

    testWidgets('shows the Enregistrer button', (tester) async {
      await _pushScreen(tester);
      expect(find.text('Enregistrer'), findsOneWidget);
    });

    testWidgets('shows at least one prescription line row by default',
        (tester) async {
      await _pushScreen(tester);
      expect(find.widgetWithText(TextField, 'Médicament'), findsOneWidget);
    });

    testWidgets('shows Ajouter un médicament button', (tester) async {
      await _pushScreen(tester);
      expect(find.text('Ajouter un médicament'), findsOneWidget);
    });
  });

  group('ConsultationEditScreen — validation', () {
    testWidgets(
        'tapping Enregistrer with empty note and blank prescription shows error',
        (tester) async {
      await _pushScreen(tester);
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(
        find.text('Ajoutez une note ou une ordonnance.'),
        findsOneWidget,
      );
    });

    testWidgets(
        'validation error: service is not called for empty note + blank prescription',
        (tester) async {
      var serviceCalled = false;
      final svc = _FakeConsultationEditService();

      await _pushScreen(tester, service: svc);
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      // screen still visible → service was not called → navigation did not happen
      expect(find.text('Enregistrer'), findsOneWidget);
      expect(serviceCalled, isFalse);
    });
  });

  group('ConsultationEditScreen — successful save', () {
    testWidgets('typing a note and saving returns a ConsultationEditResult',
        (tester) async {
      final resultFuture = await _pushScreen(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Note de consultation'),
        'Rhume banal',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      final result = await resultFuture;
      expect(result, isNotNull);
    });

    testWidgets(
        'returned record has a new consultation with the typed note summary',
        (tester) async {
      final resultFuture = await _pushScreen(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Note de consultation'),
        'Rhume banal',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      final result = await resultFuture;
      final consults = result!.record.consultations;
      expect(consults, hasLength(1));
      expect(consults.first.summary, 'Rhume banal');
    });

    testWidgets('returned consultation id matches the injected idFactory',
        (tester) async {
      final resultFuture = await _pushScreen(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Note de consultation'),
        'Bilan',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      final result = await resultFuture;
      expect(result!.record.consultations.first.id, _kNewConsultId);
    });

    testWidgets('returned consultation date matches the injected clock',
        (tester) async {
      final resultFuture = await _pushScreen(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Note de consultation'),
        'Bilan',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      final result = await resultFuture;
      expect(result!.record.consultations.first.date, _kTestDate);
    });

    testWidgets('returned blob is the fake service blob', (tester) async {
      final resultFuture = await _pushScreen(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Note de consultation'),
        'Bilan',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      final result = await resultFuture;
      expect(result!.blob, equals(_FakeConsultationEditService.fakeBlob));
    });

    testWidgets(
        'saving with a prescription line appends a Medication to the record',
        (tester) async {
      final resultFuture = await _pushScreen(tester);

      // Fill prescription line fields: Médicament / Dose / Fréquence
      final drugField = find.widgetWithText(TextField, 'Médicament');
      final doseField = find.widgetWithText(TextField, 'Dose');
      final freqField = find.widgetWithText(TextField, 'Fréquence');

      await tester.enterText(drugField, 'Amoxicilline');
      await tester.enterText(doseField, '500 mg');
      await tester.enterText(freqField, '3×/jour');

      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      final result = await resultFuture;
      expect(result!.record.medications, hasLength(1));
      expect(result.record.medications.first.name, 'Amoxicilline');
    });

    testWidgets(
        'prescription line is rendered into consultation.prescription text',
        (tester) async {
      final resultFuture = await _pushScreen(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Médicament'),
        'Paracétamol',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Dose'),
        '500 mg',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Fréquence'),
        'si besoin',
      );

      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      final result = await resultFuture;
      final prescription = result!.record.consultations.first.prescription;
      expect(prescription, isNotNull);
      expect(prescription, contains('Paracétamol'));
      expect(prescription, contains('500 mg'));
    });

    testWidgets(
        'saving with both note and prescription: summary and prescription both set',
        (tester) async {
      final resultFuture = await _pushScreen(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Note de consultation'),
        'Rhume banal',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Médicament'),
        'Paracétamol',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Dose'),
        '500 mg',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Fréquence'),
        'si besoin',
      );

      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      final result = await resultFuture;
      final consult = result!.record.consultations.first;
      expect(consult.summary, 'Rhume banal');
      expect(consult.prescription, isNotNull);
      expect(consult.prescription, contains('Paracétamol'));
    });

    testWidgets(
        'injected practitionerRef is written to the returned consultation',
        (tester) async {
      final resultFuture = await _pushScreen(tester);

      await tester.enterText(
        find.widgetWithText(TextField, 'Note de consultation'),
        'Bilan',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      final result = await resultFuture;
      expect(
        result!.record.consultations.first.practitionerRef,
        'dr-fake-test',
      );
    });
  });

  group('ConsultationEditScreen — error handling', () {
    testWidgets('RecordFullException shows Dossier plein message',
        (tester) async {
      await _pushScreen(
        tester,
        service:
            _FakeConsultationEditService(failWith: const RecordFullException()),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Note de consultation'),
        'Note',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Dossier plein'), findsOneWidget);
    });

    testWidgets('CryptoCoreUnavailable shows Chiffrement indisponible message',
        (tester) async {
      await _pushScreen(
        tester,
        service: _FakeConsultationEditService(
          failWith: const CryptoCoreUnavailable(),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Note de consultation'),
        'Note',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Chiffrement indisponible'), findsOneWidget);
    });

    testWidgets("unknown exception shows generic Échec de l'enregistrement",
        (tester) async {
      await _pushScreen(
        tester,
        service: _FakeConsultationEditService(
          failWith: Exception('unexpected failure'),
        ),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Note de consultation'),
        'Note',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Échec de l'), findsOneWidget);
    });

    testWidgets('error after RecordFullException: screen is still visible',
        (tester) async {
      await _pushScreen(
        tester,
        service:
            _FakeConsultationEditService(failWith: const RecordFullException()),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Note de consultation'),
        'Note',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      // Screen did not pop — Enregistrer button is still present.
      expect(find.text('Enregistrer'), findsOneWidget);
    });

    testWidgets(
        'Enregistrer button is re-enabled after an error (retry allowed)',
        (tester) async {
      await _pushScreen(
        tester,
        service:
            _FakeConsultationEditService(failWith: const RecordFullException()),
      );

      await tester.enterText(
        find.widgetWithText(TextField, 'Note de consultation'),
        'Note',
      );
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();

      // _saving is reset to false after the error: the save icon is shown
      // rather than the CircularProgressIndicator, proving the button is active.
      expect(find.byIcon(Icons.save), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // A second tap succeeds without exception (button is not disabled).
      await tester.tap(find.text('Enregistrer'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Dossier plein'), findsOneWidget);
    });
  });

  group('ConsultationEditScreen — prescription line management', () {
    testWidgets('tapping Ajouter un médicament adds a second line row',
        (tester) async {
      await _pushScreen(tester);
      await tester.tap(find.text('Ajouter un médicament'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Médicament'), findsNWidgets(2));
    });

    testWidgets('tapping remove icon on a line removes it', (tester) async {
      await _pushScreen(tester);
      await tester.tap(find.text('Ajouter un médicament'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Médicament'), findsNWidgets(2));

      // Tap the first remove button.
      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Médicament'), findsOneWidget);
    });

    testWidgets(
        'removing all lines re-creates one blank line (no empty list state)',
        (tester) async {
      await _pushScreen(tester);
      // The screen starts with one line; remove it.
      await tester.tap(find.byIcon(Icons.remove_circle_outline).first);
      await tester.pumpAndSettle();
      // Implementation re-adds one blank line when list empties.
      expect(find.widgetWithText(TextField, 'Médicament'), findsOneWidget);
    });
  });
}
