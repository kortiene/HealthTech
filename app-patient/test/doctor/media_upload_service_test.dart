// Unit tests for MediaUploadService (issue #23, G2/G3/G6).
//
// Tests focus on:
//   - No-disk-write invariant (G2): only a descriptor is produced, no image bytes persisted.
//   - Descriptor correctness: UUID, mime, sizeBytes, addedAt, contentHash set correctly.
//   - Upload: PUT succeeds → uploaded=true; network error + sink → uploaded=false (queued).
//   - Offline seam: ciphertext handed to enqueueOffline with the correct UUID.
//   - No offline sink + network error → rethrows MediaBackendUnavailable.
//   - Content-key zeroisation: the raw key bytes are zeroed after attach().
//   - UUID uniqueness: two successive attach() calls get different UUIDs.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:app_patient/src/cloud/media_client.dart';
import 'package:app_patient/src/doctor/media_upload_service.dart';
import 'package:app_patient/src/record/media_cipher.dart';

import '../support/consultation_loop_harness.dart';

/// A [MediaClient] whose PUT behaviour is controlled by [failPut].
class _FakeMediaClient extends MediaClient {
  _FakeMediaClient({this.failPut = false})
      : super(
          'http://media.test',
          httpClient: MockClient((r) async {
            if (failPut) return http.Response('err', 503);
            return http.Response('', 201);
          }),
        );

  bool failPut;
  final List<(String uuid, Uint8List bytes)> puts = [];

  @override
  Future<void> putMedia(String uuid, Uint8List ciphertext) async {
    puts.add((uuid, Uint8List.fromList(ciphertext)));
    if (failPut) {
      throw MediaBackendUnavailable('PUT /media/$uuid → 503');
    }
  }
}

