import 'package:neurofeed/src/feedback/import/import_types.dart';
import 'package:neurofeed/src/session_format/models.dart';

/// What an import keeps and what it loses, for the pre-save dialog.
({List<String> kept, List<String> lost}) importSummary(ImportResult result) {
  final p = result.provenance;
  final device = result.metadataJson['device'];
  final labels = device is Map && device['channelLabels'] is List
      ? (device['channelLabels'] as List).whereType<String>().toList()
      : const <String>[];
  final duration = result.metadataJson['durationS'];
  return (
    kept: [
      'Channels: ${labels.join(', ')}',
      p.rawPresent ? 'RAW EEG at 256 Hz' : 'Bands only (no RAW EEG)',
      if (duration is num) 'Duration: ${_duration(duration.round())}',
    ],
    lost: p.warnings,
  );
}

/// One-line export notice for a recording whose import was lossy; null
/// when the recording is native or its import lost nothing.
String? importLossNotice(ImportProvenance? p) {
  if (p == null || !p.lossy) return null;
  final source = p.sourceFileName.isNotEmpty ? p.sourceFileName : p.sourceFormat;
  final losses = [
    if (p.droppedChannels.isNotEmpty)
      'dropped ${p.droppedChannels.length} channel(s)',
    if (p.resampled && p.originalRateHz != null)
      'resampled ${p.originalRateHz!.round()}→256 Hz',
    if (!p.rawPresent) 'no RAW EEG (bands only)',
  ];
  return 'Imported from $source — already lost on import: '
      '${losses.isEmpty ? 'see import notes' : losses.join(', ')}';
}

String _duration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return m == 0 ? '$s s' : '$m min ${s.toString().padLeft(2, '0')} s';
}
