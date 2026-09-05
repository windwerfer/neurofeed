import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';

typedef SoLoudInitFn = Future<void> Function({required bool lowLatency});
typedef SoLoudDeinitFn = Future<void> Function();

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
class SoLoudEngine {
  static SoLoudInitFn _initNative = _defaultInit;
  static SoLoudDeinitFn _deinitNative = _defaultDeinit;

  static Future<void>? _inflight;
  static bool _ready = false;
  static bool _stable = true;
  static bool _conservativeUnavailable = false;
  static int _epoch = 0;

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

  /// Opens the engine if needed. Pass [stable] to select the Android AAudio
  /// profile; omitted, the last requested (or default conservative) profile
  /// is used. After a conservative-profile failure, a later [stable]: true
  /// stays on the working low-latency device instead of retrying the HAL.
  static Future<void> ensureInit({bool? stable}) async {
    final wantStable = stable ?? _stable;
    while (true) {
      final targetStable = wantStable && !_conservativeUnavailable;
      if (_ready && _stable == targetStable) {
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
        _epoch++;
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
    throw lastError!;
  }

  static Future<void> _close() async {
    _ready = false;
    _epoch++;
    await _deinitNative();
  }

  /// Tears the engine down. Safe when it was never opened. Used at app
  /// teardown; profile switches go through [ensureInit] instead.
  static void deinit() {
    _inflight = null;
    if (!_ready) {
      return;
    }
    _ready = false;
    _epoch++;
    unawaited(_deinitNative());
  }

  @visibleForTesting
  static void resetForTest({SoLoudInitFn? init, SoLoudDeinitFn? deinit}) {
    _initNative = init ?? _defaultInit;
    _deinitNative = deinit ?? _defaultDeinit;
    _inflight = null;
    _ready = false;
    _stable = true;
    _conservativeUnavailable = false;
    _epoch = 0;
  }
}
