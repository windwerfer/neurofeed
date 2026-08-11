import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Default warning threshold for the REVE sleep guardrail: the percent rank of
/// the eyes-closed (rest) sleep-direction distribution above which a warning
/// fires. Exposed on the session intro page for the drowsiness protocol.
const int defaultWarningThresholdPercentile = 75;

enum AppView {
  feedback,
  feedbackHistory,
  bands,
  rawEeg,
  spectrogram,
  psd,
  settings,
}

/// Data streams that can be persisted into a session file. Each maps to one
/// (or more) `.muse` event types. Future devices (e.g. an 8-electrode Crown)
/// add streams here without changing the file container format — the body is
/// a self-describing list of typed events.
enum RecordingStream {
  eeg,
  bands,
  ppg,
  pulse,
  imu,
  movement,
  peakAlpha,
  telemetry,
}

const Map<AppView, String> _viewNames = {
  AppView.feedback: 'feedback',
  AppView.feedbackHistory: 'feedbackHistory',
  AppView.bands: 'bands',
  AppView.rawEeg: 'rawEeg',
  AppView.spectrogram: 'spectrogram',
  AppView.psd: 'psd',
  AppView.settings: 'settings',
};

AppView _viewFromName(String? name) {
  switch (name) {
    case 'feedback':
      return AppView.feedback;
    case 'feedbackHistory':
      return AppView.feedbackHistory;
    case 'bands':
      return AppView.bands;
    case 'rawEeg':
      return AppView.rawEeg;
    case 'spectrogram':
      return AppView.spectrogram;
    case 'psd':
      return AppView.psd;
    case 'settings':
      return AppView.settings;
    default:
      return AppView.feedback;
  }
}

/// Persistent app settings backed by SharedPreferences.
class Settings {
  Settings._(this._prefs);

  static const String _lastViewKey = 'last_view';
  static const String _lastDeviceKey = 'last_device_id';
  static const String _masterVolumeKey = 'master_volume';
  static const String _backgroundVolumeKey = 'background_volume';
  static const String _feedbackVolumeKey = 'feedback_volume';
  static const String _introVolumeKey = 'intro_volume';
  static const String _bellVolumeKey = 'bell_volume';
  static const String _dynamicAdaptKey = 'dynamic_adapt';
  static const String _responsivenessKey = 'responsiveness';
  static const String _soundNameKey = 'sound_name';
  static const String _durationMinutesKey = 'duration_minutes';
  static const String _sessionFolderKey = 'session_folder';
  static const String _recordStreamsKey = 'record_streams';
  static const String _eyeMarkersKey = 'gesture_eye_markers';
  static const String _markersInFeedbackKey = 'gesture_markers_in_feedback';
  static const String _warningThresholdPercentileKey =
      'reve_warning_threshold_percentile';
  static const String _modelKindKey = 'model_kind';

  final SharedPreferences _prefs;

