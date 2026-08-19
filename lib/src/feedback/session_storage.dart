import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:muse_ml/src/settings.dart';

/// Absolute default history folder on desktop (user Documents).
Future<Directory> _desktopDefault() async {
  String? docsPath;
  try {
    final docs = await getApplicationDocumentsDirectory();
    docsPath = docs.path;
  } catch (e) {
    debugPrint('[storage] getApplicationDocumentsDirectory failed: $e');
  }
  if (docsPath == null || docsPath.isEmpty) {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      docsPath = '$home${Platform.pathSeparator}Documents';
    }
  }
  if (docsPath == null || docsPath.isEmpty) {
    docsPath = Directory.systemTemp.path;
  }
  return Directory('$docsPath${Platform.pathSeparator}meditation feedback');
}

/// Per-platform default history folder (used when the user has not picked a
/// custom folder).
///
///  * Linux/Windows: `~/Documents/meditation feedback`
///  * Android/iOS : the app-private documents directory
Future<Directory> defaultSessionDir() async {
  if (Platform.isAndroid || Platform.isIOS) {
    final docs = await getApplicationDocumentsDirectory();
    return docs;
  }
  return _desktopDefault();
}

/// Scratch (live-recording) directory for a given [history] storage.
///
/// Live EEG is streamed here and must be fast and reliable, so it is never
/// backed by SAF. For a filesystem history we keep it in the same folder
/// under `.cache/` (visible, matches the default layout). For a SAF history
/// we fall back to the app's private cache directory.
Directory scratchDirectory(SessionStorage history) {
  if (history is FileSystemSessionStorage) {
    return Directory('${history.location}${Platform.pathSeparator}.cache');
  }
  return Directory('${Directory.systemTemp.path}/muse_scratch');
}

/// A file handle inside the history folder. [name] is the bare file name
/// (e.g. `session_123.muse.feedback`).
class SessionFile {
  const SessionFile(this.name);

  final String name;

  String get id {
    final dot = name.lastIndexOf('.');
    final stem = dot < 0 ? name : name.substring(0, dot);
    return stem.startsWith('session_') ? stem.substring(8) : stem;
  }
}

/// Abstraction over where finished sessions are persisted.
///
/// * [FileSystemSessionStorage] — real directory (desktop, Android default).
/// * [SafSessionStorage] — Android SAF content-URI folder (custom folder only).
abstract class SessionStorage {
  SessionStorage._();

  String get displayName;

  /// Real path for filesystem storage, or the persisted content:// tree URI
  /// for SAF storage.
  String get location;

  Future<void> ensureDir();

  /// Create/overwrite [name] with [bytes]. [dir] is an optional single
  /// subdirectory (created on demand) under the storage root — used for
  /// export outputs so they never mix with session history.
  Future<void> writeFile(String name, List<int> bytes, {String? dir});

  /// Overwrite [name] with [bytes] as crash-safely as the backend allows.
  ///
  /// Filesystem storage writes to a sibling temp file and `rename`s it over
  /// the target (atomic on POSIX, so a crash leaves either the old or the new
  /// file, never a corrupt blend). SAF has no atomic swap, so it falls back to
  /// a single truncate+write call. [dir] behaves as in [writeFile].
  Future<void> writeFileAtomic(String name, List<int> bytes, {String? dir});

  /// Bytes of [name], or null if it does not exist.
  Future<List<int>?> readFile(String name);

  /// The first [limit] bytes of [name], or null if it does not exist. Used
  /// for the PNG+metadata head of a session container without pulling the
  /// (potentially large) frame body across the SAF bridge.
  Future<List<int>?> readPrefix(String name, int limit);

  /// File names currently in the folder (does not descend into subdirs).
  Future<List<String>> listFiles();

  /// Whether [name] exists in the storage root.
  Future<bool> fileExists(String name);

  Future<void> deleteFile(String name);
}

class FileSystemSessionStorage extends SessionStorage {
  FileSystemSessionStorage(this.root) : super._();

  final Directory root;

  @override
  String get displayName => root.path;

  @override
  String get location => root.path;

  @override
  Future<void> ensureDir() async {
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
  }

  @override
  Future<void> writeFile(String name, List<int> bytes, {String? dir}) async {
    final path = _path(name, dir);
    await File(path).parent.create(recursive: true);
    await File(path).writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> writeFileAtomic(String name, List<int> bytes, {String? dir}) async {
    // Write to a sibling temp file in the same directory, fsync, then rename
    // over the target. rename() is atomic on the same filesystem, so a crash
    // anywhere in the sequence leaves either the complete old file or the
    // complete new file on disk — never a truncated blend.
    final target = File(_path(name, dir));
    final tmp = File(_path('.$name.tmp', dir));
    await target.parent.create(recursive: true);
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      // A pre-existing target can make rename fail on some platforms
      // (e.g. Windows does not always let rename overwrite). Fall back to
      // delete-then-rename; the temp copy is already fsynced so worst case we
      // lose the target but never corrupt it.
      if (await target.exists()) {
        await target.delete();
      }
      await tmp.rename(target.path);
    }
  }

  @override
  Future<List<int>?> readFile(String name) async {
    final f = File('${root.path}/$name');
    if (!await f.exists()) {
      return null;
    }
    return f.readAsBytes();
  }

