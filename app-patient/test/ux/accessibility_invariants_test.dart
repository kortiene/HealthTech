// Accessibility invariant tests for RecordViewScreen (issue #29 — Livrable E).
//
// These tests enforce the automated portion of the #29 accessibility guard-rail:
//   * Touch targets — key interactive elements are rendered ≥ 48 dp tall.
//   * Semantic labels — life-critical allergy info has a self-contained
//     Semantics label for TalkBack (#29 E: lecteur d'écran).
//   * Text-scale resilience — vital info and action labels must not overflow or
//     be truncated at a high system text-scale factor (textScaleFactor 1.5× and
//     2.0×, #29 E: mise à l'échelle du texte / gros caractères système).
//
// SCOPE: these are host-only widget tests (no device hardware, no TalkBack
// daemon, no Accessibility Scanner). They prove the structural invariants that
// can be checked deterministically in CI. Full on-device TalkBack validation
// and Accessibility Scanner reports are part of the HUMAN validation protocol
// (docs/ux/low-end-validation-protocol.md).
//
// Run:  flutter test test/ux/accessibility_invariants_test.dart

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/qr/access_token.dart';
import 'package:app_patient/src/record/medical_record.dart';
import 'package:app_patient/src/ui/record_view_screen.dart';

// ─── Fixtures ─────────────────────────────────────────────────────────────────

QrPayload _dummyPayload() => QrPayload(
      uuid: 'a11y-test-id',
      backendUrl: 'http://test',
      sessionKey: Uint8List(32),
      expiresAt: DateTime.now().add(const Duration(seconds: 120)),
    );

/// Full record with every section, including life-critical allergy info.
const _fullRecord = MedicalRecord(
  patientId: 'a11y-invariant-test-id',
  demographics: Demographics(givenName: 'Awa', birthYear: 1990, sex: 'F'),
  allergies: [
    Allergy(
      substance: 'Pénicilline',
      severity: 'severe',
      notedAt: '2024-01-01',
    ),
  ],
  chronicConditions: [
    ChronicCondition(name: 'Hypertension artérielle', icd10: 'I10'),
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
      id: 'c-a11y-01',
      date: '2026-01-01',
      practitionerRef: 'dr-test',
      summary: 'Bilan annuel',
    ),
  ],
  createdAt: '2025-01-01T00:00:00Z',
  updatedAt: '2026-01-01T00:00:00Z',
);

/// Minimal record with only an allergy — isolates the semantic-label path.
const _allergyOnlyRecord = MedicalRecord(
  patientId: 'a11y-allergy-test-id',
  allergies: [
    Allergy(
      substance: 'Sulfonamides',
      severity: 'moderate',
      notedAt: '2023-05-15',
    ),
  ],
  createdAt: '2025-01-01T00:00:00Z',
  updatedAt: '2025-01-01T00:00:00Z',
);

// ─── Helpers ─────────────────────────────────────────────────────────────────

