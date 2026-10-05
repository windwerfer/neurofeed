import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:neurofeed/src/feedback/guard_lane.dart';
import 'package:neurofeed/src/feedback/trust/trust_guard.dart';
import 'package:neurofeed/src/feedback/trust/trust_inhibit.dart';
import 'package:neurofeed/src/feedback/trust/trust_pane.dart';
import 'package:neurofeed/src/feedback/trust/trust_viewport.dart';
import 'package:neurofeed/src/history/session_trust.dart';

/// History replay window. The right edge is the view end, not "now".
///
/// Pinch and Ctrl/Meta+scroll zoom use the live 15–300 s clamp. Drag pans.
/// Does not follow and is not a [TrustViewport].
class HistoryTrustViewport extends ChangeNotifier implements TrustWindow {
  HistoryTrustViewport({double? windowSeconds})
    : windowSeconds = _clamp(
        windowSeconds ?? TrustViewport.defaultWindowSeconds,
      );

  @override
  double windowSeconds;

  double _end = 0;
  bool _anchored = false;

  bool get rightEdgeIsNow => false;

  static double _clamp(double secs) => secs
      .clamp(TrustViewport.minWindowSeconds, TrustViewport.maxWindowSeconds)
      .toDouble();

  /// Place the default window so it ends at [lastSampleT].
  void anchorTo(double lastSampleT) {
    _end = lastSampleT;
    _anchored = true;
    notifyListeners();
  }

  @override
  double visibleEnd(double newestElapsed, {double? wallNow}) =>
      _anchored ? _end : newestElapsed;

  @override
  double visibleStart(double newestElapsed, {double? wallNow}) =>
      visibleEnd(newestElapsed, wallNow: wallNow) - windowSeconds;

  void setWindowSeconds(double secs) {
    final next = _clamp(secs);
    if (next == windowSeconds) return;
    windowSeconds = next;
    notifyListeners();
  }

  void pinch({required double scaleFromStart, required double windowAtStart}) {
    if (scaleFromStart <= 0 || !scaleFromStart.isFinite) return;
    setWindowSeconds(windowAtStart / scaleFromStart);
  }

  void zoomBy(double factor) {
    if (factor <= 0 || !factor.isFinite) return;
    setWindowSeconds(windowSeconds * factor);
  }

  /// Positive [dx] pans toward earlier samples. [plotWidth] is the plot
  /// width in px.
  void dragBy({required double dx, required double plotWidth}) {
    if (!_anchored) return;
    if (plotWidth <= 0 || !plotWidth.isFinite || !dx.isFinite || dx == 0) {
      return;
    }
    _end -= dx / plotWidth * windowSeconds;
    notifyListeners();
  }
}

double? historyTrustLastT(SessionTrust trust) {
  double? end;
  if (trust.reward.isNotEmpty) end = trust.reward.last.t;
  if (trust.guard.isNotEmpty) {
    final t = trust.guard.last.t;
    if (end == null || t > end) end = t;
  }
  return end;
}

String historyPercent(double? value) {
  if (value == null || !value.isFinite) return '—';
  return '${value.round()}%';
}

String historyRewardFooter(SessionTrust trust) =>
    '${historyPercent(trust.pctInZone)} in zone · ${trust.rewardChimes} chimes · ${historyPercent(trust.pctInhibited)} inhibited';

String historyGuardFooter(SessionTrust trust, {required bool ceiling}) {
  final base =
      '${historyPercent(trust.pctWarning)} warning · ${trust.guardChimes} chimes';
  if (!ceiling) return base;
  return '$base · ${historyPercent(trust.pctCeiling)} over ceiling';
}

/// Feedback chip body: existing trust panes, local Reward / Guard, no More.
class HistoryTrustReplay extends StatefulWidget {
  const HistoryTrustReplay({
    super.key,
    required this.trust,
    required this.viewport,
    required this.showReward,
    required this.showGuard,
    required this.onReward,
    required this.onGuard,
    required this.inhibit,
    required this.guardPanes,
    required this.rewardLabel,
    required this.guardLabel,
    required this.rewardColor,
    required this.guardColor,
  });

  final SessionTrust trust;
  final HistoryTrustViewport viewport;
  final bool showReward;
  final bool showGuard;
  final ValueChanged<bool> onReward;
  final ValueChanged<bool> onGuard;
  final List<TrustInhibitSpec> inhibit;
  final List<TrustGuardPaneId> guardPanes;
  final String rewardLabel;
  final String guardLabel;
  final Color rewardColor;
  final Color guardColor;

  @override
  State<HistoryTrustReplay> createState() => _HistoryTrustReplayState();
}

class _HistoryTrustReplayState extends State<HistoryTrustReplay> {
  double _pinchWindowAtStart = TrustViewport.defaultWindowSeconds;

  @override
  void initState() {
    super.initState();
    widget.viewport.addListener(_onViewport);
  }

