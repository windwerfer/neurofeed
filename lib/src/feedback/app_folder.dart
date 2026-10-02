import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Where saved sessions, recordings, and export live, and where cache and
/// AI models sit relative to that folder.
///
/// Desktop (Linux, Windows, macOS) keeps cache and models inside the app
/// folder. Mobile (Android, iOS) keeps them in the system app folder even
/// when the user picks a different save folder, including a SAF tree.
enum AppDataLayout { desktop, mobile }

AppDataLayout currentAppDataLayout() => Platform.isAndroid || Platform.isIOS
    ? AppDataLayout.mobile
    : AppDataLayout.desktop;

/// Cache and `ai_models` move with the app folder on desktop only.
bool includesPrivateAppDirs({AppDataLayout? layout}) =>
    (layout ?? currentAppDataLayout()) == AppDataLayout.desktop;

/// Documents directory chosen from `xdg-user-dir`, then `neurofeed` under it.
///
/// A missing, failing, empty, relative, or `$HOME` result uses
/// `$HOME/Documents`. The returned path is not created here.
String desktopAppFolderPath({required String home, String? xdg}) {
  return p.join(_documentsDir(home: home, xdg: xdg), 'neurofeed');
}

String _documentsDir({required String home, String? xdg}) {
  final trimmed = xdg?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return p.join(home, 'Documents');
  }
  final normalized = p.normalize(trimmed);
  final homeNorm = p.normalize(home);
  if (!p.isAbsolute(normalized) || normalized == homeNorm) {
    return p.join(home, 'Documents');
  }
  return normalized;
}

/// `xdg-user-dir DOCUMENTS`, or null when it is missing or fails.
Future<String?> readXdgDocumentsDir() {
  return Zone.root.run(() async {
    try {
      final result = await Process.run('xdg-user-dir', const ['DOCUMENTS']);
      if (result.exitCode != 0) return null;
      final out = result.stdout;
      final text = out is String ? out.trim() : '';
      return text.isEmpty ? null : text;
    } catch (_) {
      return null;
    }
  });
}

/// `$HOME/Documents/neurofeed`, creating `Documents` and `neurofeed`.
///
/// [readXdg] is called on Linux and macOS when omitted. A throw from it is
/// the same as a missing documents directory.
Future<Directory> desktopNeurofeedDir({
  Map<String, String>? env,
  Future<String?> Function()? readXdg,
}) async {
  final environment = env ?? Platform.environment;
  final home = _homeFrom(environment);
  if (home == null) {
    throw StateError('cannot resolve the home directory for the app folder');
  }
  String? xdg;
  final reader =
      readXdg ??
      ((Platform.isLinux || Platform.isMacOS) ? readXdgDocumentsDir : null);
  if (reader != null) {
    try {
      xdg = await reader();
    } catch (_) {
      xdg = null;
    }
  }
  final directory = Directory(desktopAppFolderPath(home: home, xdg: xdg));
  await directory.create(recursive: true);
  return directory;
}

String? _homeFrom(Map<String, String> env) {
  final home = env['HOME'];
  if (home != null && home.isNotEmpty) return home;
  final profile = env['USERPROFILE'];
  if (profile != null && profile.isNotEmpty) return profile;
  return null;
}

/// Default app folder. Mobile is [getApplicationSupportDirectory]. Desktop
/// is [desktopNeurofeedDir].
Future<Directory> defaultAppFolder({
  AppDataLayout? layout,
  Future<Directory> Function()? readSystemAppFolder,
  Map<String, String>? env,
  Future<String?> Function()? readXdg,
}) async {
  final mobile = (layout ?? currentAppDataLayout()) == AppDataLayout.mobile;
  if (mobile) {
    final dir = await (readSystemAppFolder ?? getApplicationSupportDirectory)();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
  return desktopNeurofeedDir(env: env, readXdg: readXdg);
}

/// SQLite history index and live scratch (`tmp_`, in-progress `session_`
/// and `recording_`). Same directory as [scratchDirectory].
Future<Directory> cacheDirectory({
  String? filesystemAppFolder,
  AppDataLayout? layout,
  Future<Directory> Function()? readSystemAppFolder,
}) async {
  final mobile = (layout ?? currentAppDataLayout()) == AppDataLayout.mobile;
  if (!mobile &&
      filesystemAppFolder != null &&
      filesystemAppFolder.isNotEmpty &&
      !filesystemAppFolder.startsWith('content://')) {
    return Directory(p.join(filesystemAppFolder, '.cache'));
  }
  final support =
      await (readSystemAppFolder ?? getApplicationSupportDirectory)();
  return Directory(p.join(support.path, '.cache'));
}

/// `ai_models/` root (model kinds are children of this directory).
Future<Directory> modelsRoot({
  String? sessionFolder,
  AppDataLayout? layout,
  Future<Directory> Function()? readSystemAppFolder,
  Future<Directory> Function()? readDesktopDefault,
}) async {
  final mobile = (layout ?? currentAppDataLayout()) == AppDataLayout.mobile;
  final saf = sessionFolder != null && sessionFolder.startsWith('content://');
  if (mobile || saf) {
    final support =
        await (readSystemAppFolder ?? getApplicationSupportDirectory)();
    return Directory(p.join(support.path, 'ai_models'));
  }
  final base = (sessionFolder == null || sessionFolder.isEmpty)
      ? (await (readDesktopDefault ?? defaultAppFolder)()).path
      : sessionFolder;
  return Directory(p.join(base, 'ai_models'));
}

/// True when [a] and [b] are the same save folder.
bool sameAppFolder(String a, String b) {
  if (a.startsWith('content://') || b.startsWith('content://')) {
    return a == b;
  }
  return p.normalize(p.absolute(a)) == p.normalize(p.absolute(b));
}

/// Readable label for a SAF tree URI. Falls back to the URI.
String safTreeLabel(String uri) {
  final parsed = Uri.tryParse(uri);
  if (parsed == null) return uri;
  final segs = parsed.pathSegments;
  if (segs.isEmpty) return uri;
  final id = Uri.decodeComponent(segs.last);
  final colon = id.indexOf(':');
  final path = colon >= 0 ? id.substring(colon + 1) : id;
  if (path.isEmpty) return uri;
  return path;
}
