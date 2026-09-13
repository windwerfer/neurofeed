/// Offset of the first framed payload after the 12-byte `MUSEBIN` header.
const int kMuseBodyHeaderLength = 12;

/// EEG packet timestamp is the first sample; later samples are 1/256 s apart.
const double kEegPacketSlackSeconds = 1.0;

class RecordingIndexEntry {
  const RecordingIndexEntry({required this.elapsedT, required this.fileLength});

  /// Last EEG timestamp in this flush, elapsed seconds from capture start.
  final double elapsedT;

  /// Exclusive end offset of this frame (start of the next).
  final int fileLength;
}

/// Frame-boundary index of an open `tmp_` / `recording_` `.raw`.
///
/// Entries are produced only at [SessionRecorder.flushRaw] boundaries.
class RecordingIndex {
  final List<RecordingIndexEntry> _entries = [];

  List<RecordingIndexEntry> get entries => List.unmodifiable(_entries);

  bool get isEmpty => _entries.isEmpty;

  int get length => _entries.length;

  void clear() => _entries.clear();

  void add({required double elapsedT, required int fileLength}) {
    _entries.add(
      RecordingIndexEntry(elapsedT: elapsedT, fileLength: fileLength),
    );
  }

  /// Inclusive index range of frames overlapping `[startElapsed, endElapsed]`.
  ({int first, int last, int startOffset, int endOffset})? covering(
    double startElapsed,
    double endElapsed,
  ) {
    if (_entries.isEmpty || endElapsed < startElapsed) return null;

    int? first;
    int? last;
    for (var i = 0; i < _entries.length; i++) {
      final frameStartT = i == 0
          ? double.negativeInfinity
          : _entries[i - 1].elapsedT;
      final frameEndT = _entries[i].elapsedT + kEegPacketSlackSeconds;
      if (frameStartT < endElapsed && frameEndT >= startElapsed) {
        first ??= i;
        last = i;
      } else if (first != null) {
        break;
      }
    }
    if (first == null || last == null) return null;

    final startOffset = first == 0
        ? kMuseBodyHeaderLength
        : _entries[first - 1].fileLength;
    return (
      first: first,
      last: last,
      startOffset: startOffset,
      endOffset: _entries[last].fileLength,
    );
  }
}
