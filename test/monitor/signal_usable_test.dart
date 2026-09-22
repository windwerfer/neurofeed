import 'package:flutter_test/flutter_test.dart';
import 'package:neurofeed/src/monitor/signal_usable.dart';

void main() {
  test('threshold matches feedback usable pad gate', () {
    expect(kUsableSignalThreshold, 80.0);
  });

  test('padSignalUsable requires score >= 80', () {
    expect(padSignalUsable([79.9, 80.0, 90], 0), isFalse);
    expect(padSignalUsable([79.9, 80.0, 90], 1), isTrue);
    expect(padSignalUsable([79.9, 80.0, 90], 2), isTrue);
  });

  test('padSignalUsable treats null or short list as unusable', () {
    expect(padSignalUsable(null, 0), isFalse);
    expect(padSignalUsable([90], 1), isFalse);
    expect(padSignalUsable([90], -1), isFalse);
  });

  test('shouldStampBandUnusable stamps bad pad', () {
    expect(
      shouldStampBandUnusable(
        electrode: 0,
        quality: [50, 90, 90, 90],
        selectedElectrodes: {0, 1},
      ),
      isTrue,
    );
    expect(
      shouldStampBandUnusable(
        electrode: 1,
        quality: [50, 90, 90, 90],
        selectedElectrodes: {0, 1},
      ),
      isFalse,
    );
  });

  test('all selected dirty stamps every selected electrode', () {
    const q = [10.0, 20.0, 90.0, 90.0];
    expect(
      shouldStampBandUnusable(
        electrode: 0,
        quality: q,
        selectedElectrodes: {0, 1},
      ),
      isTrue,
    );
    expect(
      shouldStampBandUnusable(
        electrode: 1,
        quality: q,
        selectedElectrodes: {0, 1},
      ),
      isTrue,
    );
    // Non-selected clean pad is not stamped by the all-dirty rule.
    expect(
      shouldStampBandUnusable(
        electrode: 2,
        quality: q,
        selectedElectrodes: {0, 1},
      ),
      isFalse,
    );
  });

  test('empty selection only uses per-pad quality', () {
    expect(
      shouldStampBandUnusable(
        electrode: 0,
        quality: [90, 10],
        selectedElectrodes: {},
      ),
      isFalse,
    );
    expect(
      shouldStampBandUnusable(
        electrode: 1,
        quality: [90, 10],
        selectedElectrodes: {},
      ),
      isTrue,
    );
  });
}
