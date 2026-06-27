// Consent model for the patient onboarding flow (issue #7).
//
// ConsentRecord captures which version of the legal bundle (consent policy,
// CGU, privacy policy) the patient accepted and when. It is stored inside the
// encrypted patient account so the server never sees it.
//
// Integration with the onboarding UI is in issue #13.

/// Semantic version of the legal-text bundle shipped with this build.
///
/// Increment when the consent policy, CGU, or privacy policy changes in a way
/// that requires the patient to re-accept. Keep in sync with the `version:`
/// header in `docs/legal/consent-v1.md`.
const String consentBundleVersion = '1.0';

/// Immutable record of the patient's acceptance of the legal bundle.
///
/// Created at the moment the patient taps "J'accepte" in the onboarding flow
/// (#13). Serialised to JSON for storage inside the encrypted patient account;
/// the server only ever sees the opaque AES-256-GCM ciphertext.
class ConsentRecord {
  const ConsentRecord({
    required this.version,
    required this.acceptedAt,
  });

  factory ConsentRecord.fromJson(Map<String, Object?> json) {
    return ConsentRecord(
      version: json['version'] as String,
      acceptedAt: json['accepted_at'] as String,
    );
  }

  /// Version of the legal-text bundle the patient accepted.
  ///
  /// Matches [consentBundleVersion] at acceptance time. Stored so that a
  /// future version bump can trigger a re-consent prompt.
  final String version;

  /// ISO-8601 UTC timestamp of acceptance (e.g. `"2024-01-15T10:30:00Z"`).
  ///
  /// Set by the onboarding flow (#13) via `DateTime.now().toUtc().toIso8601String()`.
  /// This timestamp is the proof of consent capture (REQ-LEX-04 / CTRL-16).
  final String acceptedAt;

  Map<String, Object?> toJson() => {
        'version': version,
        'accepted_at': acceptedAt,
      };

  @override
  bool operator ==(Object other) =>
      other is ConsentRecord &&
      other.version == version &&
      other.acceptedAt == acceptedAt;

  @override
  int get hashCode => Object.hash(version, acceptedAt);
}
