import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/cache/recording_index.dart';

void main() {
  test('empty index covers nothing', () {
    expect(RecordingIndex().covering(0, 10), isNull);
  });

  test('first frame starts at header length 12', () {
    final index = RecordingIndex()..add(elapsedT: 1.0, fileLength: 80);
    final span = index.covering(0, 2);
    expect(span, isNotNull);
    expect(span!.startOffset, kMuseBodyHeaderLength);
    expect(span.endOffset, 80);
    expect(span.first, 0);
    expect(span.last, 0);
  });

  test('window on a later frame starts at previous fileLength', () {
    final index = RecordingIndex()
      ..add(elapsedT: 1.0, fileLength: 80)
      ..add(elapsedT: 10.0, fileLength: 200);
    final span = index.covering(8, 12);
    expect(span, isNotNull);
    expect(span!.startOffset, 80);
    expect(span.endOffset, 200);
    expect(span.first, 1);
    expect(span.last, 1);
  });

  test('window spanning two frames reads both complete frames', () {
    final index = RecordingIndex()
      ..add(elapsedT: 1.0, fileLength: 80)
      ..add(elapsedT: 10.0, fileLength: 200);
    final span = index.covering(0, 12);
    expect(span!.startOffset, kMuseBodyHeaderLength);
    expect(span.endOffset, 200);
    expect(span.first, 0);
    expect(span.last, 1);
  });

  test('query after last frame is empty', () {
    final index = RecordingIndex()..add(elapsedT: 1.0, fileLength: 80);
    expect(index.covering(5, 10), isNull);
  });

  test('clear empties the index', () {
    final index = RecordingIndex()..add(elapsedT: 1.0, fileLength: 80);
    expect(index.isEmpty, isFalse);
    index.clear();
    expect(index.isEmpty, isTrue);
    expect(index.covering(0, 2), isNull);
  });
}
