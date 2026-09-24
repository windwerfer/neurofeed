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

/// Wall-clock display for History / list / detail.
///
/// Prefers the numeric offset already written on [iso] (contract: local offset
/// on `savedAt`/`startedAt`). If the stamp is `Z`-only, applies [timeZone] when
/// it is an `Etc/GMT±N` / `Etc/UTC` id; otherwise falls back to device local.
String formatSessionWallClock(
  String? iso, {
  String? timeZone,
  bool includeMinutes = true,
}) {
  final wall = sessionWallClock(iso: iso, timeZone: timeZone);
  final y = wall.year.toString().padLeft(4, '0');
  final mo = _p2(wall.month);
  final d = _p2(wall.day);
  final h = _p2(wall.hour);
  final mi = _p2(wall.minute);
  if (!includeMinutes) return '$y-$mo-$d';
  return '$y-$mo-$d $h:$mi';
}

/// Naive local [DateTime] whose Y-M-D H:M:S match the session wall clock.
DateTime sessionWallClock({String? iso, String? timeZone}) {
  final raw = iso?.trim() ?? '';
  if (raw.isNotEmpty) {
    final m = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?',
    ).firstMatch(raw);
    final hasOffset = RegExp(r'(Z|[+-]\d{2}:\d{2})$').hasMatch(raw);
    final isZulu = raw.endsWith('Z');
    if (m != null && hasOffset && !isZulu) {
      // Offset-bearing stamp: wall digits are already site-local.
      return DateTime(
        int.parse(m.group(1)!),
        int.parse(m.group(2)!),
        int.parse(m.group(3)!),
        int.parse(m.group(4)!),
        int.parse(m.group(5)!),
        int.parse(m.group(6) ?? '0'),
      );
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed != null) {
      return _wallFromUtc(parsed.toUtc(), timeZone);
    }
  }
  return _wallFromUtc(DateTime.now().toUtc(), timeZone);
}

DateTime _wallFromUtc(DateTime utc, String? timeZone) {
  final tz = timeZone?.trim();
  if (tz == null || tz.isEmpty) {
    return utc.toLocal();
  }
  if (tz == 'Etc/UTC' || tz == 'UTC' || tz == 'Zulu') {
    return DateTime.utc(
      utc.year, utc.month, utc.day, utc.hour, utc.minute, utc.second, utc.millisecond,
    );
  }
  final etc = RegExp(r'^Etc/GMT([+-])?(\d{1,2})$').firstMatch(tz);
  if (etc != null) {
    // Etc/GMT ids invert civil sign: Etc/GMT-7 == UTC+7.
    final n = int.parse(etc.group(2)!);
    final signChar = etc.group(1);
    final civilHours = signChar == '+' ? -n : n;
    final local = utc.add(Duration(hours: civilHours));
    return DateTime(
      local.year, local.month, local.day, local.hour, local.minute, local.second,
      local.millisecond,
    );
  }
  // Full IANA without a TZ DB: device local is the honest fallback.
  return utc.toLocal();
}

