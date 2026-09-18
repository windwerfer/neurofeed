import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/monitor/graph_cinema.dart';
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
    final cinema = GraphCinema.of(context);
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
                child: _PannableChromeRow(
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
                      Text(
                        inspectRangeLabel!,
                        maxLines: 1,
                        softWrap: false,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelMedium,
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
                    if (toolbarExtras != null) ...[
                      const SizedBox(width: 12),
                      toolbarExtras!,
                    ],
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


/// Horizontally pannable GraphShell toolbar. When Follow/Inspect + electrodes
/// (etc.) overflow the width, drag anywhere on the row pans the whole strip
/// so electrodes slide into view (leading chrome slides off first). Chevron
/// jumps to the end.
class _PannableChromeRow extends StatefulWidget {
  const _PannableChromeRow({required this.children});

  final List<Widget> children;

  @override
  State<_PannableChromeRow> createState() => _PannableChromeRowState();
}

class _PannableChromeRowState extends State<_PannableChromeRow> {
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
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final atEnd = pos.pixels >= pos.maxScrollExtent - 1;
    if (atEnd != _atEnd) setState(() => _atEnd = atEnd);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _recomputeOverflow());
        final scrollable = SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: widget.children,
          ),
        );
        return Row(
          children: [
            Expanded(child: scrollable),
            if (_overflows && !_atEnd)
              IconButton(
                key: const ValueKey('chrome-overflow-arrow'),
                tooltip: 'Show remaining chrome',
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
