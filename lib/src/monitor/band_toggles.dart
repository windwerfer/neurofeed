import 'package:flutter/material.dart';
import 'package:muse_ml/src/charts/band_style.dart';
import 'package:muse_ml/src/monitor/electrode_toggles.dart';

Set<int> allBandIndices() => {for (var i = 0; i < bandNames.length; i++) i};

Set<int> toggleVisibleBand(Set<int> selected, int index) =>
    toggleKeepingLast(selected, index);

bool isBandVisible(int index, Set<int>? visible) =>
    visible == null || visible.contains(index);

class BandToggles extends StatelessWidget {
  const BandToggles({
    super.key,
    required this.selected,
    required this.onToggle,
  });

  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    return ToggleButtons(
      direction: Axis.vertical,
      isSelected: [
        for (var i = 0; i < bandNames.length; i++) selected.contains(i),
      ],
      onPressed: onToggle,
      constraints: const BoxConstraints(minHeight: 28, minWidth: 52),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      borderRadius: BorderRadius.circular(4),
      children: [
        for (var i = 0; i < bandNames.length; i++)
          KeyedSubtree(
            key: ValueKey('band-toggle-${bandNames[i]}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Text(
                bandNames[i],
                style: TextStyle(
                  color: selected.contains(i)
                      ? bandColors[i]
                      : bandColors[i].withValues(alpha: 0.45),
                  fontSize: 12,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
