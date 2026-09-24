import 'dart:convert';

/// Physio + feedback-outcome + experimental scalars promoted into sqlite.
///
/// Built from a v6 metadata map (`stats` + `feedback.outcomeScalars` +
/// `stats.experimental`) or from [assembleBaseStats] + an outcome map.
class SessionRowScalars {
  const SessionRowScalars({
    this.avgHr,
    this.hrMin,
    this.hrMax,
    this.avgSpo2,
    this.spo2Min,
    this.spo2Max,
    this.peakAlphaHz,
    this.peakAlphaPower,
    this.peakAlphaMeanHz,
    this.avgMovement,
    this.stillnessPct,
    this.signalQualityMean,
    this.pctQcOk,
    this.qualityChannelUsable,
    this.annotationPauseS,
    this.annotationBadQualityS,
    this.annotationDisconnectS,
    this.batteryStartPct,
    this.batteryEndPct,
    this.pctInTarget,
    this.avgAlphaRel,
    this.guardrailWarnCount,
    this.guardWarnPct,
    this.avgSleepDir,
    this.guardThreshold,
    this.experimentalScalars,
  });

  final double? avgHr;
  final double? hrMin;
  final double? hrMax;
  final double? avgSpo2;
  final double? spo2Min;
  final double? spo2Max;
  final double? peakAlphaHz;
  final double? peakAlphaPower;
  final double? peakAlphaMeanHz;
  final double? avgMovement;
  final double? stillnessPct;
  final double? signalQualityMean;
  final double? pctQcOk;
  /// JSON string of `stats.quality.channelUsable` map, or null.
  final String? qualityChannelUsable;
  final double? annotationPauseS;
  final double? annotationBadQualityS;
  final double? annotationDisconnectS;
  final double? batteryStartPct;
  final double? batteryEndPct;
  final double? pctInTarget;
  final double? avgAlphaRel;
  final int? guardrailWarnCount;
  final double? guardWarnPct;
  final double? avgSleepDir;
  final double? guardThreshold;
  /// JSON string of `stats.experimental`, or null when omitted.
  final String? experimentalScalars;

  /// Extract from a full v6 metadata JSON object.
  static SessionRowScalars fromV6Metadata(Map<String, Object?> meta) {
    final stats = _asMap(meta['stats']);
    final feedback = _asMap(meta['feedback']);
    final outcome = _asMap(feedback?['outcomeScalars']);
    return fromStatsAndOutcome(stats: stats, outcome: outcome);
  }

  /// Extract from assembled `stats` + `feedback.outcomeScalars` maps.
  static SessionRowScalars fromStatsAndOutcome({
    Map<String, Object?>? stats,
    Map<String, Object?>? outcome,
  }) {
    final hr = _asMap(stats?['hr']);
    final spo2 = _asMap(stats?['spo2']);
    final peak = _asMap(stats?['peakAlpha']);
    final mov = _asMap(stats?['movement']);
    final quality = _asMap(stats?['quality']);
    final ann = _asMap(stats?['annotationSeconds']);
    final battery = _asMap(stats?['battery']);
    final experimental = stats?['experimental'];

    String? channelUsableJson;
    final cu = quality?['channelUsable'];
    if (cu is Map && cu.isNotEmpty) {
      channelUsableJson = jsonEncode(cu);
    }

    String? experimentalJson;
    if (experimental is Map && experimental.isNotEmpty) {
      experimentalJson = jsonEncode(experimental);
    }

    return SessionRowScalars(
      avgHr: _d(hr?['mean']),
      hrMin: _d(hr?['min']),
      hrMax: _d(hr?['max']),
      avgSpo2: _d(spo2?['mean']),
      spo2Min: _d(spo2?['min']),
      spo2Max: _d(spo2?['max']),
      peakAlphaMeanHz: _d(peak?['meanHz']),
      peakAlphaHz: _d(peak?['maxPowerHz']),
      peakAlphaPower: _d(peak?['maxPower']),
      avgMovement: _d(mov?['mean']),
      stillnessPct: _d(mov?['stillnessPct']),
      signalQualityMean: _d(quality?['mean']),
      pctQcOk: _d(quality?['pctGood']),
      qualityChannelUsable: channelUsableJson,
      annotationPauseS: _d(ann?['pause']),
      annotationBadQualityS: _d(ann?['bad_quality']),
      annotationDisconnectS: _d(ann?['disconnect']),
      batteryStartPct: _d(battery?['startPct']),
      batteryEndPct: _d(battery?['endPct']),
      pctInTarget: _d(outcome?['pctInTarget']),
      avgAlphaRel: _d(outcome?['avgAlphaRel']),
      guardrailWarnCount: _i(outcome?['guardrailWarnCount']),
      guardWarnPct: _d(outcome?['guardWarnPct']) ??
          _d(outcome?['scoreTotalPct']),
      avgSleepDir: _d(outcome?['avgSleepDir']) ??
          _d(outcome?['meanSleepDir']),
      guardThreshold: _d(outcome?['guardThreshold']) ??
          _d(outcome?['threshold']),
      experimentalScalars: experimentalJson,
    );
  }

  static Map<String, Object?>? _asMap(Object? v) {
    if (v is Map<String, Object?>) return v;
    if (v is Map) {
      return <String, Object?>{
        for (final e in v.entries) e.key.toString(): e.value,
      };
    }
    return null;
  }

  static double? _d(Object? v) => (v as num?)?.toDouble();
  static int? _i(Object? v) => (v as num?)?.toInt();
}
