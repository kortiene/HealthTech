// Widget smoke tests for QrScreen (issue #16).
//
// Uses a fake [QrController] to decouple from real platform channels and
// network calls. Verifies the loading → QR and loading → error render paths.

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:app_patient/src/qr/access_token.dart';
import 'package:app_patient/src/ui/qr_screen.dart';

// ─── Fakes ────────────────────────────────────────────────────────────────────

class _FakeQrController implements QrController {
  @override
  Future<QrPayload> generate() async => QrPayload(
        uuid: 'test-uuid',
        backendUrl: 'http://test',
        sessionKey: Uint8List(32),
        expiresAt: DateTime.now().add(const Duration(seconds: 120)),
      );
}

class _ThrowingQrController implements QrController {
  @override
  Future<QrPayload> generate() async => throw Exception('test error');
}

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  testWidgets('QrScreen shows loading indicator on startup', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: QrScreen(controller: _FakeQrController())),
    );
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('QrScreen shows QrImageView after successful generate',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: QrScreen(controller: _FakeQrController())),
    );
    // Drain the Future.microtask(_generate) + generate() Future.
    await tester.pump();
    await tester.pump();
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('QrScreen shows retry button when generate throws',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: QrScreen(controller: _ThrowingQrController())),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byType(QrImageView), findsNothing);
    expect(find.text('Réessayer'), findsOneWidget);
  });
}
