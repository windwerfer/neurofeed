enum FeedbackPhase { idle, calibrating, playing, paused, interrupted, ended }

enum FeedbackInterruptKind { disconnect, badSignal }

const double signalGoodThreshold = 80.0;
const double signalCriticalThreshold = 40.0;
const int badSignalPauseSeconds = 10;
const int interruptionGraceSeconds = 10;

/// The calibration gate requires all pads green for this long before the
/// baseline starts (guards against a transient blink/loose contact).
const int greenStableSeconds = 3;

/// If one pad has not gone green for this long while the others are green, we
/// assume that pad is faulty and surface the continue-anyway fallback.
const int faultyPadSeconds = 20;

const int calibrationBaselineSeconds = 50;
const int adaptIntervalSeconds = 30;
const Duration movementBuffer = Duration(seconds: 1);
const Duration calibrationAudioTimeout = Duration(seconds: 15);
const int defaultBaselinePercentile = 40;
const int minRecalibrateSeconds = 60;
const int minRecalibrateSamples = 30;
