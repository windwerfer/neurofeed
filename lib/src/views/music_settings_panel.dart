import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/audio/audio_service.dart';
import 'package:muse_ml/src/feedback/session_storage.dart';
import 'package:muse_ml/src/settings.dart';

/// Opens the platform folder picker (SAF tree on Android, directory chooser
/// on desktop) and returns the chosen path/URI, or null when cancelled.
Future<String?> pickMusicFolder() => Platform.isAndroid
    ? SafSessionStorage.pickFolder()
    : getDirectoryPath(
        initialDirectory: null,
        confirmButtonText: 'Choose this folder',
      );

/// Short folder label for tiles: last path segment for SAF URIs, the full
/// path otherwise.
String musicFolderLabel(String? folder) {
  if (folder == null) return 'None';
  if (folder.startsWith('content://')) {
    final idx = folder.lastIndexOf('/');
    return idx >= 0 ? folder.substring(idx + 1) : folder;
  }
  return folder;
}

/// Music-feedback options: the folder that plays through the reward-driven
/// low-pass filter, the cutoff range it sweeps, the mapping polarity, and
/// shuffle. Shared by the Settings → Music feedback card and the feedback
/// session's music bubble, so both always offer the same settings.
class MusicSettingsPanel extends ConsumerStatefulWidget {
  const MusicSettingsPanel({super.key, required this.settings});

  final Settings settings;

  @override
  MusicSettingsPanelState createState() => MusicSettingsPanelState();
}

class MusicSettingsPanelState extends ConsumerState<MusicSettingsPanel> {
  static const double _floorHz = 50.0;
  static const double _ceilingHz = 16000.0;

  static const RangeValues _defaultRange = RangeValues(200, 8000);

  RangeValues _range = const RangeValues(200, 8000);
  bool _invert = false;
  bool _shuffle = false;
  String? _folder;
  int? _trackCount;

  @override
  void initState() {
    super.initState();
    final s = widget.settings;
    RangeValues range = RangeValues(
      s.musicMinCutoffHz.clamp(_floorHz, _ceilingHz),
      s.musicMaxCutoffHz.clamp(_floorHz, _ceilingHz),
    );
    if (range.start > range.end) {
      range = RangeValues(range.end, range.start);
    }
    _range = range;
    _invert = s.musicInvertMapping;
    _shuffle = s.musicShuffle;
    _folder = s.musicFolder;
    _refreshTrackCount();
  }

  Future<void> _refreshTrackCount() async {
    final folder = _folder;
    if (folder == null) {
      setState(() => _trackCount = null);
      return;
    }
    final audio = ref.read(audioServiceProvider);
    final count = await audio.loadMusic();
    if (mounted && _folder == folder) {
      setState(() => _trackCount = count);
    }
  }

  Future<void> _pickFolder() async {
    final folder = await pickMusicFolder();
    if (folder == null) {
      return;
    }
    await widget.settings.setMusicFolder(folder);
    if (!mounted) {
      return;
    }
    setState(() {
      _folder = folder;
      _trackCount = null;
    });
    await _refreshTrackCount();
  }

  Future<void> _clearFolder() async {
    await widget.settings.clearMusicFolder();
    if (!mounted) {
      return;
    }
    setState(() {
      _folder = null;
      _trackCount = null;
    });
  }

  /// Restores the cutoff range, invert mapping and shuffle to their shipped
  /// defaults and persists them.
  void resetToDefaults() {
    setState(() {
      _range = _defaultRange;
      _invert = false;
      _shuffle = false;
    });
    widget.settings.setMusicMinCutoffHz(_defaultRange.start);
    widget.settings.setMusicMaxCutoffHz(_defaultRange.end);
    widget.settings.setMusicInvertMapping(false);
    widget.settings.setMusicShuffle(false);
  }

  String get _folderLabel {
    final folder = _folder;
    if (folder == null) {
      return 'None — pick a folder with music files';
    }
    return musicFolderLabel(folder);
  }

  String? get _trackSuffix =>
      _trackCount == null ? null : ' · $_trackCount track(s)';

  double _hzToLog(double hz) => (math.log(hz / _floorHz) /
          math.log(_ceilingHz / _floorHz))
      .clamp(0.0, 1.0);

  double _logToHz(double t) => (_floorHz * math.pow(_ceilingHz / _floorHz, t))
      .clamp(_floorHz, _ceilingHz);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final low = _range.start;
    final high = _range.end;

    Future<void> setRange(RangeValues logValues) async {
      final hz = RangeValues(
        _logToHz(logValues.start),
        _logToHz(logValues.end),
      );
      setState(() => _range = hz);
      await widget.settings.setMusicMinCutoffHz(hz.start);
      await widget.settings.setMusicMaxCutoffHz(hz.end);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.folder_outlined),
          title: const Text('Music folder'),
          subtitle: Text(
            '$_folderLabel$_trackSuffix',
            style: theme.textTheme.bodySmall,
          ),
          trailing: const Icon(Icons.edit_outlined),
          onTap: _pickFolder,
        ),
        if (_folder != null) ...[
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: _clearFolder,
            icon: const Icon(Icons.delete_outline),
            label: const Text('Clear music folder'),
          ),
        ],
        const Divider(height: 24),
        Text('Cutoff range', style: theme.textTheme.titleSmall),
        const SizedBox(height: 4),
        RangeSlider(
          min: 0,
          max: 1,
          values: RangeValues(_hzToLog(low), _hzToLog(high)),
          divisions: 200,
          labels: RangeLabels(
            '${low.round()} Hz',
            '${high.round()} Hz',
          ),
          onChanged: setRange,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('${low.round()} Hz', style: theme.textTheme.bodySmall),
            Text('${high.round()} Hz', style: theme.textTheme.bodySmall),
          ],
        ),
        const Divider(height: 24),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.swap_vert_outlined),
          title: const Text('Invert mapping'),
          subtitle: Text(
            'High scores close the filter instead of opening it.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          value: _invert,
          onChanged: (on) async {
            setState(() => _invert = on);
            await widget.settings.setMusicInvertMapping(on);
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          secondary: const Icon(Icons.shuffle_outlined),
          title: const Text('Shuffle track order'),
          subtitle: Text(
            'Randomize the play order each session start.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          value: _shuffle,
          onChanged: (on) async {
            setState(() => _shuffle = on);
            await widget.settings.setMusicShuffle(on);
          },
        ),
      ],
    );
  }
}