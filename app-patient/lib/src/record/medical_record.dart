// Medical record schema v1 (issue #15).
//
// This is the plaintext payload that gets encrypted by AES-256-GCM (issue #10)
// before any network transit. The server never sees this structure — it only
// stores the opaque encrypted blob.
//
// Design rules (PRD §4, zero-knowledge boundary):
//   - No binary data: heavy images are encrypted + offloaded to the server (#23)
//     and the record carries only a small, stable MEDIA DESCRIPTOR (anonymous
//     media UUID + per-media content key + integrity hash) — never the bytes, and
//     never a baked-in ephemeral URL (that is minted on demand, see MediaClient).
//   - patient_id is a local opaque UUID, never correlated with CMU/phone.
//   - Serialised UTF-8 JSON must stay ≤ 500 Kio (enforced by RecordSizeGuard); the
//     media descriptor is tiny, so the budget holds (the bytes live off-record).
//   - Version field `v` enables migration without breaking decryption.
//
// The media descriptor is added additively within schema v1 (issue #23): the new
// `media` field on a Consultation is optional and defaults to empty, so records
// written before #23 round-trip unchanged and no migration/version bump is needed.
// The legacy `image_urls` field is retained for back-compat (deprecated; superseded
// by `media`).

import 'dart:convert';

/// Schema version. Increment when adding required fields or changing semantics.
const int recordSchemaVersion = 1;

/// Minimal, patient-controlled demographic data.
class Demographics {
  const Demographics({
    this.givenName,
    this.birthYear,
    this.sex,
    this.bloodType,
  });

  factory Demographics.fromJson(Map<String, Object?> json) {
    return Demographics(
      givenName: json['given_name'] as String?,
      birthYear: json['birth_year'] as int?,
      sex: json['sex'] as String?,
      bloodType: json['blood_type'] as String?,
    );
  }

  final String? givenName;
  final int? birthYear;

  /// `M`, `F`, `O`, or null (not disclosed).
  final String? sex;
  final String? bloodType;

  Map<String, Object?> toJson() => {
        if (givenName != null) 'given_name': givenName,
        if (birthYear != null) 'birth_year': birthYear,
        if (sex != null) 'sex': sex,
        if (bloodType != null) 'blood_type': bloodType,
      };

  @override
  bool operator ==(Object other) =>
      other is Demographics &&
      other.givenName == givenName &&
      other.birthYear == birthYear &&
      other.sex == sex &&
      other.bloodType == bloodType;

  @override
  int get hashCode => Object.hash(givenName, birthYear, sex, bloodType);
}

class Allergy {
  const Allergy({
    required this.substance,
    required this.severity,
    required this.notedAt,
  });

  factory Allergy.fromJson(Map<String, Object?> json) {
    return Allergy(
      substance: json['substance'] as String,
      severity: json['severity'] as String,
      notedAt: json['noted_at'] as String,
    );
  }

  final String substance;

  /// `mild`, `moderate`, or `severe`.
  final String severity;

  /// ISO-8601 date string (`yyyy-MM-dd`).
  final String notedAt;

  Map<String, Object?> toJson() => {
        'substance': substance,
        'severity': severity,
        'noted_at': notedAt,
      };

  @override
  bool operator ==(Object other) =>
      other is Allergy &&
      other.substance == substance &&
      other.severity == severity &&
      other.notedAt == notedAt;

  @override
  int get hashCode => Object.hash(substance, severity, notedAt);
}

class ChronicCondition {
  const ChronicCondition({
    required this.name,
    this.icd10,
    this.since,
  });

  factory ChronicCondition.fromJson(Map<String, Object?> json) {
    return ChronicCondition(
      name: json['name'] as String,
      icd10: json['icd10'] as String?,
      since: json['since'] as String?,
    );
  }

  final String name;
  final String? icd10;

  /// Year string (e.g. `"2020"`).
  final String? since;

  Map<String, Object?> toJson() => {
        'name': name,
        if (icd10 != null) 'icd10': icd10,
        if (since != null) 'since': since,
      };

  @override
  bool operator ==(Object other) =>
      other is ChronicCondition &&
      other.name == name &&
      other.icd10 == icd10 &&
      other.since == since;

