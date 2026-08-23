import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/session_cache.dart';
import 'package:muse_ml/src/feedback/session_container.dart';
import 'package:muse_ml/src/feedback/session_metadata.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/feedback/session_metadata.dart';
import 'package:muse_ml/src/feedback/session_v5_models.dart';
import 'package:muse_ml/src/rust/api/session_format.dart';
import 'package:muse_ml/src/settings.dart';

class SessionStore {
  SessionStore({Future<SessionStorage>? storage, SessionCache? cache})
    : _storage = storage ?? _defaultStorage(),
      _cache = cache ?? SessionCache.noop();

  final Future<SessionStorage> _storage;
  final SessionCache _cache;

  /// Files (name + id + mtime) discovered by [list] that are missing from the
  /// cache or have changed since it was written. Backfilled in the background
  /// so the first history open stays fluid.
  List<({String name, String id, int mtimeMs})> _pendingBackfill = [];

  bool _backfillRunning = false;

  /// Number of sessions awaiting background backfill after the last [list].
  int get pendingBackfillCount => _pendingBackfill.length;

  /// The underlying storage (resolved) — used to place exports.
  Future<SessionStorage> get storage => _storage;

  static Future<SessionStorage> _defaultStorage() async {
    throw UnimplementedError(
      'SessionStore needs an explicit storage; use sessionStoreProvider',
    );
  }

  String _museName(String id) => 'session_$id.muse.feedback';

  /// Namespace for cache rows — a short hash of the storage location so two
  /// history folders never share metadata rows even when ids collide.
  static String storageKeyFor(SessionStorage storage) =>
      sha256.convert(utf8.encode(storage.location)).toString().substring(0, 16);

  /// Persist a finished session into the history folder as a single
  /// `.muse.feedback` container: leading PNG thumbnail, then metadata json,
  /// then the raw frame body.
  Future<SessionSummary> publishSession(
    String id,
    List<int> museBytes,
    SessionMetadata metadata, {
    List<int>? pngBytes,
  }) async {
    final storage = await _storage;
    await storage.ensureDir();
    final jsonBytes = const JsonEncoder().convert(metadata.toJson()).codeUnits;
    final container = SessionContainer.encode(
      pngBytes: pngBytes == null ? Uint8List(0) : Uint8List.fromList(pngBytes),
      jsonBytes: Uint8List.fromList(jsonBytes),
      bodyBytes: Uint8List.fromList(museBytes),
    );
    await storage.writeFileAtomic(_museName(id), container);
    final key = storageKeyFor(storage);
    String? thumbPath;
    if (pngBytes != null && pngBytes.isNotEmpty) {
      await _cache.writeThumbnail(id, Uint8List.fromList(pngBytes));
      thumbPath = await _cache.thumbnailPath(id);
    }
    // mtime is 0 ("unknown") on a fresh write: the next reconcile refreshes
    // it from listFilesMeta without re-reading the metadata we already have.
    await _cache.upsert(
      CachedSession(
        id: id,
        mtimeMs: 0,
        savedAtMs: DateTime.parse(metadata.savedAt).millisecondsSinceEpoch,
        metadataJson: const JsonEncoder().convert(metadata.toJson()),
        thumbnailPath: thumbPath,
      ),
      key,
    );
    debugPrint('[session] written ${_museName(id)} to ${storage.location}');
    return SessionSummary(id: id, metadata: metadata);
  }

  /// Replace the free-text notes of an existing session and rewrite the
  /// container head in place, preserving the thumbnail and the .muse body.
  /// Returns false when the session file is missing or unreadable.
  Future<bool> updateNotes(String id, String notes) async {
    final storage = await _storage;
    final name = _museName(id);
    final bytes = await storage.readFile(name);
    if (bytes == null || bytes.isEmpty) {
      debugPrint('[session] updateNotes($id): file not found ($name)');
      return false;
    }
    final full = Uint8List.fromList(bytes);
    final head = SessionContainer.parseHead(full);
    final decoded =
        jsonDecode(String.fromCharCodes(head.jsonBytes)) as Map<String, Object?>;
    decoded['notes'] = notes;
    final jsonBytes = Uint8List.fromList(
      const JsonEncoder().convert(decoded).codeUnits,
    );
    final body = SessionContainer.extractBody(full);
    if (body == null) {
      debugPrint('[session] updateNotes($id): body missing ($name)');
      return false;
    }
    final container = SessionContainer.encode(
      pngBytes: head.pngBytes,
      jsonBytes: jsonBytes,
      bodyBytes: body,
    );
    await storage.writeFileAtomic(name, container);
    final key = storageKeyFor(storage);
    await _cache.upsert(
      CachedSession(
        id: id,
        mtimeMs: 0,
        savedAtMs: _savedAtMs(decoded),
        metadataJson: const JsonEncoder().convert(decoded),
        thumbnailPath: await _cache.thumbnailPath(id),
      ),
      key,
    );
    debugPrint('[session] updateNotes($id): notes saved ($name)');
    return true;
  }