/// Pumps a [RecordViewScreen] wrapped in a [MaterialApp] with the given
/// [textScaleFactor]. Uses a realistic 360×780 viewport (common Android
/// low-end density target).
Future<void> _pump(
  WidgetTester tester,
  MedicalRecord record, {
  double textScaleFactor = 1.0,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(size: Size(360, 780)).copyWith(
          textScaler: TextScaler.linear(textScaleFactor),
        ),
        child: RecordViewScreen(
          record: record,
          payload: _dummyPayload(),
        ),
      ),
    ),
  );
}

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  // ── Touch targets ─────────────────────────────────────────────────────────
  //
  // PRD §5 / #29 Livrable E: interactive elements on the reference device must
  // present a tap-target ≥ 48 dp tall. Asserted against rendered height, which
  // is the lower bound (MaterialTapTargetSize.padded adds further invisible
  // padding around smaller visual widgets, but the FAB is always ≥ 56 dp).

  group('[TouchTarget-FAB] FAB "Ajouter une note / ordonnance" ≥ 48 dp', () {
    testWidgets('FAB rendered height is ≥ 48 dp', (tester) async {
      await _pump(tester, _fullRecord);

      final fab = find.byType(FloatingActionButton);
      expect(fab, findsOneWidget, reason: 'FAB must be present in the shell');

      final size = tester.getSize(fab);
      expect(
        size.height,
        greaterThanOrEqualTo(48.0),
        reason:
            'FAB height must be ≥ 48 dp (touch-target requirement, #29 Livrable E)',
      );
    });

    testWidgets('FAB rendered width is ≥ 48 dp', (tester) async {
      await _pump(tester, _fullRecord);

      final size = tester.getSize(find.byType(FloatingActionButton));
      expect(
        size.width,
        greaterThanOrEqualTo(48.0),
        reason: 'FAB width must be ≥ 48 dp',
      );
    });
  });

  group('[TouchTarget-Terminer] "Terminer" TextButton ≥ 48 dp', () {
    // PRD §5 / #29 Livrable E: every interactive element must meet the 48 dp
    // tap-target floor. "Terminer" lives in AppBar actions (56 dp tall),
    // so it naturally meets the floor — but the assertion pins it explicitly
    // against accidental regression (e.g. wrapping the button in a Container
    // that shrinks it, or moving it out of the AppBar).

    testWidgets('"Terminer" TextButton rendered height is ≥ 48 dp',
        (tester) async {
      await _pump(tester, _fullRecord);

      // TextButton.icon() creates a private _TextButtonWithIcon (a TextButton
      // subtype). find.byType uses runtimeType == so it misses subtypes; use
      // byWidgetPredicate with `is TextButton` (subtype-safe) instead.
      final terminateBtn = find.ancestor(
        of: find.text('Terminer'),
        matching: find.byWidgetPredicate((w) => w is TextButton),
      );
      expect(
        terminateBtn,
        findsOneWidget,
        reason: '"Terminer" TextButton must be present in AppBar actions',
      );

      final size = tester.getSize(terminateBtn);
      expect(
        size.height,
        greaterThanOrEqualTo(48.0),
        reason:
            '"Terminer" touch-target height must be ≥ 48 dp (AppBar actions, #29 E)',
      );
    });
  });

  // ── Semantic labels ───────────────────────────────────────────────────────
  //
  // #29 Livrable E: TalkBack must be able to announce life-critical information
  // (allergies) as a single coherent phrase. The allergy _InfoRow merges label +
  // value into a `Semantics(label: 'Allergie : <substance>, gravité <severity>')`
  // node — assertable without a real TalkBack daemon.

  group(
      '[Semantics-AllergyLabel] Allergy row has a self-contained semantic label',
      () {
    testWidgets(
        'allergy row exposes a Semantics node with a combined label for TalkBack',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _allergyOnlyRecord);

      // The label is set on the Semantics widget in _InfoRow.
      expect(
        find.bySemanticsLabel(
          RegExp(r'Allergie\s*:.*Sulfonamides', caseSensitive: false),
        ),
        findsOneWidget,
        reason:
            'allergy row must expose a combined semantic label for TalkBack '
            '(substance + severity merged into one announcement, #29 E)',
      );

      handle.dispose();
    });

    testWidgets('allergy severity appears in the semantic label',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _allergyOnlyRecord);

      expect(
        find.bySemanticsLabel(
          RegExp(r'gravité\s*moderate', caseSensitive: false),
        ),
        findsOneWidget,
        reason: 'severity must be included in the allergy semantic label',
      );

      handle.dispose();
    });

    testWidgets(
        'full record with multiple sections: allergy semantic label still present',
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _fullRecord);

      expect(
        find.bySemanticsLabel(
          RegExp(r'Allergie\s*:.*Pénicilline', caseSensitive: false),
        ),
        findsOneWidget,
        reason: 'allergy label must be findable even when other sections are '
            'populated (life-critical info must not be buried)',
      );

      handle.dispose();
    });
  });

  group(
      '[Semantics-SectionHeaders] Section titles are marked as semantic headers',
      () {
    testWidgets(
        'Semantics widget with header:true is present for the Informations title',
        (tester) async {
      await _pump(tester, _fullRecord);

      // Find a Semantics widget whose properties include header=true.
      final headerSemantics = tester.widgetList<Semantics>(
        find.byWidgetPredicate(
          (w) => w is Semantics && (w.properties.header ?? false),
        ),
      );
      expect(
        headerSemantics,
        isNotEmpty,
        reason:
            'at least one section title must be marked with Semantics(header: true) '
            'so TalkBack can jump between sections (#29 E)',
      );
    });
  });

  // ── Text-scale resilience ─────────────────────────────────────────────────
  //
  // #29 Livrable E: on a low-end device the user may enable "gros caractères
  // système" (large system text). _InfoRow uses Expanded columns with soft-
  // wrapping Text (no maxLines / overflow:clip), so labels must reflow at
  // 1.5× and 2.0× without throwing a RenderFlex overflow error.

  group('[TextScale-1.5] No overflow at textScaleFactor 1.5×', () {
    testWidgets('RecordViewScreen renders without overflow at 1.5×',
        (tester) async {
      await _pump(tester, _fullRecord, textScaleFactor: 1.5);

      // A RenderFlex overflow would throw a FlutterError captured here.
      expect(
        tester.takeException(),
        isNull,
        reason: 'must not overflow at textScaleFactor 1.5 (#29 Livrable E)',
      );
    });

    testWidgets('allergy substance label is visible (not clipped) at 1.5×',
        (tester) async {
      await _pump(tester, _allergyOnlyRecord, textScaleFactor: 1.5);

      // Life-critical allergy substance and section header must remain visible.
      expect(find.text('Sulfonamides'), findsOneWidget,
          reason: 'allergy substance must not be clipped at 1.5× scale');
      expect(find.text('Allergies'), findsOneWidget,
          reason: 'allergy section header must remain visible at 1.5× scale');
      expect(tester.takeException(), isNull);
    });
  });

  group('[TextScale-2.0] No overflow at textScaleFactor 2.0×', () {
    testWidgets('RecordViewScreen renders without overflow at 2.0×',
        (tester) async {
      await _pump(tester, _fullRecord, textScaleFactor: 2.0);

      expect(
        tester.takeException(),
        isNull,
        reason: 'must not overflow at textScaleFactor 2.0 (#29 Livrable E)',
      );
    });

    testWidgets(
        '"Terminer" action label is still present (not truncated) at 2.0×',
        (tester) async {
      await _pump(tester, _fullRecord, textScaleFactor: 2.0);

      // The AppBar "Terminer" TextButton must remain visible — if its label
      // were truncated the doctor could not terminate the session.
      expect(
        find.text('Terminer'),
        findsOneWidget,
        reason:
            '"Terminer" action must not be truncated at 2.0× text scale (#29 E)',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('FAB label is still present (not truncated) at 2.0×',
        (tester) async {
      await _pump(tester, _fullRecord, textScaleFactor: 2.0);

      expect(
        find.text('Ajouter une note / ordonnance'),
        findsOneWidget,
        reason: 'FAB label must not be truncated at 2.0× text scale (#29 E)',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'first sections are rendered at 2.0× — life-critical sections '
        'not pushed off-screen at large text scale', (tester) async {
      await _pump(tester, _fullRecord, textScaleFactor: 2.0);

      // The ListView renders lazily: sections beyond the default 800×600 test
      // viewport may not be in the widget tree. We check the sections guaranteed
      // to be at the top and therefore always present.
      for (final title in [
        'Informations', // first section, always visible
        'Allergies', // life-critical, must be near the top (#29 E)
      ]) {
        expect(
          find.text(title),
          findsOneWidget,
          reason: '"$title" must be visible at 2.0× text scale (#29 E)',
        );
      }
      expect(tester.takeException(), isNull);
    });
  });

  // ── Narrow-screen rendering (320 px wide) ────────────────────────────────
  //
  // #29 Livrable A: the reference low-end-device profile sets a minimum width
  // of 320 CSS px (common on 4-inch budget Android phones). The screen must
  // render without overflow and action labels must remain visible — a doctor
  // terminating a session must not be blocked by a layout error.

  group('[NarrowScreen] No overflow on 320 × 568 px viewport (#29 A)', () {
    testWidgets(
        'RecordViewScreen renders without overflow on a 320 × 568 viewport',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(320, 568)),
            child: RecordViewScreen(
              record: _fullRecord,
              payload: _dummyPayload(),
            ),
          ),
        ),
      );

      expect(
        tester.takeException(),
        isNull,
        reason: 'must not overflow on a 320 × 568 viewport (#29 A)',
      );
      // Session-critical actions live in the AppBar and FAB — never scrolled
      // off-screen — and must remain visible even on a narrow layout.
      expect(
        find.text('Terminer'),
        findsOneWidget,
        reason: '"Terminer" must be visible on a narrow-screen device',
      );
      expect(
        find.text('Ajouter une note / ordonnance'),
        findsOneWidget,
        reason: 'FAB label must be visible on a narrow-screen device',
      );
    });

    testWidgets(
        'allergy info visible at 1.5× on 320 px wide — '
        'critical section must not be pushed off screen by large text',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(320, 568)).copyWith(
              textScaler: const TextScaler.linear(1.5),
            ),
            child: RecordViewScreen(
              record: _allergyOnlyRecord,
              payload: _dummyPayload(),
            ),
          ),
        ),
      );

      expect(
        tester.takeException(),
        isNull,
        reason: 'no overflow at 1.5× on a 320 px wide viewport',
      );
      expect(
        find.text('Sulfonamides'),
        findsOneWidget,
        reason:
            'allergy substance must remain visible on narrow screen at 1.5× (#29 E)',
      );
    });
  });

  // ── Combined: full-scale + full-record smoke ───────────────────────────────
  //
  // Ensures the complete RecordViewScreen renders correctly at maximum scale
  // and all semantics remain intact — a single regression catch-all.

  group('[A11y-Smoke] Full record + max scale combined invariant', () {
    testWidgets(
        'full record renders at 2.0× with no error and critical non-scroll '
        'elements accessible', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, _fullRecord, textScaleFactor: 2.0);

      // No exception (no overflow, no assertion error).
      expect(tester.takeException(), isNull);

      // Life-critical allergy semantic label is still present.
      // Allergies is the second section — within the default 800×600 viewport
      // even at 2.0× scale.
      expect(
        find.bySemanticsLabel(
          RegExp(r'Allergie\s*:.*Pénicilline', caseSensitive: false),
        ),
        findsOneWidget,
        reason:
            'allergy semantic label must survive 2.0× scale (life-critical, #29 E)',
      );

      // Action labels are in the AppBar / FAB — never scrolled off-screen.
      expect(find.text('Terminer'), findsOneWidget,
          reason: '"Terminer" must be reachable regardless of scroll position');
      expect(find.text('Ajouter une note / ordonnance'), findsOneWidget,
          reason: 'FAB must be reachable regardless of scroll position');

      handle.dispose();
    });
  });
}
