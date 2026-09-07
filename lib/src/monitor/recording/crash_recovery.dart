import 'dart:io';

import 'package:flutter/foundation.dart';

bool isTmpScratchName(String name) {
  if (!name.startsWith('tmp_')) return false;
  return name.endsWith('.raw') ||
      name.endsWith('.computed') ||
      name.endsWith('.json') ||
      name.endsWith('.json.tmp');
}

/// Glob-delete leftover `tmp_*` scratch files. Does not touch `session_*` or
/// `recording_*` (those scanners stay prefix-strict).
Future<int> deleteLeftoverTmpCaptures(Directory scratch) async {
  if (!await scratch.exists()) return 0;
  var n = 0;
  await for (final entity in scratch.list()) {
    if (entity is! File) continue;
    final name = entity.uri.pathSegments.last;
    if (!isTmpScratchName(name)) continue;
    try {
      await entity.delete();
      n++;
      debugPrint('[monitor-crash] deleted leftover $name');
    } catch (e) {
      debugPrint('[monitor-crash] failed to delete $name: $e');
    }
  }
  return n;
}
