import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/protocol.dart';
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
  streaming,
  settings,
}

/// What rewards during a feedback session: bowl chimes on-target (classic),
/// a rain loop whose intensity follows the reward, the music folder through a
/// low-pass filter, or nothing. Where [soundName] is the *background* layer,
/// this is the *feedback* layer — selecting Rain or Music also suppresses the
/// background (the modulated loop is the whole soundscape).
enum FeedbackMode {
  bowlChimes,
  rain,
  music,
  binaural,
  none;

  String get label => switch (this) {
    FeedbackMode.bowlChimes => 'Bowl chimes',
    FeedbackMode.rain => 'Rain',
    FeedbackMode.music => 'Music',
    FeedbackMode.binaural => 'Binaural Beats',
    FeedbackMode.none => 'None',
  };
}

FeedbackMode feedbackModeFromName(String? name) =>
    FeedbackMode.values.where((m) => m.name == name).firstOrNull ??
    FeedbackMode.bowlChimes;

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
  AppView.streaming: 'streaming',
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
    case 'streaming':
      return AppView.streaming;
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
  static const String _feedbackModeKey = 'feedback_mode';
  static const String _durationMinutesKey = 'duration_minutes';
  static const String _sessionFolderKey = 'session_folder';
  static const String _recordStreamsKey = 'record_streams';
  static const String _eyeMarkersKey = 'gesture_eye_markers';
  static const String _markersInFeedbackKey = 'gesture_markers_in_feedback';
  static const String _warningThresholdPercentileKey =
      'reve_warning_threshold_percentile';
  static const String _modelKindKey = 'model_kind';
  static const String _guardrailEngineKey = 'guardrail_engine';
  static const String _warningSoundKey = 'warning_sound';
  static const String _lastCustomMinutesKey = 'last_custom_minutes';
  static const String _guardrailKeyPrefix = 'guardrail_';
  static const String _musicFolderKey = 'music_folder';
  static const String _musicMinCutoffKey = 'music_min_cutoff_hz';
  static const String _musicMaxCutoffKey = 'music_max_cutoff_hz';
  static const String _musicSlewKey = 'music_slew_seconds';
  static const String _musicInvertKey = 'music_invert_mapping';
  static const String _musicShuffleKey = 'music_shuffle';
  static const String _guardrailVolumeKey = 'guardrail_volume';
  static const String _binauralPresetKey = 'binaural_preset';
  static const String _binauralCarrierKey = 'binaural_carrier_hz';
  static const String _binauralBeatKey = 'binaural_beat_hz';
  static const String _streamProtocolKey = 'stream_protocol';
  static const String _oscEnabledKey = 'stream_osc_enabled';
  static const String _oscIpKey = 'stream_osc_ip';
  static const String _oscPortKey = 'stream_osc_port';
  static const String _oscPrefixKey = 'stream_osc_prefix';
  static const String _oscSeparateGroupsKey = 'stream_osc_separate_groups';
  static const String _lslEnabledKey = 'stream_lsl_enabled';
  static const String _lslPrefixKey = 'stream_lsl_prefix';
  static const String _lslSeparateGroupsKey = 'stream_lsl_separate_groups';

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

  /// The feedback layer: what sounds when the reward fires. Defaults to bowl
  /// chimes (classic behavior); Rain/Music suppress the background layer.
  FeedbackMode get feedbackMode =>
      feedbackModeFromName(_prefs.getString(_feedbackModeKey));

  Future<void> setFeedbackMode(FeedbackMode mode) =>
      _prefs.setString(_feedbackModeKey, mode.name);

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

  /// Guardrail scorer engine: an AI model kind name (`lunaBase`/`lunaLarge`/
  /// `reveBase`) or `bandMath` (no AI — classical band math on frontal delta).
  /// Falls back to [modelKindName] when unset (legacy installs).
  String? get guardrailEngineName => _prefs.getString(_guardrailEngineKey);

  Future<void> setGuardrailEngineName(String value) =>
      _prefs.setString(_guardrailEngineKey, value);

  /// Warning sound shown in the guardrail gear dialog (`softBowl`/`chime`/
  /// `cough`/`alarm`/`none`). Placeholder asset names — the files land later.
  String get warningSoundName => _prefs.getString(_warningSoundKey) ?? 'softBowl';

  Future<void> setWarningSoundName(String value) =>
      _prefs.setString(_warningSoundKey, value);

  /// Last session duration chosen via the Custom button (minutes), or null
  /// before the user has ever used it.
  int? get lastCustomMinutes => _prefs.getInt(_lastCustomMinutesKey);

  Future<void> setLastCustomMinutes(int value) =>
      _prefs.setInt(_lastCustomMinutesKey, value);

  /// Whether the on-device AI sleep guardrail runs for [type]. Every protocol
  /// except the eyes-open one offers the layer (see
  /// [ProtocolInfo.guardrailAllowed] — a protocol without it never runs the
  /// guardrail and returns false here); the default follows the protocol's
  /// shipping choice ([ProtocolInfo.guardrailDefault]), and turning it off
  /// runs the plain ratio engine (no warnings, no guardrail calibration
  /// stages). A model must additionally be installed and selected for the AI
  /// scorer (the band-math fallback works without one).
  bool guardrailEnabledFor(ProtocolType type) {
    if (!ProtocolInfo.forType(type).guardrailAllowed) return false;
    return _prefs.getBool('$_guardrailKeyPrefix${type.name}') ??
        ProtocolInfo.forType(type).guardrailDefault;
  }

  Future<void> setGuardrailEnabled(ProtocolType type, bool value) =>
      _prefs.setBool('$_guardrailKeyPrefix${type.name}', value);

  /// Music-feedback folder. A `content://` value is an Android SAF tree URI
  /// (any file must be materialized through the SAF channel before playback);
  /// any other value is a real filesystem path. Null means no music feedback.
  String? get musicFolder => _prefs.getString(_musicFolderKey);

  Future<void> setMusicFolder(String value) =>
      _prefs.setString(_musicFolderKey, value);

  Future<void> clearMusicFolder() => _prefs.remove(_musicFolderKey);

  /// Low-pass cutoff range (Hz) the music feedback sweeps between. Below the
  /// floor the music is deeply muffled; at the ceiling it is full spectrum.
  double get musicMinCutoffHz => _prefs.getDouble(_musicMinCutoffKey) ?? 200.0;

  Future<void> setMusicMinCutoffHz(double value) =>
      _prefs.setDouble(_musicMinCutoffKey, value);

  double get musicMaxCutoffHz => _prefs.getDouble(_musicMaxCutoffKey) ?? 8000.0;

  Future<void> setMusicMaxCutoffHz(double value) =>
      _prefs.setDouble(_musicMaxCutoffKey, value);

  /// Exponential smoothing time constant applied to the live cutoff changes
  /// (prevents zipper noise from the ~10 Hz percentile updates).
  double get musicSlewSeconds => _prefs.getDouble(_musicSlewKey) ?? 1.2;

  Future<void> setMusicSlewSeconds(double value) =>
      _prefs.setDouble(_musicSlewKey, value);

  /// When true, high scores close the filter instead of opening it.
  bool get musicInvertMapping => _prefs.getBool(_musicInvertKey) ?? false;

  Future<void> setMusicInvertMapping(bool value) =>
      _prefs.setBool(_musicInvertKey, value);

  /// Randomize the track order on each session start.
  bool get musicShuffle => _prefs.getBool(_musicShuffleKey) ?? false;

  Future<void> setMusicShuffle(bool value) =>
      _prefs.setBool(_musicShuffleKey, value);

  double? get guardrailVolume => _prefs.getDouble(_guardrailVolumeKey);

  Future<void> setGuardrailVolume(double value) =>
      _prefs.setDouble(_guardrailVolumeKey, value);

  /// Selected binaural preset id ([BinauralPreset] name or
  /// [binauralCustomPresetId]). Presets set both the carrier and the beat
  /// difference; moving either tuning slider flips this to `custom`.
  String get binauralPresetId => _prefs.getString(_binauralPresetKey) ?? '';

  Future<void> setBinauralPresetId(String value) =>
      _prefs.setString(_binauralPresetKey, value);

  /// Carrier tone (Hz) for the binaural layer; used when [binauralPresetId]
  /// is custom (presets supply their own carrier).
  double get binauralCarrierHz => _prefs.getDouble(_binauralCarrierKey) ?? 200.0;

  Future<void> setBinauralCarrierHz(double value) =>
      _prefs.setDouble(_binauralCarrierKey, value);

  /// Beat difference (Hz) between the ears — the perceived entrainment
  /// frequency; used when [binauralPresetId] is custom.
  double get binauralBeatHz => _prefs.getDouble(_binauralBeatKey) ?? 10.0;

  Future<void> setBinauralBeatHz(double value) =>
      _prefs.setDouble(_binauralBeatKey, value);

  /// Network streaming protocol selected in the Streaming view
  /// (`osc` or `lsl`); only one protocol runs at a time.
  String? get streamProtocolName => _prefs.getString(_streamProtocolKey);

  Future<void> setStreamProtocolName(String value) =>
      _prefs.setString(_streamProtocolKey, value);

  bool get oscEnabled => _prefs.getBool(_oscEnabledKey) ?? false;

  Future<void> setOscEnabled(bool value) =>
      _prefs.setBool(_oscEnabledKey, value);

  /// Destination PC for OSC (unicast UDP).
  String get oscIp => _prefs.getString(_oscIpKey) ?? '192.168.1.100';

  Future<void> setOscIp(String value) => _prefs.setString(_oscIpKey, value);

  int get oscPort => _prefs.getInt(_oscPortKey) ?? 5555;

  Future<void> setOscPort(int value) => _prefs.setInt(_oscPortKey, value);

  /// OSC address root, e.g. `/muse` → messages to `/muse/eeg`, `/muse/ppg`.
  String get oscPrefix => _prefs.getString(_oscPrefixKey) ?? '/muse';

  Future<void> setOscPrefix(String value) =>
      _prefs.setString(_oscPrefixKey, value);

  /// When true every sensor group gets its own OSC address / LSL stream;
  /// when false only the EEG group is streamed.
  bool get oscSeparateGroups => _prefs.getBool(_oscSeparateGroupsKey) ?? true;

  Future<void> setOscSeparateGroups(bool value) =>
      _prefs.setBool(_oscSeparateGroupsKey, value);

  bool get lslEnabled => _prefs.getBool(_lslEnabledKey) ?? false;

  Future<void> setLslEnabled(bool value) =>
      _prefs.setBool(_lslEnabledKey, value);

  /// LSL stream-name prefix, e.g. `Muse` → streams `MuseEEG`, `MusePPG`.
  String get lslPrefix => _prefs.getString(_lslPrefixKey) ?? 'Muse';

  Future<void> setLslPrefix(String value) =>
      _prefs.setString(_lslPrefixKey, value);

  bool get lslSeparateGroups => _prefs.getBool(_lslSeparateGroupsKey) ?? true;

  Future<void> setLslSeparateGroups(bool value) =>
      _prefs.setBool(_lslSeparateGroupsKey, value);
}

/// Provides the app-wide [Settings] instance. Loaded in `main()` and
/// overridden there with the concrete instance; [audioServiceProvider]
/// depends on it to restore persisted volumes.
final settingsProvider = Provider<Settings>(
  (ref) =>
      throw UnimplementedError('settingsProvider must be overridden in main()'),
);
