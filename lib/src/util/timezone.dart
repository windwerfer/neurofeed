import 'dart:io';

/// ISO-8601 with an explicit numeric offset (or `Z` when offset is zero).
/// Never returns Dart's naive local form. Prefers the device local offset at
/// [dt]'s instant so History can show wall clock without a second lookup.
String formatIso8601WithOffset(DateTime dt) {
  final local = dt.toLocal();
  final offset = local.timeZoneOffset;
  final y = local.year.toString().padLeft(4, '0');
  final mo = _p2(local.month);
  final d = _p2(local.day);
  final h = _p2(local.hour);
  final mi = _p2(local.minute);
  final s = _p2(local.second);
  final ms = local.millisecond.toString().padLeft(3, '0');
  if (offset == Duration.zero) {
    return '$y-$mo-$d' 'T$h:$mi:$s.$ms' 'Z';
  }
  final sign = offset.isNegative ? '-' : '+';
  final abs = offset.abs();
  final oh = _p2(abs.inHours);
  final om = _p2(abs.inMinutes.remainder(60));
  return '$y-$mo-$d' 'T$h:$mi:$s.$ms$sign$oh:$om';
}

/// Best-effort IANA id for the device zone at call time (offline, no network).
///
/// Order: `TZ` env → `/etc/timezone` (Linux) → `/etc/localtime` zoneinfo
/// symlink (macOS/Linux) → `Etc/GMT±N` from the current offset.
String captureIanaTimeZone() {
  final env = Platform.environment['TZ']?.trim();
  if (env != null && _looksIana(env)) {
    return env;
  }
  try {
    final etcTz = File('/etc/timezone');
    if (etcTz.existsSync()) {
      final z = etcTz.readAsStringSync().trim();
      if (_looksIana(z)) {
        return z;
      }
    }
  } catch (_) {}
  try {
    final link = Link('/etc/localtime');
    if (link.existsSync()) {
      final target = link.targetSync();
      final marker = '/zoneinfo/';
      final i = target.indexOf(marker);
      if (i >= 0) {
        final z = target.substring(i + marker.length);
        if (_looksIana(z)) {
          return z;
        }
      }
    }
  } catch (_) {}
  return etcGmtFromOffset(DateTime.now().timeZoneOffset);
}

/// `Etc/GMT` ids invert the civil sign (`Etc/GMT-7` == UTC+7).
String etcGmtFromOffset(Duration offset) {
  final minutes = offset.inMinutes;
  if (minutes == 0) {
    return 'Etc/UTC';
  }
  // Only whole-hour Etc/GMT ids are standard; fall back to nearest hour.
  final hours = (minutes / 60.0).round();
  if (hours == 0) {
    return 'Etc/UTC';
  }
  final sign = hours > 0 ? '-' : '+';
  return 'Etc/GMT$sign${hours.abs()}';
}

/// Local wall-clock components for EDF `startdate`/`starttime` from a
/// timezone-aware ISO string (prefer [startedAt]). Uses device [toLocal] —
/// correct when exporting on the recording device; offset on the timestamp
/// still yields the right absolute instant.
DateTime localWallClockFromIso({
  String? startedAt,
  String? savedAt,
  String? timeZone,
}) {
  final raw = (startedAt != null && startedAt.isNotEmpty)
      ? startedAt
      : (savedAt ?? '');
  final parsed = DateTime.tryParse(raw);
  if (parsed != null) {
    return parsed.toLocal();
  }
  return DateTime.now();
}

bool _looksIana(String z) {
  if (z.isEmpty || z.startsWith('/') || !z.contains('/')) {
    return false;
  }
  // Area/Location or Area/Location/Sub (e.g. America/Argentina/Buenos_Aires).
  return RegExp(r'^[A-Za-z_]+(?:/[A-Za-z0-9_+\-]+)+$').hasMatch(z);
}

String _p2(int n) => n.toString().padLeft(2, '0');
