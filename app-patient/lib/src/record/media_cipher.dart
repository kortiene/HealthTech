// Client-side heavy-media encryption (issue #23, G1/G2).
//
// Encrypts/decrypts a heavy medical image with a fresh PER-MEDIA AES-256 content
// key via the shared Rust crypto-core (ADR 0001/0003 — the ONLY cipher path; no
// Dart-side AES). The content key is generated inside the Rust core and only ever
// materialised to be stored INSIDE the patient's already-encrypted record (the
// [MediaDescriptor]); the server sees nothing but opaque ciphertext.
//
// RAM-only discipline (#17/#19): every Rust key handle is wiped in a `finally`
// block, and the plaintext image bytes live only on the Dart heap for as long as
// the caller holds them — this class never writes anything to disk.

import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

import '../rust/crypto_core_bindings.dart';

/// Raised when a decrypted image's SHA-256 does not match the descriptor's
/// [MediaDescriptor.contentHash] — the bytes were altered in transit/at rest
/// (independent of the GCM tag, which crypto-core already checks).
class MediaIntegrityError implements Exception {
  const MediaIntegrityError();
  @override
  String toString() => 'media integrity check failed: content hash mismatch';
}

/// The product of encrypting one image: opaque ciphertext + the per-media content
/// key (to embed in the record descriptor) + the plaintext integrity hash.
class EncryptedMedia {
  const EncryptedMedia({
    required this.ciphertext,
    required this.contentKey,
    required this.contentHash,
  });

  /// `nonce(12) || ciphertext || tag(16)` — opaque, offloaded to `/media/{uuid}`.
  final Uint8List ciphertext;

  /// The 32-byte per-media AES-256 key. Caller base64-encodes it into the
  /// descriptor and should wipe this buffer once captured.
  final Uint8List contentKey;

  /// SHA-256 (hex) of the plaintext image — the descriptor's `content_hash`.
  final String contentHash;
}

/// Encrypts/decrypts heavy media via crypto-core with a per-media content key.
class MediaCipher {
  const MediaCipher(this._crypto);

  final CryptoCore _crypto;

  /// Encrypt [imageBytes] under a fresh per-media content key generated in the
  /// Rust core. Returns the opaque ciphertext, the content key (to store in the
  /// descriptor), and the plaintext SHA-256. The Rust handle is wiped in `finally`.
  Future<EncryptedMedia> encrypt(Uint8List imageBytes) async {
    // A fresh random 256-bit key per media, generated inside crypto-core.
    final handle = await _crypto.generateMasterKey();
    try {
      // The clear key crosses the FFI once, to be stored (encrypted) in the record.
      final contentKey = await _crypto.exportSealable(handle);
      final ciphertext = await _crypto.encryptRecord(handle, imageBytes);
      final contentHash = sha256.convert(imageBytes).toString();
      return EncryptedMedia(
        ciphertext: ciphertext,
        contentKey: contentKey,
        contentHash: contentHash,
      );
    } finally {
      await _crypto.wipe(handle);
    }
  }

  /// Decrypt [ciphertext] with [contentKey] entirely in RAM. When [expectedHash]
  /// is given, the decrypted bytes' SHA-256 must match or [MediaIntegrityError] is
  /// thrown. The Rust handle is wiped in `finally`.
  ///
  /// Throws [DecryptError] (from crypto-core) on a bad key/tag/blob.
  Future<Uint8List> decrypt(
    Uint8List ciphertext,
    Uint8List contentKey, {
    String? expectedHash,
  }) async {
    final handle = await _crypto.handleFromUnsealed(contentKey);
    try {
      final plaintext = await _crypto.decryptRecord(handle, ciphertext);
      if (expectedHash != null &&
          sha256.convert(plaintext).toString() != expectedHash) {
        throw const MediaIntegrityError();
      }
      return plaintext;
    } finally {
      await _crypto.wipe(handle);
    }
  }
}