  int _savedAtMs(Map<String, Object?> decoded) {
    final raw = decoded['savedAt'];
    if (raw is String) {
      final t = DateTime.tryParse(raw);
      if (t != null) {
        return t.millisecondsSinceEpoch;
      }
    }
    return 0;
  }

  /// Read the thumbnail PNG bytes for [id], or null when missing. Cache-first:
  /// a cached thumbnail file is returned without touching the (possibly SAF)
  /// history folder; only a miss reads the container head and fills the cache.
  Future<List<int>?> readPng(String id) async {
    final cached = await _cache.readThumbnail(id);
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }
    final storage = await _storage;
    final head = await _readHead(storage, _museName(id));
    if (head == null || head.pngBytes.isEmpty) {
      return null;
    }
    await _cache.writeThumbnail(id, head.pngBytes);
    final key = storageKeyFor(storage);
    final rows = await _cache.getRows({id}, key);
    if (rows.isNotEmpty) {
      await _cache.upsert(
        rows.first.copyWith(thumbnailPath: await _cache.thumbnailPath(id)),
        key,
      );
    }
    return head.pngBytes;
  }

  /// Read the head of a session file (PNG + metadata JSON).
  Future<ContainerHead?> _readHead(SessionStorage storage, String name) async {
    final bytes = await storage.readPrefix(name, SessionContainer.headReadLimit);
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    return SessionContainer.parseHead(Uint8List.fromList(bytes));
  }

  /// Read the full session file, parse it, and return the [SessionData].
  Future<SessionData?> readMuse(String id) async {
    final storage = await _storage;
    final name = _museName(id);
    final bytes = await storage.readFile(name);
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    return sessionParseBody(bytes: Uint8List.fromList(bytes));
  }

  /// Copy every session in the current storage into [target], then delete the
  /// source copies so the folder change does not duplicate history. Returns the
  /// number of sessions moved (used for folder-change migration).
  Future<int> moveAllTo(SessionStorage target) async {
    final storage = await _storage;
    final names = await storage.listFiles();
    var moved = 0;
    for (final name in names) {
      if (!name.startsWith('session_') || !name.endsWith('.muse.feedback')) {
        continue;
      }
      final bytes = await storage.readFile(name);
      if (bytes == null) {
        continue;
      }
      await target.ensureDir();
      await target.writeFileAtomic(name, bytes);
      await storage.deleteFile(name);
      moved++;
    }
    // Ids survive a folder move verbatim, so carry the cached metadata across
    // to the new storage key. Mtimes will mismatch once and refresh on the
    // first open of the new folder.
    await _cache.moveStorageKey(storageKeyFor(storage), storageKeyFor(target));
    debugPrint('[session] moved $moved session(s)');
    return moved;
  }

  /// Fold a freshly computed [SessionOverview] (from a full-body parse of a
  /// legacy session without an embedded summary) back into the cached
  /// metadata so the next detail-view open fast-paths through the overview.
  /// Cache-only — the container file is never rewritten.
  Future<void> cacheOverview(String id, SessionOverview overview) async {
    final storage = await _storage;
    final key = storageKeyFor(storage);
    final rows = await _cache.getRows({id}, key);
    if (rows.isEmpty) {
      return;
    }
    try {
      final decoded =
          jsonDecode(rows.first.metadataJson) as Map<String, Object?>;
      decoded['summary'] = overview.toJson();
      await _cache.upsert(
        rows.first.copyWith(metadataJson: const JsonEncoder().convert(decoded)),
        key,
      );
      debugPrint('[session] cacheOverview($id): overview cached');
    } catch (e) {
      debugPrint('[session] cacheOverview($id) failed: $e');
    }
  }

  /// Lists all sessions in the history folder, using the cache for speed.
  Future<List<SessionSummary>> list() async {
    final storage = await _storage;
    debugPrint(
      '[session] list(): storage=${storage.displayName} loc=${storage.location}',
    );
    final files = await storage.listFilesMeta();
    final key = storageKeyFor(storage);
    final ids = <String>[];
    final mtimeById = <String, int>{};
    for (final f in files) {
      if (!f.name.startsWith('session_') ||
          !f.name.endsWith('.muse.feedback')) {
        continue;
      }
      final id = f.name.substring(8, f.name.length - 14);
      ids.add(id);
      mtimeById[id] = f.mtimeMs;
    }

    final rows = await _cache.getRows(ids.toSet(), key);
    final rowById = {for (final r in rows) r.id: r};

    // Deletions apply immediately: drop cache rows whose file is gone.
    final stale = <String>{
      for (final r in rows)
        if (!mtimeById.containsKey(r.id)) r.id,
    };
    if (stale.isNotEmpty) {
      await _cache.remove(stale, key);
      for (final id in stale) {
        await _cache.deleteThumbnail(id);
      }
    }

    // Changed = brand-new files, or files whose mtime no longer matches the
    // cache. New files are excluded from this pass (they appear after the
    // background backfill); mtime-mismatched rows still carry valid metadata
    // (e.g. a session saved since the last open) so they render immediately.
    final changed = <({String name, String id, int mtimeMs})>[];
    final summaries = <SessionSummary>[];
    for (final f in files) {
      if (!f.name.startsWith('session_') ||
          !f.name.endsWith('.muse.feedback')) {
        continue;
      }
      final id = f.name.substring(8, f.name.length - 14);
      final row = rowById[id];
      if (row == null) {
        changed.add((name: f.name, id: id, mtimeMs: f.mtimeMs));
        continue;
      }
      if (row.mtimeMs != f.mtimeMs) {
        changed.add((name: f.name, id: id, mtimeMs: f.mtimeMs));
      }
      summaries.add(
        SessionSummary(
          id: id,
          metadata: _metadataFromJson(row.metadataJson, id),
        ),
      );
    }

    _pendingBackfill = changed;
    summaries.sort((a, b) => b.metadata.savedAt.compareTo(a.metadata.savedAt));
    debugPrint(
      '[session] list: found ${summaries.length} cached session(s), '
      '${changed.length} to backfill',
    );
    return summaries;
  }

  /// Background-loads the session list through the metadata cache.
  /// Clears the pending set; the caller (sessionListProvider) re-reads the
  /// list once this completes so the new sessions appear.
  Future<void> backfillPending() async {
    if (_backfillRunning) {
      return;
    }
    _backfillRunning = true;
    try {
      final storage = await _storage;
      final key = storageKeyFor(await _storage);
      for (final f in _pendingBackfill) {
        final bytes = await storage.readFile(f.name);
        if (bytes == null) {
          debugPrint('[session] backfill: file missing ${f.name}');
          continue;
        }
        final head = SessionContainer.parseHead(bytes);
        if (head == null) {
          debugPrint('[session] backfill: could not parse head ${f.name}');
          continue;
        }
        final metadataJson = String.fromCharCodes(head.jsonBytes);
        final metadata = SessionMetadata.fromJson(
          jsonDecode(metadataJson) as Map<String, Object?>,
        );
        final thumbPath = await _cache.writeThumbnail(id, head.pngBytes);
        await _cache.upsert(
          CachedSession(
            id: f.id,
            mtimeMs: f.mtimeMs,
            savedAtMs: metadata.savedAt.millisecondsSinceEpoch,
            metadataJson: metadataJson,
            thumbnailPath: thumbPath,
          ),
          key,
        );
      }
    } finally {
      _backfillRunning = false;
      _pendingBackfill = [];
    }
  }

  /// Delete one session from history (the `.muse.feedback` file). Returns
  /// false when the file was already gone.
  Future<bool> delete(String id) async {
    final storage = await _storage;
    final name = _museName(id);
    final existed = await storage.fileExists(name);
    await storage.deleteFile(name);
    await _cache.remove({id}, storageKeyFor(storage));
    await _cache.deleteThumbnail(id);
    debugPrint(
      '[session] delete($id): ${existed ? 'deleted' : 'missing'} ($name)',
    );
    return existed;
  }
}