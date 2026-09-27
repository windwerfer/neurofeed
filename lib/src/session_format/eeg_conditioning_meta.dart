import 'dart:typed_data';

import '../rust/api/eeg_conditioning.dart';
import 'models.dart';

/// `device.conditioning` from the Rust conditioning.
SignalConditioning signalConditioningFrom(EegConditioning c) =>
    SignalConditioning(
      highPassHz: c.highPassHz,
      notchQ: c.notchQ,
      notchHz: c.notchHz.toList(),
      notchSource: c.notchSource.name,
    );

/// Rust conditioning from a recording's `device.conditioning`.
EegConditioning eegConditioningFrom(SignalConditioning c) => EegConditioning(
  highPassHz: c.highPassHz,
  notchQ: c.notchQ,
  notchHz: Float64List.fromList(c.notchHz),
  notchSource: NotchSource.values.firstWhere(
    (s) => s.name == c.notchSource,
    orElse: () => NotchSource.undecided,
  ),
);

/// The live stream's conditioning now (the recording lock while one runs).
SignalConditioning liveSignalConditioning() =>
    signalConditioningFrom(liveEegConditioning());
