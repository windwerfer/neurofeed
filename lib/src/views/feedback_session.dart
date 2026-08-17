import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/audio/audio_service.dart';
import 'package:muse_ml/src/audio/guardrail_sound.dart';
import 'package:muse_ml/src/connection_provider.dart';
import 'package:muse_ml/src/feedback/feedback_state.dart';
import 'package:muse_ml/src/feedback/live_stats.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/reve/model_engine.dart';
import 'package:muse_ml/src/reve/models.dart';
import 'package:muse_ml/src/reve/reve_import.dart';
import 'package:muse_ml/src/settings.dart';
import 'package:muse_ml/src/status_bar.dart';
import 'package:muse_ml/src/views/feedback_dashboard.dart';

class FeedbackSessionView extends ConsumerStatefulWidget {
  const FeedbackSessionView({super.key});

  @override
  ConsumerState<FeedbackSessionView> createState() =>
      _FeedbackSessionViewState();
}

class _FeedbackSessionViewState extends ConsumerState<FeedbackSessionView> {
  @override
  void initState() {
    super.initState();
    ref.listenManual(feedbackStateProvider, (prev, next) {
      if (prev?.phase != FeedbackPhase.ended &&
          next.phase == FeedbackPhase.ended) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const FeedbackDashboardView()),
            );
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final fb = ref.watch(feedbackStateProvider);
    final protocol = ProtocolInfo.forType(fb.protocol);
    final connected = ref.watch(appStateProvider).status.connected;
    final theme = Theme.of(context);
    final guardrailOn =
        protocol.aiSleepGuardrail &&
        ref.watch(settingsProvider).guardrailEnabledFor(fb.protocol);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          protocol.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: Icon(
              fb.showNerdStats ? Icons.science : Icons.science_outlined,
            ),
            tooltip: 'Nerd stats',
            isSelected: fb.showNerdStats,
            onPressed: () =>
                ref.read(feedbackStateProvider.notifier).toggleNerdStats(),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showGuide(context, protocol),
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(56),
          child: StatusBar(showMenu: false),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Guide card
            _GuideCard(protocol: protocol),
            // Nerd stats bubble
            if (fb.showNerdStats &&
                (fb.phase == FeedbackPhase.playing ||
                    fb.phase == FeedbackPhase.paused)) ...[
              const SizedBox(height: 8),
              const _NerdStatsBubble(),
            ],
            const SizedBox(height: 16),
            // Session settings (idle and during feedback for on-the-fly changes)
            if (fb.phase == FeedbackPhase.idle ||
                fb.phase == FeedbackPhase.playing ||
                fb.phase == FeedbackPhase.paused) ...[
              _SessionSettingsCard(showGuardrail: guardrailOn),
            ],
            // Muse-not-connected hint (idle only)
            if (fb.phase == FeedbackPhase.idle && !connected) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.bluetooth_disabled, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Muse not connected — Start Session will open the '
                      'connect window.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            // Phase-specific controls
            _PhaseControls(protocol: protocol),
            const SizedBox(height: 8),
            // Timer display
            if (fb.phase == FeedbackPhase.playing ||
                fb.phase == FeedbackPhase.paused)
              Text(
                '${fb.elapsedSeconds ~/ 60}:${(fb.elapsedSeconds % 60).toString().padLeft(2, '0')}'
                ' / ${fb.durationMinutes}:00',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _GuideCard extends StatelessWidget {
  final ProtocolInfo protocol;
  const _GuideCard({required this.protocol});

  static String _truncate(String text, {int maxParagraphs = 2}) {
    final parts = text
        .split(RegExp(r'\n\s*\n'))
        .where((p) => p.trim().isNotEmpty)
        .toList();
    if (parts.length <= maxParagraphs) {
      return text;
    }
    return '${parts.take(maxParagraphs).join('\n\n')}\n…';
  }

  void _showFullGuide(BuildContext context, String guideText) {
    final theme = Theme.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Guide'),
        content: SingleChildScrollView(
          child: Text(guideText, style: theme.textTheme.bodyMedium),
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final guideText = protocol.guideText;
    final truncated = _truncate(guideText);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showFullGuide(context, guideText),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    color: protocol.color,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text('Guide', style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Text(
                    'Tap for full guide',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(truncated, style: theme.textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _FaultyPadFallback extends StatelessWidget {
  const _FaultyPadFallback({required this.ref, required this.theme});

  final WidgetRef ref;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final quality = ref.read(appStateProvider).signalQuality;
    final bothNeeded = neededElectrodes
        .where((i) => i < (quality?.length ?? 0))
        .every((i) => (quality?[i] ?? 0) >= signalGoodThreshold);
    final anyNeeded = neededElectrodes.any(
      (i) =>
          i < (quality?.length ?? 0) &&
          (quality?[i] ?? 0) >= signalGoodThreshold,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            anyNeeded
                ? (bothNeeded ? _tierACopy : _tierBCopy)
                : 'No usable electrode signal. Keep adjusting the headband.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onTertiaryContainer,
            ),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () =>
              ref.read(feedbackStateProvider.notifier).startAnyway(),
          icon: const Icon(Icons.play_arrow),
          label: const Text('Continue'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            textStyle: const TextStyle(fontSize: 18),
          ),
        ),
      ],
    );
  }

  static const _tierACopy =
      'Not all, but enough electrodes for this program '
      'have a good fit. Continue?';
  static const _tierBCopy =
      'At least 1 of the important electrodes have a '
      'good fit — accuracy will be reduced but it should still be usable. Continue?';
}

class _PhaseControls extends ConsumerWidget {
  final ProtocolInfo protocol;
  const _PhaseControls({required this.protocol});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fb = ref.watch(feedbackStateProvider);
    final theme = Theme.of(context);
    final guardrailIntended =
        protocol.aiSleepGuardrail &&
        ref.watch(settingsProvider).guardrailEnabledFor(fb.protocol);
    final engineSel = guardrailEngineFromSettings(ref.read(settingsProvider));
    final needsModel = guardrailIntended && !engineSel.isBandMath;

    // Music feedback needs a music folder AND no AI guardrail model (the
    // band-math scorer leaves the CPU free for the audio pipeline).
    Future<void> startSession() async {
      final settings = ref.read(settingsProvider);
      if (fb.feedbackMode == FeedbackMode.music) {
        if (settings.musicFolder == null) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Music folder not set'),
              content: const Text(
                'Music feedback plays your own tracks through a reward-driven '
                'filter. Pick a music folder in Settings → Music feedback '
                'first.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          return;
        }
        if (guardrailIntended && !engineSel.isBandMath) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Music feedback unavailable'),
              content: const Text(
                'Music feedback is off while an AI guardrail model is active '
                '(the model and the audio pipeline would compete for CPU). '
                'Switch the guardrail scorer to Band math in the guardrail '
                'gear, or choose a different feedback sound.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          return;
        }
      }
      ref.read(feedbackStateProvider.notifier).startCalibration();
    }

    switch (fb.phase) {
      case FeedbackPhase.idle:
        if (needsModel && !ref.watch(modelEngineAvailabilityProvider)) {
          return Column(
            children: [
              FilledButton.icon(
                onPressed: () async {
                  final ready = await showModelGateDialog(context, ref);
                  if (ready && context.mounted) {
                    await startSession();
                  }
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Start Session'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 56),
                  textStyle: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'The guardrail AI engine is not ready yet — download or '
                'import a model to enable the AI sleep guardrail.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          );
        }
        return FilledButton.icon(
          onPressed: startSession,
          icon: const Icon(Icons.play_arrow),
          label: const Text('Start Session'),
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            textStyle: const TextStyle(fontSize: 18),
          ),
        );

      case FeedbackPhase.calibrating:
        return Column(
          children: [
            if (fb.waitingForSignal) ...[
              Icon(Icons.sensors_off, color: Colors.orange, size: 48),
              const SizedBox(height: 8),
              Text(
                'Waiting for good signal…',
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'All electrodes should be green for $greenStableSeconds s before '
                'calibration begins. Check headband placement and electrode contact.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              if (fb.startAnywayAvailable) ...[
                const SizedBox(height: 16),
                _FaultyPadFallback(ref: ref, theme: theme),
                const SizedBox(height: 8),
              ],
            ] else if (fb.calibrationStepName != null) ...[
              Icon(
                Icons.graphic_eq,
                color: theme.colorScheme.primary,
                size: 48,
              ),
              const SizedBox(height: 8),
              Text(fb.calibrationStepName!, style: theme.textTheme.titleMedium),
              if (fb.calibrationChallengeText != null) ...[
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      if (fb.calibrationChallengeHint case final hint?) ...[
                        Text(
                          hint,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      Text(
                        fb.calibrationChallengeText!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              if (fb.baselineSecondsLeft > 0) ...[
                Text(
                  'Sit quietly, let your mind wander. ${fb.baselineSecondsLeft}s',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                LinearProgressIndicator(
                  value:
                      (fb.calibrationStepTotal - fb.baselineSecondsLeft) /
                      fb.calibrationStepTotal,
                ),
              ] else ...[
                Text(
                  'Playing the calibration cue…',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
              ],
            ] else ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text('Calibrating…', style: theme.textTheme.bodyMedium),
            ],
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => ref.read(feedbackStateProvider.notifier).reset(),
              child: const Text('Cancel'),
            ),
          ],
        );

      case FeedbackPhase.playing:
      case FeedbackPhase.paused:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Recalibrate from last 90 s of clean signal',
              onPressed: () {
                final n = ref.read(feedbackStateProvider.notifier);
                if (fb.elapsedSeconds < minRecalibrateSeconds) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Recalibration needs at least $minRecalibrateSeconds s of session data.',
                      ),
                    ),
                  );
                  return;
                }
                if (!n.recalibrate()) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Not enough clean signal for recalibration yet — try again in a moment.',
                      ),
                    ),
                  );
                }
              },
            ),
            const SizedBox(width: 16),
            FilledButton.icon(
              onPressed: () {
                final n = ref.read(feedbackStateProvider.notifier);
                if (fb.phase == FeedbackPhase.playing) {
                  n.pause();
                } else {
                  n.resume();
                }
              },
              icon: Icon(
                fb.phase == FeedbackPhase.playing
                    ? Icons.pause
                    : Icons.play_arrow,
              ),
              label: Text(
                fb.phase == FeedbackPhase.playing ? 'Pause' : 'Resume',
              ),
              style: FilledButton.styleFrom(minimumSize: const Size(160, 48)),
            ),
            const SizedBox(width: 16),
            IconButton(
              icon: const Icon(Icons.stop),
              onPressed: () => ref.read(feedbackStateProvider.notifier).end(),
              tooltip: 'End session',
            ),
          ],
        );

      case FeedbackPhase.interrupted:
        return Column(
          children: [
            Icon(Icons.wifi_off, color: Colors.orange, size: 48),
            const SizedBox(height: 8),
            Text(
              fb.interruptMessage ?? 'Session interrupted',
              style: theme.textTheme.titleMedium,
            ),
            if (fb.interruptionSecondsLeft != null) ...[
              const SizedBox(height: 8),
              Text(
                'Ending in ${fb.interruptionSecondsLeft}s if not recovered…',
                style: theme.textTheme.bodyMedium,
              ),
            ] else ...[
              const SizedBox(height: 8),
              Text(
                'Waiting for the signal to return — the session resumes '
                'automatically.',
                style: theme.textTheme.bodyMedium,
              ),
            ],
            const SizedBox(height: 16),
            TextButton.icon(
              onPressed: () => ref.read(feedbackStateProvider.notifier).end(),
              icon: const Icon(Icons.stop),
              label: const Text('End session'),
            ),
          ],
        );

      case FeedbackPhase.ended:
        return Column(
          children: [
            Icon(Icons.check_circle_outline, color: protocol.color, size: 48),
            const SizedBox(height: 8),
            Text('Session ended', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Session dashboard will appear here.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        );
    }
  }
}

class _NerdStatsBubble extends ConsumerWidget {
  const _NerdStatsBubble();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(liveStatsProvider);
    final fb = ref.watch(feedbackStateProvider);
    final theme = Theme.of(context);
    final percentile = stats.currentPercentile;
    final atr = stats.currentAtr;
    final threshold = stats.threshold;
    final baselineMean = stats.baselineMean;
    final baselineStddev = stats.baselineStddev;
    final metricName =
        ProtocolInfo.forType(fb.protocol).rewardMetric ==
            RewardMetric.thetaOverAlpha
        ? 'TAR'
        : 'ATR';
    final lines = <String>[];
    if (percentile == null || atr == null) {
      lines.add('Collecting…');
    } else {
      lines.add(
        '$metricName ${atr.toStringAsFixed(2)} · p${percentile.round()} of baseline',
      );
    }
    lines.add(
      'thr ${threshold?.toStringAsFixed(2) ?? '—'} '
      '(p${stats.baselinePercentile ?? '—'})',
    );
    lines.add(
      'base mean ${baselineMean?.toStringAsFixed(2) ?? '—'} '
      '± ${baselineStddev?.toStringAsFixed(2) ?? '—'} '
      '(n=${stats.baselineCount ?? 0})',
    );
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          lines.join('\n'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSecondaryContainer,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

/// Quick duration chips (10/15/20/30 min) plus a Custom button that opens the
/// wheel picker; the last custom choice is remembered and shown as a chip.
/// One card holding all session settings: background sound, feedback sound,
/// the guardrail, and (before a session starts) the duration chips.
class _SessionSettingsCard extends ConsumerWidget {
  const _SessionSettingsCard({required this.showGuardrail});

  final bool showGuardrail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fb = ref.watch(feedbackStateProvider);
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text('Session Settings', style: theme.textTheme.titleSmall),
          ),
          const _SoundTile(),
          const Divider(height: 1, indent: 16, endIndent: 16),
          const _FeedbackTile(),
          if (showGuardrail) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            const _GuardrailTile(),
          ],
          if (fb.phase == FeedbackPhase.idle) ...[
            const Divider(height: 1, indent: 16, endIndent: 16),
            const _DurationSection(),
          ],
        ],
      ),
    );
  }
}

