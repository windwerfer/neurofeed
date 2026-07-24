import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:muse_ml/src/charts/eeg_data_source.dart';

class DiskSession extends ChangeNotifier implements EegDataSource {
  final File file;
  final String _label;
  final double _firstTimestamp = 0;
  final double _lastTimestamp = 0;
  bool _loaded = false;

  DiskSession(this.file, [this._label = '']);

  String get label => _label.isNotEmpty ? _label : file.path.split('/').last;

  Future<void> load() async {
    // TODO: binary format parser + sparse index builder
    // For now just marks as loaded. Full implementation in Phase 3.
    _loaded = true;
    notifyListeners();
  }

  @override
  double get maxTimeWindowSecs => 86400; // 24h for disk replay

  @override
  bool get hasData => _loaded;

  @override
  double get latestTimestamp => _lastTimestamp;

  @override
  double get oldestTimestamp => _firstTimestamp;

  @override
  List<int> get channels => const [0, 1, 2, 3];

  @override
  List<ChartSample> getRange(int channel, double startT, double endT) =>
      const [];

  @override
  List<SeriesSlice> slices({
    required double startT,
    required double endT,
    required Set<int> hiddenChannels,
  }) =>
      const [];
}
