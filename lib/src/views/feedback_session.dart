import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/audio/audio_service.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/feedback/feedback_state.dart';
import 'package:muse_ml/src/feedback/live_stats.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/status_bar.dart';
import 'package:muse_ml/src/views/feedback_dashboard.dart';

class FeedbackSessionView extends ConsumerStatefulWidget {
  const FeedbackSessionView({super.key});

  @override
  ConsumerState<FeedbackSessionView> createState() => _FeedbackSessionViewState();
}

class _FeedbackSessionViewState extends ConsumerState<FeedbackSessionView> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(feedbackStateProvider, (prev, next) {
      if (prev?.phase != FeedbackPhase.ended && next.phase == FeedbackPhase.ended) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const FeedbackDashboardView()),
            );
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final fb = ref.watch(feedbackStateProvider);
    final protocol = ProtocolInfo.forType(fb.protocol);
    final connected = ref.watch(appStateProvider).status.connected;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(protocol.title),
        actions: [
          IconButton(
            icon: Icon(
              fb.showNerdStats ? Icons.science : Icons.science_outlined,
            ),
            tooltip: 'Nerd stats',
            isSelected: fb.showNerdStats,
            onPressed: () =>
                ref.read(feedbackStateProvider.notifier).toggleNerdStats(),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showGuide(context, protocol),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(56),
          child: StatusBar(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Guide card
            _GuideCard(protocol: protocol),
            // Nerd stats bubble
            if (fb.showNerdStats &&
                (fb.phase == FeedbackPhase.playing ||
                    fb.phase == FeedbackPhase.paused)) ...[
              const SizedBox(height: 8),
              const _NerdStatsBubble(),
            ],
            const SizedBox(height: 16),
            // Sound + threshold (idle and during feedback for on-the-fly changes)
            if (fb.phase == FeedbackPhase.idle ||
                fb.phase == FeedbackPhase.playing ||
                fb.phase == FeedbackPhase.paused) ...[
              Row(
                children: [
                  Expanded(child: _SoundSelector()),
                  const SizedBox(width: 8),
                  const _VolumeButton(),
                ],
              ),
              const SizedBox(height: 12),
              _PercentileSelector(),
              if (fb.phase == FeedbackPhase.idle) ...[
                const SizedBox(height: 12),
                _TimerSelector(),
                if (!connected) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.bluetooth_disabled, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Muse not connected — Start Session will open the '
                          'connect window.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
            const Spacer(),
            // Phase-specific controls
            _PhaseControls(protocol: protocol),
            const SizedBox(height: 8),
            // Timer display
            if (fb.phase == FeedbackPhase.playing || fb.phase == FeedbackPhase.paused)
              Text(
                '${fb.elapsedSeconds ~/ 60}:${(fb.elapsedSeconds % 60).toString().padLeft(2, '0')}'
                ' / ${fb.durationMinutes}:00',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  final ProtocolInfo protocol;
  const _GuideCard({required this.protocol});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb_outline, color: protocol.color, size: 20),
                const SizedBox(width: 8),
                Text('Guide', style: theme.textTheme.titleSmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(protocol.guideText, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _PhaseControls extends ConsumerWidget {
  final ProtocolInfo protocol;
  const _PhaseControls({required this.protocol});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fb = ref.watch(feedbackStateProvider);
    final theme = Theme.of(context);

    switch (fb.phase) {
      case FeedbackPhase.idle:
        return FilledButton.icon(
          onPressed: () => ref.read(feedbackStateProvider.notifier).startCalibration(),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start Session'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            textStyle: const TextStyle(fontSize: 18),
          ),
        );

      case FeedbackPhase.calibrating:
        return Column(
          children: [
            if (fb.waitingForSignal) ...[
              Icon(Icons.sensors_off, color: Colors.orange, size: 48),
              const SizedBox(height: 8),
              Text('Waiting for good signal…', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Check headband placement and electrode contact.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (fb.startAnywayAvailable) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () =>
                      ref.read(feedbackStateProvider.notifier).startAnyway(),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Start anyway'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Signal unchanged for 10s with a working electrode — '
                  'proceed without full signal?',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ] else if (fb.baselineSecondsLeft > 0) ...[
              Icon(Icons.graphic_eq, color: theme.colorScheme.primary, size: 48),
              const SizedBox(height: 8),
              Text(
                'Recording baseline…',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Sit quietly, let your mind wander. ${fb.baselineSecondsLeft}s',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: (calibrationBaselineSeconds - fb.baselineSecondsLeft) /
                    calibrationBaselineSeconds,
              ),
            ] else ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text('Calibrating…', style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.read(feedbackStateProvider.notifier).reset(),
              child: const Text('Cancel'),
            ),
          ],
        );

      case FeedbackPhase.ready:
        return Column(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 48),
            const SizedBox(height: 8),
            Text('Calibration complete', style: theme.textTheme.titleMedium),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => ref.read(feedbackStateProvider.notifier).startPlaying(),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Begin Feedback'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 56),
                textStyle: const TextStyle(fontSize: 18),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.read(feedbackStateProvider.notifier).startCalibration(),
              child: const Text('Recalibrate'),
            ),
            if (fb.signalStableSeconds > 0) ...[
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: (fb.signalStableSeconds / autoStartSeconds).clamp(0.0, 1.0),
              ),
              const SizedBox(height: 4),
              Text(
                'Signal stable ${fb.signalStableSeconds}/$autoStartSeconds s — '
                'auto-starting…',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        );

      case FeedbackPhase.playing:
      case FeedbackPhase.paused:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(feedbackStateProvider.notifier).startCalibration(),
              tooltip: 'Recalibrate',
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: () {
                final n = ref.read(feedbackStateProvider.notifier);
                if (fb.phase == FeedbackPhase.playing) {
                  n.pause();
                } else {
                  n.resume();
                }
              },
              icon: Icon(fb.phase == FeedbackPhase.playing ? Icons.pause : Icons.play_arrow),
              label: Text(fb.phase == FeedbackPhase.playing ? 'Pause' : 'Resume'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(160, 48),
              ),
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: () => ref.read(feedbackStateProvider.notifier).end(),
              tooltip: 'End session',
            ),
          ],
        );

      case FeedbackPhase.interrupted:
        return Column(
          children: [
            Icon(Icons.wifi_off, color: Colors.orange, size: 48),
            const SizedBox(height: 8),
            Text(
              fb.interruptMessage ?? 'Session interrupted',
              style: theme.textTheme.titleMedium,
            ),
            if (fb.interruptionSecondsLeft != null) ...[
              const SizedBox(height: 8),
              Text(
                'Ending in ${fb.interruptionSecondsLeft}s if not recovered…',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => ref.read(feedbackStateProvider.notifier).end(),
              icon: const Icon(Icons.stop),
              label: const Text('End session'),
            ),
          ],
        );

      case FeedbackPhase.ended:
        return Column(
          children: [
            Icon(Icons.check_circle_outline, color: protocol.color, size: 48),
            const SizedBox(height: 8),
            Text('Session ended', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Session dashboard will appear here.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        );
    }
  }
}

class _NerdStatsBubble extends ConsumerWidget {
  const _NerdStatsBubble();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(liveStatsProvider);
    final theme = Theme.of(context);
    final percentile = stats.currentPercentile;
    final atr = stats.currentAtr;
    final threshold = stats.threshold;
    final baselineMean = stats.baselineMean;
    final baselineStddev = stats.baselineStddev;
    final lines = <String>[];
    if (percentile == null || atr == null) {
      lines.add('Collecting…');
    } else {
      lines.add(
          'ATR ${atr.toStringAsFixed(2)} · p${percentile.round()} of baseline');
    }
    lines.add('thr ${threshold?.toStringAsFixed(2) ?? '—'} '
        '(p${stats.baselinePercentile ?? '—'})');
    lines.add('base mean ${baselineMean?.toStringAsFixed(2) ?? '—'} '
        '± ${baselineStddev?.toStringAsFixed(2) ?? '—'} '
        '(n=${stats.baselineCount ?? 0})');
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          lines.join('\n'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSecondaryContainer,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class _TimerSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fb = ref.watch(feedbackStateProvider);
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: const Icon(Icons.timer),
        title: const Text('Session Duration'),
        subtitle: Text('${fb.durationMinutes} min'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final result = await showDialog<int>(
            context: context,
            builder: (ctx) => _DurationPicker(current: fb.durationMinutes),
          );
          if (result != null) {
            ref.read(feedbackStateProvider.notifier).selectDuration(result);
          }
        },
      ),
    );
  }
}

class _SoundSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fb = ref.watch(feedbackStateProvider);
    final sounds = ref.read(audioServiceProvider).availableSounds;
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: const Icon(Icons.music_note),
        title: const Text('Background Sound'),
        subtitle: Text(fb.soundName),
        trailing: const Icon(Icons.chevron_right),
        onTap: sounds.length > 1
            ? () async {
                final result = await showDialog<String>(
                  context: context,
                  builder: (ctx) => _SoundPicker(current: fb.soundName, sounds: sounds),
                );
                if (result != null) {
                  ref.read(feedbackStateProvider.notifier).selectSound(result);
                }
              }
            : null,
      ),
    );
  }
}