class _SoundTile extends ConsumerWidget {
  const _SoundTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fb = ref.watch(feedbackStateProvider);
    final audio = ref.read(audioServiceProvider);
    final sounds = audio.availableSounds;
    return ListTile(
      leading: const Icon(Icons.music_note),
      title: const Text('Background Sound'),
      subtitle: Text(fb.soundName),
      trailing: IconButton(
        icon: const Icon(Icons.volume_up),
        tooltip: 'Volume',
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => _VolumeDialog(audio: audio),
        ),
      ),
      onTap: sounds.length > 1
          ? () async {
              final result = await showDialog<String>(
                context: context,
                builder: (ctx) =>
                    _SoundPicker(current: fb.soundName, sounds: sounds),
              );
              if (result != null) {
                if (!context.mounted) {
                  return;
                }
                final settings = ref.read(settingsProvider);
                if (AudioService.isMusicSound(result) &&
                    settings.musicFolder == null) {
                  await showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Music folder not set'),
                      content: const Text(
                        'Music feedback plays your own tracks through a '
                        'reward-driven filter. Pick a music folder in '
                        'Settings → Music feedback first.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('OK'),
                        ),
                      ],
                    ),
                  );
                  return;
                }
                ref.read(feedbackStateProvider.notifier).selectSound(result);
              }
            }
          : null,
    );
  }
}

