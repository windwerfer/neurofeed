import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:neurofeed/src/feedback/app_folder.dart';
import 'package:neurofeed/src/feedback/session_storage.dart';

/// One file in a folder change. [dir] is a `/`-separated path under the app
/// folder, or null for the history root. [deleteOnly] files (cache `tmp_*`)
/// are removed and not copied.
class FolderFile {
  const FolderFile({required this.name, this.dir, this.deleteOnly = false});

  final String name;
  final String? dir;
  final bool deleteOnly;

  String get relative {
    final parent = dir;
    if (parent == null || parent.isEmpty) return name;
    return '$parent/$name';
  }
}

class FolderMovePlan {
  const FolderMovePlan({
    required this.files,
    required this.sessions,
    required this.recordings,
    required this.export,
    required this.cache,
    required this.models,
  });

  final List<FolderFile> files;
  final int sessions;
  final int recordings;
  final bool export;
  final bool cache;
  final bool models;

  bool get prompts =>
      sessions > 0 || recordings > 0 || export || cache || models;

  static const empty = FolderMovePlan(
    files: <FolderFile>[],
    sessions: 0,
    recordings: 0,
    export: false,
    cache: false,
    models: false,
  );
}

class FolderMoveException implements Exception {
  FolderMoveException(this.message);
  final String message;

  @override
  String toString() => message;
}

bool _isHistoryContainer(String name) {
  if (!name.endsWith('.neurofeed')) return false;
  return name.startsWith('session_') || name.startsWith('recording_');
}

bool _skipTempName(String name) =>
    name.endsWith('.tmp') || name.endsWith('.mtmp') || name.endsWith('.nfmove');

/// Files that would move out of a filesystem app folder.
///
/// Empty `export/`, `.cache`, and `ai_models/` add nothing. Cache files
/// named `tmp_*` are [FolderFile.deleteOnly] and do not set [FolderMovePlan.cache].
Future<FolderMovePlan> planFilesystemMove({
  required Directory root,
  required bool includeCacheAndModels,
}) async {
  if (!await root.exists()) return FolderMovePlan.empty;
  final files = <FolderFile>[];
  var sessions = 0;
  var recordings = 0;
  var export = false;
  var cache = false;
  var models = false;
  await for (final entity in root.list(followLinks: false)) {
    if (entity is Link) continue;
    final name = p.basename(entity.path);
    if (entity is File) {
      if (!_isHistoryContainer(name)) continue;
      if (name.startsWith('session_')) sessions++;
      if (name.startsWith('recording_')) recordings++;
      files.add(FolderFile(name: name));
      continue;
    }
    if (entity is! Directory) continue;
    if (name == 'export') {
      final any = await _collectFiles(
        entity,
        'export',
        files,
        tmpDeleteOnly: false,
      );
      if (any) export = true;
    } else if (includeCacheAndModels && name == '.cache') {
      final any = await _collectFiles(
        entity,
        '.cache',
        files,
        tmpDeleteOnly: true,
      );
      if (any) cache = true;
    } else if (includeCacheAndModels && name == 'ai_models') {
      final any = await _collectFiles(
        entity,
        'ai_models',
        files,
        tmpDeleteOnly: false,
      );
      if (any) models = true;
    }
  }
  return FolderMovePlan(
    files: files,
    sessions: sessions,
    recordings: recordings,
    export: export,
    cache: cache,
    models: models,
  );
}

/// True when a real (copied) file was added.
Future<bool> _collectFiles(
  Directory dir,
  String dirPrefix,
  List<FolderFile> out, {
  required bool tmpDeleteOnly,
}) async {
  var real = false;
  if (!await dir.exists()) return false;
  await for (final entity in dir.list(followLinks: false)) {
    if (entity is Link) continue;
    final name = p.basename(entity.path);
    if (entity is Directory) {
      final child = await _collectFiles(
        entity,
        '$dirPrefix/$name',
        out,
        tmpDeleteOnly: tmpDeleteOnly,
      );
      real = real || child;
      continue;
    }
    if (entity is! File) continue;
    if (_skipTempName(name)) continue;
    if (tmpDeleteOnly && name.startsWith('tmp_')) {
      out.add(FolderFile(name: name, dir: dirPrefix, deleteOnly: true));
      continue;
    }
    real = true;
    out.add(FolderFile(name: name, dir: dirPrefix));
  }
  return real;
}

