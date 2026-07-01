// Unit tests for MediaClient (issue #23).
//
// Uses MockClient so no real network calls are made. Tests verify:
//   - HTTP contract: PUT/POST/GET status codes → correct return or exception
//   - ZK invariant: ciphertext bytes are passed through opaquely (no decode/log)
//   - Error mapping: 403 → MediaAccessExpired, 404 → MediaNotFound, other → unavailable
//   - URL resolution: relative access-URL resolved against baseUrl

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_patient/src/cloud/media_client.dart';

void main() {
  const base = 'http://media.test';
  const uuid = 'aaaabbbb-0000-4000-8000-000000000001';
  final fakeBytes = Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]);

  // ── putMedia ─────────────────────────────────────────────────────────────

  group('MediaClient.putMedia', () {
    test('200 OK → returns normally', () async {
      final c = MediaClient(
        base,
        httpClient: MockClient((_) async => http.Response('', 200)),
      );
      await expectLater(c.putMedia(uuid, fakeBytes), completes);
    });

    test('201 Created → returns normally', () async {
      final c = MediaClient(
        base,
        httpClient: MockClient((_) async => http.Response('', 201)),
      );
      await expectLater(c.putMedia(uuid, fakeBytes), completes);
    });

    test('PUT sends bytes verbatim to correct URL (ZK: no transformation)',
        () async {
      http.Request? captured;
      final c = MediaClient(
        base,
        httpClient: MockClient((r) async {
          captured = r;
          return http.Response('', 200);
        }),
      );
      await c.putMedia(uuid, fakeBytes);
      expect(captured, isNotNull);
      expect(captured!.url.toString(), '$base/media/$uuid');
      expect(captured!.method, 'PUT');
      expect(captured!.bodyBytes, fakeBytes);
      expect(captured!.headers['Content-Type'], 'application/octet-stream');
    });

    test('5xx → throws MediaBackendUnavailable', () async {
      final c = MediaClient(
        base,
        httpClient: MockClient((_) async => http.Response('err', 500)),
      );
      await expectLater(
        c.putMedia(uuid, fakeBytes),
        throwsA(isA<MediaBackendUnavailable>()),
      );
    });

    test('network exception → throws MediaBackendUnavailable', () async {
      final c = MediaClient(
        base,
        httpClient: MockClient((_) async => throw Exception('offline')),
      );
      await expectLater(
        c.putMedia(uuid, fakeBytes),
        throwsA(isA<MediaBackendUnavailable>()),
      );
    });
  });

  // ── requestAccess ─────────────────────────────────────────────────────────

  group('MediaClient.requestAccess', () {
    test('200 → returns MediaAccessGrant with url and expiresAt', () async {
      final body = jsonEncode({
        'url': '/media/$uuid?exp=9999&sig=abc',
        'expires_at': '2099-01-01T00:00:00Z',
      });
      final c = MediaClient(
        base,
        httpClient: MockClient((_) async => http.Response(body, 200)),
      );
      final grant = await c.requestAccess(uuid);
      expect(grant.url, '/media/$uuid?exp=9999&sig=abc');
      expect(grant.expiresAt, '2099-01-01T00:00:00Z');
    });

    test('sends POST to correct URL', () async {
      http.Request? captured;
      final body = jsonEncode({'url': '/u', 'expires_at': 'x'});
      final c = MediaClient(
        base,
        httpClient: MockClient((r) async {
          captured = r;
          return http.Response(body, 200);
        }),
      );
      await c.requestAccess(uuid);
      expect(captured!.url.toString(), '$base/media/$uuid/access');
      expect(captured!.method, 'POST');
    });

    test('404 → throws MediaNotFound with uuid', () async {
      final c = MediaClient(
        base,
        httpClient: MockClient((_) async => http.Response('', 404)),
      );
      await expectLater(
        c.requestAccess(uuid),
        throwsA(
          isA<MediaNotFound>().having((e) => e.uuid, 'uuid', uuid),
        ),
      );
    });

    test('5xx → throws MediaBackendUnavailable', () async {
      final c = MediaClient(
        base,
        httpClient: MockClient((_) async => http.Response('err', 503)),
      );
      await expectLater(
        c.requestAccess(uuid),
        throwsA(isA<MediaBackendUnavailable>()),
      );
    });
  });

  // ── fetchCiphertext ───────────────────────────────────────────────────────

  group('MediaClient.fetchCiphertext', () {
    test('200 → returns body bytes verbatim (ZK: no decode)', () async {
      final c = MediaClient(
        base,
        httpClient: MockClient(
          (_) async => http.Response.bytes(fakeBytes, 200),
        ),
      );
      final result = await c.fetchCiphertext('http://media.test/u?sig=x');
      expect(result, fakeBytes);
    });

    test('403 → throws MediaAccessExpired', () async {
      final c = MediaClient(
        base,
        httpClient: MockClient((_) async => http.Response('', 403)),
      );
      await expectLater(
        c.fetchCiphertext('http://media.test/u?sig=x'),
        throwsA(isA<MediaAccessExpired>()),
      );
    });

    test('404 → throws MediaNotFound', () async {
      final c = MediaClient(
        base,
        httpClient: MockClient((_) async => http.Response('', 404)),
      );
      await expectLater(
        c.fetchCiphertext('http://media.test/u?sig=x'),
        throwsA(isA<MediaNotFound>()),
      );
    });

    test('relative URL is resolved against baseUrl', () async {
      http.Request? captured;
      final c = MediaClient(
        base,
        httpClient: MockClient((r) async {
          captured = r;
          return http.Response.bytes(fakeBytes, 200);
        }),
      );
      await c.fetchCiphertext('/media/$uuid?exp=1&sig=z');
      expect(
        captured!.url.toString(),
        '$base/media/$uuid?exp=1&sig=z',
      );
    });

    test('absolute URL is used as-is', () async {
      http.Request? captured;
      const absUrl = 'https://cdn.other.test/media/$uuid?sig=y';
      final c = MediaClient(
        base,
        httpClient: MockClient((r) async {
          captured = r;
          return http.Response.bytes(fakeBytes, 200);
        }),
      );
      await c.fetchCiphertext(absUrl);
      expect(captured!.url.toString(), absUrl);
    });

    test('network exception → throws MediaBackendUnavailable', () async {
      final c = MediaClient(
        base,
        httpClient: MockClient((_) async => throw Exception('network cut')),
      );
      await expectLater(
        c.fetchCiphertext('http://media.test/u'),
        throwsA(isA<MediaBackendUnavailable>()),
      );
    });
  });
}