  @override
  void didUpdateWidget(HistoryTrustReplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewport != widget.viewport) {
      oldWidget.viewport.removeListener(_onViewport);
      widget.viewport.addListener(_onViewport);
    }
  }

  @override
  void dispose() {
    widget.viewport.removeListener(_onViewport);
    super.dispose();
  }

  void _onViewport() {
    if (mounted) setState(() {});
  }

  void _onScaleStart(ScaleStartDetails _) {
    _pinchWindowAtStart = widget.viewport.windowSeconds;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, double plotWidth) {
    if (details.pointerCount >= 2) {
      widget.viewport.pinch(
        scaleFromStart: details.scale,
        windowAtStart: _pinchWindowAtStart,
      );
      return;
    }
    widget.viewport.dragBy(
      dx: details.focalPointDelta.dx,
      plotWidth: plotWidth,
    );
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final kb = HardwareKeyboard.instance;
    if (!kb.isControlPressed && !kb.isMetaPressed) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      widget.viewport.zoomBy(math.exp(event.scrollDelta.dy * 0.002));
    });
  }

  @override
  Widget build(BuildContext context) {
    final trust = widget.trust;
    final newest = historyTrustLastT(trust) ?? 0;
    final rewardLane = trust.reward.isNotEmpty;
    final guardLane = trust.guard.isNotEmpty && widget.guardPanes.isNotEmpty;
    final showReward = widget.showReward && rewardLane;
    final showGuard = widget.showGuard && guardLane;
    final ceiling = widget.guardPanes.contains(TrustGuardPaneId.ceiling);
    final start = widget.viewport.visibleStart(newest);
    final end = widget.viewport.visibleEnd(newest);
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 20),
      children: [
        Row(
          children: [
            _toggles(rewardLane: rewardLane, guardLane: guardLane),
            const Spacer(),
            Text(
              '${_clock(start)} – ${_clock(end)}',
              key: const Key('history-trust-range'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Listener(
          onPointerSignal: _onPointerSignal,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showReward) ...[
                _panZoom(
                  children: [
                    SizedBox(
                      height: 168,
                      child: RewardTrustPane(
                        key: const Key('trust-reward-pane'),
                        samples: trust.reward,
                        marks: trust.marks,
                        viewport: widget.viewport,
                        newestElapsed: newest,
                        wallNow: 0,
                        label: widget.rewardLabel,
                        seriesColor: widget.rewardColor,
                      ),
                    ),
                    for (final spec in widget.inhibit) ...[
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 112,
                        child: InhibitTrustPane(
                          key: Key('trust-inhibit-pane-${spec.id.name}'),
                          samples: trust.reward,
                          marks: trust.marks,
                          viewport: widget.viewport,
                          newestElapsed: newest,
                          wallNow: 0,
                          spec: spec,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  historyRewardFooter(trust),
                  key: const Key('history-reward-footer'),
                ),
                const SizedBox(height: 12),
              ],
              if (showGuard) ...[
                _panZoom(
                  children: [
                    for (var i = 0; i < widget.guardPanes.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      SizedBox(
                        height: 128,
                        child: _guardPane(widget.guardPanes[i], newest),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  historyGuardFooter(trust, ceiling: ceiling),
                  key: const Key('history-guard-footer'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _guardPane(TrustGuardPaneId id, double newest) {
    final trust = widget.trust;
    switch (id) {
      case TrustGuardPaneId.warn:
        return GuardWarnPane(
          key: const Key('trust-guard-warn-pane'),
          samples: trust.guard,
          marks: trust.marks,
          viewport: widget.viewport,
          newestElapsed: newest,
          wallNow: 0,
          label: widget.guardLabel,
          seriesColor: widget.guardColor,
        );
      case TrustGuardPaneId.ceiling:
        return GuardCeilingPane(
          key: const Key('trust-guard-ceiling-pane'),
          samples: trust.guard,
          marks: trust.marks,
          viewport: widget.viewport,
          newestElapsed: newest,
          wallNow: 0,
          seriesColor: widget.guardColor,
          ceiling: guardrailDeltaCeiling,
        );
    }
  }

  Widget _panZoom({required List<Widget> children}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final plotWidth = (constraints.maxWidth - kTrustYGutter - 8)
            .clamp(1.0, double.infinity)
            .toDouble();
        return GestureDetector(
          onScaleStart: _onScaleStart,
          onScaleUpdate: (details) => _onScaleUpdate(details, plotWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        );
      },
    );
  }

  Widget _toggles({required bool rewardLane, required bool guardLane}) {
    final labels = <String>[];
    final selected = <bool>[];
    final flips = <VoidCallback>[];
    if (rewardLane) {
      labels.add('Reward');
      selected.add(widget.showReward);
      flips.add(() => widget.onReward(!widget.showReward));
    }
    if (guardLane) {
      labels.add('Guard');
      selected.add(widget.showGuard);
      flips.add(() => widget.onGuard(!widget.showGuard));
    }
    if (labels.isEmpty) return const SizedBox.shrink();
    return ToggleButtons(
      isSelected: selected,
      onPressed: (i) => flips[i](),
      constraints: const BoxConstraints(minHeight: 28, minWidth: 40),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      borderRadius: BorderRadius.circular(4),
      children: [
        for (final label in labels)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(label, style: const TextStyle(fontSize: 12)),
          ),
      ],
    );
  }
}

String _clock(double seconds) {
  if (!seconds.isFinite) return '—';
  final negative = seconds < 0;
  final total = seconds.abs().floor();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  final ss = s.toString().padLeft(2, '0');
  final body = h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$ss' : '$m:$ss';
  return negative ? '-$body' : body;
}