class _VolumeButton extends ConsumerWidget {
  const _VolumeButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audio = ref.read(audioServiceProvider);
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.surfaceContainerHighest,
      child: IconButton(
        icon: const Icon(Icons.volume_up),
        tooltip: 'Volume',
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _VolumeDialog(audio: audio),
        ),
      ),
    );
  }
}

class _VolumeDialog extends StatefulWidget {
  final AudioService audio;
  const _VolumeDialog({required this.audio});

  @override
  State<_VolumeDialog> createState() => _VolumeDialogState();
}

class _VolumeDialogState extends State<_VolumeDialog> {
  late double _master;
  late double _background;
  late double _feedback;

  @override
  void initState() {
    super.initState();
    _master = widget.audio.masterVolume;
    _background = widget.audio.backgroundVolume;
    _feedback = widget.audio.feedbackVolume;
  }

  Widget _slider({
    required IconData icon,
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        SizedBox(width: 90, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            onChanged: (v) {
              setState(() {
                if (label == 'Master') _master = v;
                if (label == 'Background') _background = v;
                if (label == 'Feedback') _feedback = v;
              });
              onChanged(v);
            },
          ),
        ),
        SizedBox(
          width: 40,
          child: Text(
            '${(value * 100).round()}%',
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Volume'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _slider(
            icon: Icons.speaker,
            label: 'Master',
            value: _master,
            onChanged: widget.audio.setMasterVolume,
          ),
          _slider(
            icon: Icons.music_note,
            label: 'Background',
            value: _background,
            onChanged: widget.audio.setBackgroundVolume,
          ),
          _slider(
            icon: Icons.notifications_active,
            label: 'Feedback',
            value: _feedback,
            onChanged: widget.audio.setFeedbackVolume,
          ),
          const SizedBox(height: 8),
          Text(
            'Feedback covers the bowl chimes, end chime and calibration '
            'voice. Changes apply immediately and are remembered.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _SoundPicker extends StatelessWidget {
  final String current;
  final List<String> sounds;
  const _SoundPicker({required this.current, required this.sounds});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Choose Background Sound'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: sounds.map((s) {
          final sel = s == current;
          return ListTile(
            leading: Icon(
              sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: sel ? theme.colorScheme.primary : null,
            ),
            title: Text(s),
            selected: sel,
            onTap: () => Navigator.of(context).pop(s),
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

class _DurationPicker extends StatefulWidget {
  final int current;
  const _DurationPicker({required this.current});

  @override
  State<_DurationPicker> createState() => _DurationPickerState();
}

class _DurationPickerState extends State<_DurationPicker> {
  late final FixedExtentScrollController _controller;
  late int _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
    _controller = FixedExtentScrollController(initialItem: widget.current - 1);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final values = List.generate(120, (i) => i + 1);
    return AlertDialog(
      title: const Text('Duration (minutes)'),
      content: SizedBox(
        width: 120,
        height: 300,
        child: ListWheelScrollView(
          controller: _controller,
          itemExtent: 40,
          useMagnifier: true,
          perspective: 0.005,
          diameterRatio: 1.5,
          onSelectedItemChanged: (i) => _selected = values[i],
          children: values.map((v) {
            final label = v >= 60 ? '${v ~/ 60}h ${v % 60}m' : '${v}m';
            final isSel = v == _selected;
            return Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                  color: isSel ? null : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Select'),
        ),
      ],
    );
  }
}

class _PercentileSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fb = ref.watch(feedbackStateProvider);
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: ListTile(
        leading: const Icon(Icons.center_focus_strong),
        title: const Text('Reward Threshold'),
        subtitle: Text('Baseline ${fb.baselinePercentile}th percentile'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final result = await showDialog<int>(
            context: context,
            builder: (ctx) => _PercentilePicker(current: fb.baselinePercentile),
          );
          if (result != null) {
            ref.read(feedbackStateProvider.notifier).selectPercentile(result);
          }
        },
      ),
    );
  }
}

class _PercentilePicker extends StatefulWidget {
  final int current;
  const _PercentilePicker({required this.current});

  @override
  State<_PercentilePicker> createState() => _PercentilePickerState();
}

class _PercentilePickerState extends State<_PercentilePicker> {
  static const List<int> _values = [
    5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95,
  ];
  late final FixedExtentScrollController _controller;
  late int _selected;

  @override
  void initState() {
    super.initState();
    var index = _values.indexOf(widget.current);
    if (index < 0) index = _values.indexOf(defaultBaselinePercentile);
    _selected = _values[index];
    _controller = FixedExtentScrollController(initialItem: index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Reward Threshold'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'The feedback chime fires when your Alpha/Theta ratio exceeds '
            'this percentile of the 90s baseline. A lower percentile makes '
            'rewards easier; higher makes them harder.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: 140,
            height: 200,
            child: ListWheelScrollView(
              controller: _controller,
              itemExtent: 40,
              useMagnifier: true,
              perspective: 0.005,
              diameterRatio: 1.5,
              onSelectedItemChanged: (i) => _selected = _values[i],
              children: _values.map((v) {
                final isSel = v == _selected;
                return Center(
                  child: Text(
                    '$v',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                      color: isSel
                          ? null
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_values.first}–${_values.last}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Select'),
        ),
      ],
    );
  }
}

void _showGuide(BuildContext context, ProtocolInfo protocol) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${protocol.title} — Details'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(protocol.subtitle),
            const SizedBox(height: 12),
            Text(protocol.guideText),
            const SizedBox(height: 12),
            Text('Algorithm: ${protocol.algorithmDescription}'),
            const SizedBox(height: 4),
            Text('Expected delay: ${protocol.expectedDelay}'),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}
