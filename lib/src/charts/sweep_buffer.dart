import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

class SweepBuffer extends ChangeNotifier {
  static const double sampleRate = 256.0;

  final int capacity;
  final Map<int, Float64List> _channels = {};
  final Map<int, Float64List> _display = {};
  int _displayWindow = 0;
  int _cursor = 0;
  int _count = 0;
  bool _frozen = false;

  SweepBuffer({int windowSeconds = 300})
    : capacity = (windowSeconds * 256.0).toInt();

  int get cursor => _cursor;
  int get writtenCount => _count;
  bool get frozen => _frozen;
  int get displayWindow => _displayWindow;

  Float64List? getDisplay(int electrode) => _display[electrode];

  void setDisplayWindow(int window) {
    if (window == _displayWindow) return;
    _displayWindow = window;
    _display.clear();
  }

  void append(EegDto dto) {
    if (_frozen) return;
    final buf = _channels.putIfAbsent(dto.electrode, () => Float64List(capacity));
    final disp = _displayWindow > 0
        ? _display.putIfAbsent(dto.electrode, () => Float64List(_displayWindow))
        : null;
    for (final s in dto.samples) {
      buf[_cursor] = s;
      if (disp != null) disp[_cursor % _displayWindow] = s;
      _cursor = (_cursor + 1) % capacity;
      if (_count < capacity) _count++;
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

  Float64List? getChannel(int electrode) => _channels[electrode];
  List<int> get electrodes => _channels.keys.toList()..sort();
}
