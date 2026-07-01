// Heavy-media transport client (issue #23 / ADR 0004, 0005).
//
// Routes opaque AES-256-GCM media ciphertext to and from the backend's media
// endpoints, and mints the SHORT-TTL ephemeral access URL on demand:
//
//   PUT  /media/{uuid}          — upload opaque ciphertext (offload, #23 G1/G2)
//   POST /media/{uuid}/access   — mint an ephemeral, per-object capability URL
//   GET  <minted url>           — download opaque ciphertext (URL expires, #23 #2)
//
// Like BackendClient, the server is never given key material, plaintext, or PII —
// it stores/returns opaque bytes keyed by an anonymous UUID. The minted URL is a
// BEARER SECRET: it is never persisted and never logged (logs carry only the UUID
// and HTTP status). Inject a custom [http.Client] in tests via [httpClient].

import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'network_retry.dart';

/// Thrown when the backend returns 404 for the requested media UUID (unknown or
/// revoked/deleted object).
class MediaNotFound implements Exception {
  const MediaNotFound(this.uuid);
  final String uuid;
  @override
  String toString() => 'media not found: $uuid';
}

/// Thrown when a media access URL is refused (403) — expired or invalid signature.
/// Deliberately coarse (no oracle distinguishing expired from forged), mirroring
/// the backend's uniform 403.
class MediaAccessExpired implements Exception {
  const MediaAccessExpired();
  @override
  String toString() =>
      'media access URL expired or invalid — request a fresh one';
}

/// Thrown on any non-success, non-404/403 backend response or network failure.
class MediaBackendUnavailable implements Exception {
  const MediaBackendUnavailable(this.message);
  final String message;
  @override
  String toString() => 'media backend unavailable: $message';
}

/// A freshly minted ephemeral access grant for one media object.
class MediaAccessGrant {
  const MediaAccessGrant({required this.url, required this.expiresAt});

  /// Capability URL (`/media/{uuid}?exp=…&sig=…`), absolute or backend-relative.
  /// Bearer secret — do NOT persist it; it expires.
  final String url;

  /// ISO-8601 UTC expiry, for display / pre-expiry refresh.
  final String expiresAt;
}

/// HTTP transport to the heavy-media endpoints (ADR 0004/0005).
///
/// [baseUrl] is the full origin (e.g. `https://api.healthtech.ci`).
/// Pass an optional [retry] to enable automatic retry of transient failures
/// on degraded Edge/3G connections (issue #24). Default null = no retry.
class MediaClient {
  MediaClient(this.baseUrl, {http.Client? httpClient, NetworkRetry? retry})
      : _http = httpClient ?? http.Client(),
        _retry = retry;

  final String baseUrl;
  final http.Client _http;
  final NetworkRetry? _retry;

  /// Upload opaque media ciphertext — `PUT /media/{uuid}`.
  ///
  /// Returns normally on HTTP 200 or 201. The body is never inspected, logged, or
  /// decoded: it is opaque ciphertext only. Throws [MediaBackendUnavailable] on any
  /// other status or network error (the caller may then enqueue it offline, #21/#22).
  /// Retries transient failures when a [NetworkRetry] was provided (issue #24).
  Future<void> putMedia(String uuid, Uint8List ciphertext) async {
    Future<void> doPut() async {
      final uri = Uri.parse('$baseUrl/media/$uuid');
      try {
        final resp = await _http.put(
          uri,
          body: ciphertext,
          headers: const {'Content-Type': 'application/octet-stream'},
        );
        if (resp.statusCode == 200 || resp.statusCode == 201) return;
        throw MediaBackendUnavailable('PUT /media/$uuid → ${resp.statusCode}');
      } on MediaBackendUnavailable {
        rethrow;
      } catch (e) {
        throw MediaBackendUnavailable('PUT /media/$uuid: $e');
      }
    }

    if (_retry != null) {
      await _retry.run(doPut, retryIf: (e) => e is MediaBackendUnavailable);
    } else {
      await doPut();
    }
  }

  /// Mint a short-TTL ephemeral access URL — `POST /media/{uuid}/access`.
  ///
  /// Throws [MediaNotFound] on 404, [MediaBackendUnavailable] otherwise.
  Future<MediaAccessGrant> requestAccess(String uuid) async {
    final uri = Uri.parse('$baseUrl/media/$uuid/access');
    try {
      final resp = await _http.post(uri);
      if (resp.statusCode == 200) {
        final json = jsonDecode(resp.body) as Map<String, Object?>;
        return MediaAccessGrant(
          url: json['url'] as String,
          expiresAt: json['expires_at'] as String,
        );
      }
      if (resp.statusCode == 404) throw MediaNotFound(uuid);
      throw MediaBackendUnavailable(
        'POST /media/$uuid/access → ${resp.statusCode}',
      );
    } on MediaNotFound {
      rethrow;
    } on MediaBackendUnavailable {
      rethrow;
    } catch (e) {
      throw MediaBackendUnavailable('POST /media/$uuid/access: $e');
    }
  }

  /// Download opaque media ciphertext via a minted access URL — `GET <url>`.
  ///
  /// [url] is the [MediaAccessGrant.url]; a backend-relative path is resolved
  /// against [baseUrl]. Returns the raw ciphertext on 200. Throws
  /// [MediaAccessExpired] on 403 (expired/invalid URL — not retried; a new
  /// grant must be minted), [MediaNotFound] on 404, [MediaBackendUnavailable]
  /// otherwise. Retries transient failures when a [NetworkRetry] was provided
  /// (issue #24).
  Future<Uint8List> fetchCiphertext(String url) async {
    Future<Uint8List> doFetch() async {
      final uri = Uri.parse(
        url.startsWith('http') ? url : '$baseUrl$url',
      );
      try {
        final resp = await _http.get(uri);
        if (resp.statusCode == 200) return resp.bodyBytes;
        if (resp.statusCode == 403) throw const MediaAccessExpired();
        if (resp.statusCode == 404) throw const MediaNotFound('<minted-url>');
        throw MediaBackendUnavailable('GET media url → ${resp.statusCode}');
      } on MediaAccessExpired {
        rethrow;
      } on MediaNotFound {
        rethrow;
      } on MediaBackendUnavailable {
        rethrow;
      } catch (e) {
        throw MediaBackendUnavailable('GET media url: $e');
      }
    }

    if (_retry != null) {
      return _retry.run(
        doFetch,
        retryIf: (e) => e is MediaBackendUnavailable,
      );
    }
    return doFetch();
  }
}
