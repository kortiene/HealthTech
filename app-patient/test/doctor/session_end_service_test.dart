// Unit tests for SessionEndService (issue #19 — US-2.3).
//
// Verified properties:
//   - terminate with pendingBlob: issues PUT /blob/{uuid} with the blob bytes.
//   - PUT body carries the exact pending blob bytes.
//   - terminate without pendingBlob: no PUT issued.
//   - session key is zeroed after successful terminate.
//   - pending blob bytes are zeroed in-place after successful terminate.
//   - pendingBlob is null after terminate.
//   - session key is zeroed even when PUT throws BackendUnavailable.
//   - pending blob bytes are zeroed even when PUT throws BackendUnavailable.
//   - BackendUnavailable propagates after wipe when PUT fails.
//   - no error thrown when pendingBlob is null (no PUT attempted).
//   - ZK: terminate never issues GET (write-only cloud operation).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_patient/src/cloud/backend_client.dart';
import 'package:app_patient/src/doctor/consultation_session.dart';
import 'package:app_patient/src/doctor/session_end_service.dart';
import 'package:app_patient/src/qr/access_token.dart';
import 'package:app_patient/src/record/medical_record.dart';

// ─── Helpers ─────────────────────────────────────────────────────────────────

const _uuid = '00000000-0000-4000-8000-000000000001';
const _base = 'http://backend.test';

const _kRecord = MedicalRecord(
  patientId: _uuid,
  createdAt: '2025-01-01T00:00:00Z',
  updatedAt: '2026-06-29T00:00:00Z',
);

QrPayload _payload({Uint8List? key}) => QrPayload(
      uuid: _uuid,
      backendUrl: _base,
      sessionKey: key ?? Uint8List.fromList(List.filled(32, 0x42)),
      expiresAt: DateTime.now().add(const Duration(seconds: 120)),
    );

/// Creates a session, optionally with a [blob] applied via [applyMerge].
ConsultationSession _session({Uint8List? blob, Uint8List? key}) {
  final session = ConsultationSession(
    payload: _payload(key: key),
    record: _kRecord,
  );
  if (blob != null) {
    session.applyMerge(
      _kRecord.copyWith(updatedAt: '2026-06-30T00:00:00Z'),
      blob,
    );
  }
  return session;
}

SessionEndService _svc(http.Client httpClient) =>
    SessionEndService(client: BackendClient(_base, httpClient: httpClient));

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  group('SessionEndService.terminate — PUT behaviour', () {
    test('issues PUT /blob/{uuid} when pendingBlob is present', () async {
      final puts = <String>[];
      final blob = Uint8List.fromList([0x01, 0x02, 0x03]);
      final svc = _svc(
        MockClient((req) async {
          if (req.method == 'PUT') puts.add(req.url.path);
          return http.Response('', 200);
        }),
      );
      await svc.terminate(_session(blob: blob));
      expect(puts, hasLength(1));
      expect(puts.first, '/blob/$_uuid');
    });

    test('PUT body carries the exact pending blob bytes', () async {
      final captured = <Uint8List>[];
      // Take a snapshot of the original bytes before wipe zeroes them.
      final blob = Uint8List.fromList([0xAA, 0xBB, 0xCC]);
      final origBlob = Uint8List.fromList(blob);
      final svc = _svc(
        MockClient((req) async {
          // http package copies body bytes into the Request object, so this
          // snapshot is unaffected by the wipe() that follows the PUT.
          captured.add(Uint8List.fromList(req.bodyBytes));
          return http.Response('', 200);
        }),
      );
      await svc.terminate(_session(blob: blob));
      expect(captured, hasLength(1));
      expect(captured.first, equals(origBlob));
    });

    test('does not issue PUT when pendingBlob is null', () async {
      final puts = <String>[];
      final svc = _svc(
        MockClient((req) async {
          if (req.method == 'PUT') puts.add(req.url.path);
          return http.Response('', 200);
        }),
      );
      await svc.terminate(_session());
      expect(puts, isEmpty);
    });
  });

  group('SessionEndService.terminate — wipe behaviour', () {
    test('zeroes session key after successful terminate', () async {
      final key = Uint8List.fromList(List.filled(32, 0x42));
      final session = _session(
        blob: Uint8List.fromList([1, 2, 3]),
        key: key,
      );
      final svc = _svc(MockClient((_) async => http.Response('', 200)));
      await svc.terminate(session);
      expect(key, everyElement(0));
    });

    test('zeroes pending blob bytes in-place after successful terminate',
        () async {
      final blob = Uint8List.fromList([0x01, 0x02, 0x03, 0x04]);
      final session = _session(blob: blob);
      final svc = _svc(MockClient((_) async => http.Response('', 200)));
      await svc.terminate(session);
      // The original Uint8List reference should be zeroed.
      expect(blob, everyElement(0));
    });

    test('sets pendingBlob to null after terminate', () async {
      final session = _session(blob: Uint8List.fromList([1, 2, 3]));
      final svc = _svc(MockClient((_) async => http.Response('', 200)));
      await svc.terminate(session);
      expect(session.pendingBlob, isNull);
    });

    test('zeroes session key even when PUT throws BackendUnavailable',
        () async {
      final key = Uint8List.fromList(List.filled(32, 0x42));
      final session = _session(
        blob: Uint8List.fromList([1, 2, 3]),
        key: key,
      );
      final svc = _svc(MockClient((_) async => http.Response('error', 503)));
      await expectLater(
        svc.terminate(session),
        throwsA(isA<BackendUnavailable>()),
      );
      expect(key, everyElement(0));
    });

    test('zeroes pending blob bytes even when PUT throws BackendUnavailable',
        () async {
      final blob = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);
      final session = _session(blob: blob);
      final svc = _svc(MockClient((_) async => http.Response('error', 503)));
      await expectLater(
        svc.terminate(session),
        throwsA(isA<BackendUnavailable>()),
      );
      expect(blob, everyElement(0));
    });
  });

  group('SessionEndService.terminate — error propagation', () {
    test('propagates BackendUnavailable when server returns 5xx', () async {
      final session = _session(blob: Uint8List.fromList([1, 2, 3]));
      final svc = _svc(MockClient((_) async => http.Response('error', 503)));
      await expectLater(
        svc.terminate(session),
        throwsA(isA<BackendUnavailable>()),
      );
    });

    test('completes without error when pendingBlob is null', () async {
      // No PUT is attempted → BackendUnavailable is never thrown, even when
      // the MockClient would return an error status.
      final session = _session();
      final svc = _svc(MockClient((_) async => http.Response('error', 503)));
      await expectLater(svc.terminate(session), completes);
    });
  });

  group('SessionEndService ZK', () {
    test('terminate never issues GET (write-only cloud operation)', () async {
      final gets = <String>[];
      final session = _session(blob: Uint8List.fromList([1, 2, 3]));
      final svc = _svc(
        MockClient((req) async {
          if (req.method == 'GET') gets.add(req.url.path);
          return http.Response('', 200);
        }),
      );
      await svc.terminate(session);
      expect(gets, isEmpty);
    });
  });
}
