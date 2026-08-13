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
    this.heightCm,
    this.weightKg,
  });

  factory Demographics.fromJson(Map<String, Object?> json) {
    return Demographics(
      givenName: json['given_name'] as String?,
      birthYear: json['birth_year'] as int?,
      sex: json['sex'] as String?,
      bloodType: json['blood_type'] as String?,
      heightCm: json['height_cm'] as int?,
      weightKg: (json['weight_kg'] as num?)?.toDouble(),
    );
  }

  final String? givenName;
  final int? birthYear;

  /// `M`, `F`, `O`, or null (not disclosed).
  final String? sex;
  final String? bloodType;

  /// Height in centimetres (optional).
  final int? heightCm;

  /// Weight in kilograms (optional).
  final double? weightKg;

  /// Body-mass index, computed on demand. Returns null when either dimension
  /// is absent or height is zero.
  double? get bmi {
    if (heightCm == null || weightKg == null || heightCm! <= 0) return null;
    final h = heightCm! / 100.0;
    return weightKg! / (h * h);
  }

  Map<String, Object?> toJson() => {
        if (givenName != null) 'given_name': givenName,
        if (birthYear != null) 'birth_year': birthYear,
        if (sex != null) 'sex': sex,
        if (bloodType != null) 'blood_type': bloodType,
        if (heightCm != null) 'height_cm': heightCm,
        if (weightKg != null) 'weight_kg': weightKg,
      };

  @override
  bool operator ==(Object other) =>
      other is Demographics &&
      other.givenName == givenName &&
      other.birthYear == birthYear &&
      other.sex == sex &&
      other.bloodType == bloodType &&
      other.heightCm == heightCm &&
      other.weightKg == weightKg;

  @override
  int get hashCode =>
      Object.hash(givenName, birthYear, sex, bloodType, heightCm, weightKg);
}

class Allergy {
  const Allergy({
    required this.substance,
    required this.severity,
    required this.notedAt,
  });

  factory Allergy.fromJson(Map<String, Object?> json) {
    return Allergy(
      substance: json['substance'] as String? ?? '',
      severity: json['severity'] as String? ?? 'mild',
      notedAt: json['noted_at'] as String? ?? '',
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
    this.documents = const [],
    this.severity,
    this.addedAt,
  });

  factory ChronicCondition.fromJson(Map<String, Object?> json) {
    final rawDocs = json['documents'] as List<Object?>?;
    return ChronicCondition(
      name: json['name'] as String,
      icd10: json['icd10'] as String?,
      since: json['since'] as String?,
      documents: rawDocs
              ?.map((e) => MediaDescriptor.fromJson(e as Map<String, Object?>))
              .toList() ??
          const [],
      severity: json['severity'] as int?,
      addedAt: (json['added_at'] ?? json['addedAt']) as String?,
    );
  }

  final String name;
  final String? icd10;

  /// Year string (e.g. `"2020"`).
  final String? since;

  /// Encrypted justificatifs (e.g. ordonnance scan). Same local-first pattern
  /// as Consultation.media: bytes live at file:// on-device, synced on QR share.
  final List<MediaDescriptor> documents;

  /// Condition severity on a 1–5 scale: 1 = légère, 5 = critique (#138).
  /// Absent on records written before #138 — treated as unset in the UI.
  final int? severity;

  /// ISO-8601 UTC timestamp when the patient added this condition (#138).
  /// Absent on pre-#138 records — those sort after newer ones.
  final String? addedAt;

  ChronicCondition copyWith({
    String? name,
    String? icd10,
    String? since,
    List<MediaDescriptor>? documents,
    int? severity,
    String? addedAt,
  }) =>
      ChronicCondition(
        name: name ?? this.name,
        icd10: icd10 ?? this.icd10,
        since: since ?? this.since,
        documents: documents ?? this.documents,
        severity: severity ?? this.severity,
        addedAt: addedAt ?? this.addedAt,
      );

  ChronicCondition copyWithDocument(MediaDescriptor d) =>
      copyWith(documents: [...documents, d]);

  Map<String, Object?> toJson() => {
        'name': name,
        if (icd10 != null) 'icd10': icd10,
        if (since != null) 'since': since,
        if (documents.isNotEmpty)
          'documents': documents.map((d) => d.toJson()).toList(),
        if (severity != null) 'severity': severity,
        if (addedAt != null) 'added_at': addedAt,
      };