  @override
  int get hashCode => Object.hash(name, icd10, since);
}

class Medication {
  const Medication({
    required this.name,
    required this.dose,
    required this.frequency,
    required this.prescribedAt,
    this.prescribedBy,
  });

  factory Medication.fromJson(Map<String, Object?> json) {
    return Medication(
      name: json['name'] as String,
      dose: json['dose'] as String,
      frequency: json['frequency'] as String,
      prescribedAt: json['prescribed_at'] as String,
      prescribedBy: json['prescribed_by'] as String?,
    );
  }

  final String name;
  final String dose;
  final String frequency;

  /// ISO-8601 date string.
  final String prescribedAt;

  /// Opaque practitioner reference UUID.
  final String? prescribedBy;

  Map<String, Object?> toJson() => {
        'name': name,
        'dose': dose,
        'frequency': frequency,
        'prescribed_at': prescribedAt,
        if (prescribedBy != null) 'prescribed_by': prescribedBy,
      };

  @override
  bool operator ==(Object other) =>
      other is Medication &&
      other.name == name &&
      other.dose == dose &&
      other.frequency == frequency &&
      other.prescribedAt == prescribedAt &&
      other.prescribedBy == prescribedBy;

  @override
  int get hashCode =>
      Object.hash(name, dose, frequency, prescribedAt, prescribedBy);
}

/// Stable, off-record pointer to one heavy medical image (radiograph / scan) that
/// has been encrypted client-side and offloaded to the server (issue #23).
///
/// The bytes NEVER live on the patient phone — only this small descriptor does.
/// It is itself stored INSIDE the AES-256-GCM-encrypted record, so the
/// [contentKey] is protected by the record's own zero-knowledge encryption and the
/// server (which holds only opaque ciphertext keyed by [uuid]) can never read it.
///
/// No ephemeral URL is baked in: an access URL is minted on demand (and expires),
/// so a durable record never carries a stale link. See `cloud/media_client.dart`.
class MediaDescriptor {
  const MediaDescriptor({
    required this.uuid,
    required this.contentKey,
    required this.contentHash,
    required this.mime,
    required this.sizeBytes,
    required this.addedAt,
    this.alg = 'A256GCM',
  });

  factory MediaDescriptor.fromJson(Map<String, Object?> json) {
    return MediaDescriptor(
      uuid: json['uuid'] as String,
      contentKey: json['content_key'] as String,
      alg: json['alg'] as String? ?? 'A256GCM',
      contentHash: json['content_hash'] as String,
      mime: json['mime'] as String,
      sizeBytes: json['size_bytes'] as int,
      addedAt: json['added_at'] as String,
    );
  }

  /// Anonymous media UUID — the `/media/{uuid}` server index. Never derived from PII.
  final String uuid;

  /// Base64 of the 32-byte per-media AES-256 content key. Protected by the
  /// record's own encryption; never transmitted to the server.
  final String contentKey;

  /// AEAD algorithm identifier (currently always `A256GCM`, ADR 0003).
  final String alg;

  /// SHA-256 (hex) of the plaintext image — independent end-to-end integrity check
  /// on top of the GCM tag.
  final String contentHash;

  /// MIME type of the decrypted image (e.g. `image/jpeg`).
  final String mime;

  /// Size of the plaintext image in bytes (UI / budgeting; not the ciphertext size).
  final int sizeBytes;

  /// ISO-8601 UTC timestamp the media was attached.
  final String addedAt;

  Map<String, Object?> toJson() => {
        'uuid': uuid,
        'content_key': contentKey,
        'alg': alg,
        'content_hash': contentHash,
        'mime': mime,
        'size_bytes': sizeBytes,
        'added_at': addedAt,
      };

  @override
  bool operator ==(Object other) =>
      other is MediaDescriptor &&
      other.uuid == uuid &&
      other.contentKey == contentKey &&
      other.alg == alg &&
      other.contentHash == contentHash &&
      other.mime == mime &&
      other.sizeBytes == sizeBytes &&
      other.addedAt == addedAt;

  @override
  int get hashCode => Object.hash(
        uuid,
        contentKey,
        alg,
        contentHash,
        mime,
        sizeBytes,
        addedAt,
      );
}

