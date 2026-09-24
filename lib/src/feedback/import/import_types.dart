import 'dart:typed_data';

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
