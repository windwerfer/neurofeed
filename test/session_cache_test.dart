import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/session_cache.dart';
import 'package:muse_ml/src/feedback/session_container.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
import 'package:muse_ml/src/feedback/session_summary.dart';
import 'package:muse_ml/src/rust/frb_generated.dart';

SessionMetadata _meta(String id, DateTime savedAt) => SessionMetadata(
  protocol: ProtocolType.drowsiness,
  durationMinutes: 10,
  elapsedSeconds: 600,
  sound: 'Ambient Drone',
  savedAt: savedAt,
  deviceModel: 'Classic',
  notes: 'note-$id',
);

/// A SessionStore with a real SQLite cache + a filesystem history folder.
Future<(SessionStore, SessionCache, Directory, Directory)> _buildStore() async {
  final history = await Directory.systemTemp.createTemp('muse_cache_hist');
  final cacheRoot = await Directory.systemTemp.createTemp('muse_cache_db');
  final cache = await SessionCache.open(inDirectory: cacheRoot);
  final storage = FileSystemSessionStorage(history);
  final store = SessionStore(
    storage: Future.value(storage),
    cache: cache,
  );
  return (store, cache, history, cacheRoot);
}

void main() {
  setUpAll(() async {
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(
        '${Directory.current.path}/rust/target/debug/librust_lib_muse_ml.so',
      ),
    );
  });

  late Directory history;
  late Directory cacheRoot;
  late SessionCache cache;
  late SessionStore store;
  late SessionStorage storage;

  setUp(() async {
    (store, cache, history, cacheRoot) = await _buildStore();
    storage = FileSystemSessionStorage(history);
  });

  tearDown(() async {
    cache.dispose();
    await history.delete(recursive: true);
    await cacheRoot.delete(recursive: true);
  });

  final pngBytes = Uint8List.fromList(
    List<int>.generate(64, (i) => 0x80 + i % 40),
  );

  Future<void> publish(String id, DateTime savedAt) async {
    await store.publishSession(
      id,
      <int>[],
      _meta(id, savedAt),
      pngBytes: pngBytes,
    );
  }

  test('list serves published sessions from the cache after one backfill', () async {
    final saved1 = DateTime(2026, 1, 1, 10, 0);
    final saved2 = DateTime(2026, 1, 2, 10, 0);
    final saved3 = DateTime(2026, 1, 3, 10, 0);
    await publish('1', saved1);
    await publish('2', saved2);
    await publish('3', saved3);

    // First list: rows exist (metadata fresh from publish) but mtime is the
    // "unknown" sentinel, so they are included immediately and scheduled for
    // background backfill.
    final first = await store.list();
    expect(first.map((s) => s.id).toList(), ['3', '2', '1']);
    expect(first.map((s) => s.metadata.notes).toList(), [
      'note-3',
      'note-2',
      'note-1',
    ]);
    expect(store.pendingBackfillCount, 3);

    await store.backfillPending();
    expect(store.pendingBackfillCount, 0);

    // Second list: everything served from cache, nothing to backfill.
    final second = await store.list();
    expect(store.pendingBackfillCount, 0);
    expect(second.length, 3);
    expect(second.map((s) => s.id).toList(), ['3', '2', '1']);
  });

  test('readPng is served from the cached thumbnail file', () async {
    await publish('1', DateTime(2026, 1, 1));
    await store.backfillPending();

    final cached = await cache.readThumbnail('1');
    expect(cached, isNotNull);
    expect(cached!.length, pngBytes.length);

    final png = await store.readPng('1');
    expect(png, isNotNull);
    expect(png, pngBytes);
  });

  test('delete removes the cache row and the thumbnail file', () async {
    await publish('1', DateTime(2026, 1, 1));
    await publish('2', DateTime(2026, 1, 2));
    await store.backfillPending();

    expect(await store.delete('1'), isTrue);
    expect(await store.list(), hasLength(1));
    expect(await cache.readThumbnail('1'), isNull);
    final rows = await cache.getRows({'1'}, SessionStore.storageKeyFor(storage));
    expect(rows, isEmpty);
  });

  test('externally added files are picked up as new sessions', () async {
    await publish('1', DateTime(2026, 1, 1));
    await store.list();
    await store.backfillPending();
    expect(store.pendingBackfillCount, 0);

    // A container written directly to the history folder, bypassing publish.
    final external = _meta('999', DateTime(2026, 2, 1));
    final jsonBytes = Uint8List.fromList(
      const JsonEncoder().convert(external.toJson()).codeUnits,
    );
    final container = SessionContainer.encode(
      pngBytes: pngBytes,
      jsonBytes: jsonBytes,
      bodyBytes: Uint8List(0),
    );
    await storage.writeFileAtomic('session_999.muse.feedback', container);

    // First emission is lazy: the brand-new file is not yet cached, so it is
    // excluded and scheduled for background backfill.
    final first = await store.list();
    expect(first.map((s) => s.id).toList(), ['1']);
    expect(store.pendingBackfillCount, 1);

    await store.backfillPending();
    expect(store.pendingBackfillCount, 0);
    final list = await store.list();
    expect(list.map((s) => s.id).toList(), ['999', '1']);
  });

  test('cacheOverview folds a computed summary into the cached metadata', () async {
    await publish('1', DateTime(2026, 1, 1));
    await store.backfillPending();

    final overview = SessionOverview(
      bucketCount: 10,
      bucketWidthSecs: 1,
      startSecs: 0,
      endSecs: 10,
      bands: const {
        1: BandPowerSeries(
          delta: [null],
          theta: [null],
          alpha: [0.5],
          beta: [null],
          gamma: [null],
        ),
      },
      pulse: const [60.0],
      movement: const [0.1],
      peakAlphaFreq: const [10.0],
      peakAlphaPower: const [0.5],
    );
    await store.cacheOverview('1', overview);

    final list = await store.list();
    expect(list.single.metadata.summary, isNotNull);
    expect(list.single.metadata.summary!.bands[1]!.alpha, [0.5]);
  });

  test('folder namespaces do not cross-contaminate', () async {
    final other = await Directory.systemTemp.createTemp('muse_cache_other');
    addTearDown(() => other.delete(recursive: true));
    final otherStore = SessionStore(
      storage: Future.value(FileSystemSessionStorage(other)),
      cache: cache,
    );

    await publish('1', DateTime(2026, 1, 1));
    await store.backfillPending();

    // A different history folder shares the same cache instance but must not
    // see the first folder's rows.
    final otherList = await otherStore.list();
    expect(otherList, isEmpty);
    expect(otherStore.pendingBackfillCount, 0);
  });
}
