// Widget smoke tests for QrScreen (issue #16 / #118).
//
// Uses a fake [QrController] to decouple from real platform channels and
// network calls. Verifies:
//   - Default state: mode selector shown (no autoMode).
//   - After mode selection: loading indicator appears.
//   - autoMode=readWrite: loading → QR render path.
//   - autoMode=readWrite: loading → error → retry button render path.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:app_patient/src/qr/access_token.dart';
import 'package:app_patient/src/ui/qr_screen.dart';

// ─── Fakes ────────────────────────────────────────────────────────────────────

class _FakeQrController implements QrController {
  @override
  Future<QrPayload> generate({QrMode mode = QrMode.readWrite}) async =>
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
  Future<QrPayload> generate({QrMode mode = QrMode.readWrite}) async =>
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

  testWidgets('autoMode readWrite: QR shows Consultation badge', (tester) async {
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

  testWidgets('autoMode readOnly: QR shows Lecture seule badge', (tester) async {
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
}
