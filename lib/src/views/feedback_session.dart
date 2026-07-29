import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/feedback_state.dart';
import 'package:muse_ml/src/feedback/protocol.dart';

class FeedbackSessionView extends ConsumerWidget {
  const FeedbackSessionView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fb = ref.watch(feedbackStateProvider);
    final protocol = ProtocolInfo.forType(fb.protocol);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(protocol.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showGuide(context, protocol),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Guide text
            Card(
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
                    Text(
                      protocol.guideText,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Timer selector
            _TimerSelector(),
            const SizedBox(height: 16),

            // Sound selector placeholder
            Card(
              color: theme.colorScheme.surfaceContainerHighest,
              child: ListTile(
                leading: Icon(Icons.music_note, color: protocol.color),
                title: const Text('Feedback Sound'),
                subtitle: Text(fb.soundName ?? 'Harmonic Consonance'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  // Future: sound selection dialog
                },
              ),
            ),
            const Spacer(),

            // Signal quality / start controls (placeholder)
            if (fb.phase == FeedbackPhase.idle)
              FilledButton.icon(
                onPressed: () => ref.read(feedbackStateProvider.notifier).startCalibration(),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Session'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              )
            else if (fb.phase == FeedbackPhase.calibrating)
              Column(
                children: [
                  const LinearProgressIndicator(),
                  const SizedBox(height: 8),
                  const Text('Calibrating…'),
                ],
              )
            else if (fb.phase == FeedbackPhase.playing || fb.phase == FeedbackPhase.paused)
              Row(
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
              ),
            const SizedBox(height: 8),
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
    _controller = FixedExtentScrollController(
      initialItem: widget.current - 1,
    );
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
            final selected = v == _selected;
            return Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                  color: selected ? null : Theme.of(context).colorScheme.onSurfaceVariant,
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
