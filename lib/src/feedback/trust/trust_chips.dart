import 'package:flutter/material.dart';
import 'package:neurofeed/src/feedback/feedback_phase.dart';

class TrustLaneFlags {
  const TrustLaneFlags({required this.hasReward, required this.guardRunning});

  final bool hasReward;
  final bool guardRunning;

  bool get showRewardChip => hasReward;
  bool get showGuardChip => guardRunning;
  bool get showRow => showRewardChip || showGuardChip;

  /// When prefs have never been set: Guard on if the Reward chip is omitted.
  bool get defaultGuardOn => !showRewardChip;
}

bool trustGraphsVisible(FeedbackPhase phase) =>
    phase == FeedbackPhase.playing || phase == FeedbackPhase.paused;

class TrustChipRow extends StatelessWidget {
  const TrustChipRow({
    super.key,
    required this.flags,
    required this.rewardOn,
    required this.guardOn,
    required this.moreOn,
    required this.onReward,
    required this.onGuard,
    required this.onMore,
  });

  final TrustLaneFlags flags;
  final bool rewardOn;
  final bool guardOn;
  final bool moreOn;
  final ValueChanged<bool> onReward;
  final ValueChanged<bool> onGuard;
  final ValueChanged<bool> onMore;

  @override
  Widget build(BuildContext context) {
    if (!flags.showRow) return const SizedBox.shrink();
    final labels = <String>[];
    final selected = <bool>[];
    final toggles = <ValueChanged<bool>>[];
    if (flags.showRewardChip) {
      labels.add('Reward');
      selected.add(rewardOn);
      toggles.add(onReward);
    }
    if (flags.showGuardChip) {
      labels.add('Guard');
      selected.add(guardOn);
      toggles.add(onGuard);
    }
    labels.add('More');
    selected.add(moreOn);
    toggles.add(onMore);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ToggleButtons(
        isSelected: selected,
        onPressed: (i) => toggles[i](!selected[i]),
        constraints: const BoxConstraints(minHeight: 28, minWidth: 40),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        borderRadius: BorderRadius.circular(4),
        children: [
          for (final n in labels)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(n, style: const TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
