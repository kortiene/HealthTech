// Heavy-media offload orchestration (issue #23, G2/G3/G6).
//
// Turns captured image bytes into an off-record [MediaDescriptor]:
//   capture bytes → encrypt (per-media key, crypto-core) → assign anonymous UUID
//   → upload PUT /media/{uuid}  (or enqueue offline on a network cut) → descriptor.
//
// Invariants:
//   - NO DISK WRITE of the image (clear or ciphertext) ever happens here — the
//     bytes stay in RAM (G2: "aucune image lourde sur le téléphone patient"). The
//     only thing that persists in the record is the small descriptor.
//   - The UUID is assigned CLIENT-SIDE before upload, so the descriptor can be
//     attached to the consultation immediately even when offline (G6); the bytes
//     are synced later (#21/#22) without changing the descriptor.
//   - The transient raw content-key buffer is zeroed once captured into the
//     descriptor (the canonical copy lives, base64, inside the encrypted record).

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../cloud/media_client.dart';
import '../record/media_cipher.dart';
import '../record/medical_record.dart';

/// Outcome of attaching one media: the descriptor (always produced) plus whether
/// the bytes were uploaded now or queued offline for later sync.
class MediaAttachResult {
  const MediaAttachResult({required this.descriptor, required this.uploaded});

  /// The off-record pointer to embed in the consultation (#23).
  final MediaDescriptor descriptor;

  /// `true` if the ciphertext reached the backend; `false` if it was handed to the
  /// offline sink (network down) and awaits sync (#22).
  final bool uploaded;
}

/// Generate an RFC-4122 v4 UUID from the OS CSPRNG (anonymous media index).
String generateMediaUuid() {
  final rng = Random.secure();
  final b = Uint8List.fromList(List.generate(16, (_) => rng.nextInt(256)));
  b[6] = (b[6] & 0x0F) | 0x40; // version 4
  b[8] = (b[8] & 0x3F) | 0x80; // variant RFC 4122
  String hex(int v) => v.toRadixString(16).padLeft(2, '0');
  return '${hex(b[0])}${hex(b[1])}${hex(b[2])}${hex(b[3])}-'
      '${hex(b[4])}${hex(b[5])}-'
      '${hex(b[6])}${hex(b[7])}-'
      '${hex(b[8])}${hex(b[9])}-'
      '${hex(b[10])}${hex(b[11])}${hex(b[12])}${hex(b[13])}${hex(b[14])}${hex(b[15])}';
}

/// Orchestrates capture → encrypt → offload → descriptor (#23).
///
/// Inject [uuidFactory] / [clock] for deterministic tests. [enqueueOffline] is the
/// optional offline sink (the #21/#22 queue seam): when the upload fails with
/// [MediaBackendUnavailable] and a sink is provided, the ciphertext is queued and
/// the result is `uploaded: false`; otherwise the error propagates.
class MediaUploadService {
  MediaUploadService({
    required MediaCipher cipher,
    required MediaClient client,
    String Function()? uuidFactory,
    DateTime Function()? clock,
    Future<void> Function(String uuid, Uint8List ciphertext)? enqueueOffline,
  })  : _cipher = cipher,
        _client = client,
        _uuidFactory = uuidFactory ?? generateMediaUuid,
        _clock = clock ?? (() => DateTime.now().toUtc()),
        _enqueueOffline = enqueueOffline;

  final MediaCipher _cipher;
  final MediaClient _client;
  final String Function() _uuidFactory;
  final DateTime Function() _clock;
  final Future<void> Function(String uuid, Uint8List ciphertext)?
      _enqueueOffline;

  /// Encrypt [imageBytes], offload them, and return the descriptor to merge into
  /// the consultation. Never writes the image to disk (G2).
  Future<MediaAttachResult> attach(
    Uint8List imageBytes, {
    required String mime,
  }) async {
    final encrypted = await _cipher.encrypt(imageBytes);
    try {
      final uuid = _uuidFactory();
      final descriptor = MediaDescriptor(
        uuid: uuid,
        contentKey: base64Encode(encrypted.contentKey),
        contentHash: encrypted.contentHash,
        mime: mime,
        sizeBytes: imageBytes.length,
        addedAt: _clock().toUtc().toIso8601String(),
      );
      try {
        await _client.putMedia(uuid, encrypted.ciphertext);
        return MediaAttachResult(descriptor: descriptor, uploaded: true);
      } on MediaBackendUnavailable {
        final enqueue = _enqueueOffline;
        if (enqueue == null) rethrow;
        await enqueue(uuid, encrypted.ciphertext);
        return MediaAttachResult(descriptor: descriptor, uploaded: false);
      }
    } finally {
      // Zero the transient raw content-key buffer; the canonical copy now lives
      // (base64) inside the descriptor, which the record encryption protects.
      encrypted.contentKey.fillRange(0, encrypted.contentKey.length, 0);
    }
  }
}