  static Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return Settings._(prefs);
  }

  AppView get lastView => _viewFromName(_prefs.getString(_lastViewKey));

  Future<void> setLastView(AppView view) =>
      _prefs.setString(_lastViewKey, _viewNames[view]!);

  String? get lastDeviceId => _prefs.getString(_lastDeviceKey);

  Future<void> setLastDeviceId(String id) =>
      _prefs.setString(_lastDeviceKey, id);

  double? get masterVolume => _prefs.getDouble(_masterVolumeKey);

  Future<void> setMasterVolume(double value) =>
      _prefs.setDouble(_masterVolumeKey, value);

  double? get backgroundVolume => _prefs.getDouble(_backgroundVolumeKey);

  Future<void> setBackgroundVolume(double value) =>
      _prefs.setDouble(_backgroundVolumeKey, value);

  double? get feedbackVolume => _prefs.getDouble(_feedbackVolumeKey);

  Future<void> setFeedbackVolume(double value) =>
      _prefs.setDouble(_feedbackVolumeKey, value);

  double? get introVolume => _prefs.getDouble(_introVolumeKey);

  Future<void> setIntroVolume(double value) =>
      _prefs.setDouble(_introVolumeKey, value);

  double? get bellVolume => _prefs.getDouble(_bellVolumeKey);

  Future<void> setBellVolume(double value) =>
      _prefs.setDouble(_bellVolumeKey, value);

  bool? get dynamicAdapt => _prefs.getBool(_dynamicAdaptKey);

  Future<void> setDynamicAdapt(bool value) =>
      _prefs.setBool(_dynamicAdaptKey, value);

  double? get responsiveness => _prefs.getDouble(_responsivenessKey);

  Future<void> setResponsiveness(double value) =>
      _prefs.setDouble(_responsivenessKey, value);

  String? get soundName => _prefs.getString(_soundNameKey);

  Future<void> setSoundName(String value) =>
      _prefs.setString(_soundNameKey, value);

  int? get durationMinutes => _prefs.getInt(_durationMinutesKey);

  Future<void> setDurationMinutes(int value) =>
      _prefs.setInt(_durationMinutesKey, value);

  /// History folder. A `content://` value is an Android SAF tree URI; any
  /// other value is a real filesystem path. Null means "use the default".
  String? get sessionFolder => _prefs.getString(_sessionFolderKey);

  Future<void> setSessionFolder(String value) =>
      _prefs.setString(_sessionFolderKey, value);

  Future<void> clearSessionFolder() => _prefs.remove(_sessionFolderKey);

  /// Streams saved into each session file. Defaults to all streams
  /// (backward compatible with files recorded before this option existed).
  Set<RecordingStream> get recordStreams {
    final stored = _prefs.getStringList(_recordStreamsKey);
    if (stored == null) {
      return RecordingStream.values.toSet();
    }
    final set = stored
        .map(
          (name) =>
              RecordingStream.values.where((s) => s.name == name).firstOrNull,
        )
        .whereType<RecordingStream>()
        .toSet();
    return set.isEmpty ? RecordingStream.values.toSet() : set;
  }

  Future<void> setRecordStreams(Set<RecordingStream> streams) => _prefs
      .setStringList(_recordStreamsKey, streams.map((s) => s.name).toList());

  /// Whether eye up/down movements produce gesture markers. Off by default —
  /// the eye track is experimental on a 4-electrode Muse.
  bool get eyeMarkersEnabled => _prefs.getBool(_eyeMarkersKey) ?? false;

  Future<void> setEyeMarkersEnabled(bool value) =>
      _prefs.setBool(_eyeMarkersKey, value);

  /// Whether gesture markers (double blink / double clench / eye) are recorded
  /// as a track in saved feedback sessions. Independent of *detection* — when
  /// false the live detector still runs but nothing is persisted.
  bool get markersInFeedbackEnabled =>
      _prefs.getBool(_markersInFeedbackKey) ?? true;

  Future<void> setMarkersInFeedbackEnabled(bool value) =>
      _prefs.setBool(_markersInFeedbackKey, value);

  /// Percentile of the eyes-closed rest sleep-direction distribution above
  /// which the REVE sleep-guardrail warning fires (see
  /// [defaultWarningThresholdPercentile]).
  int get warningThresholdPercentile =>
      _prefs.getInt(_warningThresholdPercentileKey) ??
      defaultWarningThresholdPercentile;

  Future<void> setWarningThresholdPercentile(int value) =>
      _prefs.setInt(_warningThresholdPercentileKey, value);

  /// Which guardrail foundation model is selected (see `ModelKind` in
  /// `lib/src/reve/models.dart`). Stored as the enum name; null means "use the
  /// default (LUNA Large)".
  String? get modelKindName => _prefs.getString(_modelKindKey);

  Future<void> setModelKindName(String value) =>
      _prefs.setString(_modelKindKey, value);
}

/// Provides the app-wide [Settings] instance. Loaded in `main()` and
/// overridden there with the concrete instance; [audioServiceProvider]
/// depends on it to restore persisted volumes.
final settingsProvider = Provider<Settings>(
  (ref) =>
      throw UnimplementedError('settingsProvider must be overridden in main()'),
);
