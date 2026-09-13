import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/monitor/cache/frame_coalesced_notify.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

class _ChannelBuf {
  final Float64List samples;
  Float64List display;
  int writePos = 0;
  int dispPos = 0;
  int count = 0;

  _ChannelBuf(int capacity, int displayWindow)
    : samples = Float64List(capacity),
      display = Float64List(displayWindow);

  double sampleAt(int logicalIndex) {
    final n = count < samples.length ? count : samples.length;
    if (logicalIndex < 0 || logicalIndex >= n) return double.nan;
    if (n < samples.length) {
      return samples[logicalIndex];
    }
    return samples[(writePos + logicalIndex) % samples.length];
  }
}

class SweepBuffer extends ChangeNotifier with FrameCoalescedNotify {
  static const double sampleRate = 256.0;

  final int capacity;
  final Map<int, _ChannelBuf> _channels = {};
  int _displayWindow = 0;
  bool _frozen = false;
  int _generation = 0;

  SweepBuffer({int windowSeconds = 300})
    : capacity = (windowSeconds * sampleRate).toInt();

  /// Average per-channel cursor position for the Follow wipe bar.
  int get cursor {
    int total = 0, n = 0;
    for (final ch in _channels.values) {
      total += ch.dispPos;
      n++;
    }
    return n > 0 ? (total ~/ n) : 0;
  }

  bool get frozen => _frozen;
  int get displayWindow => _displayWindow;
  int get generation => _generation;
  int channelCount(int electrode) => _channels[electrode]?.count ?? 0;
  bool hasChannel(int electrode) => _channels.containsKey(electrode);

  int get sampleCount {
    var max = 0;
    for (final ch in _channels.values) {
      if (ch.count > max) max = ch.count;
    }
    return max;
  }

  bool get hasData => sampleCount > 0;

  double sampleAt(int electrode, int logicalIndex) {
    final ch = _channels[electrode];
    if (ch == null) return double.nan;
    return ch.sampleAt(logicalIndex);
  }

  /// Display sample at a linear position (0..displayWindow-1) for Follow.
  double displaySample(int electrode, int linearIndex) {
    final ch = _channels[electrode];
    if (ch == null) return double.nan;
    if (linearIndex < 0 || linearIndex >= ch.display.length) return double.nan;
    return ch.display[linearIndex];
  }

  /// Follow wipe-ring length in samples. `0` idles the ring (RAM-only append).
  /// Only Raw EEG uses the wipe ring.
  void setDisplayWindow(int window) {
    if (window == _displayWindow) return;
    _displayWindow = window;
    for (final ch in _channels.values) {
      ch.display = Float64List(window);
      ch.dispPos = 0;
    }
    _generation++;
    notifyListeners();
  }

  void append(EegDto dto) {
    final ch = _channels.putIfAbsent(
      dto.electrode,
      () => _ChannelBuf(capacity, _displayWindow),
    );
    if (_displayWindow == 0) {
      for (final s in dto.samples) {
        ch.samples[ch.writePos] = s;
        ch.writePos = (ch.writePos + 1) % capacity;
        if (ch.count < capacity) ch.count++;
      }
      _generation++;
      notifyListenersCoalesced();
      return;
    }
    for (final s in dto.samples) {
      ch.samples[ch.writePos] = s;
      ch.writePos = (ch.writePos + 1) % capacity;
      if (ch.count < capacity) ch.count++;
      if (_frozen) {
        if (ch.dispPos < _displayWindow) {
          ch.display[ch.dispPos] = s;
          ch.dispPos++;
        }
      } else {
        ch.display[ch.dispPos % _displayWindow] = s;
        ch.dispPos++;
      }
    }
    _generation++;
    notifyListenersCoalesced();
  }

  /// Snap the wipe to the current pass and stop wrapping. History still
  /// appends; new samples fill the display to the right until the window.
  void freeze() {
    if (_frozen) return;
    _frozen = true;
    if (_displayWindow > 0) {
      for (final ch in _channels.values) {
        ch.dispPos = ch.dispPos % _displayWindow;
      }
    }
    _generation++;
    notifyListeners();
  }

  void resume() {
    if (!_frozen) return;
    _frozen = false;
    _generation++;
    notifyListeners();
  }

  void clear() {
    _channels.clear();
    _frozen = false;
    _generation++;
    notifyListeners();
  }

  List<int> get electrodes => _channels.keys.toList()..sort();
}
