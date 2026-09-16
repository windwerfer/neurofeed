import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:muse_ml/src/feedback/guard_lane.dart';
import 'package:muse_ml/src/feedback/trust/trust_guard.dart';
import 'package:muse_ml/src/feedback/trust/trust_inhibit.dart';
import 'package:muse_ml/src/feedback/trust/trust_more.dart';
import 'package:muse_ml/src/feedback/trust/trust_pane.dart';
import 'package:muse_ml/src/feedback/trust/trust_trace.dart';
import 'package:muse_ml/src/feedback/trust/trust_viewport.dart';

class TrustGraphsColumn extends StatefulWidget {
  const TrustGraphsColumn({
    super.key,
    required this.trace,
    required this.viewport,
    required this.showReward,
    required this.showGuard,
    required this.showMore,
    required this.rewardLabel,
    required this.guardLabel,
    required this.rewardColor,
    required this.guardColor,
    this.inhibit = const [],
    this.guardPanes = const [TrustGuardPaneId.warn],
  });

  final TrustTrace trace;
  final TrustViewport viewport;
  final bool showReward;
  final bool showGuard;
  final bool showMore;
  final String rewardLabel;
  final String guardLabel;
  final Color rewardColor;
  final Color guardColor;
  final List<TrustInhibitSpec> inhibit;
  final List<TrustGuardPaneId> guardPanes;

  @override
  State<TrustGraphsColumn> createState() => _TrustGraphsColumnState();
}

class _TrustGraphsColumnState extends State<TrustGraphsColumn>
    with SingleTickerProviderStateMixin {
  Ticker? _ticker;
  double _pinchWindowAtStart = TrustViewport.defaultWindowSeconds;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    widget.trace.addListener(_onTrace);
    widget.viewport.addListener(_onViewport);
    _note();
    _ticker!.start();
  }

  @override
  void didUpdateWidget(TrustGraphsColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.trace != widget.trace) {
      oldWidget.trace.removeListener(_onTrace);
      widget.trace.addListener(_onTrace);
    }
    if (oldWidget.viewport != widget.viewport) {
      oldWidget.viewport.removeListener(_onViewport);
      widget.viewport.addListener(_onViewport);
    }
    _note();
  }

  @override
  void dispose() {
    widget.trace.removeListener(_onTrace);
    widget.viewport.removeListener(_onViewport);
    _ticker?.dispose();
    super.dispose();
  }

  void _onTrace() {
    _note();
    if (mounted) setState(() {});
  }

  void _onViewport() {
    if (mounted) setState(() {});
  }

  void _onTick(Duration _) {
    if (mounted) setState(() {});
  }

  void _note() {
    widget.viewport.noteSample(widget.trace.newestElapsed());
  }

  void _onScaleStart(ScaleStartDetails _) {
    _pinchWindowAtStart = widget.viewport.windowSeconds;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (d.pointerCount < 2) return;
    widget.viewport.pinch(
      scaleFromStart: d.scale,
      windowAtStart: _pinchWindowAtStart,
    );
  }

  void _onPointerSignal(PointerSignalEvent e) {
    final kb = HardwareKeyboard.instance;
    if (e is PointerScrollEvent) {
      if (!kb.isControlPressed && !kb.isMetaPressed) return;
      GestureBinding.instance.pointerSignalResolver.register(
        e,
        (_) => widget.viewport.zoomBy(math.exp(e.scrollDelta.dy * 0.002)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.showReward && !widget.showGuard) {
      return const SizedBox.shrink();
    }
    final newest = widget.trace.newestElapsed();
    final wallNow = DateTime.now().millisecondsSinceEpoch / 1000.0;
    final guardPanes = widget.showGuard
        ? (widget.guardPanes.isEmpty
              ? const [TrustGuardPaneId.warn]
              : widget.guardPanes)
        : const <TrustGuardPaneId>[];
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: GestureDetector(
        onScaleStart: _onScaleStart,
        onScaleUpdate: _onScaleUpdate,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.showReward) ...[
              SizedBox(
                height: 168,
                child: RewardTrustPane(
                  key: const Key('trust-reward-pane'),
                  samples: widget.trace.reward,
                  marks: widget.trace.marks,
                  viewport: widget.viewport,
                  newestElapsed: newest,
                  wallNow: wallNow,
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
                    samples: widget.trace.reward,
                    marks: widget.trace.marks,
                    viewport: widget.viewport,
                    newestElapsed: newest,
                    wallNow: wallNow,
                    spec: spec,
                  ),
                ),
              ],
              if (widget.showMore) ...[
                const SizedBox(height: 8),
                TrustRewardMore(
                  key: const Key('trust-reward-more'),
                  samples: widget.trace.reward,
                ),
              ],
              const SizedBox(height: 12),
            ],
            if (widget.showGuard) ...[
              for (var i = 0; i < guardPanes.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                SizedBox(
                  height: 128,
                  child: _guardPane(
                    guardPanes[i],
                    newest: newest,
                    wallNow: wallNow,
                  ),
                ),
              ],
              if (widget.showMore) ...[
                const SizedBox(height: 8),
                TrustGuardMore(
                  key: const Key('trust-guard-more'),
                  samples: widget.trace.guard,
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _guardPane(
    TrustGuardPaneId id, {
    required double newest,
    required double wallNow,
  }) {
    switch (id) {
      case TrustGuardPaneId.warn:
        return GuardWarnPane(
          key: const Key('trust-guard-warn-pane'),
          samples: widget.trace.guard,
          marks: widget.trace.marks,
          viewport: widget.viewport,
          newestElapsed: newest,
          wallNow: wallNow,
          label: widget.guardLabel,
          seriesColor: widget.guardColor,
        );
      case TrustGuardPaneId.ceiling:
        return GuardCeilingPane(
          key: const Key('trust-guard-ceiling-pane'),
          samples: widget.trace.guard,
          marks: widget.trace.marks,
          viewport: widget.viewport,
          newestElapsed: newest,
          wallNow: wallNow,
          seriesColor: widget.guardColor,
          ceiling: guardrailDeltaCeiling,
        );
    }
  }
}
