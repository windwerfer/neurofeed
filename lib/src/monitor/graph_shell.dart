import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

/// Shared chrome for live monitor graphs. Record is a slot, hidden until PR 5a.
class GraphShell extends ConsumerWidget {
  const GraphShell({
    super.key,
    required this.viewport,
    required this.windowOptions,
    required this.onFollow,
    required this.onInspect,
    required this.onWindowChanged,
    required this.body,
    this.title = '',
    this.toolbarExtras,
    this.showRecord = false,
  });

  final String title;
  final ViewportController viewport;
  final List<double> windowOptions;
  final VoidCallback onFollow;
  final VoidCallback onInspect;
  final ValueChanged<double> onWindowChanged;
  final Widget? toolbarExtras;
  final Widget body;

  /// Hidden until PR 5a. Slot exists so 5a only unhides.
  final bool showRecord;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Semantics(
      label: title.isEmpty ? 'Graph' : title,
      child: Column(
        children: [
          Material(
            color: theme.colorScheme.surfaceContainer,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  SegmentedButton<ViewportMode>(
                    segments: const [
                      ButtonSegment(
                        value: ViewportMode.follow,
                        label: Text('Follow'),
                      ),
                      ButtonSegment(
                        value: ViewportMode.inspect,
                        label: Text('Inspect'),
                      ),
                    ],
                    selected: {viewport.mode},
                    showSelectedIcon: false,
                    style: const ButtonStyle(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onSelectionChanged: (s) {
                      if (s.isEmpty) return;
                      final next = s.first;
                      if (next == viewport.mode) return;
                      if (next == ViewportMode.follow) {
                        onFollow();
                      } else {
                        onInspect();
                      }
                    },
                  ),
                  const SizedBox(width: 12),
                  DropdownButtonHideUnderline(
                    child: DropdownButton<double>(
                      value: presetOrCustomValue(
                        viewport.windowSeconds,
                        windowOptions,
                      ),
                      isDense: true,
                      items: [
                        for (final s in windowOptions)
                          DropdownMenuItem(
                            value: s,
                            child: Text('${s.round()}s'),
                          ),
                        if (!windowIsPreset(
                          viewport.windowSeconds,
                          windowOptions,
                        ))
                          DropdownMenuItem(
                            value: viewport.windowSeconds,
                            child: const Text('custom'),
                          ),
                      ],
                      onChanged: (v) {
                        if (v == null || v == viewport.windowSeconds) {
                          return;
                        }
                        onWindowChanged(v);
                      },
                    ),
                  ),
                  if (showRecord) ...[
                    const SizedBox(width: 12),
                    const SizedBox.shrink(),
                  ],
                  const Spacer(),
                  if (toolbarExtras != null)
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: toolbarExtras!,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}
