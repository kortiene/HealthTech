// Widget smoke tests for RecordViewScreen (issue #17 — US-2.1).
//
// Verifies that the read-only viewer renders the correct sections and fields
// from a decrypted MedicalRecord.  No storage is involved — all data lives on
// the Dart heap for the duration of each test.

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
}
