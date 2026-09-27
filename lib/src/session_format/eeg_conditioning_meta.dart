import '../rust/api/eeg_conditioning.dart';
import 'models.dart';

/// `device.conditioning` for a recording that started at [startMs]. Every
/// mains decision of the connection is listed; one made before the recording
/// started has a negative onset. No decision yet = both mains pairs notched.
SignalConditioning signalConditioningFrom(
  EegConditioning c, {
  required int startMs,
}) => SignalConditioning(
  highPassHz: c.highPassHz,
  notchQ: c.notchQ,
  notchHz: c.decisions.isEmpty ? null : c.decisions.last.notchHz,
  notchChanges: [
    for (final d in c.decisions)
      NotchChange(
        onset: (d.timestampMs - startMs) / 1000.0,
        notchHz: d.notchHz,
      ),
  ],
);

/// The live connection's conditioning, relative to a recording start.
SignalConditioning liveSignalConditioning({required int startMs}) =>
    signalConditioningFrom(liveEegConditioning(), startMs: startMs);
