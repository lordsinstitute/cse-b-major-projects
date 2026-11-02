import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/utils/utils.dart';

/// Result of validating + copying one picked file into the vault.
class StoredFile {
  final String fileName;
  final String localPath;
  final String contentHash;
  final int sizeBytes;

  const StoredFile({
    required this.fileName,
    required this.localPath,
    required this.contentHash,
    required this.sizeBytes,
  });
}

/// Application-controlled local storage for medical documents.
///
/// Picked files are COPIED into the app documents directory so they remain
/// available after the original source location changes. Temporary picker
/// paths are never depended upon. File contents are never logged.
class DocumentStorage {
  /// Override for tests (uses a temp dir instead of the app dir).
  final Directory? testDir;

  DocumentStorage({this.testDir});

  Future<Directory> _vaultDir() async {
    return vaultDirectory(override: testDir);
  }

  /// Shared vault location (used by backup/restore too).
  static Future<Directory> vaultDirectory({Directory? override}) async {
    if (override != null) {
      if (!await override.exists()) {
        await override.create(recursive: true);
      }
      return override;
    }
    final appDir = await getApplicationDocumentsDirectory();
    final vault = Directory(p.join(appDir.path, AppConstants.documentsDirName));
    if (!await vault.exists()) await vault.create(recursive: true);
    return vault;
  }

  /// Validates [source] and copies it into the vault.
  /// Throws [ValidationException] for type/size/unreadable problems.
  Future<StoredFile> storePickedFile(File source, String originalName) async {
    final ext = p.extension(originalName).replaceFirst('.', '').toLowerCase();
    if (!AppConstants.allowedDocumentExtensions.contains(ext)) {
      throw const ValidationException(
          'Only PDF documents can be imported.');
    }
    late final int size;
    try {
      if (!await source.exists()) {
        throw const ValidationException(
            'That file could not be read. It may have been moved or deleted.');
      }
      size = await source.length();
    } catch (e) {
      if (e is ValidationException) rethrow;
      throw ValidationException('That file could not be read.',
          originalError: e);
    }
    if (size <= 0) {
      throw const ValidationException('That file is empty and was skipped.');
    }
    if (size > AppConstants.maxDocumentSizeBytes) {
      final maxMb =
          AppConstants.maxDocumentSizeBytes ~/ (1024 * 1024);
      throw ValidationException(
          'That file is larger than the $maxMb MB limit and was skipped.');
    }

    // Content hash (FNV-1a 64-bit) for duplicate detection.
    // Only the hash is ever compared/stored — never file contents.
    final bytes = await source.readAsBytes();
    if (bytes.lengthInBytes != size || bytes.isEmpty) {
      throw const ValidationException('That file could not be read.');
    }
    final hash = _fnv1a64(bytes);

    final vault = await _vaultDir();
    final safeName = _safeFileName(originalName);
    final uniqueName = '${generateId()}_$safeName';
    final dest = File(p.join(vault.path, uniqueName));
    await dest.writeAsBytes(bytes, flush: true);

    return StoredFile(
      fileName: safeName,
      localPath: dest.path,
      contentHash: hash,
      sizeBytes: size,
    );
  }

  /// Deletes a vault file. Never throws for missing files.
  Future<void> deleteVaultFile(String localPath) async {
    if (localPath.isEmpty) return;
    try {
      final f = File(localPath);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // Best effort — metadata deletion still proceeds.
    }
  }

  /// Renames a vault file, preserving its extension. Returns the new path.
  Future<String> renameVaultFile(String localPath, String newFileName) async {
    final safe = _safeFileName(newFileName);
    final f = File(localPath);
    if (!await f.exists()) {
      throw const ValidationException(
          'The original file is missing, so it cannot be renamed.');
    }
    var ext = p.extension(f.path);
    if (ext.isEmpty) ext = '.pdf';
    var base = safe;
    if (p.extension(base).toLowerCase() != ext.toLowerCase()) {
      base = '$base$ext';
    }
    final dest = File(p.join(p.dirname(f.path), '${generateId()}_$base'));
    await f.rename(dest.path);
    return dest.path;
  }

  static String _safeFileName(String name) {
    var base = p.basename(name).trim();
    if (base.isEmpty) base = 'document.pdf';
    base = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (base.length > 120) base = base.substring(base.length - 120);
    return base;
  }

  /// FNV-1a 64-bit hash, hex-encoded. Dependency-free duplicate detection.
  static String _fnv1a64(List<int> bytes) {
    var hash = 0xcbf29ce484222325;
    for (final b in bytes) {
      hash ^= b;
      hash = (hash * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
