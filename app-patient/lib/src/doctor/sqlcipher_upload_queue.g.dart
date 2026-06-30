// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sqlcipher_upload_queue.dart';

// ignore_for_file: type=lint
class $PendingUploadsTable extends PendingUploads
    with TableInfo<$PendingUploadsTable, PendingUploadRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PendingUploadsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _blobUuidMeta =
      const VerificationMeta('blobUuid');
  @override
  late final GeneratedColumn<String> blobUuid = GeneratedColumn<String>(
      'blob_uuid', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _ciphertextMeta =
      const VerificationMeta('ciphertext');
  @override
  late final GeneratedColumn<Uint8List> ciphertext = GeneratedColumn<Uint8List>(
      'ciphertext', aliasedName, false,
      type: DriftSqlType.blob, requiredDuringInsert: true);
  static const VerificationMeta _ciphertextHashMeta =
      const VerificationMeta('ciphertextHash');
  @override
  late final GeneratedColumn<String> ciphertextHash = GeneratedColumn<String>(
      'ciphertext_hash', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _attemptsMeta =
      const VerificationMeta('attempts');
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
      'attempts', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _enqueuedAtMeta =
      const VerificationMeta('enqueuedAt');
  @override
  late final GeneratedColumn<String> enqueuedAt = GeneratedColumn<String>(
      'enqueued_at', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastAttemptAtMeta =
      const VerificationMeta('lastAttemptAt');
  @override
  late final GeneratedColumn<String> lastAttemptAt = GeneratedColumn<String>(
      'last_attempt_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastErrorMeta =
      const VerificationMeta('lastError');
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
      'last_error', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
      'state', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('pending'));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        blobUuid,
        ciphertext,
        ciphertextHash,
        attempts,
        enqueuedAt,
        lastAttemptAt,
        lastError,
        state
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'pending_uploads';
  @override
  VerificationContext validateIntegrity(Insertable<PendingUploadRow> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('blob_uuid')) {
      context.handle(_blobUuidMeta,
          blobUuid.isAcceptableOrUnknown(data['blob_uuid']!, _blobUuidMeta));
    } else if (isInserting) {
      context.missing(_blobUuidMeta);
    }
    if (data.containsKey('ciphertext')) {
      context.handle(
          _ciphertextMeta,
          ciphertext.isAcceptableOrUnknown(
              data['ciphertext']!, _ciphertextMeta));
    } else if (isInserting) {
      context.missing(_ciphertextMeta);
    }
    if (data.containsKey('ciphertext_hash')) {
      context.handle(
          _ciphertextHashMeta,
          ciphertextHash.isAcceptableOrUnknown(
              data['ciphertext_hash']!, _ciphertextHashMeta));
    } else if (isInserting) {
      context.missing(_ciphertextHashMeta);
    }
    if (data.containsKey('attempts')) {
      context.handle(_attemptsMeta,
          attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta));
    }
    if (data.containsKey('enqueued_at')) {
      context.handle(
          _enqueuedAtMeta,
          enqueuedAt.isAcceptableOrUnknown(
              data['enqueued_at']!, _enqueuedAtMeta));
    } else if (isInserting) {
      context.missing(_enqueuedAtMeta);
    }
    if (data.containsKey('last_attempt_at')) {
      context.handle(
          _lastAttemptAtMeta,
          lastAttemptAt.isAcceptableOrUnknown(
              data['last_attempt_at']!, _lastAttemptAtMeta));
    }
    if (data.containsKey('last_error')) {
      context.handle(_lastErrorMeta,
          lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta));
    }
    if (data.containsKey('state')) {
      context.handle(
          _stateMeta, state.isAcceptableOrUnknown(data['state']!, _stateMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
        {blobUuid, ciphertextHash},
      ];
  @override
  PendingUploadRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PendingUploadRow(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      blobUuid: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}blob_uuid'])!,
      ciphertext: attachedDatabase.typeMapping
          .read(DriftSqlType.blob, data['${effectivePrefix}ciphertext'])!,
      ciphertextHash: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}ciphertext_hash'])!,
      attempts: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}attempts'])!,
      enqueuedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}enqueued_at'])!,
      lastAttemptAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_attempt_at']),
      lastError: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_error']),
      state: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}state'])!,
    );
  }

  @override
  $PendingUploadsTable createAlias(String alias) {
    return $PendingUploadsTable(attachedDatabase, alias);
  }
}

