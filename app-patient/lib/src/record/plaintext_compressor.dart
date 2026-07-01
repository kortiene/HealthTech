// Gzip compression for record plaintext (issue #24 — degraded network).
//
// Compressing the plaintext JSON *before* AES-256-GCM encryption reduces the
// encrypted blob size by 75–85 % (JSON text compresses extremely well), cutting
// Edge/3G download time proportionally. The server still receives opaque bytes
// keyed by an anonymous UUID — the zero-knowledge boundary is unchanged.
//
// The 500 Kio budget is measured on the UNCOMPRESSED plaintext (RecordSizeGuard);
// this class operates inside the encrypt/decrypt seam, transparent to that guard.
//
// Backward compatibility: blobs written before #24 (uncompressed plaintext inside
// the AES envelope) are still decodable — decodeIfCompressed checks the gzip magic
// header (0x1f 0x8b) and falls back to returning the input unchanged. Valid JSON
// always starts with 0x7b ('{'), so the two cases are unambiguous.

import 'dart:io' show GZipCodec;
import 'dart:typed_data';

/// Gzip compression/decompression for record plaintext (issue #24).
///
/// Only call [compress] on plaintext JSON bytes — passing random bytes
/// (e.g. ciphertext) can *increase* the size.
abstract final class PlaintextCompressor {
  /// Gzip-compress [bytes]. Always produces a gzip-framed output.
  static Uint8List compress(Uint8List bytes) =>
      Uint8List.fromList(GZipCodec().encode(bytes));

  /// Decompress [bytes] if they carry a gzip frame; return unchanged otherwise.
  ///
  /// Detection: gzip magic bytes are 0x1f 0x8b. Valid JSON always starts with
  /// 0x7b ('{'), so the two cases are unambiguous. This enables transparent
  /// reading of blobs written before compression was introduced (issue #24).
  static Uint8List decodeIfCompressed(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      return Uint8List.fromList(GZipCodec().decode(bytes));
    }
    return bytes;
  }
}