Future<FolderMovePlan> planStorageMove(
  SessionStorage storage, {
  required bool includeCacheAndModels,
}) async {
  if (storage is FileSystemSessionStorage) {
    return planFilesystemMove(
      root: Directory(storage.location),
      includeCacheAndModels: includeCacheAndModels,
    );
  }
  if (storage is SafSessionStorage) {
    return _planSafMove(storage);
  }
  return FolderMovePlan.empty;
}

Future<FolderMovePlan> _planSafMove(SafSessionStorage storage) async {
  final files = <FolderFile>[];
  var sessions = 0;
  var recordings = 0;
  var export = false;
  final root = await storage.listChildren();
  for (final child in root) {
    if (child.name.isEmpty || _skipTempName(child.name)) continue;
    if (child.isDir) {
      if (child.name != 'export') continue;
      final any = await _collectSaf(storage, 'export', files);
      if (any) export = true;
      continue;
    }
    if (!_isHistoryContainer(child.name)) continue;
    if (child.name.startsWith('session_')) sessions++;
    if (child.name.startsWith('recording_')) recordings++;
    files.add(FolderFile(name: child.name));
  }
  return FolderMovePlan(
    files: files,
    sessions: sessions,
    recordings: recordings,
    export: export,
    cache: false,
    models: false,
  );
}

Future<bool> _collectSaf(
  SafSessionStorage storage,
  String dir,
  List<FolderFile> out,
) async {
  var real = false;
  final children = await storage.listChildren(dir: dir);
  for (final child in children) {
    if (child.name.isEmpty || _skipTempName(child.name)) continue;
    if (child.isDir) {
      final nested = await _collectSaf(storage, '$dir/${child.name}', out);
      real = real || nested;
      continue;
    }
    real = true;
    out.add(FolderFile(name: child.name, dir: dir));
  }
  return real;
}

/// Delete cache `tmp_*` files. Used when the folder changes and cache itself
/// is not part of the copy (Android, or the user chose not to move).
Future<void> deleteTmpScratch(SessionStorage storage) async {
  final cache = await scratchDirectory(storage);
  if (!await cache.exists()) return;
  await for (final entity in cache.list(followLinks: false)) {
    if (entity is! File) continue;
    final name = p.basename(entity.path);
    if (!name.startsWith('tmp_')) continue;
    try {
      await entity.delete();
    } catch (e) {
      debugPrint('[folder] delete tmp ${entity.path} failed: $e');
    }
  }
}

/// Copy every non-deleteOnly file, check it, then delete sources.
///
/// A failure removes destination files created by this attempt and leaves
/// every source in place. A name that already exists at the destination
/// fails before anything is written. Returns how many history containers
/// were moved.
Future<int> commitFolderMove({
  required SessionStorage source,
  required SessionStorage target,
  required List<FolderFile> files,
  Future<void> Function(FolderFile file)? copyForTest,
}) async {
  if (sameAppFolder(source.location, target.location)) return 0;
  final copying = [
    for (final f in files)
      if (!f.deleteOnly) f,
  ];
  for (final file in copying) {
    if (await _destExists(target, file)) {
      throw FolderMoveException('destination already has ${file.relative}');
    }
  }
  final copied = <FolderFile>[];
  try {
    await target.ensureDir();
    for (final file in copying) {
      if (copyForTest != null) {
        await copyForTest(file);
      } else {
        await _transfer(source, target, file);
      }
      if (!await _destExists(target, file)) {
        throw FolderMoveException('missing after copy: ${file.relative}');
      }
      final srcFile = _asFile(source, file);
      final dstFile = _asFile(target, file);
      if (srcFile != null && dstFile != null) {
        final srcLen = await srcFile.length();
        final dstLen = await dstFile.length();
        if (srcLen != dstLen) {
          throw FolderMoveException('short copy: ${file.relative}');
        }
      }
      copied.add(file);
    }
  } catch (e) {
    for (final file in copied) {
      try {
        await _deleteStored(target, file);
      } catch (deleteError) {
        debugPrint('[folder] rollback ${file.relative} failed: $deleteError');
      }
    }
    if (e is FolderMoveException) rethrow;
    throw FolderMoveException(e.toString());
  }
  for (final file in copying) {
    await _deleteStored(source, file);
  }
  for (final file in files) {
    if (!file.deleteOnly) continue;
    await _deleteStored(source, file);
  }
  var moved = 0;
  for (final file in copying) {
    if (file.dir != null && file.dir!.isNotEmpty) continue;
    if (_isHistoryContainer(file.name)) moved++;
  }
  return moved;
}

