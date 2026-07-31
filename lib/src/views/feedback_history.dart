import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
import 'package:muse_ml/src/views/feedback_dashboard.dart';

class FeedbackHistoryView extends ConsumerStatefulWidget {
  const FeedbackHistoryView({super.key});

  @override
  ConsumerState<FeedbackHistoryView> createState() => _FeedbackHistoryViewState();
}

class _FeedbackHistoryViewState extends ConsumerState<FeedbackHistoryView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.invalidate(sessionListProvider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sessions = ref.watch(sessionListProvider);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Session History',
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
                onPressed: () => ref.invalidate(sessionListProvider),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: sessions.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text(
                  'Could not load session history: $e',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              data: (list) {
                if (list.isEmpty) {
                  return _EmptyHistory(theme: theme);
                }
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(sessionListProvider);
                    await ref.read(sessionListProvider.future);
                  },
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: list.length,
                    itemBuilder: (context, index) =>
                        _HistoryTile(summary: list[index]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.summary});

  final SessionSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = summary.metadata;
    final protocol = ProtocolInfo.forType(meta.protocol);
    final stats = meta.stats;
    final date =
        '${meta.savedAt.year}-${meta.savedAt.month.toString().padLeft(2, '0')}-'
        '${meta.savedAt.day.toString().padLeft(2, '0')} '
        '${meta.savedAt.hour.toString().padLeft(2, '0')}:'
        '${meta.savedAt.minute.toString().padLeft(2, '0')}';

    final detailParts = <String>[
      '${meta.elapsedSeconds ~/ 60}:'
          '${(meta.elapsedSeconds % 60).toString().padLeft(2, '0')}',
      if (stats != null) 'target ${stats.targetPct.toStringAsFixed(0)}%',
      if (stats?.peakAlphaFreq != null)
        'peak ${stats!.peakAlphaFreq!.toStringAsFixed(1)} Hz',
      if (stats?.avgBpm != null) '${stats!.avgBpm!.toStringAsFixed(0)} bpm',
    ];

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => FeedbackDashboardView(
                sessionPath: summary.musePath,
                metadata: meta,
                readOnly: true,
              ),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: _Thumbnail(path: summary.pngPath),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${protocol.title} • $date',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detailParts.join('  •  '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (meta.notes.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        meta.notes,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final file = path == null ? null : File(path!);
    if (file == null || !file.existsSync()) {
      return Container(
        width: 64,
        height: 48,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.auto_graph,
          size: 24,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Image.file(
      file,
      width: 64,
      height: 48,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => Container(
        width: 64,
        height: 48,
        color: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.auto_graph,
          size: 24,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
          ),
          const SizedBox(height: 16),
          Text(
            'No saved sessions yet.',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Complete a session and tap Save to see it here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
