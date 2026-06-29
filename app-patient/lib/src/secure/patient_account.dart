// Patient identity model and encrypted local storage (issue #13).
//
// The patient account stores CMU number, phone, UUID, and consent record.
// ALL fields are encrypted with the master key before persisting — the clear
// values never touch the filesystem or any network interface (ZK boundary).
//
// Wire format: AES-256-GCM blob (nonce || ciphertext || tag) produced by
// CryptoCore.encryptRecord, stored by FileSealedBlobStore with a distinct
// filename from the master-key sealed blob.

import 'dart:convert';
import 'dart:typed_data';

import '../legal/consent_model.dart';
import '../rust/crypto_core_bindings.dart';
import 'sealed_blob_store.dart';

/// Immutable record of the patient's local identity.
///
/// The [anonymousUuid] is the identifier shared with the backend; the backend
/// never sees [cmuNumber] or [phone].  Those two fields are Ivorian PII and
/// stay inside the AES-256-GCM envelope on-device.
class PatientAccount {
  const PatientAccount({
    required this.anonymousUuid,
    required this.cmuNumber,
    required this.phone,
    required this.consent,
    required this.createdAt,
  });

  factory PatientAccount.fromJson(Map<String, Object?> json) => PatientAccount(
        anonymousUuid: json['uuid'] as String,
        cmuNumber: json['cmu'] as String,
        phone: json['phone'] as String,
        consent: ConsentRecord.fromJson(
          json['consent'] as Map<String, Object?>,
        ),
        createdAt: json['created_at'] as String,
      );

  /// Anonymous UUID sent to the backend — never linked to CMU or phone.
  final String anonymousUuid;

  /// Ivorian CMU number (PII — never transmitted in clear).
  final String cmuNumber;

  /// Patient phone number (PII — never transmitted in clear).
  final String phone;

  /// Legal consent record (#7).
  final ConsentRecord consent;

  /// ISO-8601 UTC creation timestamp.
  final String createdAt;

  Map<String, Object?> toJson() => {
        'uuid': anonymousUuid,
        'cmu': cmuNumber,
        'phone': phone,
        'consent': consent.toJson(),
        'created_at': createdAt,
      };

  @override
  bool operator ==(Object other) =>
      other is PatientAccount &&
      other.anonymousUuid == anonymousUuid &&
      other.cmuNumber == cmuNumber &&
      other.phone == phone &&
      other.consent == consent &&
      other.createdAt == createdAt;

  @override
  int get hashCode =>
      Object.hash(anonymousUuid, cmuNumber, phone, consent, createdAt);
}

/// Thrown when [PatientAccountStore.read] finds no persisted account.
class AccountNotFound implements Exception {
  const AccountNotFound();

  @override
  String toString() => 'no patient account found on this device';
}

/// Encrypts [PatientAccount] to/from a [SealedBlobStore] using the master key.
///
/// The caller supplies a [MasterKeyHandle] for each call — this keeps the
/// clear key lifetime as short as possible and lets the caller decide when to
/// wipe it.  This class never stores or caches the handle.
class PatientAccountStore {
  const PatientAccountStore({
    required CryptoCore crypto,
    required SealedBlobStore blobStore,
  })  : _crypto = crypto,
        _blobStore = blobStore;

  final CryptoCore _crypto;
  final SealedBlobStore _blobStore;

  /// Encrypt [account] with [handle] and persist the blob.
  ///
  /// Overwrites any previous account blob.  The handle is NOT wiped here —
  /// the caller owns its lifecycle.
  Future<void> write(PatientAccount account, MasterKeyHandle handle) async {
    final plaintext = Uint8List.fromList(
      utf8.encode(jsonEncode(account.toJson())),
    );
    final blob = await _crypto.encryptRecord(handle, plaintext);
    await _blobStore.write(blob);
  }

  /// Decrypt and return the persisted account, or throw [AccountNotFound].
  ///
  /// Throws [DecryptError] on a corrupted blob or wrong key.
  Future<PatientAccount> read(MasterKeyHandle handle) async {
    final blob = await _blobStore.read();
    if (blob == null) throw const AccountNotFound();
    final plaintext = await _crypto.decryptRecord(handle, blob);
    final json = jsonDecode(utf8.decode(plaintext)) as Map<String, Object?>;
    return PatientAccount.fromJson(json);
  }

  /// Whether an encrypted account blob exists.
  Future<bool> exists() => _blobStore.exists();
}
