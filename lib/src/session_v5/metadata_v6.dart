import 'package:neurofeed/src/feedback/session_metadata.dart';
import 'package:neurofeed/src/monitor/recording/recording_metadata.dart';
import 'package:neurofeed/src/session_v5/models.dart';
import 'package:neurofeed/src/session_v5/stats_assemble.dart';
import 'package:neurofeed/src/settings.dart';
import 'package:neurofeed/src/util/timezone.dart';
import 'package:neurofeed/src/version.dart';

/// Locked file-format major for new NFED6 files.
const int kFormatVersionV6 = 6;

/// Build the locked **base** recording metadata object (no `feedback` key).
Map<String, Object?> buildRecordingMetadataV6({
  required RecordingMetadata meta,
  required SubjectInfo subject,
  String? sessionId,
  List<SessionAnnotation> annotations = const [],
  Map<String, Object?>? stats,
  String? notes,
}) {
  final tz = meta.timeZone ?? captureIanaTimeZone();
  final sid = (sessionId != null && sessionId.isNotEmpty)
      ? sessionId
      : meta.sessionId;
  return {
    'formatVersion': kFormatVersionV6,
    'appVersion': meta.appVersion.isEmpty ? appVersion : meta.appVersion,
    'kind': meta.kind == 'tmp' ? 'tmp' : 'recording',
    'savedAt': formatIso8601WithOffset(meta.savedAt),
    'startedAt': formatIso8601WithOffset(meta.startedAt),
    'timeZone': tz,
    'elapsedSeconds': meta.elapsedSeconds,
    'durationS': meta.durationS,
    'notes': notes ?? meta.notes,
    if (sid != null && sid.isNotEmpty) 'sessionId': sid,
    'subject': subject.toJson(),
    'device': meta.device.toJson(),
    'streams': meta.streams.toJson(),
    if (stats != null) 'stats': stats,
    if (annotations.isNotEmpty)
      'annotations': [for (final a in annotations) a.toJson()],
  };
}

/// Build locked feedback metadata: base + `feedback{}` only (no parallel
/// `gestures[]`, no shared-stats duplicates under feedback).
Map<String, Object?> buildFeedbackMetadataV6({
  required SessionMetadata meta,
  required SubjectInfo subject,
  DeviceInfoV5? device,
  StreamsConfig? streams,
  Map<String, Object?>? stats,
}) {
  final tz = meta.timeZone ?? captureIanaTimeZone();
  final anns = meta.annotations.isNotEmpty
      ? meta.annotations
      : assembleAnnotations(gestures: meta.gestures);

  final base = <String, Object?>{
    'formatVersion': kFormatVersionV6,
    'appVersion': appVersion,
    'kind': 'feedback',
    'savedAt': meta.savedAt.contains(RegExp(r'(Z|[+-]\d{2}:\d{2})$'))
        ? meta.savedAt
        : formatIso8601WithOffset(
            DateTime.tryParse(meta.savedAt) ?? DateTime.now(),
          ),
    if (meta.startedAt != null)
      'startedAt': meta.startedAt!.contains(RegExp(r'(Z|[+-]\d{2}:\d{2})$'))
          ? meta.startedAt
          : formatIso8601WithOffset(
              DateTime.tryParse(meta.startedAt!) ?? DateTime.now(),
            ),
    'timeZone': tz,
    'elapsedSeconds': meta.elapsedSeconds,
    'durationS': meta.durationS == 0 ? meta.elapsedSeconds : meta.durationS,
    'notes': meta.notes,
    if (meta.sessionId != null) 'sessionId': meta.sessionId,
    'subject': subject.toJson(),
    'device': (device ??
            DeviceInfoV5(
              name: meta.deviceName ?? '',
              id: meta.deviceId ?? '',
              firmware: meta.deviceModel ?? '',
              model: meta.deviceModel ?? '',
              sensors: const ['EEG', 'PPG', 'IMU'],
              channelCount: meta.recordedChannels.isEmpty
                  ? 4
                  : meta.recordedChannels.length,
              channelLabels: meta.recordedChannels.isEmpty
                  ? const ['TP9', 'AF7', 'AF8', 'TP10']
                  : meta.recordedChannels,
            ))
        .toJson(),
    'streams': (streams ??
            RecordingMetadata.streamsConfig(
              meta.recordedData.isEmpty
                  ? RecordingStream.values.toSet()
                  : meta.recordedData
                      .map(
                        (n) => RecordingStream.values
                            .where((s) => s.name == n)
                            .firstOrNull,
                      )
                      .whereType<RecordingStream>()
                      .toSet(),
            ))
        .toJson(),
    if (stats != null) 'stats': stats,
    if (anns.isNotEmpty) 'annotations': [for (final a in anns) a.toJson()],
  };

  base['feedback'] = _feedbackExtensionV6(meta);
  return base;
}

Map<String, Object?> _feedbackExtensionV6(SessionMetadata meta) {
  final outcome = <String, Object?>{};
  if (meta.pctInTarget != null) outcome['pctInTarget'] = meta.pctInTarget;
  if (meta.avgSleepDir != null) outcome['avgSleepDir'] = meta.avgSleepDir;
  if (meta.guardrailWarnCount != null) {
    outcome['guardrailWarnCount'] = meta.guardrailWarnCount;
  }
  if (meta.drowsiness != null) {
    outcome['scoreTotalPct'] = meta.drowsiness!.scoreTotalPct;
    if (meta.drowsiness!.meanSleepDir != 0) {
      outcome['meanSleepDir'] = meta.drowsiness!.meanSleepDir;
    }
  }

  final sessionSettings = <String, Object?>{};
  final ss = meta.sessionSettings;
  if (ss != null) {
    sessionSettings.addAll(ss.toJson());
  }

  return {
    'protocol': meta.protocol,
    if (meta.protocolVersion != null) 'protocolVersion': meta.protocolVersion,
    if (meta.protocolJson != null) 'protocolJson': meta.protocolJson,
    'durationMinutes': meta.durationMinutes,
    'sound': meta.sound,
    if (meta.feedbackSound != null) 'feedbackSound': meta.feedbackSound,
    if (meta.metadataDescription != null)
      'metadataDescription': meta.metadataDescription,
    if (meta.calibration != null) 'calibration': meta.calibration!.toJson(),
    if (meta.calibrationProfile != null)
      'calibrationProfile': meta.calibrationProfile,
    if (meta.music != null) 'music': meta.music!.toJson(),
    if (sessionSettings.isNotEmpty) 'sessionSettings': sessionSettings,
    if (outcome.isNotEmpty) 'outcomeScalars': outcome,
    if (meta.audioEvents.isNotEmpty) 'audioEvents': meta.audioEvents,
  };
}
