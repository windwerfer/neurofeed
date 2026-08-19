import 'package:flutter_soloud/flutter_soloud.dart';

/// Shared single-flight initialization for the app-wide [SoLoud] engine.
///
/// Both the ambient/chime controller and the music-feedback controller use the
/// same engine; [ensureInit] runs `SoLoud.instance.init()` exactly once and
/// returns the same future for concurrent callers.
///
/// The engine initializes with the stable (conservative) audio profile — on
/// Android that is AAudio's legacy path instead of low-latency MMAP, which
/// gives the audio callback more headroom when the CPU is busy (fewer
/// dropouts, ~0.1 s more output latency). Android sessions sync to the
/// "Reduce audio stutter" setting via [reinit] at session start; the profile
/// is a no-op on other platforms.
class SoLoudEngine {
  static Future<void>? _init;

  /// Active profile: true = conservative (fewer dropouts, ~0.1 s more latency),
  /// false = low-latency (AAudio MMAP on Android; a no-op elsewhere).
  static bool _stable = true;

  /// Initializes the engine if needed. Safe to call concurrently. Uses the
  /// profile last selected via [reinit] (conservative by default).
  static Future<void> ensureInit({bool? stable}) {
    _stable = stable ?? _stable;
    return _init ??= SoLoud.instance.init(lowLatency: !_stable);
  }

  /// Switches the engine to the [stable] profile. Re-initializes the device
  /// when already running (dropping any loaded voices/sources — call while
  /// nothing is playing). No-op when the requested profile is already active;
  /// when the engine is not initialized yet, only the profile is recorded and
  /// the next [ensureInit] uses it.
  static Future<void> reinit({required bool stable}) async {
    if (stable == _stable) {
      return;
    }
    _stable = stable;
    if (_init != null) {
      deinit();
      await ensureInit();
    }
  }

  /// Tears the engine down (used at app teardown). Re-initializable afterwards.
  static void deinit() {
    if (_init != null) {
      SoLoud.instance.deinit();
      _init = null;
    }
  }
}