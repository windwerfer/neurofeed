import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

class SweepBuffer extends ChangeNotifier {
  static const double sampleRate = 256.0;

  final int capacity;
  final Map<int, Float64List> _channels = {};
  int _cursor = 0;
  int _count = 0;
  bool _frozen = false;
  int _panOffset = 0;

  SweepBuffer({int windowSeconds = 6})
    : capacity = (windowSeconds * 256.0).toInt();

  int get cursor => _cursor;
  bool get frozen => _frozen;
  int get panOffset => _panOffset;
  double get windowSeconds => capacity / sampleRate;

  void append(EegDto dto) {
    if (_frozen) return;
    final buf = _channels.putIfAbsent(dto.electrode, () => Float64List(capacity));
    for (final s in dto.samples) {
      buf[_cursor] = s;
      _cursor = (_cursor + 1) % capacity;
      if (_count < capacity) _count++;
    }
    notifyListeners();
  }

  void freeze() {
    _frozen = true;
    for (final buf in _channels.values) {
      for (int i = _cursor; i < capacity; i++) {
        buf[i] = 0;
      }
    }
    notifyListeners();
  }

  void panBy(int delta) {
    if (!_frozen) return;
    _panOffset = (_panOffset + delta).clamp(0, _cursor > 0 ? _cursor - 1 : 0);
    notifyListeners();
  }

  void resume() {
    _frozen = false;
    _panOffset = 0;
    notifyListeners();
  }

  Float64List? getChannel(int electrode) => _channels[electrode];
  List<int> get electrodes => _channels.keys.toList()..sort();
}
