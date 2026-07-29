import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/feedback_state.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/views/feedback_session.dart';

class FeedbackListView extends ConsumerWidget {
  const FeedbackListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            'Biofeedback Protocols',
            style: theme.textTheme.headlineSmall,
          ),
        ),
        for (final protocol in ProtocolInfo.all)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ProtocolCard(protocol: protocol),
          ),
      ],
    );
  }
}

class _ProtocolCard extends ConsumerWidget {
  final ProtocolInfo protocol;

  const _ProtocolCard({required this.protocol});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          ref.read(feedbackStateProvider.notifier).selectProtocol(protocol.type);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const FeedbackSessionView(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: protocol.color.withAlpha(60),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.psychology, color: protocol.color, size: 28),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          protocol.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          protocol.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.info_outline, color: theme.colorScheme.onSurfaceVariant),
                    onPressed: () => _showInfo(context, protocol),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showInfo(BuildContext context, ProtocolInfo protocol) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(protocol.title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(protocol.subtitle),
            const SizedBox(height: 12),
            Text(protocol.algorithmDescription),
            const SizedBox(height: 8),
            Text('Delay: ${protocol.expectedDelay}'),
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
