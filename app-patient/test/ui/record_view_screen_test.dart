// Widget smoke tests for RecordViewScreen (issue #17 — US-2.1).
//
// Verifies that the read-only viewer renders the correct sections and fields
// from a decrypted MedicalRecord.  No storage is involved — all data lives on
// the Dart heap for the duration of each test.
//
// UX invariant tests (issue #28 — NFR UX guard-rail):
//   - Critical section order: Informations → Allergies → Pathologies → Médicaments
//     → Consultations. An allergy must never sit below the Consultations section.
//   - No navigation drawer, bottom nav bar, or tab bar in the shell (zero-menu norm).
//   - The primary action FAB carries the correct French label.
//   - The "Terminer" AppBar action is always visible (single-tap access).

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/qr/access_token.dart';
import 'package:app_patient/src/record/medical_record.dart';
import 'package:app_patient/src/ui/record_view_screen.dart';

QrPayload _dummyPayload() => QrPayload(
      uuid: 'test-uuid',
      backendUrl: 'http://test',
      sessionKey: Uint8List(32),
      expiresAt: DateTime.now().add(const Duration(seconds: 120)),
    );

void main() {
  testWidgets('shows patient demographics when present', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecordViewScreen(
          record: const MedicalRecord(
            patientId: 'test-id',
            demographics: Demographics(givenName: 'Kofi', bloodType: 'O+'),
            createdAt: '2025-01-01T00:00:00Z',
            updatedAt: '2025-01-01T00:00:00Z',
          ),
          payload: _dummyPayload(),
        ),
      ),
    );
    expect(find.text('Kofi'), findsOneWidget);
    expect(find.text('O+'), findsOneWidget);
  });

  testWidgets('shows Allergies section when allergies are present',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecordViewScreen(
          record: const MedicalRecord(
            patientId: 'test-id',
            allergies: [
              Allergy(
                substance: 'Pénicilline',
                severity: 'severe',
                notedAt: '2024-01-01',
              ),
            ],
            createdAt: '2025-01-01T00:00:00Z',
            updatedAt: '2025-01-01T00:00:00Z',
          ),
          payload: _dummyPayload(),
        ),
      ),
    );
    expect(find.text('Allergies'), findsOneWidget);
    expect(find.text('Pénicilline'), findsOneWidget);
  });

  testWidgets('shows Informations section even when demographics are empty',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RecordViewScreen(
          record: const MedicalRecord(
            patientId: 'test-id',
            createdAt: '2025-01-01T00:00:00Z',
            updatedAt: '2025-01-01T00:00:00Z',
          ),
          payload: _dummyPayload(),
        ),
      ),
    );
    expect(find.text('Informations'), findsOneWidget);
    expect(find.text('Allergies'), findsNothing);
  });

  // ── UX invariant tests (issue #28 — NFR UX guard-rail) ──────────────────────

  group('UX invariants (#28 NFR UX — zero-menu / section order)', () {
    testWidgets(
        'Informations section appears before Allergies section '
        '(life-critical info first, guide UX §3)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
            home: RecordViewScreen(
                record: _fullRecord, payload: _dummyPayload())),
      );

      final informationsTop = tester.getTopLeft(find.text('Informations')).dy;
      final allergiesTop = tester.getTopLeft(find.text('Allergies')).dy;
      expect(informationsTop, lessThan(allergiesTop),
          reason: 'Informations must appear above Allergies');
    });

    testWidgets(
        'Allergies section appears before Consultations section '
        '(allergy never hidden below consultation history)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
            home: RecordViewScreen(
                record: _fullRecord, payload: _dummyPayload())),
      );

      final allergiesTop = tester.getTopLeft(find.text('Allergies')).dy;
      final consultationsTop = tester.getTopLeft(find.text('Consultations')).dy;
      expect(allergiesTop, lessThan(consultationsTop),
          reason: 'Allergies must appear above Consultations');
    });

    testWidgets(
        'Pathologies chroniques section appears before Consultations section',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
            home: RecordViewScreen(
                record: _fullRecord, payload: _dummyPayload())),
      );

      final pathologiesTop =
          tester.getTopLeft(find.text('Pathologies chroniques')).dy;
      final consultationsTop = tester.getTopLeft(find.text('Consultations')).dy;
      expect(pathologiesTop, lessThan(consultationsTop),
          reason: 'Pathologies chroniques must appear above Consultations');
    });

    testWidgets(
        'shell has no Drawer, BottomNavigationBar, or TabBar '
        '(zero-menu norm, guide UX §1)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
            home: RecordViewScreen(
                record: _fullRecord, payload: _dummyPayload())),
      );

      expect(find.byType(Drawer), findsNothing,
          reason: 'no navigation drawer permitted (zero-menu)');
      expect(find.byType(BottomNavigationBar), findsNothing,
          reason: 'no bottom navigation bar permitted');
      expect(find.byType(TabBar), findsNothing,
          reason: 'no tab bar permitted in the consultation shell');
    });

    testWidgets(
        'FAB label is "Ajouter une note / ordonnance" (French, action-oriented)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
            home: RecordViewScreen(
                record: _fullRecord, payload: _dummyPayload())),
      );

      expect(
        find.text('Ajouter une note / ordonnance'),
        findsOneWidget,
        reason: 'primary action FAB must carry the correct French label',
      );
    });

    testWidgets(
        '"Terminer" AppBar action is visible at all times (single-tap access)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
            home: RecordViewScreen(
                record: _fullRecord, payload: _dummyPayload())),
      );

      expect(
        find.text('Terminer'),
        findsOneWidget,
        reason:
            '"Terminer" must be in the AppBar — single-tap, always accessible',
      );
    });

    testWidgets('AppBar title is "Dossier médical" (French, no jargon)',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
            home: RecordViewScreen(
                record: _fullRecord, payload: _dummyPayload())),
      );

      expect(
        find.text('Dossier médical'),
        findsOneWidget,
        reason:
            'AppBar title must be the action-oriented French label from the guide',
      );
    });
  });
}

/// A synthetic full record with every section populated so we can check order.
const _fullRecord = MedicalRecord(
  patientId: 'ux-invariant-test-id',
  demographics: Demographics(givenName: 'Awa', birthYear: 1990, sex: 'F'),
  allergies: [
    Allergy(
        substance: 'Pénicilline', severity: 'severe', notedAt: '2024-01-01'),
  ],
  chronicConditions: [
    ChronicCondition(name: 'Hypertension', icd10: 'I10'),
  ],
  medications: [
    Medication(
      name: 'Amlodipine',
      dose: '5 mg',
      frequency: '1×/jour',
      prescribedAt: '2025-01-01',
    ),
  ],
  consultations: [
    Consultation(
      id: 'c-01',
      date: '2026-01-01',
      practitionerRef: 'dr-test',
      summary: 'Bilan annuel',
    ),
  ],
  createdAt: '2025-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);
