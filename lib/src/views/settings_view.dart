import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
import 'package:muse_ml/src/reve/reve_card.dart';
import 'package:muse_ml/src/settings.dart';

/// Settings view — session storage folder + session recording options.
class SettingsView extends ConsumerStatefulWidget {
  const SettingsView({super.key});

  @override
  ConsumerState<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends ConsumerState<SettingsView> {
  Future<String?> _pickFolder() async {
    if (Platform.isAndroid) {
      return SafSessionStorage.pickFolder();
    }
    final dir = await getDirectoryPath(
      initialDirectory: null,
      confirmButtonText: 'Choose this folder',
    );
    return dir;
  }

  Future<void> _applyFolder(
    WidgetRef ref,
    String? folder, {
    required bool migrate,
  }) async {
    if (folder == null) {
      return;
    }
    final settings = ref.read(settingsProvider);
    final current = ref.read(sessionStorageProvider);
    final oldStorage = current.valueOrNull;

    if (migrate && oldStorage != null) {
      final store = await ref.read(sessionStoreProvider.future);
      await store.moveAllTo(resolveStorageFromFolder(folder));
    }

    await settings.setSessionFolder(folder);
    ref.invalidate(sessionStorageProvider);
    ref.invalidate(sessionStoreProvider);
    ref.invalidate(sessionListProvider);
  }

  Future<void> _resetFolder(WidgetRef ref) async {
    final settings = ref.read(settingsProvider);
    await settings.clearSessionFolder();
    ref.invalidate(sessionStorageProvider);
    ref.invalidate(sessionStoreProvider);
    ref.invalidate(sessionListProvider);
  }

  Future<void> _onPickFolder(
    WidgetRef ref,
    BuildContext context,
    Settings settings,
  ) async {
    final folder = await _pickFolder();
    if (folder == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }
    final current = ref.read(sessionStorageProvider);
    final existing = current.valueOrNull;
    final count = existing == null
        ? 0
        : (await existing.listFiles())
              .where(
                (n) => n.startsWith('session_') && n.endsWith('.muse.feedback'),
              )
              .length;
    if (!context.mounted) {
      return;
    }
    final migrate = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Copy existing sessions?'),
        content: Text(
          count > 0
              ? 'Move $count existing session(s) into the new folder? '
                    'Choosing No leaves them in the current folder.'
              : 'Choose this folder for saved sessions?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(count > 0 ? 'Copy' : 'Yes'),
          ),
        ],
      ),
    );
    if (migrate != null) {
      await _applyFolder(ref, folder, migrate: migrate);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final storage = ref.watch(sessionStorageProvider);
    final folder = settings.sessionFolder;
    final streams = settings.recordStreams;

    Future<void> toggle(RecordingStream stream, bool on) async {
      final next = {...streams};
      if (on) {
        next.add(stream);
      } else {
        next.remove(stream);
      }
      await settings.setRecordStreams(next);
      if (mounted) {
        setState(() {});
      }
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Settings', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 16),
        Card(
          color: theme.colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_outlined),
                  title: const Text('Save feedback to folder'),
                  subtitle: storage.maybeWhen(
                    data: (s) =>
                        Text(s.displayName, style: theme.textTheme.bodySmall),
                    orElse: () => const Text('Resolving storage…'),
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _onPickFolder(ref, context, settings),
                ),
                const Divider(height: 24),
                Text(
                  folder == null
                      ? 'Using the default folder. Tap to choose where session '
                            'history is stored.'
                      : 'Sessions are saved to the folder above. Cache/temp '
                            'files live in a hidden .cache subfolder.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (folder != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => _resetFolder(ref),
                    icon: const Icon(Icons.autorenew),
                    label: const Text('Reset to default folder'),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _RecordingCard(streams: streams, onToggle: toggle),
        const SizedBox(height: 16),
        _GesturesCard(settings: settings),
        const SizedBox(height: 16),
        _GuardrailCard(settings: settings),
        const SizedBox(height: 16),
        const AiEngineCard(),
      ],
    );
  }
}

/// Gesture detection options: eye up/down markers (experimental) and whether
/// gesture markers are persisted into saved feedback sessions.
class _GesturesCard extends StatefulWidget {
  const _GesturesCard({required this.settings});

  final Settings settings;

  @override
  State<_GesturesCard> createState() => _GesturesCardState();
}

class _GesturesCardState extends State<_GesturesCard> {
  late bool _eye;
  late bool _persist;

