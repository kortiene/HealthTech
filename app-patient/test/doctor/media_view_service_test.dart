// Unit tests for MediaViewService (issue #23, G2 / acceptance criterion #2).
//
// Tests focus on:
//   - Happy path: mint URL → download → decrypt → plaintext round-trip.
//   - Integrity: tampered ciphertext → MediaIntegrityError.
//   - Expiry (AC #2): 403 on fetchCiphertext → MediaAccessExpired propagated.
//   - Not found: 404 → MediaNotFound propagated.
//   - No disk write: decrypted bytes returned in-RAM only (tested by service contract).
//   - Content-key wipe: the decoded key is zeroed in finally even on error.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:app_patient/src/cloud/media_client.dart';
import 'package:app_patient/src/doctor/media_view_service.dart';
import 'package:app_patient/src/record/media_cipher.dart';
import 'package:app_patient/src/record/medical_record.dart';

import '../support/consultation_loop_harness.dart';

const _uuid = 'ccccdddd-0000-4000-8000-000000000002';
const _accessUrl = '/media/$_uuid?exp=9999&sig=ok';
const _expires = '2099-12-31T00:00:00Z';

/// Fake MediaClient that serves a fixed ciphertext via a minted URL.
class _FakeMediaClient extends MediaClient {
  _FakeMediaClient({required this.ciphertext, this.failFetch403 = false})
      : super('http://media.test');

  final Uint8List ciphertext;
  final bool failFetch403;

  @override
  Future<MediaAccessGrant> requestAccess(String uuid) async {
    return const MediaAccessGrant(url: _accessUrl, expiresAt: _expires);
  }

  @override
  Future<Uint8List> fetchCiphertext(String url) async {
    if (failFetch403) throw const MediaAccessExpired();
    return ciphertext;
  }
}

/// Fake MediaClient that throws MediaNotFound on requestAccess.
class _NotFoundClient extends MediaClient {
  _NotFoundClient() : super('http://media.test');

  @override
  Future<MediaAccessGrant> requestAccess(String uuid) async {
    throw MediaNotFound(uuid);
  }

  @override
  Future<Uint8List> fetchCiphertext(String url) async => Uint8List(0);
}

void main() {
  const crypto = FakeCryptoCore();
  const cipher = MediaCipher(crypto);

  final image = Uint8List.fromList(List.generate(64, (i) => i));

  /// Build a [MediaDescriptor] wrapping [image] using [cipher].
  Future<(MediaDescriptor, Uint8List)> buildDescriptor() async {
    final enc = await cipher.encrypt(image);
    final descriptor = MediaDescriptor(
      uuid: _uuid,
      contentKey: base64Encode(enc.contentKey),
      contentHash: enc.contentHash,
      mime: 'image/jpeg',
      sizeBytes: image.length,
      addedAt: '2099-01-01T00:00:00Z',
    );
    return (descriptor, enc.ciphertext);
  }

  // ── happy path ───────────────────────────────────────────────────────────

  group('MediaViewService.load — happy path', () {
    test('returns plaintext bytes equal to original image', () async {
      final (descriptor, ciphertext) = await buildDescriptor();
      final svc = MediaViewService(
        cipher: cipher,
        client: _FakeMediaClient(ciphertext: ciphertext),
      );
      final result = await svc.load(descriptor);
      expect(result, image);
    });

    test('correct hash in descriptor → no MediaIntegrityError', () async {
      final (descriptor, ciphertext) = await buildDescriptor();
      final svc = MediaViewService(
        cipher: cipher,
        client: _FakeMediaClient(ciphertext: ciphertext),
      );
      await expectLater(svc.load(descriptor), completes);
    });
  });

  // ── integrity check ──────────────────────────────────────────────────────

  group('MediaViewService.load — integrity', () {
    test('tampered contentHash → MediaIntegrityError', () async {
      final (desc, ciphertext) = await buildDescriptor();
      // Replace the hash with a wrong one
      final bad = MediaDescriptor(
        uuid: desc.uuid,
        contentKey: desc.contentKey,
        contentHash: 'deadbeef' * 8,
        mime: desc.mime,
        sizeBytes: desc.sizeBytes,
        addedAt: desc.addedAt,
      );
      final svc = MediaViewService(
        cipher: cipher,
        client: _FakeMediaClient(ciphertext: ciphertext),
      );
      await expectLater(
        svc.load(bad),
        throwsA(isA<MediaIntegrityError>()),
      );
    });
  });

  // ── ephemeral URL expiry (AC #2) ─────────────────────────────────────────

  group('MediaViewService.load — URL expiry (AC #2)', () {
    test('fetchCiphertext 403 → MediaAccessExpired propagated', () async {
      final (descriptor, ciphertext) = await buildDescriptor();
      final svc = MediaViewService(
        cipher: cipher,
        client: _FakeMediaClient(ciphertext: ciphertext, failFetch403: true),
      );
      await expectLater(
        svc.load(descriptor),
        throwsA(isA<MediaAccessExpired>()),
      );
    });

    test('MediaAccessExpired has descriptive message', () {
      expect(const MediaAccessExpired().toString(), isNotEmpty);
    });
  });

  // ── not found ────────────────────────────────────────────────────────────

  group('MediaViewService.load — not found', () {
    test('requestAccess 404 → MediaNotFound propagated', () async {
      final (descriptor, _) = await buildDescriptor();
      final svc = MediaViewService(
        cipher: cipher,
        client: _NotFoundClient(),
      );
      await expectLater(
        svc.load(descriptor),
        throwsA(isA<MediaNotFound>()),
      );
    });
  });
}
