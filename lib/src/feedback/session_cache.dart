import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart';
import 'package:path_provider/path_provider.dart';

import 'session_metadata.dart';
import 'session_v5_models.dart';
import 'session_sqlite.dart';

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
  SessionCache._(this._sqlite, this._cacheDir);

  /// A fully non-functional cache (no database, no thumbnail dir). Used as a
  /// safe default so [SessionStore] works without a cache — e.g. in tests —
  /// and every operation degrades to reading the history files directly.
  factory SessionCache.noop() => SessionCache._(null, null);

  final SessionSqlite? _sqlite;
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
      final sqlite = await SessionSqlite.open();
      return SessionCache._(sqlite, cacheDir);
    } catch (e) {
      debugPrint('[cache] open failed — using no-op cache: $e');
      return SessionCache._(null, null);
    }
  }

  /// Cached rows for [ids].
  Future<List<CachedSession>> getRows(Set<String> ids) async {
    if (_sqlite == null || ids.isEmpty) {
      return const [];
    }
    try {
      final sqlite = _sqlite!;
      final params = ids.toList();
      final placeholders = List.filled(params.length, '?').join(',');
      final rows = sqlite.db.select(
        'SELECT id, mtime_ms, saved_at_ms, metadata_json, thumbnail_path '
        'FROM sessions '
        'WHERE id IN ($placeholders)',
        [params],
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
  Future<void> upsert(CachedSession session) async {
    if (_sqlite == null) {
      return;
    }
    try {
      final sqlite = _sqlite!;
      // We need to reconstruct a full SessionRow from the cached session
      // For simplicity, we just update the metadata_json and mtime
      sqlite.db.execute(
        'UPDATE sessions SET metadata_json = ?, mtime_ms = ? WHERE id = ?',
        [session.metadataJson, session.mtimeMs, session.id],
      );
    } catch (e) {
      debugPrint('[cache] upsert(${session.id}) failed: $e');
    }
  }

  /// Drop cached rows for [ids].
  Future<void> remove(Set<String> ids) async {
    if (_sqlite == null || ids.isEmpty) {
      return;
    }
    try {
      final sqlite = _sqlite!;
      for (final id in ids) {
        await sqlite.deleteSession(id);
      }
    } catch (e) {
      debugPrint('[cache] remove failed: $e');
    }
  }

  /// Re-namespace cached rows after a folder move.
  Future<void> moveStorageKey(String from, String to) async {
    // No storage_key column in new schema
  }

  Future<String?> _thumbnailPathFor(String id) async {
    if (_cacheDir == null) {
      return null;
    }
    return '${_cacheDir.path}${Platform.pathSeparator}thumbnails'
        '${Platform.pathSeparator}$id.webp';
  }

  /// Persist a session thumbnail WebP into the thumbnail cache.
  Future<void> writeThumbnail(String id, Uint8List bytes) async {
    if (_thumbnailMemCache.length >= _maxMemCache) {
      _thumbnailMemCache.remove(_thumbnailMemCache.keys.first);
    }
    _thumbnailMemCache[id] = bytes;
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
    _sqlite?.close();
  }
}

/// The app-global metadata cache (independent of the history folder).
final sessionCacheProvider = FutureProvider<SessionCache>(
  (ref) => SessionCache.open(),
);