import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppView { feedback, feedbackHistory, bands, rawEeg, spectrogram, psd, settings }

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
}

/// Provides the app-wide [Settings] instance. Loaded in `main()` and
/// overridden there with the concrete instance; [audioServiceProvider]
/// depends on it to restore persisted volumes.
final settingsProvider = Provider<Settings>(
  (ref) => throw UnimplementedError(
    'settingsProvider must be overridden in main()',
  ),
);
