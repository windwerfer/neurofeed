import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:muse_ml/src/feedback/feedback_state.dart';
import 'package:muse_ml/src/feedback/guardrail_mode.dart';
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
  spo2,
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
class Settings extends ChangeNotifier {
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
  static const String _baselinePercentileKey = 'baseline_percentile';
  static const String _soundNameKey = 'sound_name';
  static const String _feedbackModeKey = 'feedback_mode';
  static const String _durationMinutesKey = 'duration_minutes';
  static const String _sessionFolderKey = 'session_folder';
  static const String _recordStreamsKey = 'record_streams';
  static const String _eyeMarkersKey = 'gesture_eye_markers';
  static const String _markersInFeedbackKey = 'gesture_markers_in_feedback';
  static const String _warningThresholdPercentileKey =
      'reve_warning_threshold_percentile';
  static const String _guardrailModeKey = 'guardrail_mode';
  static const String _warningSoundKey = 'warning_sound';
  static const String _lastCustomMinutesKey = 'last_custom_minutes';
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
  static const String _backgroundBinauralPresetKey = 'background_binaural_preset';
  static const String _backgroundBinauralCarrierKey = 'background_binaural_carrier_hz';
  static const String _backgroundBinauralBeatKey = 'background_binaural_beat_hz';
  static const String _streamProtocolKey = 'stream_protocol';
  static const String _oscEnabledKey = 'stream_osc_enabled';
  static const String _oscIpKey = 'stream_osc_ip';
  static const String _oscPortKey = 'stream_osc_port';
  static const String _oscPrefixKey = 'stream_osc_prefix';
  static const String _oscSeparateGroupsKey = 'stream_osc_separate_groups';
  static const String _lslEnabledKey = 'stream_lsl_enabled';
  static const String _lslPrefixKey = 'stream_lsl_prefix';
  static const String _lslSeparateGroupsKey = 'stream_lsl_separate_groups';
  static const String _brainflowEnabledKey = 'stream_bf_enabled';
  static const String _brainflowIpKey = 'stream_bf_ip';
  static const String _brainflowPortKey = 'stream_bf_port';
  static const String _brainflowSeparateGroupsKey = 'stream_bf_separate_groups';

  final SharedPreferences _prefs;

