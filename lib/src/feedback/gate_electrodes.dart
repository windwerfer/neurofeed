/// Muse montage ([DeviceConfig.muse] electrode names).
const List<String> museMontageNames = ['TP9', 'AF7', 'AF8', 'TP10'];

/// Frontal pair used as the Muse gate when a feature has no montage extras.
const List<String> museGateElectrodeNames = ['AF7', 'AF8'];

/// Idle/default gate indices (Muse AF7/AF8) until session start resolves names.
const List<int> defaultGateElectrodes = [1, 2];

/// Gate electrode **names** for this session.
///
/// Reward montage wins; else guard montage if the guard is on. `ai.drowsiness`
/// does not add TP9/TP10 — fall back to [museGateElectrodeNames].
List<String> gateElectrodeNames({
  required bool hasReward,
  required bool guardOn,
  required String guardFeature,
  List<String>? rewardElectrodes,
  List<String>? guardElectrodes,
}) {
  if (hasReward) {
    return rewardElectrodes ?? museGateElectrodeNames;
  }
  if (guardOn) {
    if (guardFeature.startsWith('band.')) {
      return guardElectrodes ?? museGateElectrodeNames;
    }
    return museGateElectrodeNames;
  }
  return museGateElectrodeNames;
}

/// Resolve montage **names** to indices. Unknown names are dropped.
List<int> electrodeIndicesFor(
  List<String> names, {
  required List<String> montageNames,
}) {
  final out = <int>[];
  for (final name in names) {
    final i = montageNames.indexOf(name);
    if (i >= 0) {
      out.add(i);
    }
  }
  return out;
}
