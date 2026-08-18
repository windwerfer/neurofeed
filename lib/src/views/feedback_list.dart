import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/feedback_state.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/protocol_catalog.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
import 'package:muse_ml/src/views/feedback_session.dart';

class FeedbackListView extends ConsumerWidget {
  const FeedbackListView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sessions = ref.watch(sessionListProvider).valueOrNull ?? const [];
    final recent = _recentProtocols(sessions);
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
        if (recent.isNotEmpty) ...[
          _RecentTile(protocols: recent),
          const SizedBox(height: 12),
        ],
        for (final protocol in ProtocolInfo.all)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ProtocolCard(protocol: protocol),
          ),
      ],
    );
  }

  /// The 3 most recent distinct protocols from session history, oldest of the
  /// three first (leftmost slot). Legacy placeholder protocols map to the ATR
  /// info they ran under and dedupe against it.
  static List<ProtocolInfo> _recentProtocols(List<SessionSummary> sessions) {
    final seen = <ProtocolType>{};
    final recent = <ProtocolInfo>[];
    for (final s in sessions) {
      final info = ProtocolInfo.forType(s.metadata.protocol);
      if (seen.add(info.type)) {
        recent.add(info);
        if (recent.length == 3) {
          break;
        }
      }
    }
    return recent.reversed.toList();
  }
}

/// A row of up to 3 quick-start slots showing the most recent protocols by
/// short catch name only: [3rd most recent] [2nd most recent] [most recent].
class _RecentTile extends ConsumerWidget {
  final List<ProtocolInfo> protocols;
  const _RecentTile({required this.protocols});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Recent',
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (var i = 0; i < protocols.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: _RecentSlot(protocol: protocols[i])),
            ],
          ],
        ),
      ],
    );
  }
}

class _RecentSlot extends ConsumerWidget {
  final ProtocolInfo protocol;
  const _RecentSlot({required this.protocol});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final copy = useProtocolCopy(ref, protocol);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      margin: EdgeInsets.zero,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          final notifier = ref.read(feedbackStateProvider.notifier);
          if (ref.read(feedbackStateProvider).phase == FeedbackPhase.ended) {
            notifier.reset();
          }
          notifier.selectProtocol(protocol.type);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const FeedbackSessionView(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          child: Text(
            copy.catchPhrase,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProtocolCard extends ConsumerWidget {
  final ProtocolInfo protocol;

  const _ProtocolCard({required this.protocol});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final copy = useProtocolCopy(ref, protocol);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          final notifier = ref.read(feedbackStateProvider.notifier);
          if (ref.read(feedbackStateProvider).phase == FeedbackPhase.ended) {
            notifier.reset();
          }
          notifier.selectProtocol(protocol.type);
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
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: copy.catchPhrase,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize:
                                      (theme.textTheme.titleMedium?.fontSize ??
                                              16) +
                                          1,
                                ),
                              ),
                              TextSpan(
                                text: '  —  ${copy.title}',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w400,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          copy.subtitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.info_outline, color: theme.colorScheme.onSurfaceVariant),
                    onPressed: () => _showInfo(context, protocol, copy),
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

void _showInfo(BuildContext context, ProtocolInfo protocol, ProtocolCopy copy) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(copy.title),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(copy.subtitle),
            const SizedBox(height: 12),
            Text(copy.algorithmDescription),
            const SizedBox(height: 8),
            Text('Delay: ${copy.expectedDelay}'),
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
