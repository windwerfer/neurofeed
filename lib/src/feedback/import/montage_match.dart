import 'package:neurofeed/src/monitor/device_montage.dart';

/// Reference suffixes stripped from EDF labels before montage matching.
const _referenceSuffixes = ['-REF', '-LE', '-AVG'];

/// Canonical upper-case electrode name: drops an `EEG ` prefix and a
/// reference suffix (`-REF`, `-LE`, `-AVG`), case-insensitive.
String normalizeEegLabel(String raw) {
  var s = raw.trim().toUpperCase();
  if (s.startsWith('EEG ')) s = s.substring(4).trim();
  for (final suffix in _referenceSuffixes) {
    if (s.endsWith(suffix)) {
      s = s.substring(0, s.length - suffix.length).trim();
      break;
    }
  }
  return s;
}

/// Reference token from a label suffix (`REF`, `LE`, `AVG`), or null.
String? referenceSuffix(String raw) {
  final s = raw.trim().toUpperCase();
  for (final suffix in _referenceSuffixes) {
    if (s.endsWith(suffix)) return suffix.substring(1);
  }
  return null;
}

/// A supported native montage found in a source file.
class MontageMatch {
  const MontageMatch({
    required this.device,
    required this.labels,
    required this.sourceIndices,
    required this.dropped,
  });

  /// `muse` or `crown`.
  final String device;

  /// Our labels in electrode order (head channels, then AUX).
  final List<String> labels;

  /// Source signal index for each entry of [labels].
  final List<int> sourceIndices;

  /// Source labels not kept.
  final List<String> dropped;

  bool get isSubset => dropped.isNotEmpty;
}

/// Find a supported montage among [sourceLabels]: Muse TP9/AF7/AF8/TP10
/// (plus any AUX1…AUX4 present) or Crown's 8 channels. Muse wins when both
/// are complete. Null when no montage is complete; missing electrodes are
/// never interpolated.
MontageMatch? matchSupportedMontage(List<String> sourceLabels) {
  final byName = <String, int>{};
  for (var i = 0; i < sourceLabels.length; i++) {
    byName.putIfAbsent(normalizeEegLabel(sourceLabels[i]), () => i);
  }
  for (final (device, head) in const [
    ('muse', kMuseElectrodeNames),
    ('crown', kCrownElectrodeNames),
  ]) {
    if (!head.every(byName.containsKey)) continue;
    final labels = [...head];
    if (device == 'muse') {
      for (final aux in kMuseAuxElectrodeNames) {
        if (!byName.containsKey(aux)) break;
        labels.add(aux);
      }
    }
    final indices = [for (final l in labels) byName[l]!];
    final kept = indices.toSet();
    return MontageMatch(
      device: device,
      labels: labels,
      sourceIndices: indices,
      dropped: [
        for (var i = 0; i < sourceLabels.length; i++)
          if (!kept.contains(i)) sourceLabels[i],
      ],
    );
  }
  return null;
}

/// User-facing refusal when a file holds no complete supported montage.
String noSupportedMontageMessage(List<String> sourceLabels) =>
    'No supported headset montage in this file. Import needs all of '
    '${kMuseElectrodeNames.join(', ')} (Muse) or '
    '${kCrownElectrodeNames.join(', ')} (Crown); '
    'missing electrodes are never interpolated. '
    'Found: ${sourceLabels.isEmpty ? 'no EEG channels' : sourceLabels.join(', ')}.';
