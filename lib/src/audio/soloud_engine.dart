import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

typedef SoLoudInitFn = Future<void> Function({required bool lowLatency});
typedef SoLoudDeinitFn = Future<void> Function();
typedef SoLoudLoadAssetFn =
    Future<AudioSource> Function(String path, {required bool stream});
typedef SoLoudDisposeSourceFn = Future<void> Function(AudioSource source);

typedef _AssetKey = ({int epoch, String path, bool stream});

/// Shared SoLoud backend for every audio controller.
///
/// [ensureInit] is single-flight: concurrent callers share one open. A failed
/// open is not cached — the next call retries.
///
/// On Android, `stable: true` ("Reduce audio stutter") uses AAudio's legacy
/// mixer instead of the low-latency MMAP path. Some HALs never reach STARTED
/// on that path and [SoLoud.init] throws [SoLoudBackendNotInitedException].
/// When that happens we fall back to low-latency and skip the conservative
/// profile for the rest of the process. The flag is a no-op on other platforms.
///
/// The AAudio profile only reopens when [ensureInit] is called with
/// [reopenIfProfileDiffers] (session start). Other callers keep the open
/// device. Bundled files go through [loadAsset]; user music uses [SoLoud.loadFile].
class SoLoudEngine {
  static SoLoudInitFn _initNative = _defaultInit;
  static SoLoudDeinitFn _deinitNative = _defaultDeinit;
  static SoLoudLoadAssetFn _loadAssetNative = _defaultLoadAsset;
  static SoLoudDisposeSourceFn _disposeSourceNative = _defaultDisposeSource;

  static Future<void>? _inflight;
  static bool _ready = false;
  static bool _stable = true;
  static bool _conservativeUnavailable = false;
  static int _epoch = 0;

  static final Map<_AssetKey, AudioSource> _assets = {};
  static final Map<_AssetKey, Future<AudioSource>> _assetInflight = {};

  static bool get isReady => _ready;

  /// Profile that actually opened. True = conservative (higher latency).
  static bool get stable => _stable;

  /// Bumped on every successful open and on teardown. Cached [AudioSource]s
  /// from a previous value belong to a dead native engine.
  static int get epoch => _epoch;

  static Future<void> _defaultInit({required bool lowLatency}) =>
      SoLoud.instance.init(lowLatency: lowLatency);

  static Future<void> _defaultDeinit() async {
    SoLoud.instance.deinit();
  }

  static Future<AudioSource> _defaultLoadAsset(
    String path, {
    required bool stream,
  }) => SoLoud.instance.loadAsset(
    path,
    mode: stream ? LoadMode.disk : LoadMode.memory,
    autoDispose: false,
  );

  static Future<void> _defaultDisposeSource(AudioSource source) async {
    try {
      await SoLoud.instance.disposeSource(source);
    } catch (_) {}
  }

  /// Opens the engine if needed. Pass [stable] to select the Android AAudio
  /// profile; omitted, the last requested (or default conservative) profile
  /// is used. After a conservative-profile failure, a later [stable]: true
  /// stays on the working low-latency device instead of retrying the HAL.
  ///
  /// When already open at a different profile, the device is kept unless
  /// [reopenIfProfileDiffers] is true (session start only).
  static Future<void> ensureInit({
    bool? stable,
    bool reopenIfProfileDiffers = false,
  }) async {
    final wantStable = stable ?? _stable;
    while (true) {
      final targetStable = wantStable && !_conservativeUnavailable;
      if (_ready && _stable == targetStable) {
        return;
      }
      if (_ready && !reopenIfProfileDiffers) {
        return;
      }
      final existing = _inflight;
      if (existing != null) {
        await existing;
        continue;
      }
      final opened = _open(targetStable);
      _inflight = opened;
      try {
        await opened;
        return;
      } finally {
        if (identical(_inflight, opened)) {
          _inflight = null;
        }
      }
    }
  }

