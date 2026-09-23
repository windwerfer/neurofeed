/// Shared pad-quality gate for Monitor Bands dashed "signal unusable" gaps.
///
/// Keep the numeric value in sync with feedback's [atrUsableSignalThreshold]
/// / [signalGoodThreshold] (both 80). Monitor stays free of a feedback import.
const double kUsableSignalThreshold = 80.0;

/// True when [quality] reports a usable contact for [electrode].
///
/// Missing quality (null / short list) is treated as unusable — same as
/// feedback's pad autodrop.
bool padSignalUsable(List<double>? quality, int electrode) {
  if (quality == null || electrode < 0 || electrode >= quality.length) {
    return false;
  }
  return quality[electrode] >= kUsableSignalThreshold;
}

/// Whether a band sample for [electrode] should be stamped sticky-unusable
/// at append time.
///
/// - Per electrode: pad quality below [kUsableSignalThreshold].
/// - If [selectedElectrodes] is non-empty and **none** of them are clean,
///   every **selected** electrode's appended samples are stamped (so all
///   shown band series dash). Non-selected electrodes are only stamped when
///   their own pad is bad.
bool shouldStampBandUnusable({
  required int electrode,
  required List<double>? quality,
  Set<int> selectedElectrodes = const {},
}) {
  final electrodeBad = !padSignalUsable(quality, electrode);
  if (selectedElectrodes.isEmpty) return electrodeBad;
  final anyCleanSelected =
      selectedElectrodes.any((e) => padSignalUsable(quality, e));
  if (!anyCleanSelected && selectedElectrodes.contains(electrode)) {
    return true;
  }
  return electrodeBad;
}
