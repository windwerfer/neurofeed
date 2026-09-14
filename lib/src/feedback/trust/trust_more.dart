import 'package:flutter/material.dart';
import 'package:muse_ml/src/feedback/trust/trust_runs.dart';
import 'package:muse_ml/src/feedback/trust/trust_trace.dart';

class TrustRewardMore extends StatelessWidget {
  const TrustRewardMore({super.key, required this.samples});

  final List<TrustRewardSample> samples;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final window = lastWindow(samples);
    final now = samples.isEmpty ? null : samples.last;
    final warming = trustStripWarmingUp(window.length);
    final pct = inZonePercent(window);
    final verdict = rewardVerdict(now);
    final needle = now?.percentile ?? 0;
    final thr = now?.thresholdPercentile ?? 40;
    final dirty = now != null && !now.clean;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(rewardVerdictCopy(verdict), style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        _StripLine(
          glyphs: warming ? null : rewardStripText(window),
          warming: warming,
          percentLabel: warming ? null : '${(pct ?? 0).round()}% in zone',
        ),
        const SizedBox(height: 6),
        TrustNowRail(
          value: needle,
          threshold: thr,
          dirty: dirty,
          copy: rewardNowCopy(now),
          extra: chimeEligible(now) ? 'chime' : null,
        ),
        const SizedBox(height: 4),
        Text(
          'in for  ${rewardHoldSeconds(samples)} s',
          style: theme.textTheme.bodySmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class TrustGuardMore extends StatelessWidget {
  const TrustGuardMore({super.key, required this.samples});

  final List<TrustGuardSample> samples;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final window = lastGuardWindow(samples);
    final now = samples.isEmpty ? null : samples.last;
    final warming = trustStripWarmingUp(window.length);
    final pct = warningPercent(window);
    final verdict = guardVerdict(now);
    final trip = guardTripwireCopy(now);
    final copy = [guardNowCopy(now), if (trip.isNotEmpty) trip].join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(guardVerdictCopy(verdict), style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        _StripLine(
          glyphs: warming ? null : guardStripText(window),
          warming: warming,
          percentLabel: warming ? null : '${(pct ?? 0).round()}% warning',
        ),
        const SizedBox(height: 6),
        TrustNowRail(
          value: now?.featurePercentile ?? 0,
          threshold: 75,
          dirty: now != null && !now.clean,
          copy: copy,
          showThresholdTick: false,
        ),
        const SizedBox(height: 4),
        Text(
          'warning  ${guardHoldSeconds(samples)} s',
          style: theme.textTheme.bodySmall?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _StripLine extends StatelessWidget {
  const _StripLine({
    required this.glyphs,
    required this.warming,
    required this.percentLabel,
  });

  final String? glyphs;
  final bool warming;
  final String? percentLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (warming) {
      return Text('warming up…', style: theme.textTheme.bodySmall);
    }
    return Row(
      children: [
        Expanded(
          child: Text(
            glyphs ?? '',
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'monospace',
              letterSpacing: -0.5,
            ),
          ),
        ),
        if (percentLabel != null)
          Text(percentLabel!, style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class TrustNowRail extends StatelessWidget {
  const TrustNowRail({
    super.key,
    required this.value,
    required this.threshold,
    required this.dirty,
    required this.copy,
    this.extra,
    this.showThresholdTick = true,
  });

  final double value;
  final double threshold;
  final bool dirty;
  final String copy;
  final String? extra;
  final bool showThresholdTick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 28,
          child: CustomPaint(
            painter: _NowRailPainter(
              value: value.clamp(0, 100).toDouble(),
              threshold: threshold.clamp(0, 100).toDouble(),
              dirty: dirty,
              color: theme.colorScheme.onSurface,
              showThresholdTick: showThresholdTick,
            ),
          ),
        ),
        Row(
          children: [
            Text(dirty ? '○' : '●', style: theme.textTheme.bodySmall),
            const SizedBox(width: 6),
            Text(
              value.round().toString(),
              style: theme.textTheme.bodySmall?.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            Text(copy, style: theme.textTheme.bodySmall),
            if (extra != null) ...[
              const SizedBox(width: 8),
              Text(extra!, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ],
    );
  }
}

class _NowRailPainter extends CustomPainter {
  _NowRailPainter({
    required this.value,
    required this.threshold,
    required this.dirty,
    required this.color,
    required this.showThresholdTick,
  });

  final double value;
  final double threshold;
  final bool dirty;
  final Color color;
  final bool showThresholdTick;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * 0.55;
    final axis = Paint()
      ..color = color.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), axis);
    if (showThresholdTick) {
      final tx = size.width * (threshold / 100);
      canvas.drawLine(
        Offset(tx, y - 6),
        Offset(tx, y + 6),
        Paint()
          ..color = color.withValues(alpha: 0.7)
          ..strokeWidth = 1.5,
      );
    }
    final vx = size.width * (value / 100);
    canvas.drawLine(
      Offset(vx, 2),
      Offset(vx, size.height - 2),
      Paint()
        ..color = color
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _NowRailPainter old) =>
      old.value != value ||
      old.threshold != threshold ||
      old.dirty != dirty ||
      old.color != color ||
      old.showThresholdTick != showThresholdTick;
}
