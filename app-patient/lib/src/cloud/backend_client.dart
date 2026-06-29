// Zero-knowledge blob backend HTTP client (issue #14 / ADR 0004).
//
// Routes opaque AES-256-GCM ciphertext to and from PUT/GET /blob/{uuid}.
// The server is never given key material, plaintext, or PII — it stores and
// returns opaque bytes indexed by an anonymous UUID (zero-knowledge boundary).
// Logs carry only the UUID and HTTP status, never the ciphertext body.

import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Thrown when the backend returns 404 for the requested blob UUID.
class BlobNotFound implements Exception {
  const BlobNotFound(this.uuid);
  final String uuid;
  @override
  String toString() => 'blob not found: $uuid';
}

/// Thrown on any non-success, non-404 backend response or network failure.
class BackendUnavailable implements Exception {
  const BackendUnavailable(this.message);
  final String message;
  @override
  String toString() => 'backend unavailable: $message';
}

/// HTTP transport to the zero-knowledge blob backend (ADR 0004).
///
/// [baseUrl] is the full origin (e.g. `https://api.healthtech.ci`).
/// Inject a custom [http.Client] in tests via [httpClient] to avoid real
/// network calls.
class BackendClient {
  BackendClient(this.baseUrl, {http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  /// Upload opaque ciphertext — `PUT /blob/{uuid}`.
  ///
  /// Returns normally on HTTP 200 or 201. The body is never inspected,
  /// logged, or decoded: it is opaque ciphertext only. Throws
  /// [BackendUnavailable] on any other status or network error.
  Future<void> put(String uuid, Uint8List ciphertext) async {
    final uri = Uri.parse('$baseUrl/blob/$uuid');
    try {
      final resp = await _http.put(
        uri,
        body: ciphertext,
        headers: const {'Content-Type': 'application/octet-stream'},
      );
      if (resp.statusCode == 200 || resp.statusCode == 201) return;
      throw BackendUnavailable(
        'PUT /blob/$uuid → ${resp.statusCode}',
      );
    } on BackendUnavailable {
      rethrow;
    } catch (e) {
      throw BackendUnavailable('PUT /blob/$uuid: $e');
    }
  }

  /// Download opaque ciphertext — `GET /blob/{uuid}`.
  ///
  /// Returns the raw ciphertext bytes on HTTP 200. Throws [BlobNotFound] on
  /// 404, [BackendUnavailable] on any other status or network error.
  Future<Uint8List> get(String uuid) async {
    final uri = Uri.parse('$baseUrl/blob/$uuid');
    try {
      final resp = await _http.get(uri);
      if (resp.statusCode == 200) return resp.bodyBytes;
      if (resp.statusCode == 404) throw BlobNotFound(uuid);
      throw BackendUnavailable(
        'GET /blob/$uuid → ${resp.statusCode}',
      );
    } on BackendUnavailable {
      rethrow;
    } on BlobNotFound {
      rethrow;
    } catch (e) {
      throw BackendUnavailable('GET /blob/$uuid: $e');
    }
  }
}
