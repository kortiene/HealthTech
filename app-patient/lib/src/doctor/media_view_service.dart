// Heavy-media RAM-only view (issue #23, G2 / #2).
//
// Loads a [MediaDescriptor]'s image entirely in memory for transient display:
//   mint ephemeral URL (POST /media/{uuid}/access) → download ciphertext (GET,
//   the URL expires) → decrypt in RAM with the per-media content key → bytes.
//
// Invariants:
//   - The decrypted image is returned as in-RAM bytes only; this service NEVER
//     writes it to disk (G2: "aucune image lourde sur le téléphone"). The caller
//     must feed the bytes to a widget WITHOUT a disk cache and drop them when the
//     view closes (polish UI = #28).
//   - The ephemeral access URL is minted PER VIEW and is never persisted; an
//     expired URL surfaces as [MediaAccessExpired] (#2) and the caller re-mints.
//   - The transient content-key copy is zeroed in a `finally` block.

import 'dart:convert';
import 'dart:typed_data';

import '../cloud/media_client.dart';
import '../record/media_cipher.dart';
import '../record/medical_record.dart';

/// Fetches + decrypts heavy media for transient, RAM-only display (#23).
class MediaViewService {
  const MediaViewService({
    required MediaCipher cipher,
    required MediaClient client,
  })  : _cipher = cipher,
        _client = client;

  final MediaCipher _cipher;
  final MediaClient _client;

  /// Load [descriptor]'s image into RAM: mint a fresh ephemeral URL, download the
  /// opaque ciphertext, and decrypt + integrity-check it with the per-media key.
  ///
  /// Throws [MediaAccessExpired] if the minted URL is refused, [MediaNotFound] if
  /// the object was deleted/revoked, [MediaBackendUnavailable] on network failure,
  /// [DecryptError] on a bad key/tag, or [MediaIntegrityError] on a hash mismatch.
  Future<Uint8List> load(MediaDescriptor descriptor) async {
    final grant = await _client.requestAccess(descriptor.uuid);
    final ciphertext = await _client.fetchCiphertext(grant.url);
    final contentKey = base64Decode(descriptor.contentKey);
    try {
      return await _cipher.decrypt(
        ciphertext,
        contentKey,
        expectedHash: descriptor.contentHash,
      );
    } finally {
      // Zero the transient key copy; the canonical copy stays in the encrypted record.
      contentKey.fillRange(0, contentKey.length, 0);
    }
  }
}
