import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/feedback/session_store_core.dart';
import 'package:neurofeed/src/views/feedback_history.dart';
import 'package:neurofeed/src/views/settings_view.dart';

SessionSummary _sum(String id, String kind) => SessionSummary(
  id: id,
  kind: kind,
  path: kind == 'recording'
      ? 'recording_$id.neurofeed'
      : 'session_$id.neurofeed',
  metadata: SessionMetadata(
    protocol: kind == 'recording' ? '' : 'drowsiness',
    durationMinutes: 1,
    elapsedSeconds: 60,
    sound: 'Ambient Drone',
    savedAt: '2026-01-01T00:00:00.000Z',
  ),
);

void main() {
  final all = [
    _sum('fb1', 'feedback'),
    _sum('rec1', 'recording'),
    _sum('fb2', 'feedback'),
  ];

  test('filter All returns every summary', () {
    expect(filterHistoryByKind(all, HistoryKindFilter.all).map((s) => s.id), [
      'fb1',
      'rec1',
      'fb2',
    ]);
  });

  test('filter Feedback is kind=feedback only', () {
    final got = filterHistoryByKind(all, HistoryKindFilter.feedback);
    expect(got.map((s) => s.id), ['fb1', 'fb2']);
    expect(got.every((s) => s.kind == 'feedback'), isTrue);
  });

  test('filter Recordings is kind=recording only', () {
    final got = filterHistoryByKind(all, HistoryKindFilter.recordings);
    expect(got.map((s) => s.id), ['rec1']);
    expect(got.single.isRecording, isTrue);
  });

  test('countHistoryContainers splits session_ and recording_ prefixes', () {
    final counted = countHistoryContainers([
      'session_a.neurofeed',
      'recording_b.neurofeed',
      'recording_c.neurofeed',
      'tmp_d.neurofeed',
      'notes.txt',
      'session_e.raw',
    ]);
    expect(counted.sessions, 1);
    expect(counted.recordings, 2);
  });

  test('folder-change dialog copy counts both prefixes', () {
    expect(
      folderChangeMoveBody(3, 2),
      'Move 3 session(s) and 2 recording(s) into the new folder? '
      'Choosing No leaves them in the current folder.',
    );
  });

  test('isHistoryContainerName accepts session_ and recording_ only', () {
    expect(isHistoryContainerName('session_1.neurofeed'), isTrue);
    expect(isHistoryContainerName('recording_2.neurofeed'), isTrue);
    expect(isHistoryContainerName('tmp_3.neurofeed'), isFalse);
    expect(isHistoryContainerName('session_1.raw'), isFalse);
  });
}