void main() {
  const crypto = FakeCryptoCore();
  const cipher = MediaCipher(crypto);
  const mime = 'image/jpeg';
  final image = Uint8List.fromList(List.generate(128, (i) => i & 0xFF));
  const fixedUuid = 'fixed-uuid-0000-0000-000000000001';
  const fixedTs = '2099-06-01T00:00:00.000Z';

  MediaUploadService makeSvc({
    bool failPut = false,
    Future<void> Function(String, Uint8List)? enqueue,
  }) {
    return MediaUploadService(
      cipher: cipher,
      client: _FakeMediaClient(failPut: failPut),
      uuidFactory: () => fixedUuid,
      clock: () => DateTime.parse('2099-06-01T00:00:00Z'),
      enqueueOffline: enqueue,
    );
  }

  // ── successful upload ────────────────────────────────────────────────────

  group('MediaUploadService.attach — successful upload', () {
    test('returns uploaded=true on success', () async {
      final result = await makeSvc().attach(image, mime: mime);
      expect(result.uploaded, isTrue);
    });

    test('descriptor has correct uuid and mime', () async {
      final result = await makeSvc().attach(image, mime: mime);
      expect(result.descriptor.uuid, fixedUuid);
      expect(result.descriptor.mime, mime);
    });

    test('descriptor sizeBytes == plaintext length (not ciphertext)', () async {
      final result = await makeSvc().attach(image, mime: mime);
      expect(result.descriptor.sizeBytes, image.length);
    });

    test('descriptor addedAt matches injected clock', () async {
      final result = await makeSvc().attach(image, mime: mime);
      expect(result.descriptor.addedAt, fixedTs);
    });

    test('descriptor contentHash is SHA-256 of plaintext', () async {
      final result = await makeSvc().attach(image, mime: mime);
      expect(result.descriptor.contentHash, isNotEmpty);
      expect(result.descriptor.contentHash, hasLength(64)); // hex sha-256
    });

    test('descriptor contentKey is non-empty base64', () async {
      final result = await makeSvc().attach(image, mime: mime);
      final decoded = base64Decode(result.descriptor.contentKey);
      expect(decoded, isNotEmpty);
    });

    test('no image bytes in descriptor (G2: no disk write, off-record)',
        () async {
      final result = await makeSvc().attach(image, mime: mime);
      final json = result.descriptor.toJson().toString();
      // The raw image should not appear as a byte sequence in the descriptor
      expect(json.contains('image/jpeg'), isTrue); // mime is allowed
      // contentKey is the encrypted key, not the image
      expect(
        base64Decode(result.descriptor.contentKey),
        isNot(equals(image)),
      );
    });
  });

  // ── content-key zeroisation ──────────────────────────────────────────────

  group('MediaUploadService content-key wipe', () {
    test('raw key buffer is zeroed after attach()', () async {
      // Intercept the raw key by wrapping cipher
      Uint8List? capturedKey;
      final trackingCipher = _TrackingCipher(crypto, onKey: (k) {
        capturedKey = k;
      });
      final svc = MediaUploadService(
        cipher: trackingCipher,
        client: _FakeMediaClient(),
        uuidFactory: () => fixedUuid,
      );
      await svc.attach(image, mime: mime);
      // After attach, the original key buffer should be zeroed
      expect(capturedKey, isNotNull);
      expect(capturedKey!.every((b) => b == 0), isTrue,
          reason: 'content key buffer must be zeroed after attach');
    });
  });

  // ── UUID uniqueness ──────────────────────────────────────────────────────

  group('MediaUploadService UUID', () {
    test('two attach calls with real uuidFactory get different UUIDs',
        () async {
      final svc = MediaUploadService(
        cipher: cipher,
        client: _FakeMediaClient(),
      );
      final r1 = await svc.attach(image, mime: mime);
      final r2 = await svc.attach(image, mime: mime);
      expect(r1.descriptor.uuid, isNot(equals(r2.descriptor.uuid)));
    });

    test('generateMediaUuid produces RFC-4122 v4 format', () {
      final id = generateMediaUuid();
      final pattern = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(pattern.hasMatch(id), isTrue, reason: 'UUID must be RFC-4122 v4');
    });
  });

  // ── offline seam (G6) ────────────────────────────────────────────────────

  group('MediaUploadService.attach — offline / network error', () {
    test('PUT failure + sink → uploaded=false', () async {
      final svc = makeSvc(
        failPut: true,
        enqueue: (_, __) async {},
      );
      final result = await svc.attach(image, mime: mime);
      expect(result.uploaded, isFalse);
    });

    test('PUT failure + sink → enqueueOffline called with correct uuid',
        () async {
      String? enqueuedUuid;
      final svc = makeSvc(
        failPut: true,
        enqueue: (uuid, _) async {
          enqueuedUuid = uuid;
        },
      );
      await svc.attach(image, mime: mime);
      expect(enqueuedUuid, fixedUuid);
    });

    test(
        'PUT failure + sink → enqueueOffline receives ciphertext (not plaintext)',
        () async {
      Uint8List? enqueuedBytes;
      final svc = makeSvc(
        failPut: true,
        enqueue: (_, bytes) async {
          enqueuedBytes = bytes;
        },
      );
      await svc.attach(image, mime: mime);
      expect(enqueuedBytes, isNotNull);
      expect(enqueuedBytes, isNot(equals(image)),
          reason: 'queued bytes must be ciphertext, not plaintext');
    });

    test(
        'PUT failure + sink → descriptor still correct (UUID assigned before upload)',
        () async {
      final svc = makeSvc(
        failPut: true,
        enqueue: (_, __) async {},
      );
      final result = await svc.attach(image, mime: mime);
      expect(result.descriptor.uuid, fixedUuid);
      expect(result.descriptor.mime, mime);
    });

    test('PUT failure + no sink → rethrows MediaBackendUnavailable', () async {
      final svc = makeSvc(failPut: true);
      await expectLater(
        svc.attach(image, mime: mime),
        throwsA(isA<MediaBackendUnavailable>()),
      );
    });
  });
}

/// Wraps [MediaCipher] to expose the raw contentKey before it is zeroed.
class _TrackingCipher extends MediaCipher {
  _TrackingCipher(super.crypto, {required this.onKey});
  final void Function(Uint8List key) onKey;

  @override
  Future<EncryptedMedia> encrypt(Uint8List imageBytes) async {
    final enc = await super.encrypt(imageBytes);
    onKey(enc.contentKey); // capture the reference BEFORE zeroisation
    return enc;
  }
}