/// A single consultation record. Binary images are NEVER stored here — heavy media
/// is offloaded to the server (#23) and referenced by a [MediaDescriptor] in [media].
class Consultation {
  const Consultation({
    required this.id,
    required this.date,
    required this.practitionerRef,
    required this.summary,
    this.prescription,
    this.imageUrls = const [],
    this.media = const [],
  });

  factory Consultation.fromJson(Map<String, Object?> json) {
    final rawUrls = json['image_urls'] as List<Object?>?;
    final urls = rawUrls?.map((e) => e as String).toList() ?? const <String>[];
    final rawMedia = json['media'] as List<Object?>?;
    final media = rawMedia
            ?.map((e) => MediaDescriptor.fromJson(e as Map<String, Object?>))
            .toList() ??
        const <MediaDescriptor>[];
    return Consultation(
      id: json['id'] as String,
      date: json['date'] as String,
      practitionerRef: json['practitioner_ref'] as String,
      summary: json['summary'] as String,
      prescription: json['prescription'] as String?,
      imageUrls: urls,
      media: media,
    );
  }

  /// Opaque UUID for this consultation entry.
  final String id;

  /// ISO-8601 date string (`yyyy-MM-dd`). Used for truncation order.
  final String date;

  /// Opaque practitioner reference UUID.
  final String practitionerRef;
  final String summary;
  final String? prescription;

  /// Legacy ephemeral CDN URLs — deprecated, superseded by [media] (#23). Retained
  /// for back-compat with records written before the descriptor existed.
  final List<String> imageUrls;

  /// Heavy-media descriptors (#23): off-record pointers to encrypted images. No
  /// binary data, no baked-in URL — only an anonymous UUID + per-media content key.
  final List<MediaDescriptor> media;

