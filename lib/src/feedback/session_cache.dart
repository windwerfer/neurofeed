import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// One cached metadata row for a session.
class CachedSession {
  const CachedSession({
    required this.id,
    required this.mtimeMs,
    required this.savedAtMs,
    required this.metadataJson,
    this.thumbnailPath,
  });

  final String id;

  /// Last-modified ms of the `.muse.feedback` file this row mirrors. `0`
  /// means "unknown" (a freshly written file) and forces one head re-read on
  /// the next reconcile to pin the real mtime.
  final int mtimeMs;

  final int savedAtMs;

  /// The full `SessionMetadata` JSON, so the history list and detail view can
  /// render without touching the (possibly SAF) history folder.
  final String metadataJson;

  /// Absolute path to the thumbnail cache file, or null when none is cached.
  final String? thumbnailPath;

  CachedSession copyWith({
    int? mtimeMs,
    String? metadataJson,
    String? thumbnailPath,
  }) {
    return CachedSession(
      id: id,
      mtimeMs: mtimeMs ?? this.mtimeMs,
      savedAtMs: savedAtMs,
      metadataJson: metadataJson ?? this.metadataJson,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }
}

/// App-private SQLite cache of session metadata + thumbnail files.
///
/// Lives in `<support>/cache/` (`getApplicationSupportDirectory()/cache`),
/// independent of where the history folder is, so it works identically for
/// filesystem and Android SAF history. The `.muse.feedback` file stays the
/// source of truth — the cache only accelerates reads. Every operation is
/// fault-tolerant: if the database or cache dir cannot be opened the cache
/// degrades to a no-op and history falls back to reading the files.
class SessionCache {
  SessionCache._(this._db, this._cacheDir);

  /// A fully non-functional cache (no database, no thumbnail dir). Used as a
  /// safe default so [SessionStore] works without a cache — e.g. in tests —
  /// and every operation degrades to reading the history files directly.
  factory SessionCache.noop() => SessionCache._(null, null);

  final Database? _db;
  final Directory? _cacheDir;
  final Map<String, Uint8List> _thumbnailMemCache = {};
  static const int _maxMemCache = 400;

  void _addToMemCache(String id, Uint8List bytes) {
    if (_thumbnailMemCache.length >= _maxMemCache) {
      _thumbnailMemCache.remove(_thumbnailMemCache.keys.first);
    }
    _thumbnailMemCache[id] = bytes;
  }

  /// Opens (or creates) the cache DB under `<support>/cache`. [inDirectory]
  /// overrides the support directory (used by tests); otherwise the app's
  /// support dir is used.
  static Future<SessionCache> open({Directory? inDirectory}) async {
    try {
      final support = inDirectory ?? await getApplicationSupportDirectory();
      final cacheDir = Directory(
        '${support.path}${Platform.pathSeparator}cache',
      );
      await cacheDir.create(recursive: true);
      final db = sqlite3.open(
        '${cacheDir.path}${Platform.pathSeparator}session_cache.sqlite',
      );
      _initSchema(db);
      return SessionCache._(db, cacheDir);
    } catch (e) {
      debugPrint('[cache] open failed — using no-op cache: $e');
      return SessionCache._(null, null);
    }
  }

  static void _initSchema(Database db) {
    db.execute('PRAGMA journal_mode = WAL;');
    final version =
        db.select('PRAGMA user_version').first.values.first as int;
    if (version < 1) {
      db.execute(
        'CREATE TABLE IF NOT EXISTS sessions ('
        '  id TEXT PRIMARY KEY,'
        '  storage_key TEXT NOT NULL,'
        '  mtime_ms INTEGER NOT NULL DEFAULT 0,'
        '  saved_at_ms INTEGER NOT NULL DEFAULT 0,'
        '  metadata_json TEXT NOT NULL,'
        '  thumbnail_path TEXT'
        ')',
      );
      db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sessions_storage '
        'ON sessions(storage_key)',
      );
      db.execute('PRAGMA user_version = 1;');
    }
  }

  /// Cached rows for [ids] under the given [storageKey] folder namespace.
  Future<List<CachedSession>> getRows(
    Set<String> ids,
    String storageKey,
  ) async {
    if (_db == null || ids.isEmpty) {
      return const [];
    }
    try {
      final params = ids.toList();
      final placeholders = List.filled(params.length, '?').join(',');
      final rows = _db.select(
        'SELECT id, mtime_ms, saved_at_ms, metadata_json, thumbnail_path '
        'FROM sessions '
        'WHERE storage_key = ? AND id IN ($placeholders)',
        [storageKey, ...params],
      );
      return [
        for (final r in rows)
          CachedSession(
            id: r['id'] as String,
            mtimeMs: r['mtime_ms'] as int,
            savedAtMs: r['saved_at_ms'] as int,
            metadataJson: r['metadata_json'] as String,
            thumbnailPath: r['thumbnail_path'] as String?,
          ),
      ];
    } catch (e) {
      debugPrint('[cache] getRows failed: $e');
      return const [];
    }
  }