  @override
  bool operator ==(Object other) =>
      other is ChronicCondition &&
      other.name == name &&
      other.icd10 == icd10 &&
      other.since == since &&
      _listEq(other.documents, documents) &&
      other.severity == severity &&
      other.addedAt == addedAt;

  @override
  int get hashCode => Object.hash(
        name,
        icd10,
        since,
        Object.hashAll(documents),
        severity,
        addedAt,
      );
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
    this.url,
    this.durationMs,
  });

  factory MediaDescriptor.fromJson(Map<String, Object?> json) {
    // Accept both snake_case (canonical) and camelCase (PWA legacy — fixed in #120 hotfix)
    return MediaDescriptor(
      uuid: (json['uuid'] ?? json['mediaId'] ?? json['media_id']) as String? ??
          '',
      contentKey: (json['content_key'] ?? json['contentKey']) as String? ?? '',
      alg: json['alg'] as String? ?? 'A256GCM',
      contentHash:
          (json['content_hash'] ?? json['contentHash']) as String? ?? '',
      mime: json['mime'] as String? ?? 'application/octet-stream',
      sizeBytes: (json['size_bytes'] ?? json['sizeBytes']) as int? ?? 0,
      addedAt: (json['added_at'] ?? json['addedAt']) as String? ?? '',
      url: json['url'] as String?,
      durationMs: (json['duration_ms'] ?? json['durationMs']) as int?,
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

  /// Direct download URL stored by the PWA (dev only). Absent when ephemeral
  /// URLs are minted on demand via MediaClient.requestAccess (prod, #17).
  final String? url;

  /// Recording duration in milliseconds (for UI display before decode).
  final int? durationMs;

  Map<String, Object?> toJson() => {
        'uuid': uuid,
        'content_key': contentKey,
        'alg': alg,
        'content_hash': contentHash,
        'mime': mime,
        'size_bytes': sizeBytes,
        'added_at': addedAt,
        if (url != null) 'url': url,
        if (durationMs != null) 'duration_ms': durationMs,
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

/// A single medication line inside an [Ordonnance] (#121).
class OrdonnanceLine {
  const OrdonnanceLine({
    required this.medication,
    this.dose,
    this.frequency,
    this.durationDays,
    this.notes,
  });

  factory OrdonnanceLine.fromJson(Map<String, Object?> json) {
    return OrdonnanceLine(
      medication: (json['medication'] ?? '') as String,
      dose: json['dose'] as String?,
      frequency: json['frequency'] as String?,
      durationDays: (json['duration_days'] ?? json['durationDays']) as int?,
      notes: json['notes'] as String?,
    );
  }

  final String medication;
  final String? dose;
  final String? frequency;
  final int? durationDays;
  final String? notes;

  Map<String, Object?> toJson() => {
        'medication': medication,
        if (dose != null) 'dose': dose,
        if (frequency != null) 'frequency': frequency,
        if (durationDays != null) 'duration_days': durationDays,
        if (notes != null) 'notes': notes,
      };

  @override
  bool operator ==(Object other) =>
      other is OrdonnanceLine &&
      other.medication == medication &&
      other.dose == dose &&
      other.frequency == frequency &&
      other.durationDays == durationDays &&
      other.notes == notes;

  @override
  int get hashCode =>
      Object.hash(medication, dose, frequency, durationDays, notes);
}

/// A prescription document written at one consultation (#121).
/// May be linked to a global [Treatment] (same or future consultation) via
/// [treatmentId].
class Ordonnance {
  const Ordonnance({
    required this.id,
    this.treatmentId,
    this.label,
    this.createdAt,
    this.lines = const <OrdonnanceLine>[],
  });

  factory Ordonnance.fromJson(Map<String, Object?> json) {
    final rawLines = json['lines'] as List<Object?>?;
    return Ordonnance(
      id: (json['id'] ?? '') as String,
      treatmentId: (json['treatment_id'] ?? json['treatmentId']) as String?,
      label: json['label'] as String?,
      createdAt: (json['created_at'] ?? json['createdAt']) as String?,
      lines: rawLines
              ?.map((e) => OrdonnanceLine.fromJson(e as Map<String, Object?>))
              .toList() ??
          const [],
    );
  }

  /// Opaque UUID for this ordonnance document.
  final String id;

  /// Links this ordonnance to a [Treatment] in [MedicalRecord.treatments].
  final String? treatmentId;

  /// Optional label for the doctor's context, e.g. `"Médicaments"`,
  /// `"Examens biologiques"`.
  final String? label;

  /// ISO-8601 UTC timestamp when the doctor created this ordonnance.
  /// Absent on pre-#139 records — fall back to parent consultation date for sorting.
  final String? createdAt;

  final List<OrdonnanceLine> lines;

  Map<String, Object?> toJson() => {
        'id': id,
        if (treatmentId != null) 'treatment_id': treatmentId,
        if (label != null) 'label': label,
        if (createdAt != null) 'created_at': createdAt,
        'lines': lines.map((l) => l.toJson()).toList(),
      };

  @override
  bool operator ==(Object other) =>
      other is Ordonnance &&
      other.id == id &&
      other.treatmentId == treatmentId &&
      other.label == label &&
      other.createdAt == createdAt &&
      _listEq(other.lines, lines);

  @override
  int get hashCode =>
      Object.hash(id, treatmentId, label, createdAt, Object.hashAll(lines));
}

/// A global treatment record that may span multiple consultations (#121).
///
/// Ordonnances written across visits are linked back here via
/// [Ordonnance.treatmentId]. Stored at the [MedicalRecord] level so the full
/// history is visible regardless of which consultation produced each ordonnance.
class Treatment {
  const Treatment({
    required this.id,
    required this.diagnosis,
    required this.startedAt,
    this.doctorRef,
    this.endedAt,
    this.status = 'active',
    this.createdAt,
  });

  factory Treatment.fromJson(Map<String, Object?> json) {
    return Treatment(
      id: (json['id'] ?? '') as String,
      diagnosis: (json['diagnosis'] ?? '') as String,
      startedAt: (json['started_at'] ?? json['startedAt'] ?? '') as String,
      doctorRef: (json['doctor_ref'] ?? json['doctorRef']) as String?,
      endedAt: (json['ended_at'] ?? json['endedAt']) as String?,
      status: (json['status'] ?? 'active') as String,
      createdAt: (json['created_at'] ?? json['createdAt']) as String?,
    );
  }

  final String id;
  final String diagnosis;

  /// ISO-8601 date the treatment was initiated.
  final String startedAt;

  /// Display name of the practitioner who initiated this treatment.
  final String? doctorRef;
  final String? endedAt;

  /// `active` | `completed` | `discontinued`
  final String status;

  /// ISO-8601 UTC timestamp when the doctor initiated this treatment.
  /// Absent on pre-#139 records — fall back to [startedAt] for sorting.
  final String? createdAt;

  Treatment copyWith({String? status, String? endedAt}) {
    return Treatment(
      id: id,
      diagnosis: diagnosis,
      startedAt: startedAt,
      doctorRef: doctorRef,
      endedAt: endedAt ?? this.endedAt,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'diagnosis': diagnosis,
        'started_at': startedAt,
        if (doctorRef != null) 'doctor_ref': doctorRef,
        if (endedAt != null) 'ended_at': endedAt,
        'status': status,
        if (createdAt != null) 'created_at': createdAt,
      };

  @override
  bool operator ==(Object other) =>
      other is Treatment &&
      other.id == id &&
      other.diagnosis == diagnosis &&
      other.startedAt == startedAt &&
      other.doctorRef == doctorRef &&
      other.endedAt == endedAt &&
      other.status == status &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(
      id, diagnosis, startedAt, doctorRef, endedAt, status, createdAt);
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
    this.ordonnances = const <Ordonnance>[],
    this.imageUrls = const [],
    this.media = const [],
    this.createdAt,
  });

  factory Consultation.fromJson(Map<String, Object?> json) {
    final rawUrls = json['image_urls'] as List<Object?>?;
    final urls = rawUrls?.map((e) => e as String).toList() ?? const <String>[];
    final rawMedia = json['media'] as List<Object?>?;
    final media = rawMedia
            ?.map((e) => MediaDescriptor.fromJson(e as Map<String, Object?>))
            .toList() ??
        const <MediaDescriptor>[];

    final rawOrdonnances = json['ordonnances'] as List<Object?>?;
    // Migration: early #121 records stored a 'treatment' inline object.
    final rawTreatment = json['treatment'] as Map<String, Object?>?;
    List<Ordonnance> ordonnances;
    if (rawOrdonnances != null) {
      ordonnances = rawOrdonnances
          .map((e) => Ordonnance.fromJson(e as Map<String, Object?>))
          .toList();
    } else if (rawTreatment != null) {
      final rawLines = rawTreatment['prescriptions'] as List<Object?>?;
      final lines = rawLines
              ?.map((e) => OrdonnanceLine.fromJson(e as Map<String, Object?>))
              .toList() ??
          const <OrdonnanceLine>[];
      ordonnances = [
        Ordonnance(id: 'migrated-${json['id']}', lines: lines),
      ];
    } else {
      ordonnances = const [];
    }

    return Consultation(
      id: json['id'] as String,
      date: json['date'] as String,
      practitionerRef: json['practitioner_ref'] as String,
      summary: json['summary'] as String,
      prescription: json['prescription'] as String?,
      ordonnances: ordonnances,
      imageUrls: urls,
      media: media,
      createdAt: (json['created_at'] ?? json['createdAt']) as String?,
    );
  }

  /// Opaque UUID for this consultation entry.
  final String id;

  /// ISO-8601 date string (`yyyy-MM-dd`). Used for truncation order.
  final String date;

  /// Opaque practitioner reference UUID.
  final String practitionerRef;
  final String summary;

  /// Legacy free-text prescription — pre-#121 records only. Display as
  /// fallback when [ordonnances] is empty.
  final String? prescription;

  /// Ordonnances written at this consultation (#121). Each may be linked to a
  /// global [Treatment] in [MedicalRecord.treatments].
  final List<Ordonnance> ordonnances;

  /// Legacy ephemeral CDN URLs — deprecated, superseded by [media] (#23). Retained
  /// for back-compat with records written before the descriptor existed.
  final List<String> imageUrls;

  /// Heavy-media descriptors (#23): off-record pointers to encrypted images. No
  /// binary data, no baked-in URL — only an anonymous UUID + per-media content key.
  final List<MediaDescriptor> media;

  /// ISO-8601 UTC timestamp when the doctor created this consultation entry.
  /// Absent on pre-#139 records — fall back to [date] for sorting.
  final String? createdAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'date': date,
        'practitioner_ref': practitionerRef,
        'summary': summary,
        if (createdAt != null) 'created_at': createdAt,
        if (ordonnances.isNotEmpty)
          'ordonnances': ordonnances.map((o) => o.toJson()).toList()
        else if (prescription != null)
          'prescription': prescription,
        'image_urls': imageUrls,
        if (media.isNotEmpty) 'media': media.map((e) => e.toJson()).toList(),
      };

  Consultation copyWithMedia(MediaDescriptor descriptor) => Consultation(
        id: id,
        date: date,
        practitionerRef: practitionerRef,
        summary: summary,
        prescription: prescription,
        ordonnances: ordonnances,
        imageUrls: imageUrls,
        media: [...media, descriptor],
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) =>
      other is Consultation &&
      other.id == id &&
      other.date == date &&
      other.practitionerRef == practitionerRef &&
      other.summary == summary &&
      other.prescription == prescription &&
      other.createdAt == createdAt &&
      _listEq(other.ordonnances, ordonnances) &&
      _listEq(other.imageUrls, imageUrls) &&
      _listEq(other.media, media);

  @override
  int get hashCode => Object.hash(
        id,
        date,
        practitionerRef,
        summary,
        prescription,
        createdAt,
        Object.hashAll(ordonnances),
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

/// Administrative document type for [PatientDocument] (#116).
enum DocumentType {
  cmuCard,
  insuranceCard,
  other;

  String get label => switch (this) {
        DocumentType.cmuCard => 'Carte CMU',
        DocumentType.insuranceCard => "Carte d'assurance",
        DocumentType.other => 'Autre document',
      };

  String get _jsonValue => switch (this) {
        DocumentType.cmuCard => 'cmu_card',
        DocumentType.insuranceCard => 'insurance_card',
        DocumentType.other => 'other',
      };

  static DocumentType _fromJson(String s) => switch (s) {
        'cmu_card' => DocumentType.cmuCard,
        'insurance_card' => DocumentType.insuranceCard,
        _ => DocumentType.other,
      };
}

/// A patient-owned administrative document (CMU card, insurance card, etc.).
///
/// The heavy media bytes are encrypted and stored on-device (file://) until the
/// patient shares via QR, at which point they are flushed to the backend and the
/// descriptor carries a server UUID. Additive schema field: records written before
/// #116 round-trip unchanged (absent `documents` defaults to []).
class PatientDocument {
  const PatientDocument({
    required this.id,
    required this.type,
    required this.label,
    required this.media,
    required this.addedAt,
  });

  factory PatientDocument.fromJson(Map<String, Object?> json) {
    return PatientDocument(
      id: json['id'] as String? ?? '',
      type: DocumentType._fromJson(json['type'] as String? ?? 'other'),
      label: json['label'] as String? ?? '',
      media: MediaDescriptor.fromJson(json['media'] as Map<String, Object?>),
      addedAt: json['added_at'] as String? ?? '',
    );
  }

  final String id;
  final DocumentType type;
  final String label;
  final MediaDescriptor media;
  final String addedAt;

  Map<String, Object?> toJson() => {
        'id': id,
        'type': type._jsonValue,
        'label': label,
        'media': media.toJson(),
        'added_at': addedAt,
      };

  PatientDocument copyWithMedia(MediaDescriptor d) => PatientDocument(
        id: id,
        type: type,
        label: label,
        media: d,
        addedAt: addedAt,
      );

  @override
  bool operator ==(Object other) =>
      other is PatientDocument &&
      other.id == id &&
      other.type == type &&
      other.label == label &&
      other.media == media &&
      other.addedAt == addedAt;

  @override
  int get hashCode => Object.hash(id, type, label, media, addedAt);
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
    this.treatments = const [],
    this.consultations = const [],
    this.immunizations = const [],
    this.documents = const [],
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
    final rawTreatments = json['treatments'] as List<Object?>? ?? const [];
    final rawConsults = json['consultations'] as List<Object?>? ?? const [];
    final rawImm = json['immunizations'] as List<Object?>? ?? const [];
    final rawDocs = json['documents'] as List<Object?>? ?? const [];

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
      treatments: [
        for (final e in rawTreatments)
          Treatment.fromJson(e as Map<String, Object?>),
      ],
      consultations: [
        for (final e in rawConsults)
          Consultation.fromJson(e as Map<String, Object?>),
      ],
      immunizations: [
        for (final e in rawImm)
          Immunization.fromJson(e as Map<String, Object?>),
      ],
      documents: [
        for (final e in rawDocs)
          PatientDocument.fromJson(e as Map<String, Object?>),
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

  /// Global treatment records (#121). An ordonnance in any [Consultation]
  /// may reference a treatment here via [Ordonnance.treatmentId].
  final List<Treatment> treatments;

  /// Sorted oldest-first; [RecordSizeGuard] truncates from index 0.
  final List<Consultation> consultations;
  final List<Immunization> immunizations;

  /// Patient-owned administrative documents (#116): CMU card, insurance card, etc.
  /// Additive field — absent in records written before #116, defaults to [].
  final List<PatientDocument> documents;

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
        if (treatments.isNotEmpty)
          'treatments': treatments.map((e) => e.toJson()).toList(),
        'consultations': consultations.map((e) => e.toJson()).toList(),
        'immunizations': immunizations.map((e) => e.toJson()).toList(),
        if (documents.isNotEmpty)
          'documents': documents.map((e) => e.toJson()).toList(),
        'created_at': createdAt,
        'updated_at': updatedAt,
      };

  /// UTF-8 encoded JSON bytes — the plaintext payload for encryption.
  List<int> toUtf8Bytes() => utf8.encode(jsonEncode(toJson()));

  /// Returns a copy with updated fields and [updatedAt].
  MedicalRecord copyWith({
    List<Consultation>? consultations,
    List<Treatment>? treatments,
    String? updatedAt,
    Demographics? demographics,
    List<Allergy>? allergies,
    List<ChronicCondition>? chronicConditions,
    List<Medication>? medications,
    List<Immunization>? immunizations,
    List<PatientDocument>? documents,
  }) {
    return MedicalRecord(
      patientId: patientId,
      demographics: demographics ?? this.demographics,
      allergies: allergies ?? this.allergies,
      chronicConditions: chronicConditions ?? this.chronicConditions,
      medications: medications ?? this.medications,
      treatments: treatments ?? this.treatments,
      consultations: consultations ?? this.consultations,
      immunizations: immunizations ?? this.immunizations,
      documents: documents ?? this.documents,
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
      _listEq(other.treatments, treatments) &&
      _listEq(other.consultations, consultations) &&
      _listEq(other.immunizations, immunizations) &&
      _listEq(other.documents, documents) &&
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
        Object.hashAll(treatments),
        Object.hashAll(consultations),
        Object.hashAll(immunizations),
        Object.hashAll(documents),
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
