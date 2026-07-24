import 'dart:ui';
import 'package:flutter/foundation.dart';

class ChartSample {
  final double t;
  final double v;
  ChartSample(this.t, this.v);
}

class SeriesSlice {
  final String name;
  final Color color;
  final String unit;
  final List<ChartSample> samples;
  final bool visible;

  SeriesSlice({
    required this.name,
    required this.color,
    required this.unit,
    required this.samples,
    this.visible = true,
  });
}

const List<String> _kKnownChannelNames = ['TP9', 'AF7', 'AF8', 'TP10'];
const List<Color> _kDefaultColors = [
  Color(0xFF4FC3F7),
  Color(0xFFFF7043),
  Color(0xFF66BB6A),
  Color(0xFFAB47BC),
  Color(0xFFFFA726),
  Color(0xFF26C6DA),
  Color(0xFFEC407A),
  Color(0xFF8D6E63),
];

String channelName(int electrode) =>
    electrode < _kKnownChannelNames.length
        ? _kKnownChannelNames[electrode]
        : 'CH${electrode + 1}';

Color channelColor(int electrode) =>
    _kDefaultColors[electrode % _kDefaultColors.length];

abstract class EegDataSource implements Listenable {
  double get latestTimestamp;
  double get oldestTimestamp;
  bool get hasData;
  List<int> get channels;

  /// Maximum zoom-out window in seconds for this data source.
  /// Live sources cap at the ring buffer duration; disk sessions return
  /// the total recording length.
  double get maxTimeWindowSecs;

  List<SeriesSlice> slices({
    required double startT,
    required double endT,
    required Set<int> hiddenChannels,
  });

  List<ChartSample> getRange(int channel, double startT, double endT);
}