class PendingUploadRow extends DataClass
    implements Insertable<PendingUploadRow> {
  /// Local queue id (RFC-4122 v4) — primary key.
  final String id;

  /// Anonymous record UUID (the `/blob/{uuid}` key).
  final String blobUuid;

  /// Opaque AES-256-GCM ciphertext.
  final Uint8List ciphertext;

  /// Idempotence digest of [ciphertext] (non-cryptographic).
  final String ciphertextHash;

  /// Sync attempts — owned by #22; #21 always inserts 0.
  final int attempts;

  /// ISO-8601 enqueue timestamp (FIFO order).
  final String enqueuedAt;

  /// (#22 / v2) ISO-8601 timestamp of the last drain attempt — drives backoff.
  final String? lastAttemptAt;

  /// (#22 / v2) REDACTED last-failure category (HTTP status / exception type) —
  /// NEVER bytes, keys or PII.
  final String? lastError;

  /// (#22 / v2) Sync lifecycle state name (`pending` / `conflict`).
  final String state;
  const PendingUploadRow(
      {required this.id,
      required this.blobUuid,
      required this.ciphertext,
      required this.ciphertextHash,
      required this.attempts,
      required this.enqueuedAt,
      this.lastAttemptAt,
      this.lastError,
      required this.state});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['blob_uuid'] = Variable<String>(blobUuid);
    map['ciphertext'] = Variable<Uint8List>(ciphertext);
    map['ciphertext_hash'] = Variable<String>(ciphertextHash);
    map['attempts'] = Variable<int>(attempts);
    map['enqueued_at'] = Variable<String>(enqueuedAt);
    if (!nullToAbsent || lastAttemptAt != null) {
      map['last_attempt_at'] = Variable<String>(lastAttemptAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['state'] = Variable<String>(state);
    return map;
  }

  PendingUploadsCompanion toCompanion(bool nullToAbsent) {
    return PendingUploadsCompanion(
      id: Value(id),
      blobUuid: Value(blobUuid),
      ciphertext: Value(ciphertext),
      ciphertextHash: Value(ciphertextHash),
      attempts: Value(attempts),
      enqueuedAt: Value(enqueuedAt),
      lastAttemptAt: lastAttemptAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastAttemptAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      state: Value(state),
    );
  }

  factory PendingUploadRow.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PendingUploadRow(
      id: serializer.fromJson<String>(json['id']),
      blobUuid: serializer.fromJson<String>(json['blobUuid']),
      ciphertext: serializer.fromJson<Uint8List>(json['ciphertext']),
      ciphertextHash: serializer.fromJson<String>(json['ciphertextHash']),
      attempts: serializer.fromJson<int>(json['attempts']),
      enqueuedAt: serializer.fromJson<String>(json['enqueuedAt']),
      lastAttemptAt: serializer.fromJson<String?>(json['lastAttemptAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      state: serializer.fromJson<String>(json['state']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'blobUuid': serializer.toJson<String>(blobUuid),
      'ciphertext': serializer.toJson<Uint8List>(ciphertext),
      'ciphertextHash': serializer.toJson<String>(ciphertextHash),
      'attempts': serializer.toJson<int>(attempts),
      'enqueuedAt': serializer.toJson<String>(enqueuedAt),
      'lastAttemptAt': serializer.toJson<String?>(lastAttemptAt),
      'lastError': serializer.toJson<String?>(lastError),
      'state': serializer.toJson<String>(state),
    };
  }

  PendingUploadRow copyWith(
          {String? id,
          String? blobUuid,
          Uint8List? ciphertext,
          String? ciphertextHash,
          int? attempts,
          String? enqueuedAt,
          Value<String?> lastAttemptAt = const Value.absent(),
          Value<String?> lastError = const Value.absent(),
          String? state}) =>
      PendingUploadRow(
        id: id ?? this.id,
        blobUuid: blobUuid ?? this.blobUuid,
        ciphertext: ciphertext ?? this.ciphertext,
        ciphertextHash: ciphertextHash ?? this.ciphertextHash,
        attempts: attempts ?? this.attempts,
        enqueuedAt: enqueuedAt ?? this.enqueuedAt,
        lastAttemptAt:
            lastAttemptAt.present ? lastAttemptAt.value : this.lastAttemptAt,
        lastError: lastError.present ? lastError.value : this.lastError,
        state: state ?? this.state,
      );
  PendingUploadRow copyWithCompanion(PendingUploadsCompanion data) {
    return PendingUploadRow(
      id: data.id.present ? data.id.value : this.id,
      blobUuid: data.blobUuid.present ? data.blobUuid.value : this.blobUuid,
      ciphertext:
          data.ciphertext.present ? data.ciphertext.value : this.ciphertext,
      ciphertextHash: data.ciphertextHash.present
          ? data.ciphertextHash.value
          : this.ciphertextHash,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      enqueuedAt:
          data.enqueuedAt.present ? data.enqueuedAt.value : this.enqueuedAt,
      lastAttemptAt: data.lastAttemptAt.present
          ? data.lastAttemptAt.value
          : this.lastAttemptAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      state: data.state.present ? data.state.value : this.state,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PendingUploadRow(')
          ..write('id: $id, ')
          ..write('blobUuid: $blobUuid, ')
          ..write('ciphertext: $ciphertext, ')
          ..write('ciphertextHash: $ciphertextHash, ')
          ..write('attempts: $attempts, ')
          ..write('enqueuedAt: $enqueuedAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('state: $state')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      blobUuid,
      $driftBlobEquality.hash(ciphertext),
      ciphertextHash,
      attempts,
      enqueuedAt,
      lastAttemptAt,
      lastError,
      state);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PendingUploadRow &&
          other.id == this.id &&
          other.blobUuid == this.blobUuid &&
          $driftBlobEquality.equals(other.ciphertext, this.ciphertext) &&
          other.ciphertextHash == this.ciphertextHash &&
          other.attempts == this.attempts &&
          other.enqueuedAt == this.enqueuedAt &&
          other.lastAttemptAt == this.lastAttemptAt &&
          other.lastError == this.lastError &&
          other.state == this.state);
}

class PendingUploadsCompanion extends UpdateCompanion<PendingUploadRow> {
  final Value<String> id;
  final Value<String> blobUuid;
  final Value<Uint8List> ciphertext;
  final Value<String> ciphertextHash;
  final Value<int> attempts;
  final Value<String> enqueuedAt;
  final Value<String?> lastAttemptAt;
  final Value<String?> lastError;
  final Value<String> state;
  final Value<int> rowid;
  const PendingUploadsCompanion({
    this.id = const Value.absent(),
    this.blobUuid = const Value.absent(),
    this.ciphertext = const Value.absent(),
    this.ciphertextHash = const Value.absent(),
    this.attempts = const Value.absent(),
    this.enqueuedAt = const Value.absent(),
    this.lastAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.state = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PendingUploadsCompanion.insert({
    required String id,
    required String blobUuid,
    required Uint8List ciphertext,
    required String ciphertextHash,
    this.attempts = const Value.absent(),
    required String enqueuedAt,
    this.lastAttemptAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.state = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        blobUuid = Value(blobUuid),
        ciphertext = Value(ciphertext),
        ciphertextHash = Value(ciphertextHash),
        enqueuedAt = Value(enqueuedAt);
  static Insertable<PendingUploadRow> custom({
    Expression<String>? id,
    Expression<String>? blobUuid,
    Expression<Uint8List>? ciphertext,
    Expression<String>? ciphertextHash,
    Expression<int>? attempts,
    Expression<String>? enqueuedAt,
    Expression<String>? lastAttemptAt,
    Expression<String>? lastError,
    Expression<String>? state,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (blobUuid != null) 'blob_uuid': blobUuid,
      if (ciphertext != null) 'ciphertext': ciphertext,
      if (ciphertextHash != null) 'ciphertext_hash': ciphertextHash,
      if (attempts != null) 'attempts': attempts,
      if (enqueuedAt != null) 'enqueued_at': enqueuedAt,
      if (lastAttemptAt != null) 'last_attempt_at': lastAttemptAt,
      if (lastError != null) 'last_error': lastError,
      if (state != null) 'state': state,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PendingUploadsCompanion copyWith(
      {Value<String>? id,
      Value<String>? blobUuid,
      Value<Uint8List>? ciphertext,
      Value<String>? ciphertextHash,
      Value<int>? attempts,
      Value<String>? enqueuedAt,
      Value<String?>? lastAttemptAt,
      Value<String?>? lastError,
      Value<String>? state,
      Value<int>? rowid}) {
    return PendingUploadsCompanion(
      id: id ?? this.id,
      blobUuid: blobUuid ?? this.blobUuid,
      ciphertext: ciphertext ?? this.ciphertext,
      ciphertextHash: ciphertextHash ?? this.ciphertextHash,
      attempts: attempts ?? this.attempts,
      enqueuedAt: enqueuedAt ?? this.enqueuedAt,
      lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      lastError: lastError ?? this.lastError,
      state: state ?? this.state,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (blobUuid.present) {
      map['blob_uuid'] = Variable<String>(blobUuid.value);
    }
    if (ciphertext.present) {
      map['ciphertext'] = Variable<Uint8List>(ciphertext.value);
    }
    if (ciphertextHash.present) {
      map['ciphertext_hash'] = Variable<String>(ciphertextHash.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (enqueuedAt.present) {
      map['enqueued_at'] = Variable<String>(enqueuedAt.value);
    }
    if (lastAttemptAt.present) {
      map['last_attempt_at'] = Variable<String>(lastAttemptAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PendingUploadsCompanion(')
          ..write('id: $id, ')
          ..write('blobUuid: $blobUuid, ')
          ..write('ciphertext: $ciphertext, ')
          ..write('ciphertextHash: $ciphertextHash, ')
          ..write('attempts: $attempts, ')
          ..write('enqueuedAt: $enqueuedAt, ')
          ..write('lastAttemptAt: $lastAttemptAt, ')
          ..write('lastError: $lastError, ')
          ..write('state: $state, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$UploadQueueDatabase extends GeneratedDatabase {
  _$UploadQueueDatabase(QueryExecutor e) : super(e);
  $UploadQueueDatabaseManager get managers => $UploadQueueDatabaseManager(this);
  late final $PendingUploadsTable pendingUploads = $PendingUploadsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [pendingUploads];
}

typedef $$PendingUploadsTableCreateCompanionBuilder = PendingUploadsCompanion
    Function({
  required String id,
  required String blobUuid,
  required Uint8List ciphertext,
  required String ciphertextHash,
  Value<int> attempts,
  required String enqueuedAt,
  Value<String?> lastAttemptAt,
  Value<String?> lastError,
  Value<String> state,
  Value<int> rowid,
});
typedef $$PendingUploadsTableUpdateCompanionBuilder = PendingUploadsCompanion
    Function({
  Value<String> id,
  Value<String> blobUuid,
  Value<Uint8List> ciphertext,
  Value<String> ciphertextHash,
  Value<int> attempts,
  Value<String> enqueuedAt,
  Value<String?> lastAttemptAt,
  Value<String?> lastError,
  Value<String> state,
  Value<int> rowid,
});

class $$PendingUploadsTableFilterComposer
    extends Composer<_$UploadQueueDatabase, $PendingUploadsTable> {
  $$PendingUploadsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get blobUuid => $composableBuilder(
      column: $table.blobUuid, builder: (column) => ColumnFilters(column));

  ColumnFilters<Uint8List> get ciphertext => $composableBuilder(
      column: $table.ciphertext, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get ciphertextHash => $composableBuilder(
      column: $table.ciphertextHash,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get enqueuedAt => $composableBuilder(
      column: $table.enqueuedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnFilters(column));
}

class $$PendingUploadsTableOrderingComposer
    extends Composer<_$UploadQueueDatabase, $PendingUploadsTable> {
  $$PendingUploadsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get blobUuid => $composableBuilder(
      column: $table.blobUuid, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<Uint8List> get ciphertext => $composableBuilder(
      column: $table.ciphertext, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get ciphertextHash => $composableBuilder(
      column: $table.ciphertextHash,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get attempts => $composableBuilder(
      column: $table.attempts, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get enqueuedAt => $composableBuilder(
      column: $table.enqueuedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastError => $composableBuilder(
      column: $table.lastError, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get state => $composableBuilder(
      column: $table.state, builder: (column) => ColumnOrderings(column));
}

class $$PendingUploadsTableAnnotationComposer
    extends Composer<_$UploadQueueDatabase, $PendingUploadsTable> {
  $$PendingUploadsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get blobUuid =>
      $composableBuilder(column: $table.blobUuid, builder: (column) => column);

  GeneratedColumn<Uint8List> get ciphertext => $composableBuilder(
      column: $table.ciphertext, builder: (column) => column);

  GeneratedColumn<String> get ciphertextHash => $composableBuilder(
      column: $table.ciphertextHash, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<String> get enqueuedAt => $composableBuilder(
      column: $table.enqueuedAt, builder: (column) => column);

  GeneratedColumn<String> get lastAttemptAt => $composableBuilder(
      column: $table.lastAttemptAt, builder: (column) => column);

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);
}

class $$PendingUploadsTableTableManager extends RootTableManager<
    _$UploadQueueDatabase,
    $PendingUploadsTable,
    PendingUploadRow,
    $$PendingUploadsTableFilterComposer,
    $$PendingUploadsTableOrderingComposer,
    $$PendingUploadsTableAnnotationComposer,
    $$PendingUploadsTableCreateCompanionBuilder,
    $$PendingUploadsTableUpdateCompanionBuilder,
    (
      PendingUploadRow,
      BaseReferences<_$UploadQueueDatabase, $PendingUploadsTable,
          PendingUploadRow>
    ),
    PendingUploadRow,
    PrefetchHooks Function()> {
  $$PendingUploadsTableTableManager(
      _$UploadQueueDatabase db, $PendingUploadsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PendingUploadsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PendingUploadsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PendingUploadsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> blobUuid = const Value.absent(),
            Value<Uint8List> ciphertext = const Value.absent(),
            Value<String> ciphertextHash = const Value.absent(),
            Value<int> attempts = const Value.absent(),
            Value<String> enqueuedAt = const Value.absent(),
            Value<String?> lastAttemptAt = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
            Value<String> state = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PendingUploadsCompanion(
            id: id,
            blobUuid: blobUuid,
            ciphertext: ciphertext,
            ciphertextHash: ciphertextHash,
            attempts: attempts,
            enqueuedAt: enqueuedAt,
            lastAttemptAt: lastAttemptAt,
            lastError: lastError,
            state: state,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String blobUuid,
            required Uint8List ciphertext,
            required String ciphertextHash,
            Value<int> attempts = const Value.absent(),
            required String enqueuedAt,
            Value<String?> lastAttemptAt = const Value.absent(),
            Value<String?> lastError = const Value.absent(),
            Value<String> state = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              PendingUploadsCompanion.insert(
            id: id,
            blobUuid: blobUuid,
            ciphertext: ciphertext,
            ciphertextHash: ciphertextHash,
            attempts: attempts,
            enqueuedAt: enqueuedAt,
            lastAttemptAt: lastAttemptAt,
            lastError: lastError,
            state: state,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$PendingUploadsTableProcessedTableManager = ProcessedTableManager<
    _$UploadQueueDatabase,
    $PendingUploadsTable,
    PendingUploadRow,
    $$PendingUploadsTableFilterComposer,
    $$PendingUploadsTableOrderingComposer,
    $$PendingUploadsTableAnnotationComposer,
    $$PendingUploadsTableCreateCompanionBuilder,
    $$PendingUploadsTableUpdateCompanionBuilder,
    (
      PendingUploadRow,
      BaseReferences<_$UploadQueueDatabase, $PendingUploadsTable,
          PendingUploadRow>
    ),
    PendingUploadRow,
    PrefetchHooks Function()>;

class $UploadQueueDatabaseManager {
  final _$UploadQueueDatabase _db;
  $UploadQueueDatabaseManager(this._db);
  $$PendingUploadsTableTableManager get pendingUploads =>
      $$PendingUploadsTableTableManager(_db, _db.pendingUploads);
}
