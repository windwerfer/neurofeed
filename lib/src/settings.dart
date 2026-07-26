import 'package:shared_preferences/shared_preferences.dart';

enum AppView { bands, rawEeg, spectrogram, psd, settings }

const Map<AppView, String> _viewNames = {
  AppView.bands: 'bands',
  AppView.rawEeg: 'rawEeg',
  AppView.spectrogram: 'spectrogram',
  AppView.psd: 'psd',
  AppView.settings: 'settings',
};

AppView _viewFromName(String? name) {
  switch (name) {
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
      return AppView.bands;
  }
}

/// Persistent app settings backed by SharedPreferences.
class Settings {
  Settings._(this._prefs);

  static const String _lastViewKey = 'last_view';
  static const String _lastDeviceKey = 'last_device_id';

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
}
