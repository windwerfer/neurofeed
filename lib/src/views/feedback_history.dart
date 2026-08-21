import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/protocol_catalog.dart';
import 'package:muse_ml/src/feedback/session_export.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
import 'package:muse_ml/src/views/feedback_dashboard.dart';

class FeedbackHistoryView extends ConsumerStatefulWidget {
  const FeedbackHistoryView({super.key});

  @override
  ConsumerState<FeedbackHistoryView> createState() => _FeedbackHistoryViewState();
}

class _FeedbackHistoryViewState extends ConsumerState<FeedbackHistoryView> {
  final Set<String> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.invalidate(sessionListProvider);
      }
    });
  }

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) {
        _selected.add(id);
      }
    });
  }

  void _clearSelection() {
    if (_selecting) {
      setState(_selected.clear);
    }
  }

  List<SessionSummary> _selectedSessions(List<SessionSummary> all) =>
      [for (final s in all) if (_selected.contains(s.id)) s];

  Future<void> _export(
    List<SessionSummary> sessions,
    ExportKind kind,
  ) async {
    final store = await ref.read(sessionStoreProvider.future);
    final history = await store.storage;
    final target = await resolveExportStorage(history);
    if (!mounted) {
      return;
    }
    if (target == null) {
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Expanded(child: Text('Exporting…')),
          ],
        ),
      ),
    );
    try {
      final result = await SessionExporter(store, target)
          .exportSessions(sessions: sessions, kind: kind);
      if (!mounted) {
        return;
      }
      Navigator.of(context, rootNavigator: true).pop();
      _showExportResult(result);
    } catch (e) {
      if (!mounted) {
        return;
      }
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  void _showExportResult(SessionExportResult result) {
    final messenger = ScaffoldMessenger.of(context);
    if (result.warnings.isEmpty) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Exported ${result.fileCount} file(s) to ${result.location}',
          ),
        ),
      );
      return;
    }
    final files = '${result.fileCount} file(s) exported to ${result.location}.';
    final problems = [
      for (final w in result.warnings) '• ${w.sessionId}: ${w.message}',
    ].join('\n');
    messenger.showSnackBar(
      SnackBar(
        content: Text('$files\n$problems'),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  Future<void> _deleteSelected(List<SessionSummary> sessions) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${sessions.length} session(s)?'),
        content: const Text(
          'This permanently removes the selected session files and cannot '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    final store = await ref.read(sessionStoreProvider.future);
    var deleted = 0;
    for (final s in sessions) {
      if (await store.delete(s.id)) {
        deleted++;
      }
    }
    if (!mounted) {
      return;
    }
    setState(_selected.clear);
    ref.invalidate(sessionListProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Deleted $deleted session(s)')),
    );
  }

  void _openExportSheet(List<SessionSummary> sessions) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                'Export ${sessions.length} session(s)',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            _ExportOption(
              icon: Icons.picture_as_pdf,
              title: 'PDF report',
              subtitle: 'One vector page per session',
              onTap: () {
                Navigator.of(context).pop();
                _export(sessions, ExportKind.pdf);
              },
            ),
            _ExportOption(
              icon: Icons.photo,
              title: 'PNG thumbnail',
              subtitle: 'Single thumbnail image per session',
              onTap: () {
                Navigator.of(context).pop();
                _export(sessions, ExportKind.pngThumbnail);
              },
            ),
            _ExportOption(
              icon: Icons.photo_library,
              title: 'PNG charts',
              subtitle: 'Thumbnail + every chart, one image each',
              onTap: () {
                Navigator.of(context).pop();
                _export(sessions, ExportKind.pngAll);
              },
            ),
            _ExportOption(
              icon: Icons.table_chart,
              title: 'CSV (Mind Monitor)',
              subtitle: 'Per-second bands and raw EEG, absolute units',
              onTap: () {
                Navigator.of(context).pop();
                _export(sessions, ExportKind.csv);
              },
            ),
            _ExportOption(
              icon: Icons.bolt,
              title: 'EDF+ raw EEG',
              subtitle: 'Standard EEG file with calibration/gesture markers',
              onTap: () {
                Navigator.of(context).pop();
                _export(sessions, ExportKind.edf);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
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
                  _selecting ? '${_selected.length} selected' : 'Session History',
                  style: theme.textTheme.headlineSmall,
                ),
              ),
              if (_selecting)
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Cancel selection',
                  onPressed: _clearSelection,
                )
              else
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
                debugPrint('[history] loaded ${list.length} session(s)');
                if (list.isEmpty) {
                  return _EmptyHistory(theme: theme);
                }
                return Column(
                  children: [
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: () async {
                          ref.invalidate(sessionListProvider);
                          await ref.read(sessionListProvider.future);
                        },
                        child: ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: list.length,
                          itemBuilder: (context, index) {
                            final summary = list[index];
                            return _HistoryTile(
                              summary: summary,
                              selected: _selected.contains(summary.id),
                              onTap: () {
                                if (_selecting) {
                                  _toggle(summary.id);
                                } else {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => FeedbackDashboardView(
                                        sessionId: summary.id,
                                        metadata: summary.metadata,
                                        readOnly: true,
                                      ),
                                    ),
                                  );
                                }
                              },
                              onLongPress: () => _toggle(summary.id),
                            );
                          },
                        ),
                      ),
                    ),
                    if (_selecting)
                      _SelectionBar(
                        sessionCount: _selected.length,
                        onSelectAll: () => setState(
                          () => _selected.addAll([for (final s in list) s.id]),
                        ),
                        onSelectNone: _clearSelection,
                        onExport: () =>
                            _openExportSheet(_selectedSessions(list)),
                        onDelete: () => _deleteSelected(_selectedSessions(list)),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.sessionCount,
    required this.onSelectAll,
    required this.onSelectNone,
    required this.onExport,
    required this.onDelete,
  });

  final int sessionCount;
  final VoidCallback onSelectAll;
  final VoidCallback onSelectNone;
  final VoidCallback onExport;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onSelectAll,
            icon: const Icon(Icons.select_all),
            label: const Text('All'),
          ),
          TextButton.icon(
            onPressed: onSelectNone,
            icon: const Icon(Icons.deselect),
            label: const Text('None'),
          ),
          const Spacer(),
          FilledButton.tonalIcon(
            onPressed: onExport,
            icon: const Icon(Icons.ios_share),
            label: Text('Export ($sessionCount)'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: theme.colorScheme.error,
              foregroundColor: theme.colorScheme.onError,
            ),
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
            label: Text('Delete ($sessionCount)'),
          ),
        ],
      ),
    );
  }
}

