// Production offline-upload queue: drift + SQLCipher (issue #21 — ADR 0006).
//
// Persists pending uploads in a dedicated SQLCipher database (AES-256 full-DB
// encryption). The DB key is 32 CSPRNG bytes SEALED by the hardware Keystore
// (envelope encryption, same model as the master key #11) — the clear key lives
// in RAM only long enough to run `PRAGMA key`, and is never written to disk.
// Absence of a hardware keystore fails LOUDLY ([KeystoreUnavailable]); there is
// NO software fallback (ADR 0006).
//
// Defence in depth: the stored `ciphertext` is ALREADY opaque AES-256-GCM
// (#16/#18). SQLCipher is the second curtain demanded by ADR 0006 — even an
// unlocked DB file reveals only opaque ciphertext, never plaintext or PII.
//
// HOST-ONLY NOTE: the native SQLCipher library is not available in `flutter test`
// (same constraint as path_provider / FRB). The queue LOGIC is covered host-only
// by [InMemoryUploadQueue]; this binding is validated by a device-backed e2e
// (follow-up, depends on #1 + an emulator). Do NOT add `sqlite3_flutter_libs`
// alongside `sqlcipher_flutter_libs` (duplicate class at dex merge — see pubspec).

import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

import '../secure/keystore_channel.dart';
import '../secure/sealed_blob_store.dart';
import 'offline_upload_queue.dart';

part 'sqlcipher_upload_queue.g.dart';

/// Pending uploads table. `ciphertext` is opaque (`nonce||ct||tag`); nothing in
/// clear. `ciphertextHash` is a cheap non-cryptographic digest used ONLY for the
/// idempotence uniqueness key — it is not a security primitive. The schema is
/// versioned: #21 shipped v1; #22 adds the drain bookkeeping columns
/// (`last_attempt_at`, `last_error`, `state`) at v2 (see [UploadQueueDatabase]).
@DataClassName('PendingUploadRow')
class PendingUploads extends Table {
  /// Local queue id (RFC-4122 v4) — primary key.
  TextColumn get id => text()();

  /// Anonymous record UUID (the `/blob/{uuid}` key).
  TextColumn get blobUuid => text()();

  /// Opaque AES-256-GCM ciphertext.
  BlobColumn get ciphertext => blob()();

  /// Idempotence digest of [ciphertext] (non-cryptographic).
  TextColumn get ciphertextHash => text()();

  /// Sync attempts — owned by #22; #21 always inserts 0.
  IntColumn get attempts => integer().withDefault(const Constant(0))();

  /// ISO-8601 enqueue timestamp (FIFO order).
  TextColumn get enqueuedAt => text()();

  /// (#22 / v2) ISO-8601 timestamp of the last drain attempt — drives backoff.
  TextColumn get lastAttemptAt => text().nullable()();

  /// (#22 / v2) REDACTED last-failure category (HTTP status / exception type) —
  /// NEVER bytes, keys or PII.
  TextColumn get lastError => text().nullable()();

  /// (#22 / v2) Sync lifecycle state name (`pending` / `conflict`).
  TextColumn get state => text().withDefault(const Constant('pending'))();

  @override
  Set<Column> get primaryKey => {id};

  // Idempotence: re-enqueuing the same end-of-session does not duplicate. Each
  // DISTINCT ciphertext for a UUID is kept (do-not-lose-a-version), and #22
  // resolves ordering/conflicts (spec Open Question #2).
  @override
  List<Set<Column>> get uniqueKeys => [
        {blobUuid, ciphertextHash},
      ];
}

@DriftDatabase(tables: [PendingUploads])
class UploadQueueDatabase extends _$UploadQueueDatabase {
  UploadQueueDatabase(super.e);

  @override
  int get schemaVersion => 2;

