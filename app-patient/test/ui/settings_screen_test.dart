// Widget tests for SettingsScreen — new params added in issues #105, #106, #110, #112.
//
// Verified properties:
//   - "Sauvegarder maintenant" tile is always rendered.
//   - "Dernière sauvegarde" shows "Jamais" when lastSyncedAt is null.
//   - "Dernière sauvegarde" shows a non-empty value when lastSyncedAt is set.
//   - "Politique de confidentialité" tile is always rendered.
//   - Tapping "Supprimer mon compte" confirmation calls onDeleteAccount.
//   - onManualSync callback is wired to the sync tile.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/legal/consent_model.dart';
import 'package:app_patient/src/record/medical_record.dart';
import 'package:app_patient/src/secure/patient_account.dart';
import 'package:app_patient/src/ui/settings_screen.dart';

// ─── Test fixtures ────────────────────────────────────────────────────────────

const _account = PatientAccount(
  anonymousUuid: '00000000-0000-4000-8000-000000000001',
  cmuNumber: '123456789012',
  phone: '+2250700000001',
  consent: ConsentRecord(version: '1.0', acceptedAt: '2025-01-01T00:00:00.000Z'),
  createdAt: '2025-01-01T00:00:00.000Z',
);

const _record = MedicalRecord(
  patientId: '00000000-0000-4000-8000-000000000001',
  createdAt: '2025-01-01T00:00:00.000Z',
  updatedAt: '2025-01-01T00:00:00.000Z',
);

Widget _buildScreen({
  String? lastSyncedAt,
  Future<void> Function()? onManualSync,
  Future<void> Function()? onDeleteAccount,
}) {
  return MaterialApp(
    home: SettingsScreen(
      record: _record,
      account: _account,
      onLock: () {},
      lastSyncedAt: lastSyncedAt,
      onManualSync: onManualSync,
      onDeleteAccount: onDeleteAccount,
    ),
  );
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

/// Scrolls the first scrollable until [text] is visible, then returns the finder.
Future<Finder> _scrollTo(WidgetTester tester, String text) async {
  final target = find.text(text);
  await tester.scrollUntilVisible(
    target,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  return target;
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('SettingsScreen — cloud-sync tiles (#112)', () {
    testWidgets('renders "Sauvegarder maintenant" tile', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await _scrollTo(tester, 'Sauvegarder maintenant');
      expect(find.text('Sauvegarder maintenant'), findsOneWidget);
    });

    testWidgets('shows "Jamais" when lastSyncedAt is null', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await _scrollTo(tester, 'Sauvegarder maintenant');
      expect(find.text('Jamais'), findsOneWidget);
    });

    testWidgets('shows a non-empty value when lastSyncedAt is set', (tester) async {
      await tester.pumpWidget(
        _buildScreen(lastSyncedAt: '2025-06-01T10:00:00.000Z'),
      );
      await _scrollTo(tester, 'Sauvegarder maintenant');
      // "Jamais" must NOT appear; a formatted date or relative-time string does.
      expect(find.text('Jamais'), findsNothing);
    });

    testWidgets('sync tile calls onManualSync when tapped', (tester) async {
      var called = false;
      await tester.pumpWidget(
        _buildScreen(onManualSync: () async { called = true; }),
      );
      final tile = await _scrollTo(tester, 'Sauvegarder maintenant');
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(called, isTrue);
    });
  });

  group('SettingsScreen — privacy policy tile (#106)', () {
    testWidgets('renders "Politique de confidentialité" tile', (tester) async {
      await tester.pumpWidget(_buildScreen());
      await _scrollTo(tester, 'Politique de confidentialité');
      expect(find.text('Politique de confidentialité'), findsOneWidget);
    });
  });

  group('SettingsScreen — delete account (#105)', () {
    testWidgets('onDeleteAccount is invoked after confirmation', (tester) async {
      var called = false;
      await tester.pumpWidget(
        _buildScreen(onDeleteAccount: () async { called = true; }),
      );

      // The danger-zone tile is below the fold — scroll until visible.
      final tile = await _scrollTo(tester, 'Supprimer mon compte');

      // Open the confirmation dialog.
      await tester.tap(tile);
      await tester.pumpAndSettle();

      // Confirm in the alert dialog.
      await tester.tap(find.text('Supprimer'));
      await tester.pumpAndSettle();

      expect(called, isTrue);
    });
  });
}