class _ExportOption extends StatelessWidget {
  const _ExportOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}

class _HistoryTile extends ConsumerStatefulWidget {
  const _HistoryTile({
    required this.summary,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final SessionSummary summary;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  ConsumerState<_HistoryTile> createState() => _HistoryTileState();
}

class _HistoryTileState extends ConsumerState<_HistoryTile>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final meta = widget.summary.metadata;
    final protocol = ProtocolInfo.forType(meta.protocol);
    final copy = useProtocolCopy(ref, protocol);
    final stats = meta.stats;
    final date =
        '${meta.savedAt.year}-${meta.savedAt.month.toString().padLeft(2, '0')}-'
        '${meta.savedAt.day.toString().padLeft(2, '0')} '
        '${meta.savedAt.hour.toString().padLeft(2, '0')}:'
        '${meta.savedAt.minute.toString().padLeft(2, '0')}';

    final detailParts = <String>[
      if (meta.deviceModel != null && meta.deviceModel!.isNotEmpty)
        meta.deviceModel!,
      '${meta.elapsedSeconds ~/ 60}:'
          '${(meta.elapsedSeconds % 60).toString().padLeft(2, '0')}',
      if (meta.recordedChannels.isNotEmpty)
        '${meta.recordedChannels.length}ch '
            '${meta.recordedChannels.join('/')}',
      if (stats != null) 'target ${stats.targetPct.toStringAsFixed(0)}%',
      if (stats?.peakAlphaFreq != null)
        'peak ${stats!.peakAlphaFreq!.toStringAsFixed(1)} Hz',
      if (stats?.avgBpm != null) '${stats!.avgBpm!.toStringAsFixed(0)} bpm',
    ];

    return Card(
      color: widget.selected
          ? theme.colorScheme.primaryContainer.withAlpha(120)
          : theme.colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _Thumbnail(id: widget.summary.id),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${copy.title} • $date',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      detailParts.join(' • '),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (meta.notes.isNotEmpty)
                Icon(
                  Icons.edit_note,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Thumbnail extends ConsumerWidget {
  const _Thumbnail({required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final store = ref.read(sessionStoreProvider.future);
    return FutureBuilder<List<int>?>(
      future: store.then((s) => s.readPng(id)),
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null || bytes.isEmpty) {
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
        return Image.memory(
          Uint8List.fromList(bytes),
          width: 64,
          height: 48,
          fit: BoxFit.cover,
          gaplessPlayback: true,
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
      },
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