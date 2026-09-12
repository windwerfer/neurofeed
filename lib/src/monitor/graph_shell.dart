import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/monitor/monitor_providers.dart';
import 'package:muse_ml/src/monitor/monitor_state.dart';
import 'package:muse_ml/src/monitor/viewport_controller.dart';

/// Shared chrome for live monitor graphs. Record / Stop recording from PR 5a.
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
    this.toolbarMiddle,
    this.toolbarExtras,
    this.inspectRangeLabel,
    this.formatWindow,
    this.showRecord = false,
    this.followEnabled = true,
  });

  final String title;
  final ViewportController viewport;
  final List<double> windowOptions;
  final VoidCallback onFollow;
  final VoidCallback onInspect;
  final ValueChanged<double> onWindowChanged;
  final Widget? toolbarMiddle;
  final Widget? toolbarExtras;
  final String? inspectRangeLabel;
  final String Function(double seconds)? formatWindow;
  final Widget body;

  /// Record / Stop recording. Set true on the five live graph views.
  final bool showRecord;

  /// Saved-recording dashboard has no live stream. Follow stays visible
  /// but disabled.
  final bool followEnabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cinema = MediaQuery.orientationOf(context) == Orientation.landscape;
    final format = formatWindow ?? formatWindowSeconds;
    return Semantics(
      label: title.isEmpty ? 'Graph' : title,
      child: Column(
        children: [
          if (!cinema)
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
                      segments: [
                        ButtonSegment(
                          value: ViewportMode.follow,
                          label: const Text('Follow'),
                          enabled: followEnabled,
                        ),
                        const ButtonSegment(
                          value: ViewportMode.inspect,
                          label: Text('Inspect'),
                        ),
                      ],
                      selected: {
                        followEnabled ? viewport.mode : ViewportMode.inspect,
                      },
                      showSelectedIcon: false,
                      style: const ButtonStyle(
                        visualDensity: VisualDensity.compact,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onSelectionChanged: (s) {
                        if (s.isEmpty) return;
                        final next = s.first;
                        if (next == ViewportMode.follow && !followEnabled) {
                          return;
                        }
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
                            DropdownMenuItem(value: s, child: Text(format(s))),
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
                    if (inspectRangeLabel != null &&
                        viewport.mode == ViewportMode.inspect) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          inspectRangeLabel!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                    ],
                    if (toolbarMiddle != null) ...[
                      const SizedBox(width: 12),
                      toolbarMiddle!,
                    ],
                    if (showRecord) ...[
                      const SizedBox(width: 12),
                      const _RecordControls(),
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

class _RecordControls extends ConsumerStatefulWidget {
  const _RecordControls();

  @override
  ConsumerState<_RecordControls> createState() => _RecordControlsState();
}

class _RecordControlsState extends ConsumerState<_RecordControls> {
  Timer? _tick;

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _syncTick(bool recording) {
    if (recording) {
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mon = ref.watch(monitorControllerProvider);
    final connected = ref.watch(
      appStateProvider.select((s) => s.status.connected),
    );
    final recording = mon.kind == CaptureKind.recording;
    _syncTick(recording);
    final disabled =
        !recording &&
        (mon.kind == CaptureKind.feedback ||
            !connected ||
            mon.pendingScratchPath != null);
    final label = recording ? 'Stop recording' : 'Record';
    Widget button = TextButton(
      onPressed: disabled
          ? null
          : () {
              final notifier = ref.read(monitorControllerProvider.notifier);
              if (recording) {
                unawaited(notifier.stopRecording());
              } else {
                unawaited(notifier.startRecording());
              }
            },
      style: const ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
    if (disabled) {
      button = Tooltip(
        message: 'Stop the feedback session to record',
        child: button,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        button,
        if (recording) ...[
          const SizedBox(width: 8),
          Text(
            formatElapsed(mon.captureElapsedSeconds),
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ],
    );
  }
}
