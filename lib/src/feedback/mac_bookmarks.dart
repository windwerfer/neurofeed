import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:neurofeed/src/feedback/app_folder.dart';
import 'package:neurofeed/src/settings.dart';

const macSandboxChannel = MethodChannel('neurofeed/mac_sandbox');

class MacBookmarkException implements Exception {
  MacBookmarkException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MacBookmarkActivation {
  const MacBookmarkActivation({required this.path, required this.bookmark});

  final String path;
  final String bookmark;
}

/// Security-scoped bookmark for [path], or null when the platform does not
/// need one. Throws [MacBookmarkException] when macOS refuses the grant.
Future<String?> macBookmarkForPath(
  String path, {
  MethodChannel? channel,
}) async {
  if (!Platform.isMacOS) return null;
  final messenger = channel ?? macSandboxChannel;
  try {
    final value = await messenger.invokeMethod<String>('bookmark', {
      'path': path,
    });
    if (value == null || value.isEmpty) {
      throw MacBookmarkException('could not retain access to $path');
    }
    return value;
  } on PlatformException catch (e) {
    throw MacBookmarkException(e.message ?? 'could not retain access to $path');
  }
}

/// Resolves [bookmark], starts sandbox access for this process, and returns
/// the path plus the bookmark to store (refreshed when the OS marks it stale).
Future<MacBookmarkActivation> activateMacBookmark(
  String bookmark, {
  MethodChannel? channel,
}) async {
  final messenger = channel ?? macSandboxChannel;
  try {
    final value = await messenger.invokeMethod<Object?>('activate', {
      'bookmark': bookmark,
    });
    if (value is! Map) {
      throw MacBookmarkException('could not restore folder access');
    }
    final path = value['path'];
    final stored = value['bookmark'];
    if (path is! String ||
        path.isEmpty ||
        stored is! String ||
        stored.isEmpty) {
      throw MacBookmarkException('could not restore folder access');
    }
    return MacBookmarkActivation(path: path, bookmark: stored);
  } on PlatformException catch (e) {
    throw MacBookmarkException(e.message ?? 'could not restore folder access');
  }
}

/// Starts access for the saved session and music folders. No-op off macOS
/// and when no bookmark is stored. A failure leaves the saved path in place.
Future<void> activateMacFolderBookmarks(
  Settings settings, {
  MethodChannel? channel,
}) async {
  if (!Platform.isMacOS) return;
  await _activateSlot(
    bookmark: settings.sessionFolderBookmark,
    storedPath: settings.sessionFolder,
    channel: channel,
    save: (path, bookmark) =>
        settings.setSessionFolder(path, macBookmark: bookmark),
  );
  await _activateSlot(
    bookmark: settings.musicFolderBookmark,
    storedPath: settings.musicFolder,
    channel: channel,
    save: (path, bookmark) =>
        settings.setMusicFolder(path, macBookmark: bookmark),
  );
}

Future<void> _activateSlot({
  required String? bookmark,
  required String? storedPath,
  required MethodChannel? channel,
  required Future<void> Function(String path, String bookmark) save,
}) async {
  if (bookmark == null || bookmark.isEmpty) return;
  final MacBookmarkActivation activation;
  try {
    activation = await activateMacBookmark(bookmark, channel: channel);
  } on MacBookmarkException catch (e) {
    debugPrint('[folder] bookmark activate failed: $e');
    return;
  }
  final pathChanged =
      storedPath == null || !sameAppFolder(storedPath, activation.path);
  final bookmarkChanged = activation.bookmark != bookmark;
  if (!pathChanged && !bookmarkChanged) return;
  await save(activation.path, activation.bookmark);
}

/// Persists a music folder, with a macOS bookmark when one is required.
Future<void> saveMusicFolder(Settings settings, String path) async {
  final bookmark = await macBookmarkForPath(path);
  await settings.setMusicFolder(path, macBookmark: bookmark);
}
