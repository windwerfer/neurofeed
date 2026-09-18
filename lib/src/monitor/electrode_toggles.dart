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

/// Horizontally scrollable electrode chips with an overflow arrow when the
/// strip is wider than the available chrome (phone / Crown-8).
class ElectrodeToggles extends StatefulWidget {
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
  State<ElectrodeToggles> createState() => _ElectrodeTogglesState();
}

class _ElectrodeTogglesState extends State<ElectrodeToggles> {
  final ScrollController _scroll = ScrollController();
  bool _overflows = false;
  bool _atEnd = true;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeOverflow());
  }

  @override
  void didUpdateWidget(covariant ElectrodeToggles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.names.length != widget.names.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeOverflow());
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final atEnd = pos.pixels >= pos.maxScrollExtent - 1;
    if (atEnd != _atEnd) {
      setState(() => _atEnd = atEnd);
    }
  }

  void _recomputeOverflow() {
    if (!mounted || !_scroll.hasClients) return;
    final pos = _scroll.position;
    final overflows = pos.maxScrollExtent > 0.5;
    final atEnd = !overflows || pos.pixels >= pos.maxScrollExtent - 1;
    if (overflows != _overflows || atEnd != _atEnd) {
      setState(() {
        _overflows = overflows;
        _atEnd = atEnd;
      });
    }
  }

  void _jumpToEnd() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Widget _chips() {
    return ToggleButtons(
      isSelected: [
        for (var i = 0; i < widget.names.length; i++)
          widget.selected.contains(i),
      ],
      onPressed: widget.onToggle,
      constraints: const BoxConstraints(minHeight: 28, minWidth: 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      borderRadius: BorderRadius.circular(4),
      children: [
        for (final n in widget.names)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(n, style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.names.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeOverflow());
        final scrollable = SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: _chips(),
        );
        if (!constraints.hasBoundedWidth) {
          return scrollable;
        }
        return Row(
          children: [
            Expanded(child: scrollable),
            if (_overflows && !_atEnd)
              IconButton(
                key: const ValueKey('electrode-overflow-arrow'),
                tooltip: 'Show remaining electrodes',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                iconSize: 18,
                color: theme.colorScheme.primary,
                onPressed: _jumpToEnd,
                icon: const Icon(Icons.chevron_right),
              ),
          ],
        );
      },
    );
  }
}
