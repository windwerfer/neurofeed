import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Role of a calibration clip within a program's calibration sequence.
enum CalibrationPhase {
  /// Spoken/tone intro played once before the (silent) baseline collection,
  /// e.g. the ATR "short-clear" intro.
  intro,

  /// Phase A of the REVE protocol: artifact blink/jaw clip. Collected samples
  /// are never used as anchors; the recording captures the clip for repro.
  artifact,

  /// Phase B: eyes-open / counting (the "active" anchor).
  active,

  /// Phase C: eyes-closed / drifting rest (the "rest" anchor). Also the source
  /// of the V_clear reference vector for REVE.
  rest,
}

/// One entry in [CalibrationManifest]: the clip file + what it is for.
class CalibrationClip {
  const CalibrationClip({
    required this.id,
    required this.file,
    required this.protocols,
    required this.phase,
    this.eyes,
    this.text = '',
  });

  final String id;
  final String file;

  /// Protocol names (ProtocolType.name) this clip participates in.
  final List<String> protocols;

  final CalibrationPhase phase;

  /// `open`, `closed`, or null when the clip does not instruct an eye state.
  final String? eyes;

  /// Spoken transcript. Placeholder until real recordings are produced.
  final String text;

  factory CalibrationClip.fromJson(Map<String, Object?> json) {
    final phaseName = json['phase'] as String? ?? '';
    return CalibrationClip(
      id: json['id'] as String? ?? '',
      file: json['file'] as String? ?? '',
      protocols:
          (json['protocols'] as List<Object?>?)?.whereType<String>().toList() ??
          const [],
      phase:
          CalibrationPhase.values
              .where((p) => p.name == phaseName)
              .firstOrNull ??
          CalibrationPhase.intro,
      eyes: json['eyes'] as String?,
      text: json['text'] as String? ?? '',
    );
  }
}

/// Parsed `assets/audio/calibration/calibration.json`.
class CalibrationManifest {
  const CalibrationManifest({required this.version, required this.clips});

  /// Manifest schema version; persisted in session metadata.
  final int version;
  final List<CalibrationClip> clips;

  static const String asset = 'assets/audio/calibration/calibration.json';
  static const int currentVersion = 1;

  List<CalibrationClip> forProtocol(
    String protocolName, {
    CalibrationPhase? phase,
  }) {
    return clips.where((c) {
      if (!c.protocols.contains(protocolName)) {
        return false;
      }
      return phase == null || c.phase == phase;
    }).toList();
  }

  /// Intro clip for [protocolName], defaulting to the first listed variant.
  CalibrationClip? introFor(String protocolName) {
    final intros = forProtocol(protocolName, phase: CalibrationPhase.intro);
    return intros.isEmpty ? null : intros.first;
  }

  /// Ordered calibration clip sequence for [protocolName] (used by the REVE
  /// three-phase calibration; ATR sequences are a single intro clip).
  List<CalibrationClip> sequenceFor(String protocolName) {
    final order = CalibrationPhase.values;
    final clips = forProtocol(protocolName);
    clips.sort(
      (a, b) => order.indexOf(a.phase).compareTo(order.indexOf(b.phase)),
    );
    return clips;
  }

  static CalibrationManifest? fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      return null;
    }
    final raw = json['clips'] as List<Object?>? ?? const [];
    final clips = raw
        .whereType<Map<String, Object?>>()
        .map(CalibrationClip.fromJson)
        .toList();
    return CalibrationManifest(
      version: (json['version'] as num?)?.toInt() ?? currentVersion,
      clips: clips,
    );
  }

  static Future<CalibrationManifest> load() async {
    final raw = await rootBundle.loadString(asset);
    final parsed = fromJson(jsonDecode(raw));
    if (parsed == null) {
      throw FormatException('calibration.json is not a valid manifest');
    }
    return parsed;
  }
}

final calibrationManifestProvider = FutureProvider<CalibrationManifest>(
  (ref) => CalibrationManifest.load(),
);
