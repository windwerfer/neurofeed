// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session_metadata.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

SessionMetadata _$SessionMetadataFromJson(Map<String, dynamic> json) {
  return _SessionMetadata.fromJson(json);
}

/// @nodoc
mixin _$SessionMetadata {
  String get protocol => throw _privateConstructorUsedError;
  int get durationMinutes => throw _privateConstructorUsedError;
  int get elapsedSeconds => throw _privateConstructorUsedError;
  String get sound => throw _privateConstructorUsedError;
  String get savedAt => throw _privateConstructorUsedError;
  String get notes => throw _privateConstructorUsedError;
  SessionStatsData? get stats => throw _privateConstructorUsedError;
  String? get deviceName => throw _privateConstructorUsedError;
  String? get deviceModel => throw _privateConstructorUsedError;
  String? get deviceId => throw _privateConstructorUsedError;
  List<String> get recordedChannels => throw _privateConstructorUsedError;
  List<String> get recordedData => throw _privateConstructorUsedError;
  SessionOverview? get summary => throw _privateConstructorUsedError;
  List<GestureMarker> get gestures => throw _privateConstructorUsedError;
  SessionCalibration? get calibration => throw _privateConstructorUsedError;
  SessionDrowsiness? get drowsiness => throw _privateConstructorUsedError;
  SessionMusic? get music => throw _privateConstructorUsedError;
  String? get feedbackSound => throw _privateConstructorUsedError;
  String? get metadataDescription => throw _privateConstructorUsedError;
  SessionSettings? get sessionSettings => throw _privateConstructorUsedError;
  int get formatVersion => throw _privateConstructorUsedError;
  String get appVersion => throw _privateConstructorUsedError;
  DeviceInfoV5? get device => throw _privateConstructorUsedError;
  StreamsConfig? get streams => throw _privateConstructorUsedError;
  ModelSnapshot? get modelSnapshot => throw _privateConstructorUsedError;

  /// Serializes this SessionMetadata to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SessionMetadata
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SessionMetadataCopyWith<SessionMetadata> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SessionMetadataCopyWith<$Res> {
  factory $SessionMetadataCopyWith(
    SessionMetadata value,
    $Res Function(SessionMetadata) then,
  ) = _$SessionMetadataCopyWithImpl<$Res, SessionMetadata>;
  @useResult
  $Res call({
    String protocol,
    int durationMinutes,
    int elapsedSeconds,
    String sound,
    String savedAt,
    String notes,
    SessionStatsData? stats,
    String? deviceName,
    String? deviceModel,
    String? deviceId,
    List<String> recordedChannels,
    List<String> recordedData,
    SessionOverview? summary,
    List<GestureMarker> gestures,
    SessionCalibration? calibration,
    SessionDrowsiness? drowsiness,
    SessionMusic? music,
    String? feedbackSound,
    String? metadataDescription,
    SessionSettings? sessionSettings,
    int formatVersion,
    String appVersion,
    DeviceInfoV5? device,
    StreamsConfig? streams,
    ModelSnapshot? modelSnapshot,
  });

  $SessionStatsDataCopyWith<$Res>? get stats;
  $SessionSettingsCopyWith<$Res>? get sessionSettings;
}

/// @nodoc
class _$SessionMetadataCopyWithImpl<$Res, $Val extends SessionMetadata>
    implements $SessionMetadataCopyWith<$Res> {
  _$SessionMetadataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SessionMetadata
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? protocol = null,
    Object? durationMinutes = null,
    Object? elapsedSeconds = null,
    Object? sound = null,
    Object? savedAt = null,
    Object? notes = null,
    Object? stats = freezed,
    Object? deviceName = freezed,
    Object? deviceModel = freezed,
    Object? deviceId = freezed,
    Object? recordedChannels = null,
    Object? recordedData = null,
    Object? summary = freezed,
    Object? gestures = null,
    Object? calibration = freezed,
    Object? drowsiness = freezed,
    Object? music = freezed,
    Object? feedbackSound = freezed,
    Object? metadataDescription = freezed,
    Object? sessionSettings = freezed,
    Object? formatVersion = null,
    Object? appVersion = null,
    Object? device = freezed,
    Object? streams = freezed,
    Object? modelSnapshot = freezed,
  }) {
    return _then(
      _value.copyWith(
            protocol: null == protocol
                ? _value.protocol
                : protocol // ignore: cast_nullable_to_non_nullable
                      as String,
            durationMinutes: null == durationMinutes
                ? _value.durationMinutes
                : durationMinutes // ignore: cast_nullable_to_non_nullable
                      as int,
            elapsedSeconds: null == elapsedSeconds
                ? _value.elapsedSeconds
                : elapsedSeconds // ignore: cast_nullable_to_non_nullable
                      as int,
            sound: null == sound
                ? _value.sound
                : sound // ignore: cast_nullable_to_non_nullable
                      as String,
            savedAt: null == savedAt
                ? _value.savedAt
                : savedAt // ignore: cast_nullable_to_non_nullable
                      as String,
            notes: null == notes
                ? _value.notes
                : notes // ignore: cast_nullable_to_non_nullable
                      as String,
            stats: freezed == stats
                ? _value.stats
                : stats // ignore: cast_nullable_to_non_nullable
                      as SessionStatsData?,
            deviceName: freezed == deviceName
                ? _value.deviceName
                : deviceName // ignore: cast_nullable_to_non_nullable
                      as String?,
            deviceModel: freezed == deviceModel
                ? _value.deviceModel
                : deviceModel // ignore: cast_nullable_to_non_nullable
                      as String?,
            deviceId: freezed == deviceId
                ? _value.deviceId
                : deviceId // ignore: cast_nullable_to_non_nullable
                      as String?,
            recordedChannels: null == recordedChannels
                ? _value.recordedChannels
                : recordedChannels // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            recordedData: null == recordedData
                ? _value.recordedData
                : recordedData // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            summary: freezed == summary
                ? _value.summary
                : summary // ignore: cast_nullable_to_non_nullable
                      as SessionOverview?,
            gestures: null == gestures
                ? _value.gestures
                : gestures // ignore: cast_nullable_to_non_nullable
                      as List<GestureMarker>,
            calibration: freezed == calibration
                ? _value.calibration
                : calibration // ignore: cast_nullable_to_non_nullable
                      as SessionCalibration?,
            drowsiness: freezed == drowsiness
                ? _value.drowsiness
                : drowsiness // ignore: cast_nullable_to_non_nullable
                      as SessionDrowsiness?,
            music: freezed == music
                ? _value.music
                : music // ignore: cast_nullable_to_non_nullable
                      as SessionMusic?,
            feedbackSound: freezed == feedbackSound
                ? _value.feedbackSound
                : feedbackSound // ignore: cast_nullable_to_non_nullable
                      as String?,
            metadataDescription: freezed == metadataDescription
                ? _value.metadataDescription
                : metadataDescription // ignore: cast_nullable_to_non_nullable
                      as String?,
            sessionSettings: freezed == sessionSettings
                ? _value.sessionSettings
                : sessionSettings // ignore: cast_nullable_to_non_nullable
                      as SessionSettings?,
            formatVersion: null == formatVersion
                ? _value.formatVersion
                : formatVersion // ignore: cast_nullable_to_non_nullable
                      as int,
            appVersion: null == appVersion
                ? _value.appVersion
                : appVersion // ignore: cast_nullable_to_non_nullable
                      as String,
            device: freezed == device
                ? _value.device
                : device // ignore: cast_nullable_to_non_nullable
                      as DeviceInfoV5?,
            streams: freezed == streams
                ? _value.streams
                : streams // ignore: cast_nullable_to_non_nullable
                      as StreamsConfig?,
            modelSnapshot: freezed == modelSnapshot
                ? _value.modelSnapshot
                : modelSnapshot // ignore: cast_nullable_to_non_nullable
                      as ModelSnapshot?,
          )
          as $Val,
    );
  }

  /// Create a copy of SessionMetadata
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $SessionStatsDataCopyWith<$Res>? get stats {
    if (_value.stats == null) {
      return null;
    }

    return $SessionStatsDataCopyWith<$Res>(_value.stats!, (value) {
      return _then(_value.copyWith(stats: value) as $Val);
    });
  }

  /// Create a copy of SessionMetadata
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $SessionSettingsCopyWith<$Res>? get sessionSettings {
    if (_value.sessionSettings == null) {
      return null;
    }

    return $SessionSettingsCopyWith<$Res>(_value.sessionSettings!, (value) {
      return _then(_value.copyWith(sessionSettings: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$SessionMetadataImplCopyWith<$Res>
    implements $SessionMetadataCopyWith<$Res> {
  factory _$$SessionMetadataImplCopyWith(
    _$SessionMetadataImpl value,
    $Res Function(_$SessionMetadataImpl) then,
  ) = __$$SessionMetadataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String protocol,
    int durationMinutes,
    int elapsedSeconds,
    String sound,
    String savedAt,
    String notes,
    SessionStatsData? stats,
    String? deviceName,
    String? deviceModel,
    String? deviceId,
    List<String> recordedChannels,
    List<String> recordedData,
    SessionOverview? summary,
    List<GestureMarker> gestures,
    SessionCalibration? calibration,
    SessionDrowsiness? drowsiness,
    SessionMusic? music,
    String? feedbackSound,
    String? metadataDescription,
    SessionSettings? sessionSettings,
    int formatVersion,
    String appVersion,
    DeviceInfoV5? device,
    StreamsConfig? streams,
    ModelSnapshot? modelSnapshot,
  });

  @override
  $SessionStatsDataCopyWith<$Res>? get stats;
  @override
  $SessionSettingsCopyWith<$Res>? get sessionSettings;
}

/// @nodoc
class __$$SessionMetadataImplCopyWithImpl<$Res>
    extends _$SessionMetadataCopyWithImpl<$Res, _$SessionMetadataImpl>
    implements _$$SessionMetadataImplCopyWith<$Res> {
  __$$SessionMetadataImplCopyWithImpl(
    _$SessionMetadataImpl _value,
    $Res Function(_$SessionMetadataImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SessionMetadata
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? protocol = null,
    Object? durationMinutes = null,
    Object? elapsedSeconds = null,
    Object? sound = null,
    Object? savedAt = null,
    Object? notes = null,
    Object? stats = freezed,
    Object? deviceName = freezed,
    Object? deviceModel = freezed,
    Object? deviceId = freezed,
    Object? recordedChannels = null,
    Object? recordedData = null,
    Object? summary = freezed,
    Object? gestures = null,
    Object? calibration = freezed,
    Object? drowsiness = freezed,
    Object? music = freezed,
    Object? feedbackSound = freezed,
    Object? metadataDescription = freezed,
    Object? sessionSettings = freezed,
    Object? formatVersion = null,
    Object? appVersion = null,
    Object? device = freezed,
    Object? streams = freezed,
    Object? modelSnapshot = freezed,
  }) {
    return _then(
      _$SessionMetadataImpl(
        protocol: null == protocol
            ? _value.protocol
            : protocol // ignore: cast_nullable_to_non_nullable
                  as String,
        durationMinutes: null == durationMinutes
            ? _value.durationMinutes
            : durationMinutes // ignore: cast_nullable_to_non_nullable
                  as int,
        elapsedSeconds: null == elapsedSeconds
            ? _value.elapsedSeconds
            : elapsedSeconds // ignore: cast_nullable_to_non_nullable
                  as int,
        sound: null == sound
            ? _value.sound
            : sound // ignore: cast_nullable_to_non_nullable
                  as String,
        savedAt: null == savedAt
            ? _value.savedAt
            : savedAt // ignore: cast_nullable_to_non_nullable
                  as String,
        notes: null == notes
            ? _value.notes
            : notes // ignore: cast_nullable_to_non_nullable
                  as String,
        stats: freezed == stats
            ? _value.stats
            : stats // ignore: cast_nullable_to_non_nullable
                  as SessionStatsData?,
        deviceName: freezed == deviceName
            ? _value.deviceName
            : deviceName // ignore: cast_nullable_to_non_nullable
                  as String?,
        deviceModel: freezed == deviceModel
            ? _value.deviceModel
            : deviceModel // ignore: cast_nullable_to_non_nullable
                  as String?,
        deviceId: freezed == deviceId
            ? _value.deviceId
            : deviceId // ignore: cast_nullable_to_non_nullable
                  as String?,
        recordedChannels: null == recordedChannels
            ? _value._recordedChannels
            : recordedChannels // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        recordedData: null == recordedData
            ? _value._recordedData
            : recordedData // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        summary: freezed == summary
            ? _value.summary
            : summary // ignore: cast_nullable_to_non_nullable
                  as SessionOverview?,
        gestures: null == gestures
            ? _value._gestures
            : gestures // ignore: cast_nullable_to_non_nullable
                  as List<GestureMarker>,
        calibration: freezed == calibration
            ? _value.calibration
            : calibration // ignore: cast_nullable_to_non_nullable
                  as SessionCalibration?,
        drowsiness: freezed == drowsiness
            ? _value.drowsiness
            : drowsiness // ignore: cast_nullable_to_non_nullable
                  as SessionDrowsiness?,
        music: freezed == music
            ? _value.music
            : music // ignore: cast_nullable_to_non_nullable
                  as SessionMusic?,
        feedbackSound: freezed == feedbackSound
            ? _value.feedbackSound
            : feedbackSound // ignore: cast_nullable_to_non_nullable
                  as String?,
        metadataDescription: freezed == metadataDescription
            ? _value.metadataDescription
            : metadataDescription // ignore: cast_nullable_to_non_nullable
                  as String?,
        sessionSettings: freezed == sessionSettings
            ? _value.sessionSettings
            : sessionSettings // ignore: cast_nullable_to_non_nullable
                  as SessionSettings?,
        formatVersion: null == formatVersion
            ? _value.formatVersion
            : formatVersion // ignore: cast_nullable_to_non_nullable
                  as int,
        appVersion: null == appVersion
            ? _value.appVersion
            : appVersion // ignore: cast_nullable_to_non_nullable
                  as String,
        device: freezed == device
            ? _value.device
            : device // ignore: cast_nullable_to_non_nullable
                  as DeviceInfoV5?,
        streams: freezed == streams
            ? _value.streams
            : streams // ignore: cast_nullable_to_non_nullable
                  as StreamsConfig?,
        modelSnapshot: freezed == modelSnapshot
            ? _value.modelSnapshot
            : modelSnapshot // ignore: cast_nullable_to_non_nullable
                  as ModelSnapshot?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$SessionMetadataImpl implements _SessionMetadata {
  const _$SessionMetadataImpl({
    required this.protocol,
    required this.durationMinutes,
    required this.elapsedSeconds,
    required this.sound,
    required this.savedAt,
    this.notes = '',
    this.stats,
    this.deviceName,
    this.deviceModel,
    this.deviceId,
    final List<String> recordedChannels = const [],
    final List<String> recordedData = const [],
    this.summary,
    final List<GestureMarker> gestures = const [],
    this.calibration,
    this.drowsiness,
    this.music,
    this.feedbackSound,
    this.metadataDescription,
    this.sessionSettings,
    this.formatVersion = 5,
    this.appVersion = '1.0.0+1',
    this.device,
    this.streams,
    this.modelSnapshot,
  }) : _recordedChannels = recordedChannels,
       _recordedData = recordedData,
       _gestures = gestures;

  factory _$SessionMetadataImpl.fromJson(Map<String, dynamic> json) =>
      _$$SessionMetadataImplFromJson(json);

  @override
  final String protocol;
  @override
  final int durationMinutes;
  @override
  final int elapsedSeconds;
  @override
  final String sound;
  @override
  final String savedAt;
  @override
  @JsonKey()
  final String notes;
  @override
  final SessionStatsData? stats;
  @override
  final String? deviceName;
  @override
  final String? deviceModel;
  @override
  final String? deviceId;
  final List<String> _recordedChannels;
  @override
  @JsonKey()
  List<String> get recordedChannels {
    if (_recordedChannels is EqualUnmodifiableListView)
      return _recordedChannels;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_recordedChannels);
  }

  final List<String> _recordedData;
  @override
  @JsonKey()
  List<String> get recordedData {
    if (_recordedData is EqualUnmodifiableListView) return _recordedData;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_recordedData);
  }

  @override
  final SessionOverview? summary;
  final List<GestureMarker> _gestures;
  @override
  @JsonKey()
  List<GestureMarker> get gestures {
    if (_gestures is EqualUnmodifiableListView) return _gestures;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_gestures);
  }

  @override
  final SessionCalibration? calibration;
  @override
  final SessionDrowsiness? drowsiness;
  @override
  final SessionMusic? music;
  @override
  final String? feedbackSound;
  @override
  final String? metadataDescription;
  @override
  final SessionSettings? sessionSettings;
  @override
  @JsonKey()
  final int formatVersion;
  @override
  @JsonKey()
  final String appVersion;
  @override
  final DeviceInfoV5? device;
  @override
  final StreamsConfig? streams;
  @override
  final ModelSnapshot? modelSnapshot;

  @override
  String toString() {
    return 'SessionMetadata(protocol: $protocol, durationMinutes: $durationMinutes, elapsedSeconds: $elapsedSeconds, sound: $sound, savedAt: $savedAt, notes: $notes, stats: $stats, deviceName: $deviceName, deviceModel: $deviceModel, deviceId: $deviceId, recordedChannels: $recordedChannels, recordedData: $recordedData, summary: $summary, gestures: $gestures, calibration: $calibration, drowsiness: $drowsiness, music: $music, feedbackSound: $feedbackSound, metadataDescription: $metadataDescription, sessionSettings: $sessionSettings, formatVersion: $formatVersion, appVersion: $appVersion, device: $device, streams: $streams, modelSnapshot: $modelSnapshot)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SessionMetadataImpl &&
            (identical(other.protocol, protocol) ||
                other.protocol == protocol) &&
            (identical(other.durationMinutes, durationMinutes) ||
                other.durationMinutes == durationMinutes) &&
            (identical(other.elapsedSeconds, elapsedSeconds) ||
                other.elapsedSeconds == elapsedSeconds) &&
            (identical(other.sound, sound) || other.sound == sound) &&
            (identical(other.savedAt, savedAt) || other.savedAt == savedAt) &&
            (identical(other.notes, notes) || other.notes == notes) &&
            (identical(other.stats, stats) || other.stats == stats) &&
            (identical(other.deviceName, deviceName) ||
                other.deviceName == deviceName) &&
            (identical(other.deviceModel, deviceModel) ||
                other.deviceModel == deviceModel) &&
            (identical(other.deviceId, deviceId) ||
                other.deviceId == deviceId) &&
            const DeepCollectionEquality().equals(
              other._recordedChannels,
              _recordedChannels,
            ) &&
            const DeepCollectionEquality().equals(
              other._recordedData,
              _recordedData,
            ) &&
            (identical(other.summary, summary) || other.summary == summary) &&
            const DeepCollectionEquality().equals(other._gestures, _gestures) &&
            (identical(other.calibration, calibration) ||
                other.calibration == calibration) &&
            (identical(other.drowsiness, drowsiness) ||
                other.drowsiness == drowsiness) &&
            (identical(other.music, music) || other.music == music) &&
            (identical(other.feedbackSound, feedbackSound) ||
                other.feedbackSound == feedbackSound) &&
            (identical(other.metadataDescription, metadataDescription) ||
                other.metadataDescription == metadataDescription) &&
            (identical(other.sessionSettings, sessionSettings) ||
                other.sessionSettings == sessionSettings) &&
            (identical(other.formatVersion, formatVersion) ||
                other.formatVersion == formatVersion) &&
            (identical(other.appVersion, appVersion) ||
                other.appVersion == appVersion) &&
            (identical(other.device, device) || other.device == device) &&
            (identical(other.streams, streams) || other.streams == streams) &&
            (identical(other.modelSnapshot, modelSnapshot) ||
                other.modelSnapshot == modelSnapshot));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hashAll([
    runtimeType,
    protocol,
    durationMinutes,
    elapsedSeconds,
    sound,
    savedAt,
    notes,
    stats,
    deviceName,
    deviceModel,
    deviceId,
    const DeepCollectionEquality().hash(_recordedChannels),
    const DeepCollectionEquality().hash(_recordedData),
    summary,
    const DeepCollectionEquality().hash(_gestures),
    calibration,
    drowsiness,
    music,
    feedbackSound,
    metadataDescription,
    sessionSettings,
    formatVersion,
    appVersion,
    device,
    streams,
    modelSnapshot,
  ]);

  /// Create a copy of SessionMetadata
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SessionMetadataImplCopyWith<_$SessionMetadataImpl> get copyWith =>
      __$$SessionMetadataImplCopyWithImpl<_$SessionMetadataImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$SessionMetadataImplToJson(this);
  }
}

abstract class _SessionMetadata implements SessionMetadata {
  const factory _SessionMetadata({
    required final String protocol,
    required final int durationMinutes,
    required final int elapsedSeconds,
    required final String sound,
    required final String savedAt,
    final String notes,
    final SessionStatsData? stats,
    final String? deviceName,
    final String? deviceModel,
    final String? deviceId,
    final List<String> recordedChannels,
    final List<String> recordedData,
    final SessionOverview? summary,
    final List<GestureMarker> gestures,
    final SessionCalibration? calibration,
    final SessionDrowsiness? drowsiness,
    final SessionMusic? music,
    final String? feedbackSound,
    final String? metadataDescription,
    final SessionSettings? sessionSettings,
    final int formatVersion,
    final String appVersion,
    final DeviceInfoV5? device,
    final StreamsConfig? streams,
    final ModelSnapshot? modelSnapshot,
  }) = _$SessionMetadataImpl;

  factory _SessionMetadata.fromJson(Map<String, dynamic> json) =
      _$SessionMetadataImpl.fromJson;

  @override
  String get protocol;
  @override
  int get durationMinutes;
  @override
  int get elapsedSeconds;
  @override
  String get sound;
  @override
  String get savedAt;
  @override
  String get notes;
  @override
  SessionStatsData? get stats;
  @override
  String? get deviceName;
  @override
  String? get deviceModel;
  @override
  String? get deviceId;
  @override
  List<String> get recordedChannels;
  @override
  List<String> get recordedData;
  @override
  SessionOverview? get summary;
  @override
  List<GestureMarker> get gestures;
  @override
  SessionCalibration? get calibration;
  @override
  SessionDrowsiness? get drowsiness;
  @override
  SessionMusic? get music;
  @override
  String? get feedbackSound;
  @override
  String? get metadataDescription;
  @override
  SessionSettings? get sessionSettings;
  @override
  int get formatVersion;
  @override
  String get appVersion;
  @override
  DeviceInfoV5? get device;
  @override
  StreamsConfig? get streams;
  @override
  ModelSnapshot? get modelSnapshot;

  /// Create a copy of SessionMetadata
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SessionMetadataImplCopyWith<_$SessionMetadataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

SessionStatsData _$SessionStatsDataFromJson(Map<String, dynamic> json) {
  return _SessionStatsData.fromJson(json);
}

/// @nodoc
mixin _$SessionStatsData {
  double? get peakAlphaFreq => throw _privateConstructorUsedError;
  double? get peakAlphaPower => throw _privateConstructorUsedError;
  double? get targetPct => throw _privateConstructorUsedError;
  double? get stillnessPct => throw _privateConstructorUsedError;
  double? get avgBpm => throw _privateConstructorUsedError;
  double? get avgAlphaRel => throw _privateConstructorUsedError;

  /// Serializes this SessionStatsData to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SessionStatsData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SessionStatsDataCopyWith<SessionStatsData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SessionStatsDataCopyWith<$Res> {
  factory $SessionStatsDataCopyWith(
    SessionStatsData value,
    $Res Function(SessionStatsData) then,
  ) = _$SessionStatsDataCopyWithImpl<$Res, SessionStatsData>;
  @useResult
  $Res call({
    double? peakAlphaFreq,
    double? peakAlphaPower,
    double? targetPct,
    double? stillnessPct,
    double? avgBpm,
    double? avgAlphaRel,
  });
}

/// @nodoc
class _$SessionStatsDataCopyWithImpl<$Res, $Val extends SessionStatsData>
    implements $SessionStatsDataCopyWith<$Res> {
  _$SessionStatsDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SessionStatsData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? peakAlphaFreq = freezed,
    Object? peakAlphaPower = freezed,
    Object? targetPct = freezed,
    Object? stillnessPct = freezed,
    Object? avgBpm = freezed,
    Object? avgAlphaRel = freezed,
  }) {
    return _then(
      _value.copyWith(
            peakAlphaFreq: freezed == peakAlphaFreq
                ? _value.peakAlphaFreq
                : peakAlphaFreq // ignore: cast_nullable_to_non_nullable
                      as double?,
            peakAlphaPower: freezed == peakAlphaPower
                ? _value.peakAlphaPower
                : peakAlphaPower // ignore: cast_nullable_to_non_nullable
                      as double?,
            targetPct: freezed == targetPct
                ? _value.targetPct
                : targetPct // ignore: cast_nullable_to_non_nullable
                      as double?,
            stillnessPct: freezed == stillnessPct
                ? _value.stillnessPct
                : stillnessPct // ignore: cast_nullable_to_non_nullable
                      as double?,
            avgBpm: freezed == avgBpm
                ? _value.avgBpm
                : avgBpm // ignore: cast_nullable_to_non_nullable
                      as double?,
            avgAlphaRel: freezed == avgAlphaRel
                ? _value.avgAlphaRel
                : avgAlphaRel // ignore: cast_nullable_to_non_nullable
                      as double?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$SessionStatsDataImplCopyWith<$Res>
    implements $SessionStatsDataCopyWith<$Res> {
  factory _$$SessionStatsDataImplCopyWith(
    _$SessionStatsDataImpl value,
    $Res Function(_$SessionStatsDataImpl) then,
  ) = __$$SessionStatsDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    double? peakAlphaFreq,
    double? peakAlphaPower,
    double? targetPct,
    double? stillnessPct,
    double? avgBpm,
    double? avgAlphaRel,
  });
}

/// @nodoc
class __$$SessionStatsDataImplCopyWithImpl<$Res>
    extends _$SessionStatsDataCopyWithImpl<$Res, _$SessionStatsDataImpl>
    implements _$$SessionStatsDataImplCopyWith<$Res> {
  __$$SessionStatsDataImplCopyWithImpl(
    _$SessionStatsDataImpl _value,
    $Res Function(_$SessionStatsDataImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SessionStatsData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? peakAlphaFreq = freezed,
    Object? peakAlphaPower = freezed,
    Object? targetPct = freezed,
    Object? stillnessPct = freezed,
    Object? avgBpm = freezed,
    Object? avgAlphaRel = freezed,
  }) {
    return _then(
      _$SessionStatsDataImpl(
        peakAlphaFreq: freezed == peakAlphaFreq
            ? _value.peakAlphaFreq
            : peakAlphaFreq // ignore: cast_nullable_to_non_nullable
                  as double?,
        peakAlphaPower: freezed == peakAlphaPower
            ? _value.peakAlphaPower
            : peakAlphaPower // ignore: cast_nullable_to_non_nullable
                  as double?,
        targetPct: freezed == targetPct
            ? _value.targetPct
            : targetPct // ignore: cast_nullable_to_non_nullable
                  as double?,
        stillnessPct: freezed == stillnessPct
            ? _value.stillnessPct
            : stillnessPct // ignore: cast_nullable_to_non_nullable
                  as double?,
        avgBpm: freezed == avgBpm
            ? _value.avgBpm
            : avgBpm // ignore: cast_nullable_to_non_nullable
                  as double?,
        avgAlphaRel: freezed == avgAlphaRel
            ? _value.avgAlphaRel
            : avgAlphaRel // ignore: cast_nullable_to_non_nullable
                  as double?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$SessionStatsDataImpl implements _SessionStatsData {
  const _$SessionStatsDataImpl({
    this.peakAlphaFreq,
    this.peakAlphaPower,
    this.targetPct,
    this.stillnessPct,
    this.avgBpm,
    this.avgAlphaRel,
  });

  factory _$SessionStatsDataImpl.fromJson(Map<String, dynamic> json) =>
      _$$SessionStatsDataImplFromJson(json);

  @override
  final double? peakAlphaFreq;
  @override
  final double? peakAlphaPower;
  @override
  final double? targetPct;
  @override
  final double? stillnessPct;
  @override
  final double? avgBpm;
  @override
  final double? avgAlphaRel;

  @override
  String toString() {
    return 'SessionStatsData(peakAlphaFreq: $peakAlphaFreq, peakAlphaPower: $peakAlphaPower, targetPct: $targetPct, stillnessPct: $stillnessPct, avgBpm: $avgBpm, avgAlphaRel: $avgAlphaRel)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SessionStatsDataImpl &&
            (identical(other.peakAlphaFreq, peakAlphaFreq) ||
                other.peakAlphaFreq == peakAlphaFreq) &&
            (identical(other.peakAlphaPower, peakAlphaPower) ||
                other.peakAlphaPower == peakAlphaPower) &&
            (identical(other.targetPct, targetPct) ||
                other.targetPct == targetPct) &&
            (identical(other.stillnessPct, stillnessPct) ||
                other.stillnessPct == stillnessPct) &&
            (identical(other.avgBpm, avgBpm) || other.avgBpm == avgBpm) &&
            (identical(other.avgAlphaRel, avgAlphaRel) ||
                other.avgAlphaRel == avgAlphaRel));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    peakAlphaFreq,
    peakAlphaPower,
    targetPct,
    stillnessPct,
    avgBpm,
    avgAlphaRel,
  );

  /// Create a copy of SessionStatsData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SessionStatsDataImplCopyWith<_$SessionStatsDataImpl> get copyWith =>
      __$$SessionStatsDataImplCopyWithImpl<_$SessionStatsDataImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$SessionStatsDataImplToJson(this);
  }
}

abstract class _SessionStatsData implements SessionStatsData {
  const factory _SessionStatsData({
    final double? peakAlphaFreq,
    final double? peakAlphaPower,
    final double? targetPct,
    final double? stillnessPct,
    final double? avgBpm,
    final double? avgAlphaRel,
  }) = _$SessionStatsDataImpl;

  factory _SessionStatsData.fromJson(Map<String, dynamic> json) =
      _$SessionStatsDataImpl.fromJson;

  @override
  double? get peakAlphaFreq;
  @override
  double? get peakAlphaPower;
  @override
  double? get targetPct;
  @override
  double? get stillnessPct;
  @override
  double? get avgBpm;
  @override
  double? get avgAlphaRel;

  /// Create a copy of SessionStatsData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SessionStatsDataImplCopyWith<_$SessionStatsDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

SessionSettings _$SessionSettingsFromJson(Map<String, dynamic> json) {
  return _SessionSettings.fromJson(json);
}

/// @nodoc
mixin _$SessionSettings {
  bool get dynamicAdapt => throw _privateConstructorUsedError;
  double get responsiveness => throw _privateConstructorUsedError;
  int get baselinePercentile => throw _privateConstructorUsedError;
  bool get guardrailEnabled => throw _privateConstructorUsedError;
  String get guardrailEngine => throw _privateConstructorUsedError;
  int get warningThresholdPercentile => throw _privateConstructorUsedError;
  String get warningSound => throw _privateConstructorUsedError;
  String? get musicFolder => throw _privateConstructorUsedError;
  double get musicMinCutoffHz => throw _privateConstructorUsedError;
  double get musicMaxCutoffHz => throw _privateConstructorUsedError;
  bool get musicInvert => throw _privateConstructorUsedError;
  bool get musicShuffle => throw _privateConstructorUsedError;
  String get binauralPresetId => throw _privateConstructorUsedError;
  double get binauralCarrierHz => throw _privateConstructorUsedError;
  double get binauralBeatHz => throw _privateConstructorUsedError;
  bool get markersInFeedbackEnabled => throw _privateConstructorUsedError;
  bool get eyeMarkersEnabled => throw _privateConstructorUsedError;
  ModelSnapshot? get modelSnapshot => throw _privateConstructorUsedError;

  /// Serializes this SessionSettings to a JSON map.
  Map<String, dynamic> toJson() => throw _privateConstructorUsedError;

  /// Create a copy of SessionSettings
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SessionSettingsCopyWith<SessionSettings> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SessionSettingsCopyWith<$Res> {
  factory $SessionSettingsCopyWith(
    SessionSettings value,
    $Res Function(SessionSettings) then,
  ) = _$SessionSettingsCopyWithImpl<$Res, SessionSettings>;
  @useResult
  $Res call({
    bool dynamicAdapt,
    double responsiveness,
    int baselinePercentile,
    bool guardrailEnabled,
    String guardrailEngine,
    int warningThresholdPercentile,
    String warningSound,
    String? musicFolder,
    double musicMinCutoffHz,
    double musicMaxCutoffHz,
    bool musicInvert,
    bool musicShuffle,
    String binauralPresetId,
    double binauralCarrierHz,
    double binauralBeatHz,
    bool markersInFeedbackEnabled,
    bool eyeMarkersEnabled,
    ModelSnapshot? modelSnapshot,
  });
}

/// @nodoc
class _$SessionSettingsCopyWithImpl<$Res, $Val extends SessionSettings>
    implements $SessionSettingsCopyWith<$Res> {
  _$SessionSettingsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SessionSettings
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? dynamicAdapt = null,
    Object? responsiveness = null,
    Object? baselinePercentile = null,
    Object? guardrailEnabled = null,
    Object? guardrailEngine = null,
    Object? warningThresholdPercentile = null,
    Object? warningSound = null,
    Object? musicFolder = freezed,
    Object? musicMinCutoffHz = null,
    Object? musicMaxCutoffHz = null,
    Object? musicInvert = null,
    Object? musicShuffle = null,
    Object? binauralPresetId = null,
    Object? binauralCarrierHz = null,
    Object? binauralBeatHz = null,
    Object? markersInFeedbackEnabled = null,
    Object? eyeMarkersEnabled = null,
    Object? modelSnapshot = freezed,
  }) {
    return _then(
      _value.copyWith(
            dynamicAdapt: null == dynamicAdapt
                ? _value.dynamicAdapt
                : dynamicAdapt // ignore: cast_nullable_to_non_nullable
                      as bool,
            responsiveness: null == responsiveness
                ? _value.responsiveness
                : responsiveness // ignore: cast_nullable_to_non_nullable
                      as double,
            baselinePercentile: null == baselinePercentile
                ? _value.baselinePercentile
                : baselinePercentile // ignore: cast_nullable_to_non_nullable
                      as int,
            guardrailEnabled: null == guardrailEnabled
                ? _value.guardrailEnabled
                : guardrailEnabled // ignore: cast_nullable_to_non_nullable
                      as bool,
            guardrailEngine: null == guardrailEngine
                ? _value.guardrailEngine
                : guardrailEngine // ignore: cast_nullable_to_non_nullable
                      as String,
            warningThresholdPercentile: null == warningThresholdPercentile
                ? _value.warningThresholdPercentile
                : warningThresholdPercentile // ignore: cast_nullable_to_non_nullable
                      as int,
            warningSound: null == warningSound
                ? _value.warningSound
                : warningSound // ignore: cast_nullable_to_non_nullable
                      as String,
            musicFolder: freezed == musicFolder
                ? _value.musicFolder
                : musicFolder // ignore: cast_nullable_to_non_nullable
                      as String?,
            musicMinCutoffHz: null == musicMinCutoffHz
                ? _value.musicMinCutoffHz
                : musicMinCutoffHz // ignore: cast_nullable_to_non_nullable
                      as double,
            musicMaxCutoffHz: null == musicMaxCutoffHz
                ? _value.musicMaxCutoffHz
                : musicMaxCutoffHz // ignore: cast_nullable_to_non_nullable
                      as double,
            musicInvert: null == musicInvert
                ? _value.musicInvert
                : musicInvert // ignore: cast_nullable_to_non_nullable
                      as bool,
            musicShuffle: null == musicShuffle
                ? _value.musicShuffle
                : musicShuffle // ignore: cast_nullable_to_non_nullable
                      as bool,
            binauralPresetId: null == binauralPresetId
                ? _value.binauralPresetId
                : binauralPresetId // ignore: cast_nullable_to_non_nullable
                      as String,
            binauralCarrierHz: null == binauralCarrierHz
                ? _value.binauralCarrierHz
                : binauralCarrierHz // ignore: cast_nullable_to_non_nullable
                      as double,
            binauralBeatHz: null == binauralBeatHz
                ? _value.binauralBeatHz
                : binauralBeatHz // ignore: cast_nullable_to_non_nullable
                      as double,
            markersInFeedbackEnabled: null == markersInFeedbackEnabled
                ? _value.markersInFeedbackEnabled
                : markersInFeedbackEnabled // ignore: cast_nullable_to_non_nullable
                      as bool,
            eyeMarkersEnabled: null == eyeMarkersEnabled
                ? _value.eyeMarkersEnabled
                : eyeMarkersEnabled // ignore: cast_nullable_to_non_nullable
                      as bool,
            modelSnapshot: freezed == modelSnapshot
                ? _value.modelSnapshot
                : modelSnapshot // ignore: cast_nullable_to_non_nullable
                      as ModelSnapshot?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$SessionSettingsImplCopyWith<$Res>
    implements $SessionSettingsCopyWith<$Res> {
  factory _$$SessionSettingsImplCopyWith(
    _$SessionSettingsImpl value,
    $Res Function(_$SessionSettingsImpl) then,
  ) = __$$SessionSettingsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    bool dynamicAdapt,
    double responsiveness,
    int baselinePercentile,
    bool guardrailEnabled,
    String guardrailEngine,
    int warningThresholdPercentile,
    String warningSound,
    String? musicFolder,
    double musicMinCutoffHz,
    double musicMaxCutoffHz,
    bool musicInvert,
    bool musicShuffle,
    String binauralPresetId,
    double binauralCarrierHz,
    double binauralBeatHz,
    bool markersInFeedbackEnabled,
    bool eyeMarkersEnabled,
    ModelSnapshot? modelSnapshot,
  });
}

/// @nodoc
class __$$SessionSettingsImplCopyWithImpl<$Res>
    extends _$SessionSettingsCopyWithImpl<$Res, _$SessionSettingsImpl>
    implements _$$SessionSettingsImplCopyWith<$Res> {
  __$$SessionSettingsImplCopyWithImpl(
    _$SessionSettingsImpl _value,
    $Res Function(_$SessionSettingsImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SessionSettings
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? dynamicAdapt = null,
    Object? responsiveness = null,
    Object? baselinePercentile = null,
    Object? guardrailEnabled = null,
    Object? guardrailEngine = null,
    Object? warningThresholdPercentile = null,
    Object? warningSound = null,
    Object? musicFolder = freezed,
    Object? musicMinCutoffHz = null,
    Object? musicMaxCutoffHz = null,
    Object? musicInvert = null,
    Object? musicShuffle = null,
    Object? binauralPresetId = null,
    Object? binauralCarrierHz = null,
    Object? binauralBeatHz = null,
    Object? markersInFeedbackEnabled = null,
    Object? eyeMarkersEnabled = null,
    Object? modelSnapshot = freezed,
  }) {
    return _then(
      _$SessionSettingsImpl(
        dynamicAdapt: null == dynamicAdapt
            ? _value.dynamicAdapt
            : dynamicAdapt // ignore: cast_nullable_to_non_nullable
                  as bool,
        responsiveness: null == responsiveness
            ? _value.responsiveness
            : responsiveness // ignore: cast_nullable_to_non_nullable
                  as double,
        baselinePercentile: null == baselinePercentile
            ? _value.baselinePercentile
            : baselinePercentile // ignore: cast_nullable_to_non_nullable
                  as int,
        guardrailEnabled: null == guardrailEnabled
            ? _value.guardrailEnabled
            : guardrailEnabled // ignore: cast_nullable_to_non_nullable
                  as bool,
        guardrailEngine: null == guardrailEngine
            ? _value.guardrailEngine
            : guardrailEngine // ignore: cast_nullable_to_non_nullable
                  as String,
        warningThresholdPercentile: null == warningThresholdPercentile
            ? _value.warningThresholdPercentile
            : warningThresholdPercentile // ignore: cast_nullable_to_non_nullable
                  as int,
        warningSound: null == warningSound
            ? _value.warningSound
            : warningSound // ignore: cast_nullable_to_non_nullable
                  as String,
        musicFolder: freezed == musicFolder
            ? _value.musicFolder
            : musicFolder // ignore: cast_nullable_to_non_nullable
                  as String?,
        musicMinCutoffHz: null == musicMinCutoffHz
            ? _value.musicMinCutoffHz
            : musicMinCutoffHz // ignore: cast_nullable_to_non_nullable
                  as double,
        musicMaxCutoffHz: null == musicMaxCutoffHz
            ? _value.musicMaxCutoffHz
            : musicMaxCutoffHz // ignore: cast_nullable_to_non_nullable
                  as double,
        musicInvert: null == musicInvert
            ? _value.musicInvert
            : musicInvert // ignore: cast_nullable_to_non_nullable
                  as bool,
        musicShuffle: null == musicShuffle
            ? _value.musicShuffle
            : musicShuffle // ignore: cast_nullable_to_non_nullable
                  as bool,
        binauralPresetId: null == binauralPresetId
            ? _value.binauralPresetId
            : binauralPresetId // ignore: cast_nullable_to_non_nullable
                  as String,
        binauralCarrierHz: null == binauralCarrierHz
            ? _value.binauralCarrierHz
            : binauralCarrierHz // ignore: cast_nullable_to_non_nullable
                  as double,
        binauralBeatHz: null == binauralBeatHz
            ? _value.binauralBeatHz
            : binauralBeatHz // ignore: cast_nullable_to_non_nullable
                  as double,
        markersInFeedbackEnabled: null == markersInFeedbackEnabled
            ? _value.markersInFeedbackEnabled
            : markersInFeedbackEnabled // ignore: cast_nullable_to_non_nullable
                  as bool,
        eyeMarkersEnabled: null == eyeMarkersEnabled
            ? _value.eyeMarkersEnabled
            : eyeMarkersEnabled // ignore: cast_nullable_to_non_nullable
                  as bool,
        modelSnapshot: freezed == modelSnapshot
            ? _value.modelSnapshot
            : modelSnapshot // ignore: cast_nullable_to_non_nullable
                  as ModelSnapshot?,
      ),
    );
  }
}

/// @nodoc
@JsonSerializable()
class _$SessionSettingsImpl implements _SessionSettings {
  const _$SessionSettingsImpl({
    required this.dynamicAdapt,
    required this.responsiveness,
    required this.baselinePercentile,
    required this.guardrailEnabled,
    required this.guardrailEngine,
    required this.warningThresholdPercentile,
    required this.warningSound,
    this.musicFolder,
    required this.musicMinCutoffHz,
    required this.musicMaxCutoffHz,
    required this.musicInvert,
    required this.musicShuffle,
    required this.binauralPresetId,
    required this.binauralCarrierHz,
    required this.binauralBeatHz,
    required this.markersInFeedbackEnabled,
    required this.eyeMarkersEnabled,
    this.modelSnapshot,
  });

  factory _$SessionSettingsImpl.fromJson(Map<String, dynamic> json) =>
      _$$SessionSettingsImplFromJson(json);

  @override
  final bool dynamicAdapt;
  @override
  final double responsiveness;
  @override
  final int baselinePercentile;
  @override
  final bool guardrailEnabled;
  @override
  final String guardrailEngine;
  @override
  final int warningThresholdPercentile;
  @override
  final String warningSound;
  @override
  final String? musicFolder;
  @override
  final double musicMinCutoffHz;
  @override
  final double musicMaxCutoffHz;
  @override
  final bool musicInvert;
  @override
  final bool musicShuffle;
  @override
  final String binauralPresetId;
  @override
  final double binauralCarrierHz;
  @override
  final double binauralBeatHz;
  @override
  final bool markersInFeedbackEnabled;
  @override
  final bool eyeMarkersEnabled;
  @override
  final ModelSnapshot? modelSnapshot;

  @override
  String toString() {
    return 'SessionSettings(dynamicAdapt: $dynamicAdapt, responsiveness: $responsiveness, baselinePercentile: $baselinePercentile, guardrailEnabled: $guardrailEnabled, guardrailEngine: $guardrailEngine, warningThresholdPercentile: $warningThresholdPercentile, warningSound: $warningSound, musicFolder: $musicFolder, musicMinCutoffHz: $musicMinCutoffHz, musicMaxCutoffHz: $musicMaxCutoffHz, musicInvert: $musicInvert, musicShuffle: $musicShuffle, binauralPresetId: $binauralPresetId, binauralCarrierHz: $binauralCarrierHz, binauralBeatHz: $binauralBeatHz, markersInFeedbackEnabled: $markersInFeedbackEnabled, eyeMarkersEnabled: $eyeMarkersEnabled, modelSnapshot: $modelSnapshot)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SessionSettingsImpl &&
            (identical(other.dynamicAdapt, dynamicAdapt) ||
                other.dynamicAdapt == dynamicAdapt) &&
            (identical(other.responsiveness, responsiveness) ||
                other.responsiveness == responsiveness) &&
            (identical(other.baselinePercentile, baselinePercentile) ||
                other.baselinePercentile == baselinePercentile) &&
            (identical(other.guardrailEnabled, guardrailEnabled) ||
                other.guardrailEnabled == guardrailEnabled) &&
            (identical(other.guardrailEngine, guardrailEngine) ||
                other.guardrailEngine == guardrailEngine) &&
            (identical(
                  other.warningThresholdPercentile,
                  warningThresholdPercentile,
                ) ||
                other.warningThresholdPercentile ==
                    warningThresholdPercentile) &&
            (identical(other.warningSound, warningSound) ||
                other.warningSound == warningSound) &&
            (identical(other.musicFolder, musicFolder) ||
                other.musicFolder == musicFolder) &&
            (identical(other.musicMinCutoffHz, musicMinCutoffHz) ||
                other.musicMinCutoffHz == musicMinCutoffHz) &&
            (identical(other.musicMaxCutoffHz, musicMaxCutoffHz) ||
                other.musicMaxCutoffHz == musicMaxCutoffHz) &&
            (identical(other.musicInvert, musicInvert) ||
                other.musicInvert == musicInvert) &&
            (identical(other.musicShuffle, musicShuffle) ||
                other.musicShuffle == musicShuffle) &&
            (identical(other.binauralPresetId, binauralPresetId) ||
                other.binauralPresetId == binauralPresetId) &&
            (identical(other.binauralCarrierHz, binauralCarrierHz) ||
                other.binauralCarrierHz == binauralCarrierHz) &&
            (identical(other.binauralBeatHz, binauralBeatHz) ||
                other.binauralBeatHz == binauralBeatHz) &&
            (identical(
                  other.markersInFeedbackEnabled,
                  markersInFeedbackEnabled,
                ) ||
                other.markersInFeedbackEnabled == markersInFeedbackEnabled) &&
            (identical(other.eyeMarkersEnabled, eyeMarkersEnabled) ||
                other.eyeMarkersEnabled == eyeMarkersEnabled) &&
            (identical(other.modelSnapshot, modelSnapshot) ||
                other.modelSnapshot == modelSnapshot));
  }

  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  int get hashCode => Object.hash(
    runtimeType,
    dynamicAdapt,
    responsiveness,
    baselinePercentile,
    guardrailEnabled,
    guardrailEngine,
    warningThresholdPercentile,
    warningSound,
    musicFolder,
    musicMinCutoffHz,
    musicMaxCutoffHz,
    musicInvert,
    musicShuffle,
    binauralPresetId,
    binauralCarrierHz,
    binauralBeatHz,
    markersInFeedbackEnabled,
    eyeMarkersEnabled,
    modelSnapshot,
  );

  /// Create a copy of SessionSettings
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SessionSettingsImplCopyWith<_$SessionSettingsImpl> get copyWith =>
      __$$SessionSettingsImplCopyWithImpl<_$SessionSettingsImpl>(
        this,
        _$identity,
      );

  @override
  Map<String, dynamic> toJson() {
    return _$$SessionSettingsImplToJson(this);
  }
}

abstract class _SessionSettings implements SessionSettings {
  const factory _SessionSettings({
    required final bool dynamicAdapt,
    required final double responsiveness,
    required final int baselinePercentile,
    required final bool guardrailEnabled,
    required final String guardrailEngine,
    required final int warningThresholdPercentile,
    required final String warningSound,
    final String? musicFolder,
    required final double musicMinCutoffHz,
    required final double musicMaxCutoffHz,
    required final bool musicInvert,
    required final bool musicShuffle,
    required final String binauralPresetId,
    required final double binauralCarrierHz,
    required final double binauralBeatHz,
    required final bool markersInFeedbackEnabled,
    required final bool eyeMarkersEnabled,
    final ModelSnapshot? modelSnapshot,
  }) = _$SessionSettingsImpl;

  factory _SessionSettings.fromJson(Map<String, dynamic> json) =
      _$SessionSettingsImpl.fromJson;

  @override
  bool get dynamicAdapt;
  @override
  double get responsiveness;
  @override
  int get baselinePercentile;
  @override
  bool get guardrailEnabled;
  @override
  String get guardrailEngine;
  @override
  int get warningThresholdPercentile;
  @override
  String get warningSound;
  @override
  String? get musicFolder;
  @override
  double get musicMinCutoffHz;
  @override
  double get musicMaxCutoffHz;
  @override
  bool get musicInvert;
  @override
  bool get musicShuffle;
  @override
  String get binauralPresetId;
  @override
  double get binauralCarrierHz;
  @override
  double get binauralBeatHz;
  @override
  bool get markersInFeedbackEnabled;
  @override
  bool get eyeMarkersEnabled;
  @override
  ModelSnapshot? get modelSnapshot;

  /// Create a copy of SessionSettings
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SessionSettingsImplCopyWith<_$SessionSettingsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
