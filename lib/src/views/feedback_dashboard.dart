import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/feedback_state.dart';
import 'package:muse_ml/src/feedback/protocol.dart';

class FeedbackDashboardView extends ConsumerWidget {
  const FeedbackDashboardView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fb = ref.watch(feedbackStateProvider);
    final protocol = ProtocolInfo.forType(fb.protocol);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text('${protocol.title} — Session')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Session summary', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 12),
                  _SummaryRow(label: 'Protocol', value: protocol.title),
                  _SummaryRow(
                    label: 'Duration',
                    value: '${fb.durationMinutes} min',
                  ),
                  _SummaryRow(
                    label: 'Elapsed',
                    value:
                        '${fb.elapsedSeconds ~/ 60}:'
                        '${(fb.elapsedSeconds % 60).toString().padLeft(2, '0')}',
                  ),
                  _SummaryRow(label: 'Background sound', value: fb.soundName),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Charts and stats arrive in Phase 5.', style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          Text(value, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}