Future<bool> _destExists(SessionStorage storage, FolderFile file) async {
  final fs = _asFile(storage, file);
  if (fs != null) return fs.exists();
  if (storage is SafSessionStorage) {
    final children = await storage.listChildren(dir: file.dir);
    return children.any((c) => c.name == file.name && !c.isDir);
  }
  return false;
}

File? _asFile(SessionStorage storage, FolderFile file) {
  if (storage is! FileSystemSessionStorage) return null;
  final parts = <String>[storage.location];
  final parent = file.dir;
  if (parent != null && parent.isNotEmpty) {
    parts.addAll(parent.split('/'));
  }
  parts.add(file.name);
  return File(p.joinAll(parts));
}

Future<void> _deleteStored(SessionStorage storage, FolderFile file) async {
  final fs = _asFile(storage, file);
  if (fs != null) {
    if (await fs.exists()) await fs.delete();
    return;
  }
  if (storage is SafSessionStorage) {
    await storage.deleteChild(file.name, dir: file.dir);
  }
}

Future<void> _transfer(
  SessionStorage source,
  SessionStorage target,
  FolderFile file,
) async {
  final srcFile = _asFile(source, file);
  final destFile = _asFile(target, file);
  if (srcFile != null && destFile != null) {
    await _streamCopyFile(srcFile, destFile);
    return;
  }
  if (srcFile != null && target is SafSessionStorage) {
    await target.copyFromPath(file.name, srcFile.path, dir: file.dir);
    return;
  }
  if (source is SafSessionStorage && destFile != null) {
    final temp = await source.copySafFileToCache(
      file.name,
      'nfmove_${file.name}',
      dir: file.dir,
    );
    try {
      await _streamCopyFile(File(temp), destFile);
    } finally {
      final tmp = File(temp);
      if (await tmp.exists()) await tmp.delete();
    }
    return;
  }
  if (source is SafSessionStorage && target is SafSessionStorage) {
    final temp = await source.copySafFileToCache(
      file.name,
      'nfmove_${file.name}',
      dir: file.dir,
    );
    try {
      await target.copyFromPath(file.name, temp, dir: file.dir);
    } finally {
      final tmp = File(temp);
      if (await tmp.exists()) await tmp.delete();
    }
    return;
  }
  throw FolderMoveException('cannot move ${file.relative}');
}

Future<void> _streamCopyFile(File src, File dest) async {
  await dest.parent.create(recursive: true);
  final tmp = File('${dest.path}.nfmove');
  if (await tmp.exists()) await tmp.delete();
  final sink = tmp.openWrite();
  try {
    await src.openRead().pipe(sink);
  } catch (e) {
    if (await tmp.exists()) {
      await tmp.delete();
    }
    rethrow;
  }
  if (await src.length() != await tmp.length()) {
    await tmp.delete();
    throw FolderMoveException('short copy ${src.path}');
  }
  if (await dest.exists()) {
    await tmp.delete();
    throw FolderMoveException('destination exists ${dest.path}');
  }
  await tmp.rename(dest.path);
}
