// Minimal smoke test so `flutter test` has something to run on the skeleton.
//
// TODO(#13): widget tests for onboarding.
// TODO(#16): QR generate/scan tests (120 s TTL expiry).
// TODO(#11): crypto-core FRB integration tests (NIST vectors gate CI in ADR 0003).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/main.dart';

void main() {
  testWidgets('patient app renders with key-state routing', (tester) async {
    await tester.pumpWidget(const PatientApp());

    // First frame: the master-key state probe is still in flight → spinner.
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
