// Medical record schema v1 (issue #15).
//
// This is the plaintext payload that gets encrypted by AES-256-GCM (issue #10)
// before any network transit. The server never sees this structure — it only
// stores the opaque encrypted blob.
//
// Design rules (PRD §4, zero-knowledge boundary):
//   - No binary data: images are stored remotely; only ephemeral URLs here.
//   - patient_id is a local opaque UUID, never correlated with CMU/phone.
//   - Serialised UTF-8 JSON must stay ≤ 500 Kio (enforced by RecordSizeGuard).
//   - Version field `v` enables migration without breaking decryption.

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

/// A single consultation record. Binary images are NEVER stored here —
/// only ephemeral CDN URLs (PRD §4).
class Consultation {
  const Consultation({
    required this.id,
    required this.date,
    required this.practitionerRef,
    required this.summary,
    this.prescription,
    this.imageUrls = const [],
  });

  factory Consultation.fromJson(Map<String, Object?> json) {
    final rawUrls = json['image_urls'] as List<Object?>?;
    final urls = rawUrls?.map((e) => e as String).toList() ?? const <String>[];
    return Consultation(
      id: json['id'] as String,
      date: json['date'] as String,
      practitionerRef: json['practitioner_ref'] as String,
      summary: json['summary'] as String,
      prescription: json['prescription'] as String?,
      imageUrls: urls,
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

  /// Ephemeral CDN URLs — no binary data, no credentials.
  final List<String> imageUrls;

  Map<String, Object?> toJson() => {
        'id': id,
        'date': date,
        'practitioner_ref': practitionerRef,
        'summary': summary,
        if (prescription != null) 'prescription': prescription,
        'image_urls': imageUrls,
      };

  @override
  bool operator ==(Object other) =>
      other is Consultation &&
      other.id == id &&
      other.date == date &&
      other.practitionerRef == practitionerRef &&
      other.summary == summary &&
      other.prescription == prescription &&
      _listEq(other.imageUrls, imageUrls);

  @override
  int get hashCode => Object.hash(
        id,
        date,
        practitionerRef,
        summary,
        prescription,
        Object.hashAll(imageUrls),
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
