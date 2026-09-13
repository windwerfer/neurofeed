import 'package:flutter/material.dart';

Set<int> allElectrodeIndices(int count) => {for (var i = 0; i < count; i++) i};

Set<int> toggleKeepingLast(Set<int> selected, int index) {
  if (!selected.contains(index)) {
    return {...selected, index};
  }
  if (selected.length <= 1) return Set<int>.from(selected);
  return {...selected}..remove(index);
}

Set<int> toggleAverageElectrode(Set<int> selected, int index) =>
    toggleKeepingLast(selected, index);

class ElectrodeToggles extends StatelessWidget {
  const ElectrodeToggles({
    super.key,
    required this.names,
    required this.selected,
    required this.onToggle,
  });

  final List<String> names;
  final Set<int> selected;
  final ValueChanged<int> onToggle;

  @override
  Widget build(BuildContext context) {
    if (names.isEmpty) return const SizedBox.shrink();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ToggleButtons(
        isSelected: [
          for (var i = 0; i < names.length; i++) selected.contains(i),
        ],
        onPressed: onToggle,
        constraints: const BoxConstraints(minHeight: 28, minWidth: 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        borderRadius: BorderRadius.circular(4),
        children: [
          for (final n in names)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(n, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
