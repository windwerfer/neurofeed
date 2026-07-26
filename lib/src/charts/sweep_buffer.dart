import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

class _ChannelBuf {
  final Float64List samples;    // main ring buffer (history)
  Float64List display;          // sweep display ring buffer
  int writePos = 0;             // position in samples (wraps at capacity)
  int dispPos = 0;              // position in display (wraps at displayWindow)
  int count = 0;                // total samples written (capped at capacity)

  _ChannelBuf(int capacity, int displayWindow)
      : samples = Float64List(capacity),
        display = Float64List(displayWindow);

  int get displayCursor => dispPos < display.length ? dispPos : dispPos % display.length;

  double sampleAt(int logicalIndex) {
    final n = count < samples.length ? count : samples.length;
    if (n < samples.length) {
      return samples[logicalIndex];
    }
    return samples[(writePos + logicalIndex) % samples.length];
  }
}

class SweepBuffer extends ChangeNotifier {
  static const double sampleRate = 256.0;

  final int capacity;
  final Map<int, _ChannelBuf> _channels = {};
  int _displayWindow = 0;
  bool _frozen = false;

  SweepBuffer({int windowSeconds = 300})
    : capacity = (windowSeconds * 256.0).toInt();

  /// Average per-channel cursor position for the green sweep bar.
  int get cursor {
    int total = 0, count = 0;
    for (final ch in _channels.values) {
      total += ch.dispPos;
      count++;
    }
    return count > 0 ? (total ~/ count) : 0;
  }

  bool get frozen => _frozen;
  int get displayWindow => _displayWindow;
  int channelCount(int electrode) => _channels[electrode]?.count ?? 0;
  bool hasChannel(int electrode) => _channels.containsKey(electrode);

  double sampleAt(int electrode, int logicalIndex) {
    return _channels[electrode]!.sampleAt(logicalIndex);
  }

  /// Returns the display sample at a given linear position (0..displayWindow-1)
  /// for the sweep view.
  double displaySample(int electrode, int linearIndex) {
    return _channels[electrode]!.display[linearIndex];
  }

  void setDisplayWindow(int window) {
    if (window == _displayWindow) return;
    _displayWindow = window;
    for (final ch in _channels.values) {
      ch.display = Float64List(window);
      ch.dispPos = 0;
    }
  }

  void append(EegDto dto) {
    final ch = _channels.putIfAbsent(
      dto.electrode,
      () => _ChannelBuf(capacity, _displayWindow > 0 ? _displayWindow : 1),
    );
    if (_displayWindow == 0) {
      // No display window configured yet — just store in main buffer.
      for (final s in dto.samples) {
        ch.samples[ch.writePos] = s;
        ch.writePos = (ch.writePos + 1) % capacity;
        if (ch.count < capacity) ch.count++;
      }
      return;
    }
    for (final s in dto.samples) {
      ch.samples[ch.writePos] = s;
      ch.display[ch.dispPos % _displayWindow] = s;
      ch.writePos = (ch.writePos + 1) % capacity;
      ch.dispPos++;
      if (ch.count < capacity) ch.count++;
    }
    notifyListeners();
  }

  void freeze() {
    _frozen = true;
    notifyListeners();
  }

  void resume() {
    _frozen = false;
    notifyListeners();
  }

  List<int> get electrodes => _channels.keys.toList()..sort();
}
