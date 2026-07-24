import 'package:flutter/material.dart';
import 'package:muse_ml/src/charts/eeg_data_source.dart';
import 'package:muse_ml/src/charts/eeg_chart.dart';
import 'package:muse_ml/src/charts/chart_controller.dart';
import 'package:muse_ml/src/charts/graph_config.dart';

class EegDashboard extends StatefulWidget {
  final EegDataSource source;
  const EegDashboard({super.key, required this.source});

  @override
  State<EegDashboard> createState() => _EegDashboardState();
}

class _EegDashboardState extends State<EegDashboard> {
  final ChartController _controller = ChartController();
  late List<GraphConfig> _graphs;

  @override
  void initState() {
    super.initState();
    _graphs = GraphConfig.defaults.map((g) => g).toList();
  }

  void _reset() {
    setState(() {
      _graphs = GraphConfig.defaults.map((g) => g).toList();
      _controller.autoScroll = true;
      _controller.timeWindowSecs = 10;
      _controller.snapToLive(widget.source);
      _controller.forceNotify();
    });
  }

  void _removeGraph(int index) {
    if (_graphs.length <= 1) return;
    setState(() => _graphs.removeAt(index));
  }

  void _addGraph() {
    final allChannels = widget.source.channels;
    if (allChannels.isEmpty) return;
    final selected = <int>{};
    var label = '';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          backgroundColor: const Color(0xFF1E212A),
          title: const Text('Add Graph', style: TextStyle(color: Colors.white, fontSize: 14)),
          content: SizedBox(
            width: 240,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final ch in allChannels) ...[
                  CheckboxListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    value: selected.contains(ch),
                    onChanged: (v) {
                      setDState(() {
                        if (v == true) { selected.add(ch); } else { selected.remove(ch); }
                      });
                    },
                    title: Text(channelName(ch), style: const TextStyle(color: Colors.white, fontSize: 13)),
                    activeColor: channelColor(ch),
                    checkColor: Colors.black,
                  ),
                ],
                const SizedBox(height: 8),
                TextField(
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: const InputDecoration(
                    hintText: 'Label (optional)',
                    hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  ),
                  onChanged: (v) => label = v,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ),
            TextButton(
              onPressed: selected.isEmpty ? null : () {
                Navigator.pop(ctx);
                final names = selected.map((ch) => channelName(ch)).join('+');
                setState(() {
                  _graphs.add(GraphConfig(
                    label: label.isNotEmpty ? label : names,
                    electrodes: selected.toList()..sort(),
                    avgMode: selected.length > 1,
                  ));
                });
              },
              child: const Text('Add', style: TextStyle(color: Color(0xFF4FC3F7), fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  void _toggleAvg(int index) {
    setState(() {
      final g = _graphs[index];
      _graphs[index] = g.copyWith(avgMode: !g.avgMode);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final graphHeight = (constraints.maxHeight / _graphs.length).clamp(120.0, double.infinity);
              return Column(
                children: [
                  for (int i = 0; i < _graphs.length; i++)
                    SizedBox(
                      height: graphHeight,
                      child: _GraphCard(
                        key: ValueKey('graph_$i'),
                        config: _graphs[i],
                        source: widget.source,
                        controller: _controller,
                        onRemove: _graphs.length > 1 ? () => _removeGraph(i) : null,
                        onToggleAvg: () => _toggleAvg(i),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF16181F),
        border: Border(bottom: BorderSide(color: Color(0xFF2A2D37))),
      ),
      child: Row(
        children: [
          _headerBtn(Icons.remove, 'Zoom out', () => _controller.zoomOut(widget.source.maxTimeWindowSecs)),
          const SizedBox(width: 4),
          _headerBtn(Icons.add, 'Zoom in', () => _controller.zoomIn(widget.source.maxTimeWindowSecs)),
          const SizedBox(width: 8),
          Text(
            '${_controller.timeWindowSecs.toStringAsFixed(0)}s',
            style: const TextStyle(color: Color(0xFF6B7280), fontSize: 11, fontFeatures: [FontFeature.tabularFigures()]),
          ),
          const SizedBox(width: 8),
          if (!_controller.autoScroll)
            GestureDetector(
              onTap: () => _controller.enableAutoScroll(widget.source),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF00AA00).withAlpha(60),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('LIVE', style: TextStyle(color: Color(0xFF66FF66), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ),
            ),
          const Spacer(),
          _headerBtn(Icons.add_box_outlined, 'Add graph', _addGraph),
          const SizedBox(width: 4),
          _headerBtn(Icons.refresh, 'Reset defaults', _reset),
        ],
      ),
    );
  }

  Widget _headerBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          child: Icon(icon, color: Colors.white70, size: 18),
        ),
      ),
    );
  }
}

class _GraphCard extends StatelessWidget {
  final GraphConfig config;
  final EegDataSource source;
  final ChartController controller;
  final VoidCallback? onRemove;
  final VoidCallback onToggleAvg;

  const _GraphCard({
    super.key,
    required this.config,
    required this.source,
    required this.controller,
    this.onRemove,
    required this.onToggleAvg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF2A2D37))),
      ),
      child: Row(
        children: [
          _Sidebar(config: config, onRemove: onRemove, onToggleAvg: onToggleAvg),
          Expanded(
            child: EegChartWidget(
              source: source,
              controller: controller,
              config: config,
            ),
          ),
        ],
      ),
    );
  }
}

class _Sidebar extends StatelessWidget {
  final GraphConfig config;
  final VoidCallback? onRemove;
  final VoidCallback onToggleAvg;

  const _Sidebar({
    required this.config,
    this.onRemove,
    required this.onToggleAvg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: const BoxDecoration(
        color: Color(0xFF16181F),
        border: Border(right: BorderSide(color: Color(0xFF2A2D37))),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            config.label,
            style: const TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: onToggleAvg,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: config.avgMode ? const Color(0xFF4FC3F7).withAlpha(40) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: config.avgMode ? const Color(0xFF4FC3F7) : const Color(0xFF4A4D57),
                  width: 1,
                ),
              ),
              child: Text(
                'avg',
                style: TextStyle(
                  color: config.avgMode ? const Color(0xFF4FC3F7) : const Color(0xFF6B7280),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          if (onRemove != null) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(Icons.close, color: Color(0xFF6B7280), size: 14),
            ),
          ],
        ],
      ),
    );
  }
}
