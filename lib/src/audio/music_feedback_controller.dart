import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:muse_ml/src/audio/soloud_engine.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:path_provider/path_provider.dart';

/// Supported music file extensions (SoLoud decoders: MP3/WAV/OGG/Opus/FLAC).
const Set<String> musicSupportedExtensions = {
  '.mp3',
  '.wav',
  '.ogg',
  '.opus',
  '.flac',
};

/// One playable track in the music feedback folder.
class MusicTrack {
  const MusicTrack({required this.name, required this.path});

  /// Display name (file name without extension) shown in the player UI and
  /// persisted in session metadata.
  final String name;

  /// Filesystem path SoLoud can stream from (real path on desktop; a
  /// materialized temp-file copy of a SAF-backed track on Android).
  final String path;
}

/// Continuous music feedback channel: streams a user-picked folder through a
/// low-pass filter whose cutoff follows the live reward percentile.
///
/// Drives a single SoLoud voice plus a per-voice biquad resonant filter. The
/// notifier feeds [setTargetCutoff] at ~10 Hz from the ratio engine's
/// percentile rank; an exponential-moving-average slew in [MusicFeedbackController]
/// smooths those jumps into a clean cutoff glide (no zipper noise). Volumes and
/// filter values are clamped to SoLoud's accepted ranges.
class MusicFeedbackController {
  MusicFeedbackController(this._settings);

  final Settings _settings;

  /// How often the cutoff slew is applied to the live filter (100 ms).
  static const Duration _slewTick = Duration(milliseconds: 100);

  bool _isSaf = false;
  Directory? _cacheDir;
  final List<MusicTrack> _tracks = [];
  final List<int> _order = [];
  int _position = -1;
  bool _shuffle = false;

  AudioSource? _src;
  SoundHandle? _handle;
  StreamSubscription? _endSub;
  Timer? _slewTimer;
  bool _playing = false;
  bool _paused = false;
  double _volume = 1.0;

  late double _minCutoff;
  late double _maxCutoff;
  late double _slewSeconds;
  bool _muffle = false;
  double _targetCutoff = 0;
  double _currentCutoff = 0;

  final StreamController<String> _trackChanges = StreamController.broadcast();

  /// Emits the new track name whenever playback advances to a new track.
  Stream<String> get trackChanges => _trackChanges.stream;

  /// True when a folder is configured and contains audio files.
  bool get hasTracks => _tracks.isNotEmpty;

  bool get isPlaying => _playing && !_paused;

  int get trackCount => _tracks.length;

  int get position => _position;

  bool get shuffle => _shuffle;

  String? get currentTrackName =>
      _position >= 0 && _position < _order.length
      ? _tracks[_order[_position]].name
      : null;

  /// Currently applied cutoff in Hz (slewed), for recording the trace.
  double get currentCutoffHz => _currentCutoff;

  /// Usable cutoff bounds for the session's settings.
  double get minCutoff => _minCutoff;

  double get maxCutoff => _maxCutoff;

  /// Reloads settings from [_settings] (folder, filter params, shuffle).
  void refreshSettings() {
    _minCutoff = _settings.musicMinCutoffHz.clamp(50.0, 8000.0);
    _maxCutoff = _settings.musicMaxCutoffHz.clamp(200.0, 16000.0);
    if (_maxCutoff <= _minCutoff) {
      _maxCutoff = _minCutoff + 50;
    }
    _slewSeconds = _settings.musicSlewSeconds.clamp(0.1, 30.0);
    _shuffle = _settings.musicShuffle;
  }

