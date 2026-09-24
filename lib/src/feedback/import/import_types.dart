import 'dart:typed_data';

import 'package:neurofeed/src/feedback/session_metadata.dart';

/// Non-fatal note from an import (shown in snackbar / logged).
class ImportWarning {
  const ImportWarning(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Assembled recording ready to publish into History.
class ImportResult {
  const ImportResult({
    required this.id,
    required this.containerBytes,
    required this.metadataJson,
    this.warnings = const [],
  });

  /// Timestamp-style id used for `recording_$id.neurofeed`.
  final String id;

  /// Complete NFED6 `.neurofeed` bytes.
  final Uint8List containerBytes;

  /// Metadata map that was encoded (for tests / diagnostics).
  final Map<String, Object?> metadataJson;

  final List<ImportWarning> warnings;
}

/// Locked v6 annotation `type` tokens we accept from EDF TAL / CSV Elements.
const Set<String> kLockedAnnotationTypes = {
  'pause',
  'bad_quality',
  'disconnect',
  'double_blink',
  'double_jaw_clench',
  'eye_up',
  'eye_down',
};

/// Map free-text TAL / marker labels onto locked annotation types when possible.
/// Unknown tokens return null (skipped — do not invent types).
String? mapImportAnnotationType(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final snake = t.toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
  if (kLockedAnnotationTypes.contains(snake)) return snake;
  // Humanized export leftovers / Mind Monitor Elements doubles.
  return switch (snake) {
    'doubleblink' || 'double_blinks' => 'double_blink',
    'doubleclench' ||
    'double_clench' ||
    'double_jawclench' ||
    'jaw_clench_double' =>
      'double_jaw_clench',
    'eyeup' || 'eyes_up' => 'eye_up',
    'eyedown' || 'eyes_down' => 'eye_down',
    'badquality' || 'bad_qual' || 'unusable' => 'bad_quality',
    _ => null,
  };
}

/// First subfield of EDF Local Patient ID (`code sex birthdate name`).
/// Returns null when missing or anonymous `X`.
String? edfPatientCode(String patientId) {
  final parts = patientId.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return null;
  final code = parts.first.trim();
  if (code.isEmpty || code.toUpperCase() == 'X') return null;
  return code;
}

/// Window used to promote consecutive Mind Monitor Blink / Jaw_Clench into
/// locked double_* annotation types (matches [TrustGestureTracker]).
const Duration kElementsDoubleWindow = Duration(seconds: 2);

/// One Elements cell with recording-relative onset.
class ElementMark {
  const ElementMark({required this.onsetSeconds, required this.raw});
  final double onsetSeconds;
  final String raw;
}

/// Map Mind Monitor Elements column values onto locked annotation types.
///
/// Prefer (a) consecutive Blink / Jaw_Clench within [kElementsDoubleWindow] →
/// `double_blink` / `double_jaw_clench`; (b) skip singles with a warning;
/// numbered markers and unknown tokens get warnings. Never invent types
/// outside [kLockedAnnotationTypes].
({List<SessionAnnotation> annotations, List<ImportWarning> warnings})
    mapElementsToAnnotations(List<ElementMark> marks) {
  final warnings = <ImportWarning>[];
  final annotations = <SessionAnnotation>[];
  double? pendingBlinkAt;
  double? pendingJawAt;
  var skippedSingles = 0;
  var skippedMarkers = 0;
  var skippedUnknown = 0;

  void flushBlink({required bool asDouble, required double at}) {
    if (asDouble) {
      annotations.add(
        SessionAnnotation(onset: at, duration: 0, type: 'double_blink'),
      );
    } else {
      skippedSingles++;
    }
  }

  void flushJaw({required bool asDouble, required double at}) {
    if (asDouble) {
      annotations.add(
        SessionAnnotation(
          onset: at,
          duration: 0,
          type: 'double_jaw_clench',
        ),
      );
    } else {
      skippedSingles++;
    }
  }

  for (final m in marks) {
    final token = m.raw.trim();
    if (token.isEmpty) continue;
    final locked = mapImportAnnotationType(token);
    if (locked != null) {
      // Already a locked type (e.g. exported double_blink string).
      if (pendingBlinkAt != null) {
        flushBlink(asDouble: false, at: pendingBlinkAt!);
        pendingBlinkAt = null;
      }
      if (pendingJawAt != null) {
        flushJaw(asDouble: false, at: pendingJawAt!);
        pendingJawAt = null;
      }
      annotations.add(
        SessionAnnotation(onset: m.onsetSeconds, duration: 0, type: locked),
      );
      continue;
    }
    final lower = token.toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    final isBlink = lower == 'blink' || lower == '/muse/elements/blink';
    final isJaw = lower == 'jaw_clench' ||
        lower == 'jawclench' ||
        lower == '/muse/elements/jaw_clench';
    final isMarker = RegExp(r'^(/marker/)?\d+$').hasMatch(lower) ||
        lower.startsWith('/marker/') ||
        lower.startsWith('marker_');

    if (isBlink) {
      if (pendingJawAt != null) {
        flushJaw(asDouble: false, at: pendingJawAt!);
        pendingJawAt = null;
      }
      if (pendingBlinkAt != null &&
          (m.onsetSeconds - pendingBlinkAt!) <=
              kElementsDoubleWindow.inMilliseconds / 1000.0) {
        flushBlink(asDouble: true, at: m.onsetSeconds);
        pendingBlinkAt = null;
      } else {
        if (pendingBlinkAt != null) {
          flushBlink(asDouble: false, at: pendingBlinkAt!);
        }
        pendingBlinkAt = m.onsetSeconds;
      }
      continue;
    }
    if (isJaw) {
      if (pendingBlinkAt != null) {
        flushBlink(asDouble: false, at: pendingBlinkAt!);
        pendingBlinkAt = null;
      }
      if (pendingJawAt != null &&
          (m.onsetSeconds - pendingJawAt!) <=
              kElementsDoubleWindow.inMilliseconds / 1000.0) {
        flushJaw(asDouble: true, at: m.onsetSeconds);
        pendingJawAt = null;
      } else {
        if (pendingJawAt != null) {
          flushJaw(asDouble: false, at: pendingJawAt!);
        }
        pendingJawAt = m.onsetSeconds;
      }
      continue;
    }
    if (isMarker) {
      skippedMarkers++;
      continue;
    }
    skippedUnknown++;
  }
  if (pendingBlinkAt != null) {
    flushBlink(asDouble: false, at: pendingBlinkAt!);
  }
  if (pendingJawAt != null) {
    flushJaw(asDouble: false, at: pendingJawAt!);
  }
  if (skippedSingles > 0) {
    warnings.add(
      ImportWarning(
        'skipped $skippedSingles single Blink/Jaw_Clench '
        '(locked types are doubles only)',
      ),
    );
  }
  if (skippedMarkers > 0) {
    warnings.add(
      ImportWarning(
        'skipped $skippedMarkers numbered Elements markers '
        '(no locked note type)',
      ),
    );
  }
  if (skippedUnknown > 0) {
    warnings.add(
      ImportWarning('skipped $skippedUnknown unknown Elements values'),
    );
  }
  return (annotations: annotations, warnings: warnings);
}