  /// Insert or replace a cached row.
  Future<void> upsert(CachedSession session, String storageKey) async {
    if (_db == null) {
      return;
    }
    try {
      _db.execute(
        'INSERT INTO sessions '
        '(id, storage_key, mtime_ms, saved_at_ms, metadata_json, thumbnail_path) '
        'VALUES (?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(id) DO UPDATE SET '
        'storage_key = excluded.storage_key, '
        'mtime_ms = excluded.mtime_ms, '
        'saved_at_ms = excluded.saved_at_ms, '
        'metadata_json = excluded.metadata_json, '
        'thumbnail_path = excluded.thumbnail_path',
        [
          session.id,
          storageKey,
          session.mtimeMs,
          session.savedAtMs,
          session.metadataJson,
          session.thumbnailPath,
        ],
      );
    } catch (e) {
      debugPrint('[cache] upsert(${session.id}) failed: $e');
    }
  }

  /// Drop cached rows for [ids] under [storageKey].
  Future<void> remove(Set<String> ids, String storageKey) async {
    if (_db == null || ids.isEmpty) {
      return;
    }
    try {
      final params = ids.toList();
      final placeholders = List.filled(params.length, '?').join(',');
      _db.execute(
        'DELETE FROM sessions WHERE storage_key = ? AND id IN ($placeholders)',
        [storageKey, ...params],
      );
    } catch (e) {
      debugPrint('[cache] remove failed: $e');
    }
  }

  /// Re-namespace cached rows after a folder move (ids survive the move, only
  /// the storage key changes).
  Future<void> moveStorageKey(String from, String to) async {
    if (_db == null) {
      return;
    }
    try {
      _db.execute(
        'UPDATE sessions SET storage_key = ? WHERE storage_key = ?',
        [to, from],
      );
    } catch (e) {
      debugPrint('[cache] moveStorageKey failed: $e');
    }
  }

  Future<String?> _thumbnailPathFor(String id) async {
    if (_cacheDir == null) {
      return null;
    }
    return '${_cacheDir.path}${Platform.pathSeparator}thumbnails'
        '${Platform.pathSeparator}$id.png';
  }

  /// Persist a session thumbnail PNG into the thumbnail cache.
  Future<void> writeThumbnail(String id, Uint8List bytes) async {
    _addToMemCache(id, bytes);
    if (_cacheDir == null || bytes.isEmpty) {
      return;
    }
    try {
      final dir = Directory(
        "${_cacheDir.path}${Platform.pathSeparator}thumbnails",
      );
      await dir.create(recursive: true);
      await File((await _thumbnailPathFor(id))!).writeAsBytes(bytes);
    } catch (e) {
      debugPrint("[cache] writeThumbnail($id) failed: $e");
    }
  }

  /// Bytes of the cached thumbnail for [id], or null when not cached.
  Future<List<int>?> readThumbnail(String id) async {
    if (_thumbnailMemCache.containsKey(id)) {
      return _thumbnailMemCache[id];
    }
    if (_cacheDir == null) {
      return null;
    }
    try {
      final f = File((await _thumbnailPathFor(id))!);
      if (!await f.exists()) {
        return null;
      }
      final bytes = await f.readAsBytes();
      _addToMemCache(id, Uint8List.fromList(bytes));
      return bytes;
    } catch (e) {
      debugPrint("[cache] readThumbnail($id) failed: $e");
      return null;
    }
  }

  /// Absolute path to the thumbnail cache file for [id], or null when the
  /// cache dir is unavailable. The file itself may not exist yet.
  Future<String?> thumbnailPath(String id) => _thumbnailPathFor(id);

  Future<void> deleteThumbnail(String id) async {
    _thumbnailMemCache.remove(id);
    if (_cacheDir == null) {
      return;
    }
    try {
      final f = File((await _thumbnailPathFor(id))!);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (e) {
      debugPrint("[cache] deleteThumbnail($id) failed: $e");
    }
  }

  void dispose() {
    _db?.dispose();
  }
}

/// The app-global metadata cache (independent of the history folder).
final sessionCacheProvider = FutureProvider<SessionCache>(
  (ref) => SessionCache.open(),
);