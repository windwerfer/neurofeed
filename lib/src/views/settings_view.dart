import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/feedback/session_store.dart';
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
        : (await existing.listFiles()).where(
            (n) => n.startsWith('session_') && n.endsWith('.muse.feedback'),
          ).length;
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
                    data: (s) => Text(
                      s.displayName,
                      style: theme.textTheme.bodySmall,
                    ),
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
        _RecordingCard(
          streams: streams,
          onToggle: toggle,
        ),
      ],
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
                Icon(Icons.dataset_outlined,
                    color: theme.colorScheme.onSurfaceVariant),
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