  @override
  Future<List<int>?> readPrefix(String name, int limit) async {
    final f = File('${root.path}/$name');
    if (!await f.exists()) {
      return null;
    }
    return f.openRead(0, limit).fold<List<int>>([], (acc, chunk) {
      acc.addAll(chunk);
      return acc;
    });
  }

  @override
  Future<List<String>> listFiles() async {
    if (!await root.exists()) {
      return [];
    }
    return root
        .listSync()
        .whereType<File>()
        .map((f) => f.uri.pathSegments.last)
        // Hide stale tmp siblings from an interrupted writeFileAtomic.
        .where((n) => !n.endsWith('.tmp'))
        .toList();
  }

  @override
  Future<bool> fileExists(String name) async {
    return File(_path(name)).exists();
  }

  @override
  Future<void> deleteFile(String name) async {
    final f = File(_path(name));
    if (await f.exists()) {
      await f.delete();
    }
  }

  String _path(String name, [String? dir]) {
    final base = dir == null || dir.isEmpty
        ? root.path
        : '${root.path}${Platform.pathSeparator}$dir';
    return '$base${Platform.pathSeparator}$name';
  }
}

/// Android SAF history storage. The live recording never goes here — [writeFile]
/// is only called when a session is saved, so each call is a single
/// ContentResolver write (plus the small .json/.png companions).
class SafSessionStorage extends SessionStorage {
  SafSessionStorage(this.treeUri) : super._();

  final String treeUri;

  static const MethodChannel _channel = MethodChannel('muse_ml/saf');

  @override
  String get displayName => 'Android folder';

  @override
  String get location => treeUri;

  Future<dynamic> _invoke(String method, [Map<String, dynamic>? args]) async {
    final result = await _channel.invokeMethod(method, args);
    debugPrint('[saf] $method -> $result');
    return result;
  }

  /// Launch the native SAF folder picker. Returns the persisted content://
  /// tree URI, or null if the user cancelled.
  static Future<String?> pickFolder() async {
    final result = await _channel.invokeMethod<dynamic>('getDir');
    debugPrint('[saf] getDir -> $result');
    if (result is String) {
      return result;
    }
    return null;
  }

  @override
  Future<void> ensureDir() async {
    _invoke('ensureDir', {'tree': treeUri});
  }

  @override
  Future<void> writeFile(String name, List<int> bytes, {String? dir}) async {
    await _invoke('writeFile', {
      'tree': treeUri,
      'name': name,
      'bytes': bytes,
      if (dir != null && dir.isNotEmpty) 'dir': dir,
    });
  }

  @override
  Future<void> writeFileAtomic(String name, List<int> bytes, {String? dir}) async {
    // SAF cannot swap URIs atomically, so the native side does the closest
    // safe sequence: write name.mtmp, sync, delete the old target, rename the
    // temp over it. [recoverDoc] on the native side heals an interrupted swap
    // the next time the file is read.
    await _invoke('writeFileAtomic', {
      'tree': treeUri,
      'name': name,
      'bytes': bytes,
      if (dir != null && dir.isNotEmpty) 'dir': dir,
    });
  }

  @override
  Future<void> deleteFile(String name) async {
    await _invoke('deleteFile', {'tree': treeUri, 'name': name});
  }

  @override
  Future<List<int>?> readFile(String name) async {
    final bytes = await _invoke('readFile', {'tree': treeUri, 'name': name});
    if (bytes == null) {
      return null;
    }
    return (bytes as List<dynamic>).cast<int>();
  }

  @override
  Future<List<int>?> readPrefix(String name, int limit) async {
    final bytes = await _invoke('readFilePrefix', {
      'tree': treeUri,
      'name': name,
      'limit': limit,
    });
    if (bytes == null) {
      return null;
    }
    return (bytes as List<dynamic>).cast<int>();
  }

  @override
  Future<List<String>> listFiles() async {
    final files = await _invoke('listFiles', {'tree': treeUri});
    if (files == null) {
      return [];
    }
    return (files as List<dynamic>).cast<String>();
  }

  @override
  Future<bool> fileExists(String name) async {
    return await readPrefix(name, 1) != null;
  }
}

/// Builds the active history [SessionStorage] from settings.
///
///  * `content://...` value → [SafSessionStorage] (Android custom folder).
///  * any other non-empty value → [FileSystemSessionStorage] (real path).
///  * not configured → default [FileSystemSessionStorage].
Future<SessionStorage> resolveSessionStorage(Settings settings) async {
  final folder = settings.sessionFolder;
  if (folder == null || folder.isEmpty) {
    final dir = await defaultSessionDir();
    return FileSystemSessionStorage(dir);
  }
  return resolveStorageFromFolder(folder);
}

/// Synchronously-happy factory for a storage from a folder value (used both
/// for the active setting and for a prospective new folder during migration).
SessionStorage resolveStorageFromFolder(String? folder) {
  if (folder != null && folder.startsWith('content://')) {
    return SafSessionStorage(folder);
  }
  if (folder != null && folder.isNotEmpty) {
    return FileSystemSessionStorage(Directory(folder));
  }
  throw ArgumentError.notNull('folder');
}

final sessionStorageProvider = FutureProvider<SessionStorage>((ref) {
  final settings = ref.watch(settingsProvider);
  return resolveSessionStorage(settings);
});