  /// Loads the track list for the configured folder. Returns false when the
  /// folder is unset or contains no supported audio files.
  Future<bool> load() async {
    refreshSettings();
    final folder = _settings.musicFolder;
    _tracks.clear();
    _order.clear();
    _position = -1;
    if (folder == null || folder.isEmpty) {
      return false;
    }
    _isSaf = folder.startsWith('content://');
    if (_isSaf) {
      _cacheDir ??= await getTemporaryDirectory();
      final safe = SafSessionStorage(folder);
      final names = await safe.listFiles();
      final paths = <String>[];
      for (final name in names) {
        if (!musicSupportedExtensions.contains(_extensionOf(name))) {
          continue;
        }
        final cached = await _materialize(safe, name, paths.length);
        if (cached != null) {
          _tracks.add(MusicTrack(name: _nameOf(name), path: cached));
          paths.add(name);
        }
      }
    } else {
      final dir = Directory(folder);
      if (!await dir.exists()) {
        return false;
      }
      final entries = dir.listSync().whereType<File>();
      final files = entries
          .where((f) => musicSupportedExtensions.contains(_extensionOf(f.path)))
          .toList()
        ..sort((a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()));
      _tracks.addAll(
        files.map(
          (f) => MusicTrack(name: _nameOf(f.path), path: f.path),
        ),
      );
    }
    if (_tracks.isEmpty) {
      return false;
    }
    _order.addAll(List.generate(_tracks.length, (i) => i));
    if (_shuffle) {
      _order.shuffle();
    }
    return true;
  }

  String _extensionOf(String name) {
    final idx = name.lastIndexOf('.');
    return idx < 0 ? '' : name.substring(idx).toLowerCase();
  }

  String _nameOf(String path) {
    var name = path;
    if (path.contains('/')) {
      name = path.substring(path.lastIndexOf('/') + 1);
    }
    final dot = name.lastIndexOf('.');
    if (dot > 0) {
      name = name.substring(0, dot);
    }
    return name;
  }

  /// Copies a SAF-backed file into the cache so SoLoud can stream from a real
  /// path. Returns null on failure.
  Future<String?> _materialize(
    SafSessionStorage safe,
    String name,
    int index,
  ) async {
    try {
      final bytes = await safe.readFile(name);
      if (bytes == null) {
        return null;
      }
      final cache = _cacheDir!;
      if (!await cache.exists()) {
        await cache.create(recursive: true);
      }
      final file = File('${cache.path}/music_playlist_$index.${_extensionOf(name)}');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    } catch (e) {
      debugPrint('[music] could not materialize $name: $e');
      return null;
    }
  }

  /// Starts (or restarts) playback from the first track.
  Future<void> start() async {
    if (_playing) {
      return;
    }
    if (!hasTracks) {
      await load();
    }
    if (!hasTracks) {
      return;
    }
    await SoLoudEngine.ensureInit();
    _playing = true;
    _paused = false;
    _position = 0;
    _targetCutoff = _minCutoff;
    _currentCutoff = _minCutoff;
    await _playCurrent();
    _startSlew();
  }

  Future<void> pause() async {
    if (!_playing || _paused) {
      return;
    }
    _paused = true;
    final handle = _handle;
    if (handle != null) {
      try {
        SoLoud.instance.setPause(handle, true);
      } catch (_) {}
    }
  }

  Future<void> resume() async {
    if (!_playing || !_paused) {
      return;
    }
    final handle = _handle;
    if (handle != null) {
      try {
        SoLoud.instance.setPause(handle, false);
      } catch (_) {}
    }
    _paused = false;
  }

  Future<void> stop() async {
    _playing = false;
    _paused = false;
    _stopSlew();
    await _endSub?.cancel();
    _endSub = null;
    final handle = _handle;
    if (handle != null) {
      try {
        SoLoud.instance.stop(handle);
      } catch (_) {}
      _handle = null;
    }
    final src = _src;
    if (src != null) {
      try {
        await SoLoud.instance.disposeSource(src);
      } catch (_) {}
      _src = null;
    }
    _position = -1;
  }

  Future<void> next() async {
    if (!_playing || _tracks.isEmpty) {
      return;
    }
    _position = (_position + 1) % _tracks.length;
    await _playCurrent();
  }

  Future<void> previous() async {
    if (!_playing || _tracks.isEmpty) {
      return;
    }
    _position = (_position - 1 + _tracks.length) % _tracks.length;
    await _playCurrent();
  }

