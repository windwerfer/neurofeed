import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:muse_ml/src/audio/modulated_voice.dart';
import 'package:muse_ml/src/audio/soloud_engine.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:path_provider/path_provider.dart';

const Set<String> musicSupportedExtensions = {
  '.mp3',
  '.wav',
  '.ogg',
  '.opus',
  '.flac',
};

enum MusicPlaybackMode { background, feedback }

enum MusicModulation { none, filterCutoff, volumeSlew }

class MusicTrack {
  const MusicTrack({required this.name, required this.path});

  final String name;
  final String path;
}

class MusicController {
  MusicController(
    this._settings, {
    required this.mode,
    required this.modulation,
  });

  final Settings _settings;
  final MusicPlaybackMode mode;
  final MusicModulation modulation;

  final ModulatedVoice _voice = ModulatedVoice(
    initialCutoff: 0,
    muffleCutoff: 10,
  );

  bool _isSaf = false;
  Directory? _cacheDir;
  final List<MusicTrack> _tracks = [];
  final List<int> _order = [];
  int _position = -1;
  bool _shuffle = false;

  StreamSubscription? _endSub;
  int _engineEpoch = -1;

  final StreamController<String> _trackChanges = StreamController.broadcast();

  late double _minCutoff;
  late double _maxCutoff;

  bool get hasTracks => _tracks.isNotEmpty;

  bool get isPlaying => _voice.playing && hasTracks;

  bool get muffleActive => _voice.muffleActive;

  int get trackCount => _tracks.length;

  int get position => _position;

  String? get currentTrackName => _position >= 0 && _position < _order.length
      ? _tracks[_order[_position]].name
      : null;

  double get currentCutoffHz => _voice.currentCutoff;

  double get minCutoff => _minCutoff;

  double get maxCutoff => _maxCutoff;

  void refreshSettings() {
    _minCutoff = _settings.musicMinCutoffHz.clamp(50.0, 8000.0);
    _maxCutoff = _settings.musicMaxCutoffHz.clamp(200.0, 16000.0);
    if (_maxCutoff <= _minCutoff) {
      _maxCutoff = _minCutoff + 50;
    }
    _voice.slewSeconds = _settings.musicSlewSeconds.clamp(0.1, 30.0);
    _voice.muffleCutoff = _minCutoff;
    _shuffle = _settings.musicShuffle;
  }

  Future<bool> load() async {
    refreshSettings();
    if (_voice.playing) {
      return hasTracks;
    }
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
      final List<File> files;
      try {
        files =
            dir
                .listSync()
                .whereType<File>()
                .where(
                  (f) =>
                      musicSupportedExtensions.contains(_extensionOf(f.path)),
                )
                .toList()
              ..sort(
                (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
              );
      } catch (e) {
        debugPrint('[music] list failed: $e');
        return false;
      }
      _tracks.addAll(
        files.map((f) => MusicTrack(name: _nameOf(f.path), path: f.path)),
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

  Future<String?> _materialize(
    SafSessionStorage safe,
    String name,
    int index,
  ) async {
    try {
      final destName = 'music_playlist_$index.${_extensionOf(name)}';
      final path = await safe.copySafFileToCache(name, destName);
      return path;
    } catch (e) {
      debugPrint('[music] could not materialize $name: $e');
      return null;
    }
  }

  Future<void> start() async {
    if (_voice.playing) {
      return;
    }
    if (!hasTracks) {
      await load();
    }
    if (!hasTracks) {
      return;
    }
    await SoLoudEngine.ensureInit();
    _engineEpoch = SoLoudEngine.epoch;
    _position = 0;
    await _playCurrent();
  }

  Future<void> pause() async {
    _voice.pause();
  }

  Future<void> resume() async {
    _voice.resume();
  }

  Future<void> stop() async {
    await _endSub?.cancel();
    _endSub = null;
    _voice.stop();
    await _voice.disposeSource();
    _position = -1;
  }

  Future<void> next() async {
    if (!_voice.playing || _tracks.isEmpty) {
      return;
    }
    _position = (_position + 1) % _tracks.length;
    await _playCurrent();
  }

  Future<void> previous() async {
    if (!_voice.playing || _tracks.isEmpty) {
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
    _position = moveCurrentToFront(_order, _position);
  }

  void setTargetCutoff(double hz) {
    if (modulation != MusicModulation.filterCutoff) {
      return;
    }
    _voice.setTargetCutoff(hz);
  }

  void setMuffle(bool on) {
    if (modulation == MusicModulation.none) {
      return;
    }
    _voice.setMuffle(on);
  }

  void setVolume(double v) {
    _voice.setVolume(v);
  }

  Future<void> _playCurrent() async {
    if (_position < 0 || _position >= _tracks.length) {
      return;
    }
    await _endSub?.cancel();
    _endSub = null;
    _voice.stop();
    await _voice.disposeSource();
    if (_engineEpoch != SoLoudEngine.epoch) {
      _engineEpoch = SoLoudEngine.epoch;
    }
    final track = _tracks[_order[_position]];
    try {
      final src = await SoLoud.instance.loadFile(
        track.path,
        mode: LoadMode.disk,
        autoDispose: false,
      );
      final volume = _voice.voiceVolume;
      final activateFilter = modulation == MusicModulation.filterCutoff;
      _voice.play(src, volume: volume, activateFilter: activateFilter);
      _wireCompressor(src, _voice.handle!);
      _endSub = src.soundEvents.listen((event) {
        if (event.event == SoundEventType.handleIsNoMoreValid &&
            event.handle == _voice.handle &&
            _voice.playing) {
          unawaited(next());
        }
      });
      debugPrint(
        '[music] playing "${track.name}" (${_position + 1}/${_tracks.length})'
        '${_shuffle ? ' shuffled' : ''}'
        '${mode == MusicPlaybackMode.background ? ' (background)' : ''}',
      );
      _trackChanges.add(track.name);
    } catch (e) {
      debugPrint('[music] failed to play "${track.name}": $e');
    }
  }

  void _wireCompressor(AudioSource src, SoundHandle h) {
    try {
      src.filters.compressorFilter.activate();
      src.filters.compressorFilter.threshold(soundHandle: h).value = -12;
      src.filters.compressorFilter.ratio(soundHandle: h).value = 2.5;
      src.filters.compressorFilter.makeupGain(soundHandle: h).value = 4;
      src.filters.compressorFilter.wet(soundHandle: h).value = 1.0;
    } catch (e) {
      debugPrint('[music] compressor wiring failed: $e');
    }
  }

  Future<void> dispose() async {
    await _endSub?.cancel();
    _endSub = null;
    _voice.stop();
    await _voice.disposeSource();
    await _trackChanges.close();
  }
}

/// After shuffling [order], move the track at [position] to index 0.
/// Returns 0 when a current track existed, otherwise [position].
@visibleForTesting
int moveCurrentToFront(List<int> order, int position) {
  if (position >= 0 && position < order.length) {
    final current = order.removeAt(position);
    order.insert(0, current);
    return 0;
  }
  return position;
}