  @override
  void initState() {
    super.initState();
    _eye = widget.settings.eyeMarkersEnabled;
    _persist = widget.settings.markersInFeedbackEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.touch_app_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('Gesture markers', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Blink twice, clench twice, or look up/down to drop a marker '
              'during a feedback session. Detection runs in Rust at 1 Hz.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.visibility_outlined),
              title: const Text('Eye up/down markers'),
              subtitle: Text(
                'Experimental on a 4-electrode Muse — eye direction is '
                'estimated from frontal-vs-rear EEG. Off by default.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              value: _eye,
              onChanged: (on) async {
                setState(() => _eye = on);
                await widget.settings.setEyeMarkersEnabled(on);
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.bookmark_add_outlined),
              title: const Text('Add markers to feedback sessions'),
              subtitle: Text(
                'Persist double-blink / double-clench / eye markers in the '
                'session metadata (.muse.feedback). Detection still runs when '
                'off, markers are just not saved.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              value: _persist,
              onChanged: (on) async {
                setState(() => _persist = on);
                await widget.settings.setMarkersInFeedbackEnabled(on);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Per-protocol AI sleep-guardrail toggle. One switch per protocol whose spec
/// offers the guardrail layer ([ProtocolInfo.aiSleepGuardrail]); protocols
/// without the layer run the plain ratio engine regardless.
class _GuardrailCard extends StatefulWidget {
  const _GuardrailCard({required this.settings});

  final Settings settings;

  @override
  State<_GuardrailCard> createState() => _GuardrailCardState();
}

class _GuardrailCardState extends State<_GuardrailCard> {
  late final Map<ProtocolType, bool> _enabled = {
    for (final p in ProtocolInfo.all)
      if (p.aiSleepGuardrail)
        p.type: widget.settings.guardrailEnabledFor(p.type),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.bedtime_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('AI sleep guardrail', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'The on-device layer watches for the EEG signature of actually '
              'falling asleep and plays a soft warning chime. It is a cue, '
              'never a reward or a safety device — and it only runs when a '
              'model is installed (card below).',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 24),
            for (final p in ProtocolInfo.all)
              if (p.aiSleepGuardrail)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    Icons.psychology_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  title: Text(p.title),
                  subtitle: Text(
                    'Off: runs the plain Alpha-over-Theta ratio engine without '
                    'warnings.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  value: _enabled[p.type] ?? true,
                  onChanged: (on) async {
                    setState(() => _enabled[p.type] = on);
                    await widget.settings.setGuardrailEnabled(p.type, on);
                  },
                ),
          ],
        ),
      ),
    );
  }
}

/// Which sensor data streams get persisted into each session file.
class _RecordingCard extends StatelessWidget {
  const _RecordingCard({required this.streams, required this.onToggle});

  final Set<RecordingStream> streams;
  final void Function(RecordingStream stream, bool on) onToggle;

  static const Map<RecordingStream, (String, String)> _labels = {
    RecordingStream.eeg: (
      'Raw EEG samples',
      'Full-resolution waveforms per electrode (largest data)',
    ),
    RecordingStream.bands: (
      'Band powers',
      'Delta/theta/alpha/beta/gamma power per channel (ATR uses this)',
    ),
    RecordingStream.ppg: (
      'PPG optical / fNIRS',
      'Raw light channels (incl. Athena fNIRS optical data)',
    ),
    RecordingStream.pulse: (
      'Pulse / heart rate',
      'BPM estimate derived from PPG',
    ),
    RecordingStream.imu: (
      'Accelerometer + gyroscope',
      'Raw 3-axis motion and gyro samples',
    ),
    RecordingStream.movement: (
      'Movement score',
      'Derived motion magnitude from accelerometer',
    ),
    RecordingStream.peakAlpha: (
      'Peak alpha',
      'Dominant alpha frequency/power (parabolic-interpolated)',
    ),
    RecordingStream.telemetry: (
      'Telemetry',
      'Battery, voltage, temperature snapshots',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.dataset_outlined,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('Session recording', style: theme.textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Choose which data is included when a session is saved. Streams '
              'are stored per-type in the file, so disabled ones simply leave '
              'smaller sessions.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 24),
            for (final entry in _labels.entries)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.multiline_chart_outlined),
                title: Text(entry.value.$1),
                subtitle: Text(
                  entry.value.$2,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                value: streams.contains(entry.key),
                onChanged: (on) => onToggle(entry.key, on),
              ),
            const Divider(height: 24),
            Text(
              'Note: blood-oxygen (SpO2) and fNIRS metrics (HbO/HbR) are not '
              'currently derived — the raw optical light channels above are '
              'what the sensor provides, on both Classic and Athena firmware.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
