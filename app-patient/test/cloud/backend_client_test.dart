// Unit tests for BackendClient (issue #14).
//
// Uses MockClient from package:http/testing.dart so no real network calls
// are made. Tests verify HTTP contract (status codes, byte passthrough, error
// mapping) and the ZK invariant (body is never logged or transformed).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_patient/src/cloud/backend_client.dart';

void main() {
  const base = 'http://backend.test';
  const uuid = '00000000-0000-4000-8000-000000000001';

  group('BackendClient.put', () {
    test('201 Created → returns normally', () async {
      final client = BackendClient(
        base,
        httpClient: MockClient((_) async => http.Response('', 201)),
      );
      await expectLater(
        client.put(uuid, Uint8List.fromList([1, 2, 3])),
        completes,
      );
    });

    test('200 OK (overwrite) → returns normally', () async {
      final client = BackendClient(
        base,
        httpClient: MockClient((_) async => http.Response('', 200)),
      );
      await expectLater(
        client.put(uuid, Uint8List.fromList([4, 5, 6])),
        completes,
      );
    });

    test('5xx → throws BackendUnavailable', () async {
      final client = BackendClient(
        base,
        httpClient: MockClient((_) async => http.Response('', 503)),
      );
      expect(
        () => client.put(uuid, Uint8List(4)),
        throwsA(isA<BackendUnavailable>()),
      );
    });

    test('network error → throws BackendUnavailable', () async {
      final client = BackendClient(
        base,
        httpClient: MockClient((_) async => throw Exception('timeout')),
      );
      expect(
        () => client.put(uuid, Uint8List(4)),
        throwsA(isA<BackendUnavailable>()),
      );
    });

    test('transmits exact bytes to PUT endpoint', () async {
      final payload = Uint8List.fromList([0xAB, 0xCD, 0xEF]);
      http.Request? captured;
      final client = BackendClient(
        base,
        httpClient: MockClient((req) async {
          captured = req;
          return http.Response('', 201);
        }),
      );
      await client.put(uuid, payload);
      expect(captured, isNotNull);
      expect(captured!.url.path, '/blob/$uuid');
      expect(captured!.method, 'PUT');
      expect(captured!.bodyBytes, payload);
    });
  });

  group('BackendClient.get', () {
    test('200 OK → returns body bytes verbatim', () async {
      final blob = Uint8List.fromList([0x01, 0x02, 0x03]);
      final client = BackendClient(
        base,
        httpClient: MockClient(
          (_) async => http.Response.bytes(blob, 200),
        ),
      );
      final result = await client.get(uuid);
      expect(result, equals(blob));
    });

    test('404 → throws BlobNotFound', () async {
      final client = BackendClient(
        base,
        httpClient: MockClient((_) async => http.Response('', 404)),
      );
      expect(
        () => client.get(uuid),
        throwsA(isA<BlobNotFound>()),
      );
    });

    test('5xx → throws BackendUnavailable', () async {
      final client = BackendClient(
        base,
        httpClient: MockClient((_) async => http.Response('', 500)),
      );
      expect(
        () => client.get(uuid),
        throwsA(isA<BackendUnavailable>()),
      );
    });

    test('network error → throws BackendUnavailable', () async {
      final client = BackendClient(
        base,
        httpClient: MockClient((_) async => throw Exception('unreachable')),
      );
      expect(
        () => client.get(uuid),
        throwsA(isA<BackendUnavailable>()),
      );
    });

    test('issues GET to correct path', () async {
      http.Request? captured;
      final client = BackendClient(
        base,
        httpClient: MockClient((req) async {
          captured = req;
          return http.Response.bytes(Uint8List(8), 200);
        }),
      );
      await client.get(uuid);
      expect(captured!.url.path, '/blob/$uuid');
      expect(captured!.method, 'GET');
    });
  });

  group('BlobNotFound', () {
    test('toString is non-empty', () {
      expect(const BlobNotFound('x').toString(), isNotEmpty);
    });
    test('is an Exception', () {
      expect(const BlobNotFound('x'), isA<Exception>());
    });
  });

  group('BackendUnavailable', () {
    test('toString is non-empty', () {
      expect(const BackendUnavailable('msg').toString(), isNotEmpty);
    });
    test('is an Exception', () {
      expect(const BackendUnavailable('msg'), isA<Exception>());
    });
  });
}