  // v1 (#21) → v2 (#22): add the drain bookkeeping columns. `state` defaults to
  // 'pending' so any row queued offline under v1 is drained normally after the
  // upgrade — no data loss across the migration. (The real SQLCipher migration
  // is exercised by a device-backed e2e; CI is host-only — see file header.)
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(pendingUploads, pendingUploads.lastAttemptAt);
            await m.addColumn(pendingUploads, pendingUploads.lastError);
            await m.addColumn(pendingUploads, pendingUploads.state);
          }
        },
      );
}

/// Drift + SQLCipher implementation of [OfflineUploadQueue].
///
/// The database connection is opened LAZILY on first use: the constructor is
/// cheap, so it can sit behind the production [SessionEndService] default without
/// touching the Keystore or disk until an offline enqueue actually happens.
class SqlCipherUploadQueue implements OfflineUploadQueue {
  /// Production wiring: a SQLCipher DB under the app documents dir, keyed by a
  /// Keystore-sealed 32-byte DB key persisted via [keyStore].
  SqlCipherUploadQueue({
    this.dbFileName = 'offline_upload_queue.db',
    KeystoreChannel keystore = const KeystoreChannel(),
    SealedBlobStore? keyStore,
    String Function()? idFactory,
    DateTime Function()? clock,
  })  : _keystore = keystore,
        _keyStore = keyStore ??
            const FileSealedBlobStore(fileName: 'upload_queue_db.key.sealed'),
        _idFactory = idFactory ?? generateUploadId,
        _clock = clock ?? (() => DateTime.now().toUtc());

  /// Test/advanced seam: inject an already-built database (e.g. an in-memory
  /// SQLCipher executor) instead of the Keystore-sealed file open path.
  SqlCipherUploadQueue.withDatabase(
    UploadQueueDatabase database, {
    String Function()? idFactory,
    DateTime Function()? clock,
  })  : _db = database,
        dbFileName = 'offline_upload_queue.db',
        _keystore = const KeystoreChannel(),
        _keyStore =
            const FileSealedBlobStore(fileName: 'upload_queue_db.key.sealed'),
        _idFactory = idFactory ?? generateUploadId,
        _clock = clock ?? (() => DateTime.now().toUtc());

  final String dbFileName;
  final KeystoreChannel _keystore;
  final SealedBlobStore _keyStore;
  final String Function() _idFactory;
  final DateTime Function() _clock;

  UploadQueueDatabase? _db;

  Future<UploadQueueDatabase> _open() async {
    return _db ??= UploadQueueDatabase(await _openExecutor());
  }