  void toggleShuffle() {
    _shuffle = !_shuffle;
    _settings.setMusicShuffle(_shuffle);
    _order.clear();
    _order.addAll(List.generate(_tracks.length, (i) => i));
    if (_shuffle) {
      _order.shuffle();
    }
    if (_position >= 0 && _position < _order.length) {
      final current = _order[_position];
      _order.removeAt(_position);
      _order.insert(0, current);
    }
  }

  /// Target cutoff for the reward; an EMA slew glides the live filter toward
  /// it. Values are clamped by the underlying biquad (10–16000 Hz) on apply.
  void setTargetCutoff(double hz) {
    _targetCutoff = hz.isFinite ? hz.clamp(10.0, 16000.0) : _minCutoff;
  }

  /// Forces the filter fully closed while a guardrail warning is active.
  void setMuffle(bool on) {
    _muffle = on;
  }

  /// Effective volume (master × feedback channel); applied to the live voice.
  void setVolume(double v) {
    _volume = v.clamp(0.0, 1.0);
    final handle = _handle;
    if (handle != null) {
      try {
        SoLoud.instance.setVolume(handle, _volume);
      } catch (_) {}
    }
  }

  Future<void> _playCurrent() async {
    if (!_playing || _position < 0 || _position >= _tracks.length) {
      return;
    }
    await _endSub?.cancel();
    _endSub = null;
    final handle = _handle;
    if (handle != null) {
      try {
        SoLoud.instance.stop(handle);
      } catch (_) {}
    }
    final old = _src;
    if (old != null) {
      try {
        await SoLoud.instance.disposeSource(old);
      } catch (_) {}
    }
    final track = _tracks[_order[_position]];
    try {
      final src = await SoLoud.instance.loadFile(
        track.path,
        mode: LoadMode.disk,
        autoDispose: false,
      );
      src.filters.biquadFilter.activate();
      final newHandle = SoLoud.instance.play(src, volume: _volume);
      src.filters.biquadFilter.type(soundHandle: newHandle).value = 0;
      src.filters.biquadFilter.wet(soundHandle: newHandle).value = 1.0;
      src.filters.biquadFilter.resonance(soundHandle: newHandle).value = 0.15;
      _src = src;
      _handle = newHandle;
      _applyCutoff();
      _endSub = src.soundEvents.listen((event) {
        if (event.event == SoundEventType.handleIsNoMoreValid &&
            event.handle == newHandle) {
          if (_playing && !_paused) {
            unawaited(next());
          }
        }
      });
      debugPrint(
        '[music] playing "${track.name}" (${_position + 1}/${_tracks.length})'
        '${_shuffle ? ' shuffled' : ''}',
      );
      _trackChanges.add(track.name);
    } catch (e) {
      debugPrint('[music] failed to play "${track.name}": $e');
    }
  }

  void _startSlew() {
    _stopSlew();
    _slewTimer = Timer.periodic(_slewTick, (_) => _applyCutoff());
  }

  void _stopSlew() {
    _slewTimer?.cancel();
    _slewTimer = null;
  }

  /// Advances the live cutoff one EMA step toward the current target (the
  /// reward cutoff, or [minCutoff] while muffled) and writes it to the voice's
  /// filter.
  void _applyCutoff() {
    if (!_playing) {
      return;
    }
    final handle = _handle;
    final src = _src;
    if (handle == null || src == null) {
      return;
    }
    final target = _muffle ? _minCutoff : _targetCutoff;
    final dt = _slewTick.inMilliseconds / 1000.0;
    final alpha = 1 - exp(-dt / _slewSeconds);
    _currentCutoff += (target - _currentCutoff) * alpha;
    if ((target - _currentCutoff).abs() < 1.0) {
      _currentCutoff = target;
    }
    final clamped = _currentCutoff.clamp(10.0, 16000.0);
    try {
      src.filters.biquadFilter
          .frequency(soundHandle: handle)
          .value = clamped.toDouble();
    } catch (e) {
      debugPrint('[music] cutoff apply failed: $e');
    }
  }

  void dispose() {
    _stopSlew();
    _trackChanges.close();
  }
}