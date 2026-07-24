import 'package:flutter/material.dart';
import 'package:muse_ml/src/charts/eeg_data_source.dart';

class GraphConfig {
  final String label;
  final List<int> electrodes;
  final bool avgMode;

  const GraphConfig({
    required this.label,
    required this.electrodes,
    this.avgMode = true,
  });

  GraphConfig copyWith({String? label, List<int>? electrodes, bool? avgMode}) =>
      GraphConfig(
        label: label ?? this.label,
        electrodes: electrodes ?? this.electrodes,
        avgMode: avgMode ?? this.avgMode,
      );

  Color color(int index) => channelColor(index);

  static const defaults = [
    GraphConfig(label: 'TP9+TP10', electrodes: [0, 3], avgMode: true),
    GraphConfig(label: 'AF7+AF8', electrodes: [1, 2], avgMode: true),
  ];
}