  /// Resolve the SQLCipher key (sealed by the Keystore), open the encrypted DB
  /// with `PRAGMA key`, and enable WAL for crash durability.
  Future<QueryExecutor> _openExecutor() async {
    final clearKey = await _resolveDbKey();
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, dbFileName));
    return LazyDatabase(() async {
      await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
      open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
      final keyLiteral = _hexKeyLiteral(clearKey);
      try {
        return NativeDatabase(
          file,
          setup: (sqlite.Database raw) {
            // Unlock the encrypted DB before any other statement runs.
            raw.execute("PRAGMA key = \"x'$keyLiteral'\";");
            // Crash durability: WAL survives a brutal process/power kill.
            raw.execute('PRAGMA journal_mode = WAL;');
            // Fail loudly if the key did not actually unlock a cipher DB.
            raw.execute('PRAGMA cipher_version;');
          },
        );
      } finally {
        // Scrub the clear key copy used to build the PRAGMA literal.
        clearKey.fillRange(0, clearKey.length, 0);
      }
    });
  }

  /// Get the clear SQLCipher DB key: unseal the persisted sealed blob, or — on
  /// first run — generate 32 CSPRNG bytes, seal them via the Keystore and
  /// persist only the sealed blob. The clear key is returned for one-shot use.
  Future<Uint8List> _resolveDbKey() async {
    final sealed = await _keyStore.read();
    if (sealed != null) {
      return _keystore.unseal(sealed);
    }
    final clearKey = _randomKey(32);
    try {
      final sealedBlob = await _keystore.seal(clearKey);
      await _keyStore.write(sealedBlob);
      return Uint8List.fromList(clearKey);
    } finally {
      clearKey.fillRange(0, clearKey.length, 0);
    }
  }

  @override
  Future<void> enqueue(String blobUuid, Uint8List ciphertext) async {
    // Defensive copy: the caller's blob is wiped right after this returns.
    final bytes = Uint8List.fromList(ciphertext);
    try {
      final db = await _open();
      await db.transaction(() async {
        await db.into(db.pendingUploads).insert(
              // Companion so `attempts`/`state` take their column defaults (0 /
              // 'pending'); #22 owns those after enqueue.
              PendingUploadsCompanion.insert(
                id: _idFactory(),
                blobUuid: blobUuid,
                ciphertext: bytes,
                ciphertextHash: _hash(bytes),
                enqueuedAt: _clock().toIso8601String(),
              ),
              // Idempotent on (blobUuid, ciphertextHash): a re-tap is a no-op.
              mode: InsertMode.insertOrIgnore,
            );
      });
    } on KeystoreException catch (e) {
      // The only path that can still lose data — surface it loudly to the UI.
      throw OfflineQueueUnavailable('keystore: ${e.message}');
    } catch (e) {
      throw OfflineQueueUnavailable('persist failed: $e');
    }
  }

  @override
  Future<List<PendingUpload>> pending() async {
    final db = await _open();
    final rows = await (db.select(db.pendingUploads)
          ..orderBy([(t) => OrderingTerm.asc(t.enqueuedAt)]))
        .get();
    return rows
        .map(
          (r) => PendingUpload(
            id: r.id,
            blobUuid: r.blobUuid,
            ciphertext: r.ciphertext,
            enqueuedAtIso: r.enqueuedAt,
            attempts: r.attempts,
            lastAttemptAtIso: r.lastAttemptAt,
            lastError: r.lastError,
            state: uploadStateFromName(r.state),
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> remove(String id) async {
    final db = await _open();
    await (db.delete(db.pendingUploads)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<void> markAttempt(String id, {required String redactedError}) async {
    final db = await _open();
    // Read-modify-write the attempt counter in one transaction; never touch the
    // ciphertext. `redactedError` is a category only (validated by the caller).
    await db.transaction(() async {
      final row = await (db.select(db.pendingUploads)
            ..where((t) => t.id.equals(id)))
          .getSingleOrNull();
      if (row == null) return;
      await (db.update(db.pendingUploads)..where((t) => t.id.equals(id))).write(
        PendingUploadsCompanion(
          attempts: Value(row.attempts + 1),
          lastAttemptAt: Value(_clock().toIso8601String()),
          lastError: Value(redactedError),
        ),
      );
    });
  }

  @override
  Future<void> markConflict(
    String id, {
    required String redactedReason,
  }) async {
    final db = await _open();
    await (db.update(db.pendingUploads)..where((t) => t.id.equals(id))).write(
      PendingUploadsCompanion(
        state: const Value('conflict'),
        lastError: Value(redactedReason),
      ),
    );
  }

  @override
  Future<int> count() async {
    final db = await _open();
    final c = db.pendingUploads.id.count();
    final q = db.selectOnly(db.pendingUploads)..addColumns([c]);
    final row = await q.getSingle();
    return row.read(c) ?? 0;
  }

  /// Close the underlying database (release the file handle).
  Future<void> close() async {
    await _db?.close();
    _db = null;
  }

  static Uint8List _randomKey(int n) {
    final rng = Random.secure();
    return Uint8List.fromList(List.generate(n, (_) => rng.nextInt(256)));
  }

  static String _hexKeyLiteral(Uint8List key) =>
      key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  /// Cheap, stable, non-cryptographic digest (FNV-1a, 64-bit) for idempotence.
  /// NOT a security primitive — collision-resistance is not relied upon.
  static String _hash(Uint8List bytes) {
    var hash = 0xcbf29ce484222325;
    const prime = 0x100000001b3;
    const mask = 0xFFFFFFFFFFFFFFFF;
    for (final b in bytes) {
      hash = (hash ^ b) & mask;
      hash = (hash * prime) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