  static Future<void> _open(bool wantStable) async {
    if (_ready && wantStable != _stable) {
      await _close();
    }
    if (!_ready) {
      await _initWithFallback(wantStable);
    }
  }

  static Future<void> _initWithFallback(bool wantStable) async {
    final tryStableFirst = wantStable && !_conservativeUnavailable;
    Object? lastError;
    for (final stable in [tryStableFirst, !tryStableFirst]) {
      if (stable && _conservativeUnavailable) {
        continue;
      }
      try {
        await _initNative(lowLatency: !stable);
        _stable = stable;
        _ready = true;
        await _advanceEpoch();
        if (stable != wantStable) {
          debugPrint(
            '[audio] opened with stable=$stable (requested stable=$wantStable)',
          );
        }
        return;
      } catch (e) {
        lastError = e;
        debugPrint('[audio] init stable=$stable failed: $e');
        if (stable) {
          _conservativeUnavailable = true;
        }
      }
    }
    throw lastError ?? StateError('SoLoud init failed');
  }

  static Future<void> _close() async {
    final wasReady = _ready;
    _ready = false;
    await _advanceEpoch();
    if (wasReady) {
      await _deinitNative();
    }
  }

  static Future<void> _advanceEpoch() async {
    _epoch++;
    await _disposeCachedAssets();
  }

  static Future<void> _disposeCachedAssets() async {
    final sources = List<AudioSource>.of(_assets.values);
    _assets.clear();
    _assetInflight.clear();
    for (final src in sources) {
      await _disposeSourceNative(src);
    }
  }

  /// Tears the engine down. Safe when it was never opened. Used at app
  /// teardown; profile switches go through [ensureInit] instead.
  ///
  /// Awaits an in-flight [ensureInit] (ignoring its error) before closing.
  /// Do not null [_inflight] first — that would let the open finish against
  /// a torn-down device.
  static Future<void> deinit() async {
    final existing = _inflight;
    if (existing != null) {
      try {
        await existing;
      } catch (_) {}
    }
    await _close();
  }

  /// Loads a bundled asset, sharing one native [AudioSource] per
  /// `(epoch, path, stream)` key. [stream] true uses disk; false uses memory.
  /// In-flight loads of the same key share one Future.
  static Future<AudioSource> loadAsset(String path, {required bool stream}) {
    final key = (epoch: _epoch, path: path, stream: stream);
    final cached = _assets[key];
    if (cached != null) {
      return Future.value(cached);
    }
    final existing = _assetInflight[key];
    if (existing != null) {
      return existing;
    }
    final loading = _loadAndCache(key, path, stream);
    _assetInflight[key] = loading;
    return loading;
  }

  static Future<AudioSource> _loadAndCache(
    _AssetKey key,
    String path,
    bool stream,
  ) async {
    try {
      final source = await _loadAssetNative(path, stream: stream);
      if (_epoch != key.epoch) {
        await _disposeSourceNative(source);
        if (!_ready) {
          throw StateError('SoLoud engine closed during loadAsset');
        }
        return loadAsset(path, stream: stream);
      }
      _assets[key] = source;
      return source;
    } finally {
      _assetInflight.remove(key);
    }
  }

  @visibleForTesting
  static void resetForTest({
    SoLoudInitFn? init,
    SoLoudDeinitFn? deinit,
    SoLoudLoadAssetFn? loadAsset,
    SoLoudDisposeSourceFn? disposeSource,
  }) {
    _initNative = init ?? _defaultInit;
    _deinitNative = deinit ?? _defaultDeinit;
    _loadAssetNative = loadAsset ?? _defaultLoadAsset;
    _disposeSourceNative = disposeSource ?? _defaultDisposeSource;
    _inflight = null;
    _ready = false;
    _stable = true;
    _conservativeUnavailable = false;
    _epoch = 0;
    _assets.clear();
    _assetInflight.clear();
  }
}