  Map<String, Object?> toJson() => {
        'id': id,
        'date': date,
        'practitioner_ref': practitionerRef,
        'summary': summary,
        if (prescription != null) 'prescription': prescription,
        'image_urls': imageUrls,
        if (media.isNotEmpty) 'media': media.map((e) => e.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      other is Consultation &&
      other.id == id &&
      other.date == date &&
      other.practitionerRef == practitionerRef &&
      other.summary == summary &&
      other.prescription == prescription &&
      _listEq(other.imageUrls, imageUrls) &&
      _listEq(other.media, media);

  @override
  int get hashCode => Object.hash(
        id,
        date,
        practitionerRef,
        summary,
        prescription,
        Object.hashAll(imageUrls),
        Object.hashAll(media),
      );
}

class Immunization {
  const Immunization({
    required this.name,
    required this.date,
    this.dose,
  });

  factory Immunization.fromJson(Map<String, Object?> json) {
    return Immunization(
      name: json['name'] as String,
      date: json['date'] as String,
      dose: json['dose'] as int?,
    );
  }

  final String name;

  /// ISO-8601 date string.
  final String date;
  final int? dose;

  Map<String, Object?> toJson() => {
        'name': name,
        'date': date,
        if (dose != null) 'dose': dose,
      };

  @override
  bool operator ==(Object other) =>
      other is Immunization &&
      other.name == name &&
      other.date == date &&
      other.dose == dose;

  @override
  int get hashCode => Object.hash(name, date, dose);
}

/// The versioned patient medical record — root of the encrypted payload.
///
/// Serialise with [toJson]; the resulting UTF-8 bytes are passed to
/// `crypto_core.encrypt_record`. The 500 Kio plaintext limit is enforced by
/// [RecordSizeGuard] before encryption.
class MedicalRecord {
  const MedicalRecord({
    required this.patientId,
    this.demographics = const Demographics(),
    this.allergies = const [],
    this.chronicConditions = const [],
    this.medications = const [],
    this.consultations = const [],
    this.immunizations = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  // ignore: prefer_constructors_over_static_methods
  static MedicalRecord fromJson(Map<String, Object?> json) {
    final version = json['v'] as int? ?? 0;
    if (version != recordSchemaVersion) {
      throw UnsupportedError(
        'Unsupported record schema version $version '
        '(expected $recordSchemaVersion). '
        'Run the record migrator before opening this record.',
      );
    }
    final rawDemo = json['demographics'] as Map<String, Object?>?;
    final rawAllergies = json['allergies'] as List<Object?>? ?? const [];
    final rawConditions =
        json['chronic_conditions'] as List<Object?>? ?? const [];
    final rawMeds = json['medications'] as List<Object?>? ?? const [];
    final rawConsults = json['consultations'] as List<Object?>? ?? const [];
    final rawImm = json['immunizations'] as List<Object?>? ?? const [];

    return MedicalRecord(
      patientId: json['patient_id'] as String,
      demographics: rawDemo != null
          ? Demographics.fromJson(rawDemo)
          : const Demographics(),
      allergies: [
        for (final e in rawAllergies)
          Allergy.fromJson(e as Map<String, Object?>),
      ],
      chronicConditions: [
        for (final e in rawConditions)
          ChronicCondition.fromJson(e as Map<String, Object?>),
      ],
      medications: [
        for (final e in rawMeds) Medication.fromJson(e as Map<String, Object?>),
      ],
      consultations: [
        for (final e in rawConsults)
          Consultation.fromJson(e as Map<String, Object?>),
      ],
      immunizations: [
        for (final e in rawImm)
          Immunization.fromJson(e as Map<String, Object?>),
      ],
      createdAt: json['created_at'] as String,
      updatedAt: json['updated_at'] as String,
    );
  }

  /// Schema version — always [recordSchemaVersion] for newly created records.
  final int v = recordSchemaVersion;

  /// Locally generated opaque UUID — never correlated with CMU / phone.
  final String patientId;
  final Demographics demographics;
  final List<Allergy> allergies;
  final List<ChronicCondition> chronicConditions;
  final List<Medication> medications;

  /// Sorted oldest-first; [RecordSizeGuard] truncates from index 0.
  final List<Consultation> consultations;
  final List<Immunization> immunizations;

  /// ISO-8601 UTC timestamp of record creation.
  final String createdAt;

  /// ISO-8601 UTC timestamp of the most recent local update.
  final String updatedAt;

  Map<String, Object?> toJson() => {
        'v': v,
        'patient_id': patientId,
        'demographics': demographics.toJson(),
        'allergies': allergies.map((e) => e.toJson()).toList(),
        'chronic_conditions': chronicConditions.map((e) => e.toJson()).toList(),
        'medications': medications.map((e) => e.toJson()).toList(),
        'consultations': consultations.map((e) => e.toJson()).toList(),
        'immunizations': immunizations.map((e) => e.toJson()).toList(),
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  /// UTF-8 encoded JSON bytes — the plaintext payload for encryption.
  List<int> toUtf8Bytes() => utf8.encode(jsonEncode(toJson()));

  /// Returns a copy with an updated [consultations] list and [updatedAt].
  MedicalRecord copyWith({
    List<Consultation>? consultations,
    String? updatedAt,
    Demographics? demographics,
    List<Allergy>? allergies,
    List<ChronicCondition>? chronicConditions,
    List<Medication>? medications,
    List<Immunization>? immunizations,
  }) {
    return MedicalRecord(
      patientId: patientId,
      demographics: demographics ?? this.demographics,
      allergies: allergies ?? this.allergies,
      chronicConditions: chronicConditions ?? this.chronicConditions,
      medications: medications ?? this.medications,
      consultations: consultations ?? this.consultations,
      immunizations: immunizations ?? this.immunizations,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MedicalRecord &&
      other.v == v &&
      other.patientId == patientId &&
      other.demographics == demographics &&
      _listEq(other.allergies, allergies) &&
      _listEq(other.chronicConditions, chronicConditions) &&
      _listEq(other.medications, medications) &&
      _listEq(other.consultations, consultations) &&
      _listEq(other.immunizations, immunizations) &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
        v,
        patientId,
        demographics,
        Object.hashAll(allergies),
        Object.hashAll(chronicConditions),
        Object.hashAll(medications),
        Object.hashAll(consultations),
        Object.hashAll(immunizations),
        createdAt,
        updatedAt,
      );
}

bool _listEq<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