class _FeedbackTile extends ConsumerWidget {
  const _FeedbackTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fb = ref.watch(feedbackStateProvider);
    return ListTile(
      leading: const Icon(Icons.headphones),
      title: const Text('Feedback Sound'),
      subtitle: Text(
        '${fb.feedbackMode.label} • ${fb.baselinePercentile}th percentile',
      ),
      trailing: IconButton(
        icon: const Icon(Icons.settings),
        tooltip: 'Target settings',
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const _TargetSettingsDialog(),
        ),
      ),
      onTap: () async {
        final result = await showDialog<FeedbackMode>(
          context: context,
          builder: (ctx) => _FeedbackModePicker(current: fb.feedbackMode),
        );
        if (result == null || result == fb.feedbackMode) {
          return;
        }
        if (!context.mounted) {
          return;
        }
        if (result == FeedbackMode.music) {
          final settings = ref.read(settingsProvider);
          if (settings.musicFolder == null) {
            await showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Music folder not set'),
                content: const Text(
                  'Music feedback plays your own tracks through a '
                  'reward-driven filter. Pick a music folder in '
                  'Settings → Music feedback first.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('OK'),
                  ),
                ],
              ),
            );
            return;
          }
        }
        ref.read(feedbackStateProvider.notifier).selectFeedbackMode(result);
      },
    );
  }
}