  static Future<Settings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return Settings._(prefs);
  }

  AppView get lastView => _viewFromName(_prefs.getString(_lastViewKey));

  Future<void> setLastView(AppView view) async {
    await _prefs.setString(_lastViewKey, _viewNames[view]!);
    notifyListeners();
  }

  String? get lastDeviceId => _prefs.getString(_lastDeviceKey);

  Future<void> setLastDeviceId(String id) async {
    await _prefs.setString(_lastDeviceKey, id);
    notifyListeners();
  }

  double? get masterVolume => _prefs.getDouble(_masterVolumeKey);

  Future<void> setMasterVolume(double value) async {
    await _prefs.setDouble(_masterVolumeKey, value);
    notifyListeners();
  }

  double? get backgroundVolume => _prefs.getDouble(_backgroundVolumeKey);

  Future<void> setBackgroundVolume(double value) async {
    await _prefs.setDouble(_backgroundVolumeKey, value);
    notifyListeners();
  }

  double? get feedbackVolume => _prefs.getDouble(_feedbackVolumeKey);

  Future<void> setFeedbackVolume(double value) async {
    await _prefs.setDouble(_feedbackVolumeKey, value);
    notifyListeners();
  }

  double? get introVolume => _prefs.getDouble(_introVolumeKey);

  Future<void> setIntroVolume(double value) async {
    await _prefs.setDouble(_introVolumeKey, value);
    notifyListeners();
  }

  double? get bellVolume => _prefs.getDouble(_bellVolumeKey);

  Future<void> setBellVolume(double value) async {
    await _prefs.setDouble(_bellVolumeKey, value);
    notifyListeners();
  }

  bool? get dynamicAdapt => _prefs.getBool(_dynamicAdaptKey);

  Future<void> setDynamicAdapt(bool value) async {
    await _prefs.setBool(_dynamicAdaptKey, value);
    notifyListeners();
  }

  double? get responsiveness => _prefs.getDouble(_responsivenessKey);

  Future<void> setResponsiveness(double value) async {
    await _prefs.setDouble(_responsivenessKey, value);
    notifyListeners();
  }

  /// Baseline percentile for the ATR threshold (default 40). Persisted so the
  /// last used value becomes the default for new sessions.
  int get baselinePercentile =>
      _prefs.getInt(_baselinePercentileKey) ?? defaultBaselinePercentile;

  Future<void> setBaselinePercentile(int value) async {
    await _prefs.setInt(_baselinePercentileKey, value);
    notifyListeners();
  }

  String? get soundName => _prefs.getString(_soundNameKey);

  Future<void> setSoundName(String value) async {
    await _prefs.setString(_soundNameKey, value);
    notifyListeners();
  }

  /// The feedback layer: what sounds when the reward fires. Defaults to bowl
  /// chimes (classic behavior); Rain/Music suppress the background layer.
  FeedbackMode get feedbackMode =>
      feedbackModeFromName(_prefs.getString(_feedbackModeKey));

  Future<void> setFeedbackMode(FeedbackMode mode) async {
    await _prefs.setString(_feedbackModeKey, mode.name);
    notifyListeners();
  }

  int? get durationMinutes => _prefs.getInt(_durationMinutesKey);

  Future<void> setDurationMinutes(int value) async {
    await _prefs.setInt(_durationMinutesKey, value);
    notifyListeners();
  }

  /// History folder. A `content://` value is an Android SAF tree URI; any
  /// other value is a real filesystem path. Null means "use the default".
  String? get sessionFolder => _prefs.getString(_sessionFolderKey);

  Future<void> setSessionFolder(String value) async {
    await _prefs.setString(_sessionFolderKey, value);
    notifyListeners();
  }

  Future<void> clearSessionFolder() async {
    await _prefs.remove(_sessionFolderKey);
    notifyListeners();
  }

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

  Future<void> setRecordStreams(Set<RecordingStream> streams) async {
    await _prefs.setStringList(_recordStreamsKey, streams.map((s) => s.name).toList());
    notifyListeners();
  }

  /// Whether eye up/down movements produce gesture markers. Off by default —
  /// the eye track is experimental on a 4-electrode Muse.
  bool get eyeMarkersEnabled => _prefs.getBool(_eyeMarkersKey) ?? false;

  Future<void> setEyeMarkersEnabled(bool value) async {
    await _prefs.setBool(_eyeMarkersKey, value);
    notifyListeners();
  }

  /// Whether gesture markers (double blink / double clench / eye) are recorded
  /// as a track in saved feedback sessions. Independent of *detection* — when
  /// false the live detector still runs but nothing is persisted.
  bool get markersInFeedbackEnabled =>
      _prefs.getBool(_markersInFeedbackKey) ?? true;

  Future<void> setMarkersInFeedbackEnabled(bool value) async {
    await _prefs.setBool(_markersInFeedbackKey, value);
    notifyListeners();
  }

  /// Percentile of the eyes-closed rest sleep-direction distribution above
  /// which the REVE sleep-guardrail warning fires (see
  /// [defaultWarningThresholdPercentile]).
  int get warningThresholdPercentile =>
      _prefs.getInt(_warningThresholdPercentileKey) ??
      defaultWarningThresholdPercentile;

  Future<void> setWarningThresholdPercentile(int value) async {
    await _prefs.setInt(_warningThresholdPercentileKey, value);
    notifyListeners();
  }

  /// Per-protocol guardrail mode setting. Persisted as a JSON map of
  /// ProtocolType.name -> GuardrailMode.name.
  /// Defaults to drowsinessMath for all protocols (from assets/protocols.json).
  Map<ProtocolType, GuardrailMode> get guardrailModeForProtocol {
    final stored = _prefs.getString(_guardrailModeKey);
    if (stored != null) {
      final map = jsonDecode(stored) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(
        ProtocolType.values.byName(k),
        GuardrailMode.values.byName(v),
      ));
    }
    // Default: drowsinessMath for all protocols
    return Map.fromEntries(ProtocolType.values.map((t) => MapEntry(t, GuardrailMode.drowsinessMath)));
  }

  Future<void> setGuardrailMode(ProtocolType type, GuardrailMode mode) async {
    final current = guardrailModeForProtocol;
    current[type] = mode;
    await _prefs.setString(_guardrailModeKey, jsonEncode(
      current.map((k, v) => MapEntry(k.name, v.name)),
    ));
    notifyListeners();
  }

  /// Whether the guardrail is enabled for [type]. Returns false if the
  /// protocol doesn't allow the guardrail, or if the mode is 'none'.
  bool guardrailEnabledFor(ProtocolType type) {
    if (!ProtocolInfo.forType(type).guardrailAllowed) return false;
    return guardrailModeForProtocol[type] != GuardrailMode.none;
  }

  /// Whether the guardrail runs in band-math mode (no AI model) for [type].
  bool guardrailIsBandMathFor(ProtocolType type) {
    return guardrailModeForProtocol[type] == GuardrailMode.drowsinessMath;
  }

  /// Whether the guardrail runs an AI model for [type].
  bool guardrailIsAiFor(ProtocolType type) {
    final mode = guardrailModeForProtocol[type];
    return mode != null && mode.isAi;
  }

  /// Warning sound shown in the guardrail gear dialog (`softBowl`/`chime`/
  /// `cough`/`alarm`/`none`). Placeholder asset names — the files land later.
  String get warningSoundName => _prefs.getString(_warningSoundKey) ?? 'softBowl';

  Future<void> setWarningSoundName(String value) async {
    await _prefs.setString(_warningSoundKey, value);
    notifyListeners();
  }

  /// Last session duration chosen via the Custom button (minutes), or null
  /// before the user has ever used it.
  int? get lastCustomMinutes => _prefs.getInt(_lastCustomMinutesKey);

  Future<void> setLastCustomMinutes(int value) async {
    await _prefs.setInt(_lastCustomMinutesKey, value);
    notifyListeners();
  }

  /// Music-feedback folder. A `content://` value is an Android SAF tree URI
  /// (any file must be materialized through the SAF channel before playback);
  /// any other value is a real filesystem path. Null means no music feedback.
  String? get musicFolder => _prefs.getString(_musicFolderKey);

  Future<void> setMusicFolder(String value) async {
    await _prefs.setString(_musicFolderKey, value);
    notifyListeners();
  }

  Future<void> clearMusicFolder() async {
    await _prefs.remove(_musicFolderKey);
    notifyListeners();
  }

  static const String _audioStableModeKey = 'audio_stable_mode';

  /// Conservative audio profile (Android): gives the audio engine more
  /// headroom so dropouts are rare when the CPU is busy (e.g. music feedback
  /// with the AI guardrail), at the cost of ~0.1 s more output latency.
  /// Default on; only surfaced in Settings on Android (a no-op elsewhere).
  bool get audioStableMode => _prefs.getBool(_audioStableModeKey) ?? true;

  Future<void> setAudioStableMode(bool value) async {
    await _prefs.setBool(_audioStableModeKey, value);
    notifyListeners();
  }

  static const String _musicAiCpuWarningKey = 'music_ai_cpu_warning_shown';

  /// Whether the one-time "music + AI guardrail may stutter" warning has
  /// already been shown. The combo is allowed — the warning only informs.
  bool get musicAiCpuWarningShown =>
      _prefs.getBool(_musicAiCpuWarningKey) ?? false;

  Future<void> markMusicAiCpuWarningShown() async {
    await _prefs.setBool(_musicAiCpuWarningKey, true);
    notifyListeners();
  }

  /// Low-pass cutoff range (Hz) the music feedback sweeps between. Below the
  /// floor the music is deeply muffled; at the ceiling it is full spectrum.
  double get musicMinCutoffHz => _prefs.getDouble(_musicMinCutoffKey) ?? 200.0;

  Future<void> setMusicMinCutoffHz(double value) async {
    await _prefs.setDouble(_musicMinCutoffKey, value);
    notifyListeners();
  }

  double get musicMaxCutoffHz => _prefs.getDouble(_musicMaxCutoffKey) ?? 8000.0;

  Future<void> setMusicMaxCutoffHz(double value) async {
    await _prefs.setDouble(_musicMaxCutoffKey, value);
    notifyListeners();
  }

  /// Exponential smoothing time constant applied to the live cutoff changes
  /// (prevents zipper noise from the ~10 Hz percentile updates).
  double get musicSlewSeconds => _prefs.getDouble(_musicSlewKey) ?? 1.2;

  Future<void> setMusicSlewSeconds(double value) async {
    await _prefs.setDouble(_musicSlewKey, value);
    notifyListeners();
  }

  /// When true, high scores close the filter instead of opening it.
  bool get musicInvertMapping => _prefs.getBool(_musicInvertKey) ?? false;

  Future<void> setMusicInvertMapping(bool value) async {
    await _prefs.setBool(_musicInvertKey, value);
    notifyListeners();
  }

  /// Randomize the track order on each session start.
  bool get musicShuffle => _prefs.getBool(_musicShuffleKey) ?? false;

  Future<void> setMusicShuffle(bool value) async {
    await _prefs.setBool(_musicShuffleKey, value);
    notifyListeners();
  }

  double? get guardrailVolume => _prefs.getDouble(_guardrailVolumeKey);

  Future<void> setGuardrailVolume(double value) async {
    await _prefs.setDouble(_guardrailVolumeKey, value);
    notifyListeners();
  }

  /// Selected binaural preset id ([BinauralPreset] name or
  /// [binauralCustomPresetId]). Presets set both the carrier and the beat
  /// difference; moving either tuning slider flips this to `custom`.
  String get binauralPresetId => _prefs.getString(_binauralPresetKey) ?? '';

  Future<void> setBinauralPresetId(String value) async {
    await _prefs.setString(_binauralPresetKey, value);
    notifyListeners();
  }

  /// Carrier tone (Hz) for the binaural layer; used when [binauralPresetId]
  /// is custom (presets supply their own carrier).
  double get binauralCarrierHz => _prefs.getDouble(_binauralCarrierKey) ?? 200.0;

  Future<void> setBinauralCarrierHz(double value) async {
    await _prefs.setDouble(_binauralCarrierKey, value);
    notifyListeners();
  }

  /// Beat difference (Hz) between the ears — the perceived entrainment
  /// frequency; used when [binauralPresetId] is custom.
  double get binauralBeatHz => _prefs.getDouble(_binauralBeatKey) ?? 10.0;

  Future<void> setBinauralBeatHz(double value) async {
    await _prefs.setDouble(_binauralBeatKey, value);
    notifyListeners();
  }

  String get backgroundBinauralPresetId =>
      _prefs.getString(_backgroundBinauralPresetKey) ?? '';

  Future<void> setBackgroundBinauralPresetId(String value) async {
    await _prefs.setString(_backgroundBinauralPresetKey, value);
    notifyListeners();
  }

  double get backgroundBinauralCarrierHz =>
      _prefs.getDouble(_backgroundBinauralCarrierKey) ?? 200.0;

  Future<void> setBackgroundBinauralCarrierHz(double value) async {
    await _prefs.setDouble(_backgroundBinauralCarrierKey, value);
    notifyListeners();
  }

  double get backgroundBinauralBeatHz =>
      _prefs.getDouble(_backgroundBinauralBeatKey) ?? 10.0;

  Future<void> setBackgroundBinauralBeatHz(double value) async {
    await _prefs.setDouble(_backgroundBinauralBeatKey, value);
    notifyListeners();
  }

  /// Network streaming protocol selected in the Streaming view
  /// (`osc` or `lsl`); only one protocol runs at a time.
  String? get streamProtocolName => _prefs.getString(_streamProtocolKey);

  Future<void> setStreamProtocolName(String value) async {
    await _prefs.setString(_streamProtocolKey, value);
    notifyListeners();
  }

  bool get oscEnabled => _prefs.getBool(_oscEnabledKey) ?? false;

  Future<void> setOscEnabled(bool value) async {
    await _prefs.setBool(_oscEnabledKey, value);
    notifyListeners();
  }

  /// Destination PC for OSC (unicast UDP).
  String get oscIp => _prefs.getString(_oscIpKey) ?? '192.168.1.100';

  Future<void> setOscIp(String value) async {
    await _prefs.setString(_oscIpKey, value);
    notifyListeners();
  }

  int get oscPort => _prefs.getInt(_oscPortKey) ?? 9000;

  Future<void> setOscPort(int value) async {
    await _prefs.setInt(_oscPortKey, value);
    notifyListeners();
  }

  /// True once the user has entered an OSC IP at least once; before that the
  /// streaming view auto-fills the current subnet as the example address.
  bool get oscIpUserSet => _prefs.containsKey(_oscIpKey) && oscIp.isNotEmpty;

  /// OSC address root, e.g. `/muse` → messages to `/muse/eeg`, `/muse/ppg`.
  String get oscPrefix => _prefs.getString(_oscPrefixKey) ?? '/muse';

  Future<void> setOscPrefix(String value) async {
    await _prefs.setString(_oscPrefixKey, value);
    notifyListeners();
  }

  /// When true every sensor group gets its own OSC address / LSL stream;
  /// when false only the EEG group is streamed.
  bool get oscSeparateGroups => _prefs.getBool(_oscSeparateGroupsKey) ?? true;

  Future<void> setOscSeparateGroups(bool value) async {
    await _prefs.setBool(_oscSeparateGroupsKey, value);
    notifyListeners();
  }

  bool get lslEnabled => _prefs.getBool(_lslEnabledKey) ?? false;

  Future<void> setLslEnabled(bool value) async {
    await _prefs.setBool(_lslEnabledKey, value);
    notifyListeners();
  }

  /// LSL stream-name prefix, e.g. `Muse` → streams `MuseEEG`, `MusePPG`.
  String get lslPrefix => _prefs.getString(_lslPrefixKey) ?? 'Muse';

  Future<void> setLslPrefix(String value) async {
    await _prefs.setString(_lslPrefixKey, value);
    notifyListeners();
  }

  bool get lslSeparateGroups => _prefs.getBool(_lslSeparateGroupsKey) ?? true;

  Future<void> setLslSeparateGroups(bool value) async {
    await _prefs.setBool(_lslSeparateGroupsKey, value);
    notifyListeners();
  }

  bool get brainflowEnabled => _prefs.getBool(_brainflowEnabledKey) ?? false;

  Future<void> setBrainflowEnabled(bool value) async {
    await _prefs.setBool(_brainflowEnabledKey, value);
    notifyListeners();
  }

  /// Multicast group the BrainFlow Streaming Board format is sent to.
  String get brainflowIp => _prefs.getString(_brainflowIpKey) ?? '225.1.1.1';

  Future<void> setBrainflowIp(String value) async {
    await _prefs.setString(_brainflowIpKey, value);
    notifyListeners();
  }

  int get brainflowPort => _prefs.getInt(_brainflowPortKey) ?? 6677;

  Future<void> setBrainflowPort(int value) async {
    await _prefs.setInt(_brainflowPortKey, value);
    notifyListeners();
  }

  /// When true BrainFlow streams all presets (EEG on the configured port,
  /// IMU on port+1, PPG on port+2); when false only the EEG default preset.
  bool get brainflowSeparateGroups =>
      _prefs.getBool(_brainflowSeparateGroupsKey) ?? true;

  Future<void> setBrainflowSeparateGroups(bool value) async {
    await _prefs.setBool(_brainflowSeparateGroupsKey, value);
    notifyListeners();
  }
}

/// Provides the app-wide [Settings] instance. Loaded in `main()` and
/// overridden there with the concrete instance; [audioServiceProvider]
/// depends on it to restore persisted volumes.
final settingsProvider = ChangeNotifierProvider<Settings>(
  (ref) =>
      throw UnimplementedError('settingsProvider must be overridden in main()'),
);
