import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:muse_ml/src/monitor/cache/stft_ring.dart';
import 'package:muse_ml/src/monitor/cache/sweep_buffer.dart';
import 'package:muse_ml/src/monitor/cache/sweep_mean.dart';
import 'package:muse_ml/src/monitor/dsp.dart';
import 'package:muse_ml/src/rust/api/muse.dart';

EegDto _eeg(int electrode, List<double> samples, {double ts = 0}) => EegDto(
  index: 0,
  electrode: electrode,
  timestamp: ts,
  samples: Float64List.fromList(samples),
);

const double _hopSec = kStftHopSamples / SweepBuffer.sampleRate;
const double _windowSec = 2;

void _appendSine(
  SweepBuffer buf, {
  required int electrode,
  required int count,
  required double hz,
}) {
  final origin = buf.channelCount(electrode);
  var i = 0;
  while (i < count) {
    final take = math.min(256, count - i);
    buf.append(
      _eeg(electrode, [
        for (var k = 0; k < take; k++)
          math.sin(
            2 * math.pi * hz * (origin + i + k) / SweepBuffer.sampleRate,
          ),
      ]),
    );
    i += take;
  }
}

double _newest(SweepBuffer buf) =>
    (buf.sampleCount - 1) / SweepBuffer.sampleRate;

List<StftColumn> _stftColumns(
  SweepBuffer buf,
  Set<int> electrodes,
  double start,
  double end,
) {
  final pad = kDefaultFftN / SweepBuffer.sampleRate;
  final samples = meanEegWindow(
    buffer: buf,
    electrodes: electrodes,
    startElapsed: start - pad,
    endElapsed: end,
    newestElapsed: _newest(buf),
  );
  return stftColumns(samples, startElapsed: start - pad);
}

void _expectMatch(List<StftColumn> a, List<StftColumn> b) {
  expect(a.length, b.length);
  for (var i = 0; i < a.length; i++) {
    expect(a[i].elapsed, closeTo(b[i].elapsed, 1e-9));
    expect(a[i].db.length, b[i].db.length);
    for (var k = 0; k < a[i].db.length; k++) {
      expect(a[i].db[k], closeTo(b[i].db[k], 1e-9));
    }
  }
}

void main() {
  test('N hops of a sine match stftColumns; one extra hop slides the ring', () {
    final buf = SweepBuffer();
    const hops = 8;
    final samples =
        ((hops * _hopSec) + kDefaultFftN / SweepBuffer.sampleRate) *
        SweepBuffer.sampleRate;
    _appendSine(buf, electrode: 0, count: samples.round(), hz: 10);

    var newest = _newest(buf);
    var start = newest - _windowSec;
    var end = newest;
    final ring = StftRing();
    final cols = ring.columnsFor(
      buffer: buf,
      electrodes: {0},
      start: start,
      end: end,
      newest: newest,
    );
    expect(cols, isNotEmpty);
    _expectMatch(cols, _stftColumns(buf, {0}, start, end));

    final first = cols.first;
    final second = cols[1];
    final last = cols.last;
    final count = cols.length;

    _appendSine(buf, electrode: 0, count: kStftHopSamples, hz: 10);
    newest = _newest(buf);
    start += _hopSec;
    end += _hopSec;
    final slid = ring.columnsFor(
      buffer: buf,
      electrodes: {0},
      start: start,
      end: end,
      newest: newest,
    );
    expect(slid, hasLength(count));
    expect(identical(slid.first, second), isTrue);
    expect(slid.contains(first), isFalse);
    expect(slid.where((c) => !cols.contains(c)), hasLength(1));
    expect(identical(slid.last, last), isFalse);
    _expectMatch(slid, _stftColumns(buf, {0}, start, end));
    _expectMatch(
      slid,
      StftRing().columnsFor(
        buffer: buf,
        electrodes: {0},
        start: start,
        end: end,
        newest: newest,
      ),
    );
  });

  test('electrode-set change forces a full rebuild', () {
    final buf = SweepBuffer();
    final n =
        ((_windowSec + kDefaultFftN / SweepBuffer.sampleRate) *
                SweepBuffer.sampleRate)
            .round();
    _appendSine(buf, electrode: 0, count: n, hz: 10);
    _appendSine(buf, electrode: 1, count: n, hz: 20);
    final newest = _newest(buf);
    final start = newest - _windowSec;
    final end = newest;

    final ring = StftRing();
    final one = ring.columnsFor(
      buffer: buf,
      electrodes: {0},
      start: start,
      end: end,
      newest: newest,
    );
    expect(one, isNotEmpty);
    final oneIdentity = one;

    final two = ring.columnsFor(
      buffer: buf,
      electrodes: {0, 1},
      start: start,
      end: end,
      newest: newest,
    );
    expect(identical(two, oneIdentity), isFalse);
    expect(identical(two.first, one.first), isFalse);

    final fresh = StftRing().columnsFor(
      buffer: buf,
      electrodes: {0, 1},
      start: start,
      end: end,
      newest: newest,
    );
    _expectMatch(two, fresh);
    _expectMatch(two, _stftColumns(buf, {0, 1}, start, end));
  });
}