class _GuardrailTile extends ConsumerWidget {
  const _GuardrailTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.read(settingsProvider);
    final engine = guardrailEngineFromSettings(settings);
    final sound = GuardrailSound.fromName(settings.warningSoundName);
    return ListTile(
      leading: const Icon(Icons.shield_outlined),
      title: const Text('Guardrail'),
      subtitle: Text('${engine.label} • ${sound.label}'),
      trailing: IconButton(
        icon: const Icon(Icons.settings_outlined),
        tooltip: 'Guardrail engine, warning sound and threshold',
        onPressed: () => showDialog<void>(
          context: context,
          builder: (_) => const _GuardrailGearDialog(),
        ),
      ),
      onTap: () => showDialog<void>(
        context: context,
        builder: (_) => const _GuardrailGearDialog(),
      ),
    );
  }
}

/// Quick duration chips plus a Custom button that asks for a number. Nothing
/// is applied unless the user actively picks something; a confirmed custom
/// value is remembered and shown as its own chip.
class _DurationSection extends ConsumerWidget {
  const _DurationSection();

  static const List<int> quickDurations = [7, 15, 25, 45];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fb = ref.watch(feedbackStateProvider);
    final settings = ref.read(settingsProvider);
    final lastCustom = settings.lastCustomMinutes;
    final selected = fb.durationMinutes;
    final theme = Theme.of(context);
    final chips = <int>[
      ...quickDurations,
      if (lastCustom != null && !quickDurations.contains(lastCustom)) lastCustom,
    ];

