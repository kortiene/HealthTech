// Widget smoke tests for QrScreen (issue #16 / #118).
//
// Uses a fake [QrController] to decouple from real platform channels and
// network calls. Verifies:
//   - Default state: mode selector shown (no autoMode).
//   - After mode selection: loading indicator appears.
//   - autoMode=readWrite: loading → QR render path.
//   - autoMode=readWrite: loading → error → retry button render path.
//   - _MediaSelectionSheet (#173): icons for audio/image/document items.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:app_patient/src/qr/access_token.dart';
import 'package:app_patient/src/record/medical_record.dart';
import 'package:app_patient/src/ui/qr_screen.dart';

// ─── Fakes ────────────────────────────────────────────────────────────────────

class _FakeQrController implements QrController {
  @override
  Future<QrPayload> generate({
    QrMode mode = QrMode.readWrite,
    Set<String> selectedMediaUuids = const {},
  }) async =>
      QrPayload(
        uuid: 'test-uuid',
        backendUrl: 'http://test',
        sessionKey: Uint8List(32),
        expiresAt: DateTime.now().add(const Duration(seconds: 120)),
        writeToken: mode == QrMode.readWrite ? Uint8List(32) : null,
      );
}

class _ThrowingQrController implements QrController {
  @override
  Future<QrPayload> generate({
    QrMode mode = QrMode.readWrite,
    Set<String> selectedMediaUuids = const {},
  }) async =>
      throw Exception('test error');
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  testWidgets('QrScreen shows mode selector by default', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: QrScreen(controller: _FakeQrController())),
    );
    expect(find.text('Lecture seule'), findsOneWidget);
    expect(find.text('Consultation'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('selecting Consultation starts loading', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: QrScreen(controller: _FakeQrController())),
    );
    await tester.tap(find.text('Consultation'));
    await tester.pump(); // setState → _generating = true
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('selecting Lecture seule starts loading', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: QrScreen(controller: _FakeQrController())),
    );
    await tester.tap(find.text('Lecture seule'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('autoMode: shows loading indicator on startup', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrScreen(
          controller: _FakeQrController(),
          autoMode: QrMode.readWrite,
        ),
      ),
    );
    await tester.pump(); // let microtask fire → rebuild with _generating=true
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('autoMode: shows QrImageView after successful generate',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrScreen(
          controller: _FakeQrController(),
          autoMode: QrMode.readWrite,
        ),
      ),
    );
    // Drain the Future.microtask + generate() Future.
    await tester.pump();
    await tester.pump();
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('autoMode readWrite: QR shows Consultation badge',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrScreen(
          controller: _FakeQrController(),
          autoMode: QrMode.readWrite,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Consultation'), findsOneWidget);
  });

  testWidgets('autoMode readOnly: QR shows Lecture seule badge',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrScreen(
          controller: _FakeQrController(),
          autoMode: QrMode.readOnly,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Lecture seule'), findsOneWidget);
  });

  testWidgets('autoMode: shows retry button when generate throws',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: QrScreen(
          controller: _ThrowingQrController(),
          autoMode: QrMode.readWrite,
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  // ── _MediaSelectionSheet thumbnail icons (#173) ───────────────────────────

  group('_MediaSelectionSheet thumbnails', () {
    // Helper: pump QrScreen with a record that contains the given media and
    // wait until the media-selection bottom sheet is visible.
    Future<void> pumpSheet(
      WidgetTester tester,
      List<MediaDescriptor> media,
    ) async {
      final record = MedicalRecord(
        patientId: 'p-test',
        createdAt: '2026-01-01T00:00:00Z',
        updatedAt: '2026-01-01T00:00:00Z',
        consultations: [
          Consultation(
            id: 'c1',
            date: '2026-01-01',
            practitionerRef: 'dr-test',
            summary: 'test',
            media: media,
          ),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: QrScreen(
            controller: _FakeQrController(),
            autoMode: QrMode.readWrite,
            autoShareMedia: false,
            record: record,
          ),
        ),
      );
      // Microtask → _generate → _showMediaSelectionSheet
      await tester.pump();
      // Bottom sheet slide-in animation
      await tester.pumpAndSettle();
    }

    MediaDescriptor desc({
      required String uuid,
      required String mime,
      String? url,
    }) =>
        MediaDescriptor(
          uuid: uuid,
          contentKey: 'key',
          contentHash: 'hash',
          mime: mime,
          sizeBytes: 102400,
          addedAt: '2026-08-20T10:00:00Z',
          url: url,
        );

    testWidgets('sheet header is visible', (tester) async {
      await pumpSheet(tester, [
        desc(uuid: 'u1', mime: 'audio/webm'),
      ]);
      expect(find.text('Partager avec le médecin'), findsOneWidget);
    });

    testWidgets('audio item shows mic icon', (tester) async {
      await pumpSheet(tester, [
        desc(uuid: 'u1', mime: 'audio/webm'),
      ]);
      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Symbols.mic_rounded,
        ),
        findsOneWidget,
      );
    });

    testWidgets('image item without local file shows photo icon',
        (tester) async {
      await pumpSheet(tester, [
        desc(uuid: 'u2', mime: 'image/jpeg'), // url == null
      ]);
      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Symbols.photo_rounded,
        ),
        findsOneWidget,
      );
    });

    testWidgets('document item shows description icon', (tester) async {
      await pumpSheet(tester, [
        desc(uuid: 'u3', mime: 'application/pdf'),
      ]);
      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Symbols.description_rounded,
        ),
        findsOneWidget,
      );
    });

    testWidgets('mixed items: first two icons visible, count button correct',
        (tester) async {
      await pumpSheet(tester, [
        desc(uuid: 'u1', mime: 'audio/webm'),
        desc(uuid: 'u2', mime: 'image/jpeg'),
        desc(uuid: 'u3', mime: 'application/pdf'),
      ]);
      // Audio and image thumbnails are in the initial viewport.
      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Symbols.mic_rounded,
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Symbols.photo_rounded,
        ),
        findsOneWidget,
      );
      // Count button confirms all 3 items are tracked regardless of scroll.
      expect(find.text('Partager 3 fichiers'), findsOneWidget);
    });

    testWidgets('item label and size are shown', (tester) async {
      await pumpSheet(tester, [
        desc(uuid: 'u1', mime: 'audio/webm'),
      ]);
      // Label: "Audio · 20 août 2026"
      expect(find.textContaining('Audio'), findsOneWidget);
      // Size: "0.1 MB" (102400 bytes)
      expect(find.textContaining('MB'), findsOneWidget);
    });

    testWidgets('all items pre-selected — confirm button shows count',
        (tester) async {
      await pumpSheet(tester, [
        desc(uuid: 'u1', mime: 'audio/webm'),
        desc(uuid: 'u2', mime: 'image/jpeg'),
      ]);
      expect(find.text('Partager 2 fichiers'), findsOneWidget);
    });
  });
}
