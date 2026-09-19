import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:neurofeed/src/charts/band_style.dart';
import 'package:neurofeed/src/feedback/feedback_state.dart';
import 'package:neurofeed/src/feedback/protocol_catalog.dart';
import 'package:neurofeed/src/feedback/trust/nerd_model.dart';
import 'package:neurofeed/src/settings.dart';

Future<void> showNerdSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scroll) => NerdSheet(scrollController: scroll),
      );
    },
  );
}

class NerdSheet extends ConsumerWidget {
  const NerdSheet({super.key, this.scrollController});

  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fb = ref.watch(feedbackStateProvider);
    final catalog = ref.watch(protocolCatalogProvider).valueOrNull;
    final protocol = protocolOrPlaceholder(catalog, fb.protocol);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(feedbackStateProvider.notifier);
    final rewardLabel =
        catalog?.features[protocol.reward?.feature ?? '']?.shortLabel ??
        protocol.reward?.feature ??
        '';
    final guardFeature = settings.guardFeatureFor(fb.protocol);
    final guardLabel =
        catalog?.features[guardFeature]?.shortLabel ?? guardFeature;
    return ListenableBuilder(
      listenable: notifier.trust,
      builder: (context, _) {
        final snap = nerdSheetFromLanes(
          reward: notifier.rewardLane,
          guard: notifier.guardLane,
          inhibit: protocol.conditions,
          rewardLabel: rewardLabel,
          guardLabel: guardLabel,
          trace: notifier.trust,
          now: DateTime.now(),
          warningThresholdPercentile: settings.warningThresholdPercentile,
        );
        return NerdSheetBody(
          snapshot: snap,
          scrollController: scrollController,
        );
      },
    );
  }
}

class NerdSheetBody extends StatelessWidget {
  const NerdSheetBody({
    super.key,
    required this.snapshot,
    this.scrollController,
  });