    Future<void> openCustom() async {
      final result = await showDialog<int>(
        context: context,
        builder: (ctx) => const _DurationInputDialog(),
      );
      if (result == null) {
        return;
      }
      await ref.read(settingsProvider).setLastCustomMinutes(result);
      ref.read(feedbackStateProvider.notifier).selectDuration(result);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Duration', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final d in chips)
                ChoiceChip(
                  label: Text('$d min'),
                  selected: d == selected,
                  onSelected: (_) =>
                      ref.read(feedbackStateProvider.notifier).selectDuration(d),
                ),
              ChoiceChip(
                label: const Text('Custom…'),
                selected: false,
                onSelected: (_) => openCustom(),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Simple number entry for a custom duration — no wheel. The Apply button
/// stays disabled until a valid number is typed, so cancel/empty leaves
/// everything untouched.
class _DurationInputDialog extends StatefulWidget {
  const _DurationInputDialog();

  @override
  State<_DurationInputDialog> createState() => _DurationInputDialogState();
}

class _DurationInputDialogState extends State<_DurationInputDialog> {
  final TextEditingController _controller = TextEditingController();
  int? _parsed;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Custom Duration'),
      content: SizedBox(
        width: 220,
        child: TextField(
          controller: _controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(
            labelText: 'Minutes',
            helperText: 'e.g. 30',
          ),
          onChanged: (text) {
            final n = int.tryParse(text);
            final ok = n != null && n >= 1 && n <= 999;
            setState(() => _parsed = ok ? n : null);
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _parsed == null
              ? null
              : () => Navigator.of(context).pop(_parsed),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

/// A 5%-step percentile slider with the chosen value shown on the right and
/// a marker line at the default position.
class _PercentileSlider extends StatelessWidget {
  static const int min = 5;
  static const int max = 95;

  const _PercentileSlider({
    required this.value,
    required this.defaultValue,
    required this.onChanged,
  });

  final int value;
  final int defaultValue;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value.clamp(min, max);
    final divisions = ((max - min) ~/ 5);
    final frac = (defaultValue - min) / (max - min);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Slider(
          value: v.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: divisions,
          label: '$v%',
          onChanged: (d) => onChanged(d.round()),
        ),
        // AlertDialog measures its content with IntrinsicWidth, so no
        // LayoutBuilder here — Align positions the marker at the default's
        // fraction of the track width instead.
        SizedBox(
          height: 18,
          child: Stack(
            children: [
              Align(
                alignment: Alignment(2 * frac - 1, 0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 2,
                      height: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'default $defaultValue%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$v%',
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
        )
      ],
    );
  }
}

class _VolumeDialog extends StatefulWidget {
  final AudioService audio;
  const _VolumeDialog({required this.audio});

  @override
  State<_VolumeDialog> createState() => _VolumeDialogState();
}

class _VolumeDialogState extends State<_VolumeDialog> {
  late double _master;
  late double _background;
  late double _feedback;
  late double _intro;
  late double _bell;

  @override
  void initState() {
    super.initState();
    _master = widget.audio.masterVolume;
    _background = widget.audio.backgroundVolume;
    _feedback = widget.audio.feedbackVolume;
    _intro = widget.audio.introVolume;
    _bell = widget.audio.bellVolume;
  }

  Widget _slider({
    required IconData icon,
    required String label,
    required double value,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        SizedBox(width: 90, child: Text(label)),
        Expanded(
          child: Slider(
            value: value,
            onChanged: (v) {
              setState(() {
                if (label == 'Master') _master = v;
                if (label == 'Background') _background = v;
                if (label == 'Feedback') _feedback = v;
                if (label == 'Intro') _intro = v;
                if (label == 'End Bell') _bell = v;
              });
              onChanged(v);
            },
          ),
        ),
        SizedBox(
          width: 40,
          child: Text('${(value * 100).round()}%', textAlign: TextAlign.right),
        ),
      ],
    );
  }

  void _reset() {
    widget.audio.resetVolumes();
    setState(() {
      _master = widget.audio.masterVolume;
      _background = widget.audio.backgroundVolume;
      _feedback = widget.audio.feedbackVolume;
      _intro = widget.audio.introVolume;
      _bell = widget.audio.bellVolume;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Volume'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _slider(
            icon: Icons.speaker,
            label: 'Master',
            value: _master,
            onChanged: widget.audio.setMasterVolume,
          ),
          _slider(
            icon: Icons.music_note,
            label: 'Background',
            value: _background,
            onChanged: widget.audio.setBackgroundVolume,
          ),
          _slider(
            icon: Icons.notifications_active,
            label: 'Feedback',
            value: _feedback,
            onChanged: widget.audio.setFeedbackVolume,
          ),
          _slider(
            icon: Icons.record_voice_over,
            label: 'Intro',
            value: _intro,
            onChanged: widget.audio.setIntroVolume,
          ),
          _slider(
            icon: Icons.ring_volume,
            label: 'End Bell',
            value: _bell,
            onChanged: widget.audio.setBellVolume,
          ),
          const SizedBox(height: 8),
          Text(
            'Feedback covers the reward bowl chimes. Changes apply immediately '
            'and are remembered.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _reset, child: const Text('Reset')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}


class _TargetSettingsDialog extends ConsumerStatefulWidget {
  const _TargetSettingsDialog();

  @override
  ConsumerState<_TargetSettingsDialog> createState() =>
      _TargetSettingsDialogState();
}

class _TargetSettingsDialogState extends ConsumerState<_TargetSettingsDialog> {
  late bool _dynamicAdapt;
  late double _responsiveness;
  late int _percentile;

  @override
  void initState() {
    super.initState();
    final engine = ref.read(feedbackStateProvider.notifier);
    _dynamicAdapt = engine.dynamicAdapt;
    _responsiveness = engine.responsiveness;
    _percentile = ref.read(feedbackStateProvider).baselinePercentile;
  }

  void _reset() {
    final notifier = ref.read(feedbackStateProvider.notifier);
    notifier.resetTargetSettings();
    setState(() {
      _dynamicAdapt = notifier.dynamicAdapt;
      _responsiveness = notifier.responsiveness;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notifier = ref.read(feedbackStateProvider.notifier);
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Target Settings')),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'What do these do?',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const _TargetSettingsInfoDialog(),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Dynamic target'),
            subtitle: const Text('Let the target follow your performance'),
            value: _dynamicAdapt,
            onChanged: (v) {
              setState(() => _dynamicAdapt = v);
              notifier.setDynamicAdapt(v);
            },
          ),
          const SizedBox(height: 8),
          Slider(
            value: _responsiveness,
            onChanged: (v) {
              setState(() => _responsiveness = v);
              notifier.setResponsiveness(v);
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Gentle',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  'Responsive',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          Text(
            'How quickly the target adapts to you',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          Text('Reward threshold', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text(
            'The baseline percentile that sets your target — how strict it '
            'is versus your calibration. 40% (default) keeps the target near '
            'your typical ratio.',
            style: theme.textTheme.bodySmall,
          ),
          _PercentileSlider(
            value: _percentile,
            defaultValue: defaultBaselinePercentile,
            onChanged: (v) {
              setState(() => _percentile = v);
              notifier.selectPercentile(v);
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: _reset, child: const Text('Reset')),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}


class _TargetSettingsInfoDialog extends StatelessWidget {
  const _TargetSettingsInfoDialog();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('What do these do?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Dynamic target', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'When on, the app gently moves your target based on how often '
              'you reach it — it raises it a little when you are often in the '
              'zone, and lowers it (or resets it) if you miss too often. '
              'Turn it off to keep your calibrated target fixed for the whole '
              'session.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text('Gentle ↔ Responsive', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'How quickly the target follows you. Gentle takes small, '
              'cautious steps; Responsive moves faster, forgiving misses '
              'sooner. If the target ever feels unreachable, slide towards '
              'Gentle or turn Dynamic target off — the target is always '
              'kept within reach of your baseline.',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Got it'),
        ),
      ],
    );
  }
}


class _SoundPicker extends StatelessWidget {
  final String current;
  final List<String> sounds;
  const _SoundPicker({required this.current, required this.sounds});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Choose Background Sound'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: sounds.map((s) {
          final sel = s == current;
          return ListTile(
            leading: Icon(
              sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: sel ? theme.colorScheme.primary : null,
            ),
            title: Text(s),
            selected: sel,
            onTap: () => Navigator.of(context).pop(s),
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
class _FeedbackModePicker extends StatelessWidget {
  final FeedbackMode current;
  const _FeedbackModePicker({required this.current});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Choose Feedback Sound'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...FeedbackMode.values.map((m) {
            final sel = m == current;
            return ListTile(
              leading: Icon(
                sel ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: sel ? theme.colorScheme.primary : null,
              ),
              title: Text(m.label),
              subtitle: m == FeedbackMode.bowlChimes
                  ? const Text('Warm chimes when you reach the target')
                  : m == FeedbackMode.rain
                  ? const Text('Rain that quiets as you get closer')
                  : m == FeedbackMode.music
                  ? const Text('Your folder through a reward-driven filter')
                  : const Text('Silent feedback — no reward sound'),
              selected: sel,
              onTap: () => Navigator.of(context).pop(m),
            );
          }),
          const SizedBox(height: 8),
          const Text(
            'Rain and Music become the whole soundscape and replace the '
            'background sound for the session.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// Guardrail gear dialog: scorer engine (AI models or band math), warning
/// sound, and warning threshold. Engine changes apply from the next session;
/// the sound and threshold apply immediately.
class _GuardrailGearDialog extends ConsumerStatefulWidget {
  const _GuardrailGearDialog();

  @override
  ConsumerState<_GuardrailGearDialog> createState() =>
      _GuardrailGearDialogState();
}

class _GuardrailGearDialogState extends ConsumerState<_GuardrailGearDialog> {
  late GuardrailEngine _engine;
  late GuardrailSound _sound;
  late int _threshold;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider);
    _engine = guardrailEngineFromSettings(settings);
    _sound = GuardrailSound.fromName(settings.warningSoundName);
    _threshold = settings.warningThresholdPercentile;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.read(settingsProvider);
    final audio = ref.read(audioServiceProvider);
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Guardrail'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Scorer engine', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            DropdownButtonFormField<GuardrailEngine>(
              initialValue: _engine,
              isExpanded: true,
              items: [
                for (final e in GuardrailEngine.values)
                  DropdownMenuItem(value: e, child: Text(e.label)),
              ],
              onChanged: (v) {
                if (v == null) {
                  return;
                }
                setState(() => _engine = v);
                settings.setGuardrailEngineName(v.name);
              },
            ),
            const SizedBox(height: 4),
            Text(
              _engine.isBandMath
                  ? 'Classical frontal-delta math, no AI model'
                  : 'AI embedding scorer (${_engine.modelKind!.ffId})',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text('Warning sound', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            DropdownButtonFormField<GuardrailSound>(
              initialValue: _sound,
              isExpanded: true,
              items: [
                for (final snd in GuardrailSound.values)
                  DropdownMenuItem(value: snd, child: Text(snd.label)),
              ],
              onChanged: (s) {
                if (s == null) {
                  return;
                }
                setState(() => _sound = s);
                settings.setWarningSoundName(s.name);
                audio.setWarningSound(s);
              },
            ),
            const SizedBox(height: 4),
            Text(
              _sound.playsContinuously
                  ? 'Repeats with a volume ramp while a warning stays active'
                  : _sound == GuardrailSound.none
                      ? 'Warnings stay silent'
                      : 'Plays once per warning',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            Text('Warning threshold', style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(
              'Percentile of the eyes-closed rest baseline that triggers a '
              'warning (75% default). Low = warnings come early and often.',
              style: theme.textTheme.bodySmall,
            ),
            _PercentileSlider(
              value: _threshold,
              defaultValue: defaultWarningThresholdPercentile,
              onChanged: (v) {
                setState(() => _threshold = v);
                settings.setWarningThresholdPercentile(v);
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

void _showGuide(BuildContext context, ProtocolInfo protocol) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${protocol.title} — Details'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(protocol.subtitle),
            const SizedBox(height: 12),
            Text(protocol.guideText),
            const SizedBox(height: 12),
            Text('Algorithm: ${protocol.algorithmDescription}'),
            const SizedBox(height: 4),
            Text('Expected delay: ${protocol.expectedDelay}'),
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

