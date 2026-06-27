// Persistence for the hardware-sealed master-key blob (issue #11, G4).
//
// IMPORTANT: the value stored here is NOT a clear secret — it is the master key
// already wrapped (AES-GCM) by the non-exportable hardware KEK. The clear master
// key never touches non-volatile storage. ADR 0001 reserves
// `flutter_secure_storage` for non-critical items; since the blob is already
// hardware-sealed, a private app file is sufficient and is what we use.
//
// This is an interface plus a file-backed default so the master-key flow stays
// unit-testable with an in-memory store (the file path uses path_provider, which
// is not available in host-only tests).

import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Stores exactly one sealed blob per install.
abstract class SealedBlobStore {
  /// The sealed blob, or null if none has been persisted yet.
  Future<Uint8List?> read();

  /// Persist (overwrite) the sealed blob.
  Future<void> write(Uint8List sealedBlob);

  /// Whether a sealed blob is currently persisted.
  Future<bool> exists();

  /// Remove the sealed blob (used on crypto-erase / recovery reset).
  Future<void> delete();
}

/// Default store: a single private file in the app's documents directory.
class FileSealedBlobStore implements SealedBlobStore {
  const FileSealedBlobStore({this.fileName = 'master_key.sealed'});

  final String fileName;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, fileName));
  }

  @override
  Future<Uint8List?> read() async {
    final f = await _file();
    if (!await f.exists()) return null;
    return Uint8List.fromList(await f.readAsBytes());
  }

  @override
  Future<void> write(Uint8List sealedBlob) async {
    final f = await _file();
    // Atomic-ish: write then flush. The blob is non-secret (hardware-sealed).
    await f.writeAsBytes(sealedBlob, flush: true);
  }

  @override
  Future<bool> exists() async => (await _file()).exists();

  @override
  Future<void> delete() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}

/// In-memory store for tests and host-only environments.
class InMemorySealedBlobStore implements SealedBlobStore {
  InMemorySealedBlobStore([this._blob]);

  Uint8List? _blob;

  @override
  Future<Uint8List?> read() async => _blob;

  @override
  Future<void> write(Uint8List sealedBlob) async => _blob = sealedBlob;

  @override
  Future<bool> exists() async => _blob != null;

  @override
  Future<void> delete() async => _blob = null;
}