  final NerdSheetSnapshot snapshot;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const Key('nerd-sheet'),
      color: theme.colorScheme.surface,
      child: ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        children: [
          Text('Nerd', style: theme.textTheme.titleMedium),
          if (snapshot.rewardPile != null) ...[
            const SizedBox(height: 12),
            NerdPileChart(
              key: const Key('nerd-reward-pile'),
              pile: snapshot.rewardPile!,
            ),
            const SizedBox(height: 4),
            for (final row in snapshot.rewardRows) NerdInfoRow(row: row),
          ],
          if (snapshot.bands != null) ...[
            const SizedBox(height: 16),
            NerdBandStackChart(
              key: const Key('nerd-band-stack'),
              stack: snapshot.bands!,
            ),
          ],
          if (snapshot.guardPile != null) ...[
            const SizedBox(height: 16),
            NerdPileChart(
              key: const Key('nerd-guard-pile'),
              pile: snapshot.guardPile!,
            ),
            const SizedBox(height: 4),
            for (final row in snapshot.guardRows) NerdInfoRow(row: row),
          ],
          if (snapshot.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text('Collecting…', style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

class NerdInfoRow extends StatelessWidget {
  const NerdInfoRow({super.key, required this.row});

  final NerdInfoRowData row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      key: Key('nerd-row-${row.id}'),
      height: 36,
      child: Row(
        children: [
          Expanded(child: Text(row.label, style: theme.textTheme.bodyMedium)),
          Text(
            row.value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          IconButton(
            key: Key('nerd-info-${row.id}'),
            icon: const Icon(Icons.info_outline, size: 18),
            tooltip: row.infoTitle,
            visualDensity: VisualDensity.compact,
            onPressed: () => showNerdInfo(context, row),
          ),
        ],
      ),
    );
  }
}

void showNerdInfo(BuildContext context, NerdInfoRowData row) {
  final theme = Theme.of(context);
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(row.infoTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 48,
            width: 200,
            child: CustomPaint(
              painter: NerdInfoDiagramPainter(
                kind: row.diagram,
                color: theme.colorScheme.onSurface,
                fill: theme.colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(row.infoBody, style: theme.textTheme.bodyMedium),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Done'),
        ),
      ],
    ),
  );
}

class NerdPileChart extends StatelessWidget {
  const NerdPileChart({super.key, required this.pile});

  final NerdPileView pile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(pile.title, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        SizedBox(
          height: 72,
          child: CustomPaint(
            painter: NerdPilePainter(
              histogram: pile.histogram,
              live: pile.live,
              threshold: pile.threshold,
              thresholdLabel: pile.thresholdLabel,
              extraTick: pile.extraTick,
              extraTickLabel: pile.extraTickLabel,
              barColor: theme.colorScheme.primary,
              axisColor: theme.colorScheme.onSurfaceVariant,
              onSurface: theme.colorScheme.onSurface,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
  }
}

class NerdPilePainter extends CustomPainter {
  NerdPilePainter({
    required this.histogram,
    required this.live,
    required this.threshold,
    required this.thresholdLabel,
    required this.extraTick,
    required this.extraTickLabel,
    required this.barColor,
    required this.axisColor,
    required this.onSurface,
  });

  final NerdHistogram histogram;
  final double? live;
  final double? threshold;
  final String thresholdLabel;
  final double? extraTick;
  final String? extraTickLabel;
  final Color barColor;
  final Color axisColor;
  final Color onSurface;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 14.0;
    const bottomPad = 16.0;
    final plot = Rect.fromLTWH(
      0,
      top,
      size.width,
      (size.height - top - bottomPad).clamp(8, double.infinity),
    );
    final counts = histogram.counts;
    var peak = 1;
    for (final c in counts) {
      if (c > peak) peak = c;
    }
    final bw = plot.width / counts.length;
    final barPaint = Paint()..color = barColor.withValues(alpha: 0.7);
    for (var i = 0; i < counts.length; i++) {
      if (counts[i] <= 0) continue;
      final h = plot.height * (counts[i] / peak);
      canvas.drawRect(
        Rect.fromLTWH(plot.left + i * bw + 0.5, plot.bottom - h, bw - 1, h),
        barPaint,
      );
    }
    canvas.drawLine(
      Offset(plot.left, plot.bottom),
      Offset(plot.right, plot.bottom),
      Paint()
        ..color = axisColor.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
    void tick(double value, String label) {
      final x = plot.left + histogram.xFraction(value) * plot.width;
      canvas.drawLine(
        Offset(x, plot.top),
        Offset(x, plot.bottom),
        Paint()
          ..color = onSurface.withValues(alpha: 0.7)
          ..strokeWidth = 1.5,
      );
      _paintText(
        canvas,
        label,
        Offset(x + 3, 0),
        onSurface.withValues(alpha: 0.75),
        10,
      );
    }

    final thr = threshold;
    if (thr != null && thr.isFinite) tick(thr, thresholdLabel);
    final extra = extraTick;
    if (extra != null && extra.isFinite) {
      tick(extra, extraTickLabel ?? '');
    }
    final now = live;
    if (now != null && now.isFinite) {
      final x = plot.left + histogram.xFraction(now) * plot.width;
      final path = Path()
        ..moveTo(x, plot.bottom)
        ..lineTo(x - 6, plot.bottom + 10)
        ..lineTo(x + 6, plot.bottom + 10)
        ..close();
      canvas.drawPath(path, Paint()..color = onSurface);
      _paintText(
        canvas,
        'now',
        Offset(x + 8, plot.bottom + 1),
        onSurface.withValues(alpha: 0.75),
        10,
      );
    }
  }

  @override
  bool shouldRepaint(covariant NerdPilePainter old) =>
      old.histogram != histogram ||
      old.live != live ||
      old.threshold != threshold ||
      old.extraTick != extraTick ||
      old.barColor != barColor ||
      old.onSurface != onSurface;
}

class NerdBandStackChart extends StatelessWidget {
  const NerdBandStackChart({super.key, required this.stack});

  final NerdBandStackView stack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caps = <String>[];
    if (stack.deltaCeiling != null) caps.add('δ ceiling');
    if (stack.betaCeiling != null) caps.add('β ceiling');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 64,
          child: CustomPaint(
            painter: NerdBandStackPainter(
              stack: stack,
              axisColor: theme.colorScheme.onSurfaceVariant,
              onSurface: theme.colorScheme.onSurface,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        if (caps.isNotEmpty)
          Text(caps.join('  ·  '), style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class NerdBandStackPainter extends CustomPainter {
  NerdBandStackPainter({
    required this.stack,
    required this.axisColor,
    required this.onSurface,
  });

  static const labels = ['δ', 'θ', 'α', 'β', 'γ'];

  final NerdBandStackView stack;
  final Color axisColor;
  final Color onSurface;

  @override
  void paint(Canvas canvas, Size size) {
    const top = 4.0;
    const bottomPad = 14.0;
    final plot = Rect.fromLTWH(
      0,
      top,
      size.width,
      (size.height - top - bottomPad).clamp(8, double.infinity),
    );
    final values = stack.values;
    final n = values.length;
    final gap = plot.width * 0.04;
    final bw = (plot.width - gap * (n - 1)) / n;
    for (var i = 0; i < n; i++) {
      final x = plot.left + i * (bw + gap);
      final v = values[i].clamp(0.0, 1.0);
      final h = plot.height * v;
      canvas.drawRect(
        Rect.fromLTWH(x, plot.bottom - h, bw, h),
        Paint()..color = bandColors[i].withValues(alpha: 0.85),
      );
      _paintText(
        canvas,
        labels[i],
        Offset(x + bw / 2 - 4, plot.bottom + 1),
        axisColor,
        11,
      );
      final ceil = switch (i) {
        0 => stack.deltaCeiling,
        3 => stack.betaCeiling,
        _ => null,
      };
      if (ceil != null) {
        final y = plot.bottom - plot.height * ceil.clamp(0.0, 1.0);
        canvas.drawLine(
          Offset(x - 2, y),
          Offset(x + bw + 2, y),
          Paint()
            ..color = onSurface
            ..strokeWidth = 1.5,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant NerdBandStackPainter old) =>
      old.stack != stack || old.onSurface != onSurface;
}

class NerdInfoDiagramPainter extends CustomPainter {
  NerdInfoDiagramPainter({
    required this.kind,
    required this.color,
    required this.fill,
  });

  final NerdDiagramKind kind;
  final Color color;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final axis = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    final ink = Paint()
      ..color = color
      ..strokeWidth = 1.5;
    final y = size.height * 0.55;
    canvas.drawLine(Offset(8, y), Offset(size.width - 8, y), axis);
    switch (kind) {
      case NerdDiagramKind.live:
        final x = size.width * 0.62;
        final path = Path()
          ..moveTo(x, y - 10)
          ..lineTo(x - 6, y)
          ..lineTo(x + 6, y)
          ..close();
        canvas.drawPath(path, Paint()..color = fill);
      case NerdDiagramKind.percentile:
        for (var i = 0; i < 8; i++) {
          final x = 16.0 + i * 20;
          final h = 6.0 + (i == 5 ? 16 : 8);
          canvas.drawRect(
            Rect.fromCenter(center: Offset(x, y), width: 10, height: h),
            Paint()..color = i == 5 ? fill : color.withValues(alpha: 0.35),
          );
        }
      case NerdDiagramKind.threshold:
        final x = size.width * 0.4;
        canvas.drawLine(Offset(x, 8), Offset(x, size.height - 8), ink);
      case NerdDiagramKind.mean:
        final x = size.width * 0.5;
        canvas.drawLine(Offset(x, 10), Offset(x, size.height - 10), ink);
        canvas.drawCircle(Offset(x, y), 3, Paint()..color = fill);
      case NerdDiagramKind.spread:
        canvas.drawLine(
          Offset(size.width * 0.28, y),
          Offset(size.width * 0.72, y),
          ink,
        );
        canvas.drawLine(
          Offset(size.width * 0.28, y - 6),
          Offset(size.width * 0.28, y + 6),
          ink,
        );
        canvas.drawLine(
          Offset(size.width * 0.72, y - 6),
          Offset(size.width * 0.72, y + 6),
          ink,
        );
      case NerdDiagramKind.samples:
        for (var i = 0; i < 6; i++) {
          canvas.drawCircle(
            Offset(24.0 + i * 22, y),
            3.5,
            Paint()..color = fill,
          );
        }
      case NerdDiagramKind.success:
        for (var i = 0; i < 10; i++) {
          canvas.drawRect(
            Rect.fromLTWH(12 + i * 16, y - 6, 12, 12),
            Paint()..color = i < 6 ? fill : color.withValues(alpha: 0.25),
          );
        }
      case NerdDiagramKind.warning:
        canvas.drawRect(
          Rect.fromLTWH(12, y - 8, size.width - 24, 16),
          Paint()..color = fill.withValues(alpha: 0.35),
        );
      case NerdDiagramKind.cooldown:
        for (var i = 0; i < 4; i++) {
          final x = 24.0 + i * 48;
          canvas.drawCircle(Offset(x, y), 3, Paint()..color = fill);
        }
    }
  }

  @override
  bool shouldRepaint(covariant NerdInfoDiagramPainter old) =>
      old.kind != kind || old.color != color || old.fill != fill;
}

void _paintText(
  Canvas canvas,
  String text,
  Offset at,
  Color color,
  double size,
) {
  if (text.isEmpty) return;
  final tp = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(color: color, fontSize: size),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  tp.paint(canvas, at);
}
