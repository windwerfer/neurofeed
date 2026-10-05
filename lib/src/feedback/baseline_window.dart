import 'package:neurofeed/src/feedback/feedback_phase.dart';

class BaselineWindow {
  const BaselineWindow({
    this.started,
    this.validSeconds = 0,
    this.targetValidSeconds = calibrationBaselineValidSeconds,
    this.maxWallSeconds = calibrationBaselineMaxSeconds,
  });

  final DateTime? started;
  final int validSeconds;
  final int targetValidSeconds;
  final int maxWallSeconds;

  int get secondsLeft {
    final left = targetValidSeconds - validSeconds;
    if (left < 0) return 0;
    if (left > targetValidSeconds) return targetValidSeconds;
    return left;
  }

  bool finishedAt(DateTime now) {
    if (validSeconds >= targetValidSeconds) return true;
    final start = started;
    if (start == null) return false;
    return now.difference(start) >= Duration(seconds: maxWallSeconds);
  }

  int wallSecondsAt(DateTime now) {
    final start = started;
    if (start == null) return 0;
    final ms = now.difference(start).inMilliseconds;
    if (ms <= 0) return 0;
    return (ms / 1000).round();
  }

  BaselineWindow start(DateTime now) => BaselineWindow(
    started: now,
    targetValidSeconds: targetValidSeconds,
    maxWallSeconds: maxWallSeconds,
  );

  BaselineWindow recordAccepted() => BaselineWindow(
    started: started,
    validSeconds: validSeconds + 1,
    targetValidSeconds: targetValidSeconds,
    maxWallSeconds: maxWallSeconds,
  );
}

class _SourceSecond {
  _SourceSecond(this.accepted);

  final bool accepted;
  final Set<String> stored = {};
}

class BaselineFrameClock {
  final Map<int, _SourceSecond> _seconds = {};

  bool contains(int sourceSecond) => _seconds.containsKey(sourceSecond);

  ({bool opened, bool accepted, bool store}) take({
    required int sourceSecond,
    required String featureId,
    required bool accept,
  }) {
    final existing = _seconds[sourceSecond];
    if (existing == null) {
      final frame = _SourceSecond(accept);
      if (accept) frame.stored.add(featureId);
      _seconds[sourceSecond] = frame;
      return (opened: true, accepted: accept, store: accept);
    }
    if (!existing.accepted || existing.stored.contains(featureId)) {
      return (opened: false, accepted: existing.accepted, store: false);
    }
    existing.stored.add(featureId);
    return (opened: false, accepted: true, store: true);
  }

  void reset() {
    _seconds.clear();
  }
}
