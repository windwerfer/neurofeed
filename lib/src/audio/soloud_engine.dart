import 'package:flutter_soloud/flutter_soloud.dart';

/// Shared single-flight initialization for the app-wide [SoLoud] engine.
///
/// Both the ambient/chime controller and the music-feedback controller use the
/// same engine; [ensureSoloudInit] runs `SoLoud.instance.init()` exactly once
/// and returns the same future for concurrent callers.
class SoLoudEngine {
  static Future<void>? _init;

  /// Initializes the engine if needed. Safe to call concurrently.
  static Future<void> ensureInit() => _init ??= SoLoud.instance.init();

  /// Tears the engine down (used at app teardown). Re-initializable afterwards.
  static void deinit() {
    if (_init != null) {
      SoLoud.instance.deinit();
      _init = null;
    }
  }
}