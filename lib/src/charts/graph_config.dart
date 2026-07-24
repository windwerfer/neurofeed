

class GraphConfig {
  final List<int> allElectrodes;
  final Set<int> activeElectrodes;
  final bool avgMode;

  const GraphConfig({
    required this.allElectrodes,
    required this.activeElectrodes,
    this.avgMode = true,
  });

  GraphConfig copyWith({List<int>? allElectrodes, Set<int>? activeElectrodes, bool? avgMode}) =>
      GraphConfig(
        allElectrodes: allElectrodes ?? this.allElectrodes,
        activeElectrodes: activeElectrodes ?? this.activeElectrodes,
        avgMode: avgMode ?? this.avgMode,
      );

  static GraphConfig defaultFor(List<int> electrodes, {bool avg = true}) =>
      GraphConfig(
        allElectrodes: List.of(electrodes),
        activeElectrodes: Set.of(electrodes),
        avgMode: avg,
      );
}
