// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session_format.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$BandsRecord {
  double get timestamp => throw _privateConstructorUsedError;
  int get electrode => throw _privateConstructorUsedError;
  double get delta => throw _privateConstructorUsedError;
  double get theta => throw _privateConstructorUsedError;
  double get alpha => throw _privateConstructorUsedError;
  double get beta => throw _privateConstructorUsedError;
  double get gamma => throw _privateConstructorUsedError;

  /// Create a copy of BandsRecord
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $BandsRecordCopyWith<BandsRecord> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BandsRecordCopyWith<$Res> {
  factory $BandsRecordCopyWith(
    BandsRecord value,
    $Res Function(BandsRecord) then,
  ) = _$BandsRecordCopyWithImpl<$Res, BandsRecord>;
  @useResult
  $Res call({
    double timestamp,
    int electrode,
    double delta,
    double theta,
    double alpha,
    double beta,
    double gamma,
  });
}

/// @nodoc
class _$BandsRecordCopyWithImpl<$Res, $Val extends BandsRecord>
    implements $BandsRecordCopyWith<$Res> {
  _$BandsRecordCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of BandsRecord
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? timestamp = null,
    Object? electrode = null,
    Object? delta = null,
    Object? theta = null,
    Object? alpha = null,
    Object? beta = null,
    Object? gamma = null,
  }) {
    return _then(
      _value.copyWith(
            timestamp: null == timestamp
                ? _value.timestamp
                : timestamp // ignore: cast_nullable_to_non_nullable
                      as double,
            electrode: null == electrode
                ? _value.electrode
                : electrode // ignore: cast_nullable_to_non_nullable
                      as int,
            delta: null == delta
                ? _value.delta
                : delta // ignore: cast_nullable_to_non_nullable
                      as double,
            theta: null == theta
                ? _value.theta
                : theta // ignore: cast_nullable_to_non_nullable
                      as double,
            alpha: null == alpha
                ? _value.alpha
                : alpha // ignore: cast_nullable_to_non_nullable
                      as double,
            beta: null == beta
                ? _value.beta
                : beta // ignore: cast_nullable_to_non_nullable
                      as double,
            gamma: null == gamma
                ? _value.gamma
                : gamma // ignore: cast_nullable_to_non_nullable
                      as double,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$BandsRecordImplCopyWith<$Res>
    implements $BandsRecordCopyWith<$Res> {
  factory _$$BandsRecordImplCopyWith(
    _$BandsRecordImpl value,
    $Res Function(_$BandsRecordImpl) then,
  ) = __$$BandsRecordImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    double timestamp,
    int electrode,
    double delta,
    double theta,
    double alpha,
    double beta,
    double gamma,
  });
}

/// @nodoc
class __$$BandsRecordImplCopyWithImpl<$Res>
    extends _$BandsRecordCopyWithImpl<$Res, _$BandsRecordImpl>
    implements _$$BandsRecordImplCopyWith<$Res> {
  __$$BandsRecordImplCopyWithImpl(
    _$BandsRecordImpl _value,
    $Res Function(_$BandsRecordImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of BandsRecord
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? timestamp = null,
    Object? electrode = null,
    Object? delta = null,
    Object? theta = null,
    Object? alpha = null,
    Object? beta = null,
    Object? gamma = null,
  }) {
    return _then(
      _$BandsRecordImpl(
        timestamp: null == timestamp
            ? _value.timestamp
            : timestamp // ignore: cast_nullable_to_non_nullable
                  as double,
        electrode: null == electrode
            ? _value.electrode
            : electrode // ignore: cast_nullable_to_non_nullable
                  as int,
        delta: null == delta
            ? _value.delta
            : delta // ignore: cast_nullable_to_non_nullable
                  as double,
        theta: null == theta
            ? _value.theta
            : theta // ignore: cast_nullable_to_non_nullable
                  as double,
        alpha: null == alpha
            ? _value.alpha
            : alpha // ignore: cast_nullable_to_non_nullable
                  as double,
        beta: null == beta
            ? _value.beta
            : beta // ignore: cast_nullable_to_non_nullable
                  as double,
        gamma: null == gamma
            ? _value.gamma
            : gamma // ignore: cast_nullable_to_non_nullable
                  as double,
      ),
    );
  }
}

/// @nodoc

class _$BandsRecordImpl implements _BandsRecord {
  const _$BandsRecordImpl({
    required this.timestamp,
    required this.electrode,
    required this.delta,
    required this.theta,
    required this.alpha,
    required this.beta,
    required this.gamma,
  });

  @override
  final double timestamp;
  @override
  final int electrode;
  @override
  final double delta;
  @override
  final double theta;
  @override
  final double alpha;
  @override
  final double beta;
  @override
  final double gamma;

  @override
  String toString() {
    return 'BandsRecord(timestamp: $timestamp, electrode: $electrode, delta: $delta, theta: $theta, alpha: $alpha, beta: $beta, gamma: $gamma)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BandsRecordImpl &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            (identical(other.electrode, electrode) ||
                other.electrode == electrode) &&
            (identical(other.delta, delta) || other.delta == delta) &&
            (identical(other.theta, theta) || other.theta == theta) &&
            (identical(other.alpha, alpha) || other.alpha == alpha) &&
            (identical(other.beta, beta) || other.beta == beta) &&
            (identical(other.gamma, gamma) || other.gamma == gamma));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    timestamp,
    electrode,
    delta,
    theta,
    alpha,
    beta,
    gamma,
  );

  /// Create a copy of BandsRecord
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$BandsRecordImplCopyWith<_$BandsRecordImpl> get copyWith =>
      __$$BandsRecordImplCopyWithImpl<_$BandsRecordImpl>(this, _$identity);
}

abstract class _BandsRecord implements BandsRecord {
  const factory _BandsRecord({
    required final double timestamp,
    required final int electrode,
    required final double delta,
    required final double theta,
    required final double alpha,
    required final double beta,
    required final double gamma,
  }) = _$BandsRecordImpl;

  @override
  double get timestamp;
  @override
  int get electrode;
  @override
  double get delta;
  @override
  double get theta;
  @override
  double get alpha;
  @override
  double get beta;
  @override
  double get gamma;

  /// Create a copy of BandsRecord
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$BandsRecordImplCopyWith<_$BandsRecordImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$ComputedFrame {
  double get t => throw _privateConstructorUsedError;
  List<Float32List> get bands => throw _privateConstructorUsedError;
  double? get pulse => throw _privateConstructorUsedError;
  double? get movement => throw _privateConstructorUsedError;
  PeakAlphaInfo? get peakAlpha => throw _privateConstructorUsedError;
  double? get spo2 => throw _privateConstructorUsedError;
  Float32List get lineNoise => throw _privateConstructorUsedError;
  Uint8List get signalQuality => throw _privateConstructorUsedError;
  GuardrailInfo get guardrail => throw _privateConstructorUsedError;
  FeedbackInfo get feedback => throw _privateConstructorUsedError;
  List<String> get gestures => throw _privateConstructorUsedError;

  /// Create a copy of ComputedFrame
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ComputedFrameCopyWith<ComputedFrame> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ComputedFrameCopyWith<$Res> {
  factory $ComputedFrameCopyWith(
    ComputedFrame value,
    $Res Function(ComputedFrame) then,
  ) = _$ComputedFrameCopyWithImpl<$Res, ComputedFrame>;
  @useResult
  $Res call({
    double t,
    List<Float32List> bands,
    double? pulse,
    double? movement,
    PeakAlphaInfo? peakAlpha,
    double? spo2,
    Float32List lineNoise,
    Uint8List signalQuality,
    GuardrailInfo guardrail,
    FeedbackInfo feedback,
    List<String> gestures,
  });

  $PeakAlphaInfoCopyWith<$Res>? get peakAlpha;
  $GuardrailInfoCopyWith<$Res> get guardrail;
  $FeedbackInfoCopyWith<$Res> get feedback;
}

/// @nodoc
class _$ComputedFrameCopyWithImpl<$Res, $Val extends ComputedFrame>
    implements $ComputedFrameCopyWith<$Res> {
  _$ComputedFrameCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ComputedFrame
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? t = null,
    Object? bands = null,
    Object? pulse = freezed,
    Object? movement = freezed,
    Object? peakAlpha = freezed,
    Object? spo2 = freezed,
    Object? lineNoise = null,
    Object? signalQuality = null,
    Object? guardrail = null,
    Object? feedback = null,
    Object? gestures = null,
  }) {
    return _then(
      _value.copyWith(
            t: null == t
                ? _value.t
                : t // ignore: cast_nullable_to_non_nullable
                      as double,
            bands: null == bands
                ? _value.bands
                : bands // ignore: cast_nullable_to_non_nullable
                      as List<Float32List>,
            pulse: freezed == pulse
                ? _value.pulse
                : pulse // ignore: cast_nullable_to_non_nullable
                      as double?,
            movement: freezed == movement
                ? _value.movement
                : movement // ignore: cast_nullable_to_non_nullable
                      as double?,
            peakAlpha: freezed == peakAlpha
                ? _value.peakAlpha
                : peakAlpha // ignore: cast_nullable_to_non_nullable
                      as PeakAlphaInfo?,
            spo2: freezed == spo2
                ? _value.spo2
                : spo2 // ignore: cast_nullable_to_non_nullable
                      as double?,
            lineNoise: null == lineNoise
                ? _value.lineNoise
                : lineNoise // ignore: cast_nullable_to_non_nullable
                      as Float32List,
            signalQuality: null == signalQuality
                ? _value.signalQuality
                : signalQuality // ignore: cast_nullable_to_non_nullable
                      as Uint8List,
            guardrail: null == guardrail
                ? _value.guardrail
                : guardrail // ignore: cast_nullable_to_non_nullable
                      as GuardrailInfo,
            feedback: null == feedback
                ? _value.feedback
                : feedback // ignore: cast_nullable_to_non_nullable
                      as FeedbackInfo,
            gestures: null == gestures
                ? _value.gestures
                : gestures // ignore: cast_nullable_to_non_nullable
                      as List<String>,
          )
          as $Val,
    );
  }

  /// Create a copy of ComputedFrame
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $PeakAlphaInfoCopyWith<$Res>? get peakAlpha {
    if (_value.peakAlpha == null) {
      return null;
    }

    return $PeakAlphaInfoCopyWith<$Res>(_value.peakAlpha!, (value) {
      return _then(_value.copyWith(peakAlpha: value) as $Val);
    });
  }

  /// Create a copy of ComputedFrame
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $GuardrailInfoCopyWith<$Res> get guardrail {
    return $GuardrailInfoCopyWith<$Res>(_value.guardrail, (value) {
      return _then(_value.copyWith(guardrail: value) as $Val);
    });
  }

  /// Create a copy of ComputedFrame
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $FeedbackInfoCopyWith<$Res> get feedback {
    return $FeedbackInfoCopyWith<$Res>(_value.feedback, (value) {
      return _then(_value.copyWith(feedback: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$ComputedFrameImplCopyWith<$Res>
    implements $ComputedFrameCopyWith<$Res> {
  factory _$$ComputedFrameImplCopyWith(
    _$ComputedFrameImpl value,
    $Res Function(_$ComputedFrameImpl) then,
  ) = __$$ComputedFrameImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    double t,
    List<Float32List> bands,
    double? pulse,
    double? movement,
    PeakAlphaInfo? peakAlpha,
    double? spo2,
    Float32List lineNoise,
    Uint8List signalQuality,
    GuardrailInfo guardrail,
    FeedbackInfo feedback,
    List<String> gestures,
  });

  @override
  $PeakAlphaInfoCopyWith<$Res>? get peakAlpha;
  @override
  $GuardrailInfoCopyWith<$Res> get guardrail;
  @override
  $FeedbackInfoCopyWith<$Res> get feedback;
}

/// @nodoc
class __$$ComputedFrameImplCopyWithImpl<$Res>
    extends _$ComputedFrameCopyWithImpl<$Res, _$ComputedFrameImpl>
    implements _$$ComputedFrameImplCopyWith<$Res> {
  __$$ComputedFrameImplCopyWithImpl(
    _$ComputedFrameImpl _value,
    $Res Function(_$ComputedFrameImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ComputedFrame
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? t = null,
    Object? bands = null,
    Object? pulse = freezed,
    Object? movement = freezed,
    Object? peakAlpha = freezed,
    Object? spo2 = freezed,
    Object? lineNoise = null,
    Object? signalQuality = null,
    Object? guardrail = null,
    Object? feedback = null,
    Object? gestures = null,
  }) {
    return _then(
      _$ComputedFrameImpl(
        t: null == t
            ? _value.t
            : t // ignore: cast_nullable_to_non_nullable
                  as double,
        bands: null == bands
            ? _value._bands
            : bands // ignore: cast_nullable_to_non_nullable
                  as List<Float32List>,
        pulse: freezed == pulse
            ? _value.pulse
            : pulse // ignore: cast_nullable_to_non_nullable
                  as double?,
        movement: freezed == movement
            ? _value.movement
            : movement // ignore: cast_nullable_to_non_nullable
                  as double?,
        peakAlpha: freezed == peakAlpha
            ? _value.peakAlpha
            : peakAlpha // ignore: cast_nullable_to_non_nullable
                  as PeakAlphaInfo?,
        spo2: freezed == spo2
            ? _value.spo2
            : spo2 // ignore: cast_nullable_to_non_nullable
                  as double?,
        lineNoise: null == lineNoise
            ? _value.lineNoise
            : lineNoise // ignore: cast_nullable_to_non_nullable
                  as Float32List,
        signalQuality: null == signalQuality
            ? _value.signalQuality
            : signalQuality // ignore: cast_nullable_to_non_nullable
                  as Uint8List,
        guardrail: null == guardrail
            ? _value.guardrail
            : guardrail // ignore: cast_nullable_to_non_nullable
                  as GuardrailInfo,
        feedback: null == feedback
            ? _value.feedback
            : feedback // ignore: cast_nullable_to_non_nullable
                  as FeedbackInfo,
        gestures: null == gestures
            ? _value._gestures
            : gestures // ignore: cast_nullable_to_non_nullable
                  as List<String>,
      ),
    );
  }
}

/// @nodoc

class _$ComputedFrameImpl extends _ComputedFrame {
  const _$ComputedFrameImpl({
    required this.t,
    required final List<Float32List> bands,
    this.pulse,
    this.movement,
    this.peakAlpha,
    this.spo2,
    required this.lineNoise,
    required this.signalQuality,
    required this.guardrail,
    required this.feedback,
    required final List<String> gestures,
  }) : _bands = bands,
       _gestures = gestures,
       super._();

  @override
  final double t;
  final List<Float32List> _bands;
  @override
  List<Float32List> get bands {
    if (_bands is EqualUnmodifiableListView) return _bands;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_bands);
  }

  @override
  final double? pulse;
  @override
  final double? movement;
  @override
  final PeakAlphaInfo? peakAlpha;
  @override
  final double? spo2;
  @override
  final Float32List lineNoise;
  @override
  final Uint8List signalQuality;
  @override
  final GuardrailInfo guardrail;
  @override
  final FeedbackInfo feedback;
  final List<String> _gestures;
  @override
  List<String> get gestures {
    if (_gestures is EqualUnmodifiableListView) return _gestures;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_gestures);
  }

  @override
  String toString() {
    return 'ComputedFrame(t: $t, bands: $bands, pulse: $pulse, movement: $movement, peakAlpha: $peakAlpha, spo2: $spo2, lineNoise: $lineNoise, signalQuality: $signalQuality, guardrail: $guardrail, feedback: $feedback, gestures: $gestures)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ComputedFrameImpl &&
            (identical(other.t, t) || other.t == t) &&
            const DeepCollectionEquality().equals(other._bands, _bands) &&
            (identical(other.pulse, pulse) || other.pulse == pulse) &&
            (identical(other.movement, movement) ||
                other.movement == movement) &&
            (identical(other.peakAlpha, peakAlpha) ||
                other.peakAlpha == peakAlpha) &&
            (identical(other.spo2, spo2) || other.spo2 == spo2) &&
            const DeepCollectionEquality().equals(other.lineNoise, lineNoise) &&
            const DeepCollectionEquality().equals(
              other.signalQuality,
              signalQuality,
            ) &&
            (identical(other.guardrail, guardrail) ||
                other.guardrail == guardrail) &&
            (identical(other.feedback, feedback) ||
                other.feedback == feedback) &&
            const DeepCollectionEquality().equals(other._gestures, _gestures));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    t,
    const DeepCollectionEquality().hash(_bands),
    pulse,
    movement,
    peakAlpha,
    spo2,
    const DeepCollectionEquality().hash(lineNoise),
    const DeepCollectionEquality().hash(signalQuality),
    guardrail,
    feedback,
    const DeepCollectionEquality().hash(_gestures),
  );

  /// Create a copy of ComputedFrame
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ComputedFrameImplCopyWith<_$ComputedFrameImpl> get copyWith =>
      __$$ComputedFrameImplCopyWithImpl<_$ComputedFrameImpl>(this, _$identity);
}

abstract class _ComputedFrame extends ComputedFrame {
  const factory _ComputedFrame({
    required final double t,
    required final List<Float32List> bands,
    final double? pulse,
    final double? movement,
    final PeakAlphaInfo? peakAlpha,
    final double? spo2,
    required final Float32List lineNoise,
    required final Uint8List signalQuality,
    required final GuardrailInfo guardrail,
    required final FeedbackInfo feedback,
    required final List<String> gestures,
  }) = _$ComputedFrameImpl;
  const _ComputedFrame._() : super._();

  @override
  double get t;
  @override
  List<Float32List> get bands;
  @override
  double? get pulse;
  @override
  double? get movement;
  @override
  PeakAlphaInfo? get peakAlpha;
  @override
  double? get spo2;
  @override
  Float32List get lineNoise;
  @override
  Uint8List get signalQuality;
  @override
  GuardrailInfo get guardrail;
  @override
  FeedbackInfo get feedback;
  @override
  List<String> get gestures;

  /// Create a copy of ComputedFrame
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ComputedFrameImplCopyWith<_$ComputedFrameImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$ContainerHead {
  Uint8List get pngBytes => throw _privateConstructorUsedError;
  Uint8List get jsonBytes => throw _privateConstructorUsedError;
  int? get bodyLen => throw _privateConstructorUsedError;

  /// Create a copy of ContainerHead
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ContainerHeadCopyWith<ContainerHead> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ContainerHeadCopyWith<$Res> {
  factory $ContainerHeadCopyWith(
    ContainerHead value,
    $Res Function(ContainerHead) then,
  ) = _$ContainerHeadCopyWithImpl<$Res, ContainerHead>;
  @useResult
  $Res call({Uint8List pngBytes, Uint8List jsonBytes, int? bodyLen});
}

/// @nodoc
class _$ContainerHeadCopyWithImpl<$Res, $Val extends ContainerHead>
    implements $ContainerHeadCopyWith<$Res> {
  _$ContainerHeadCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ContainerHead
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? pngBytes = null,
    Object? jsonBytes = null,
    Object? bodyLen = freezed,
  }) {
    return _then(
      _value.copyWith(
            pngBytes: null == pngBytes
                ? _value.pngBytes
                : pngBytes // ignore: cast_nullable_to_non_nullable
                      as Uint8List,
            jsonBytes: null == jsonBytes
                ? _value.jsonBytes
                : jsonBytes // ignore: cast_nullable_to_non_nullable
                      as Uint8List,
            bodyLen: freezed == bodyLen
                ? _value.bodyLen
                : bodyLen // ignore: cast_nullable_to_non_nullable
                      as int?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ContainerHeadImplCopyWith<$Res>
    implements $ContainerHeadCopyWith<$Res> {
  factory _$$ContainerHeadImplCopyWith(
    _$ContainerHeadImpl value,
    $Res Function(_$ContainerHeadImpl) then,
  ) = __$$ContainerHeadImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({Uint8List pngBytes, Uint8List jsonBytes, int? bodyLen});
}

/// @nodoc
class __$$ContainerHeadImplCopyWithImpl<$Res>
    extends _$ContainerHeadCopyWithImpl<$Res, _$ContainerHeadImpl>
    implements _$$ContainerHeadImplCopyWith<$Res> {
  __$$ContainerHeadImplCopyWithImpl(
    _$ContainerHeadImpl _value,
    $Res Function(_$ContainerHeadImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ContainerHead
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? pngBytes = null,
    Object? jsonBytes = null,
    Object? bodyLen = freezed,
  }) {
    return _then(
      _$ContainerHeadImpl(
        pngBytes: null == pngBytes
            ? _value.pngBytes
            : pngBytes // ignore: cast_nullable_to_non_nullable
                  as Uint8List,
        jsonBytes: null == jsonBytes
            ? _value.jsonBytes
            : jsonBytes // ignore: cast_nullable_to_non_nullable
                  as Uint8List,
        bodyLen: freezed == bodyLen
            ? _value.bodyLen
            : bodyLen // ignore: cast_nullable_to_non_nullable
                  as int?,
      ),
    );
  }
}

/// @nodoc

class _$ContainerHeadImpl implements _ContainerHead {
  const _$ContainerHeadImpl({
    required this.pngBytes,
    required this.jsonBytes,
    this.bodyLen,
  });

  @override
  final Uint8List pngBytes;
  @override
  final Uint8List jsonBytes;
  @override
  final int? bodyLen;

  @override
  String toString() {
    return 'ContainerHead(pngBytes: $pngBytes, jsonBytes: $jsonBytes, bodyLen: $bodyLen)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ContainerHeadImpl &&
            const DeepCollectionEquality().equals(other.pngBytes, pngBytes) &&
            const DeepCollectionEquality().equals(other.jsonBytes, jsonBytes) &&
            (identical(other.bodyLen, bodyLen) || other.bodyLen == bodyLen));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    const DeepCollectionEquality().hash(pngBytes),
    const DeepCollectionEquality().hash(jsonBytes),
    bodyLen,
  );

  /// Create a copy of ContainerHead
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ContainerHeadImplCopyWith<_$ContainerHeadImpl> get copyWith =>
      __$$ContainerHeadImplCopyWithImpl<_$ContainerHeadImpl>(this, _$identity);
}

abstract class _ContainerHead implements ContainerHead {
  const factory _ContainerHead({
    required final Uint8List pngBytes,
    required final Uint8List jsonBytes,
    final int? bodyLen,
  }) = _$ContainerHeadImpl;

  @override
  Uint8List get pngBytes;
  @override
  Uint8List get jsonBytes;
  @override
  int? get bodyLen;

  /// Create a copy of ContainerHead
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ContainerHeadImplCopyWith<_$ContainerHeadImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$EegSampleRecord {
  double get timestamp => throw _privateConstructorUsedError;
  int get electrode => throw _privateConstructorUsedError;
  Float32List get samples => throw _privateConstructorUsedError;

  /// Create a copy of EegSampleRecord
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $EegSampleRecordCopyWith<EegSampleRecord> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $EegSampleRecordCopyWith<$Res> {
  factory $EegSampleRecordCopyWith(
    EegSampleRecord value,
    $Res Function(EegSampleRecord) then,
  ) = _$EegSampleRecordCopyWithImpl<$Res, EegSampleRecord>;
  @useResult
  $Res call({double timestamp, int electrode, Float32List samples});
}

/// @nodoc
class _$EegSampleRecordCopyWithImpl<$Res, $Val extends EegSampleRecord>
    implements $EegSampleRecordCopyWith<$Res> {
  _$EegSampleRecordCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of EegSampleRecord
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? timestamp = null,
    Object? electrode = null,
    Object? samples = null,
  }) {
    return _then(
      _value.copyWith(
            timestamp: null == timestamp
                ? _value.timestamp
                : timestamp // ignore: cast_nullable_to_non_nullable
                      as double,
            electrode: null == electrode
                ? _value.electrode
                : electrode // ignore: cast_nullable_to_non_nullable
                      as int,
            samples: null == samples
                ? _value.samples
                : samples // ignore: cast_nullable_to_non_nullable
                      as Float32List,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$EegSampleRecordImplCopyWith<$Res>
    implements $EegSampleRecordCopyWith<$Res> {
  factory _$$EegSampleRecordImplCopyWith(
    _$EegSampleRecordImpl value,
    $Res Function(_$EegSampleRecordImpl) then,
  ) = __$$EegSampleRecordImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double timestamp, int electrode, Float32List samples});
}

/// @nodoc
class __$$EegSampleRecordImplCopyWithImpl<$Res>
    extends _$EegSampleRecordCopyWithImpl<$Res, _$EegSampleRecordImpl>
    implements _$$EegSampleRecordImplCopyWith<$Res> {
  __$$EegSampleRecordImplCopyWithImpl(
    _$EegSampleRecordImpl _value,
    $Res Function(_$EegSampleRecordImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of EegSampleRecord
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? timestamp = null,
    Object? electrode = null,
    Object? samples = null,
  }) {
    return _then(
      _$EegSampleRecordImpl(
        timestamp: null == timestamp
            ? _value.timestamp
            : timestamp // ignore: cast_nullable_to_non_nullable
                  as double,
        electrode: null == electrode
            ? _value.electrode
            : electrode // ignore: cast_nullable_to_non_nullable
                  as int,
        samples: null == samples
            ? _value.samples
            : samples // ignore: cast_nullable_to_non_nullable
                  as Float32List,
      ),
    );
  }
}

/// @nodoc

class _$EegSampleRecordImpl implements _EegSampleRecord {
  const _$EegSampleRecordImpl({
    required this.timestamp,
    required this.electrode,
    required this.samples,
  });

  @override
  final double timestamp;
  @override
  final int electrode;
  @override
  final Float32List samples;

  @override
  String toString() {
    return 'EegSampleRecord(timestamp: $timestamp, electrode: $electrode, samples: $samples)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$EegSampleRecordImpl &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            (identical(other.electrode, electrode) ||
                other.electrode == electrode) &&
            const DeepCollectionEquality().equals(other.samples, samples));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    timestamp,
    electrode,
    const DeepCollectionEquality().hash(samples),
  );

  /// Create a copy of EegSampleRecord
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$EegSampleRecordImplCopyWith<_$EegSampleRecordImpl> get copyWith =>
      __$$EegSampleRecordImplCopyWithImpl<_$EegSampleRecordImpl>(
        this,
        _$identity,
      );
}

abstract class _EegSampleRecord implements EegSampleRecord {
  const factory _EegSampleRecord({
    required final double timestamp,
    required final int electrode,
    required final Float32List samples,
  }) = _$EegSampleRecordImpl;

  @override
  double get timestamp;
  @override
  int get electrode;
  @override
  Float32List get samples;

  /// Create a copy of EegSampleRecord
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$EegSampleRecordImplCopyWith<_$EegSampleRecordImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$FeedbackInfo {
  double get ratio => throw _privateConstructorUsedError;
  double get threshold => throw _privateConstructorUsedError;
  bool get inTarget => throw _privateConstructorUsedError;
  double get pct => throw _privateConstructorUsedError;

  /// Create a copy of FeedbackInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $FeedbackInfoCopyWith<FeedbackInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FeedbackInfoCopyWith<$Res> {
  factory $FeedbackInfoCopyWith(
    FeedbackInfo value,
    $Res Function(FeedbackInfo) then,
  ) = _$FeedbackInfoCopyWithImpl<$Res, FeedbackInfo>;
  @useResult
  $Res call({double ratio, double threshold, bool inTarget, double pct});
}

/// @nodoc
class _$FeedbackInfoCopyWithImpl<$Res, $Val extends FeedbackInfo>
    implements $FeedbackInfoCopyWith<$Res> {
  _$FeedbackInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of FeedbackInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ratio = null,
    Object? threshold = null,
    Object? inTarget = null,
    Object? pct = null,
  }) {
    return _then(
      _value.copyWith(
            ratio: null == ratio
                ? _value.ratio
                : ratio // ignore: cast_nullable_to_non_nullable
                      as double,
            threshold: null == threshold
                ? _value.threshold
                : threshold // ignore: cast_nullable_to_non_nullable
                      as double,
            inTarget: null == inTarget
                ? _value.inTarget
                : inTarget // ignore: cast_nullable_to_non_nullable
                      as bool,
            pct: null == pct
                ? _value.pct
                : pct // ignore: cast_nullable_to_non_nullable
                      as double,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$FeedbackInfoImplCopyWith<$Res>
    implements $FeedbackInfoCopyWith<$Res> {
  factory _$$FeedbackInfoImplCopyWith(
    _$FeedbackInfoImpl value,
    $Res Function(_$FeedbackInfoImpl) then,
  ) = __$$FeedbackInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double ratio, double threshold, bool inTarget, double pct});
}

/// @nodoc
class __$$FeedbackInfoImplCopyWithImpl<$Res>
    extends _$FeedbackInfoCopyWithImpl<$Res, _$FeedbackInfoImpl>
    implements _$$FeedbackInfoImplCopyWith<$Res> {
  __$$FeedbackInfoImplCopyWithImpl(
    _$FeedbackInfoImpl _value,
    $Res Function(_$FeedbackInfoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of FeedbackInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? ratio = null,
    Object? threshold = null,
    Object? inTarget = null,
    Object? pct = null,
  }) {
    return _then(
      _$FeedbackInfoImpl(
        ratio: null == ratio
            ? _value.ratio
            : ratio // ignore: cast_nullable_to_non_nullable
                  as double,
        threshold: null == threshold
            ? _value.threshold
            : threshold // ignore: cast_nullable_to_non_nullable
                  as double,
        inTarget: null == inTarget
            ? _value.inTarget
            : inTarget // ignore: cast_nullable_to_non_nullable
                  as bool,
        pct: null == pct
            ? _value.pct
            : pct // ignore: cast_nullable_to_non_nullable
                  as double,
      ),
    );
  }
}

/// @nodoc

class _$FeedbackInfoImpl implements _FeedbackInfo {
  const _$FeedbackInfoImpl({
    required this.ratio,
    required this.threshold,
    required this.inTarget,
    required this.pct,
  });

  @override
  final double ratio;
  @override
  final double threshold;
  @override
  final bool inTarget;
  @override
  final double pct;

  @override
  String toString() {
    return 'FeedbackInfo(ratio: $ratio, threshold: $threshold, inTarget: $inTarget, pct: $pct)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FeedbackInfoImpl &&
            (identical(other.ratio, ratio) || other.ratio == ratio) &&
            (identical(other.threshold, threshold) ||
                other.threshold == threshold) &&
            (identical(other.inTarget, inTarget) ||
                other.inTarget == inTarget) &&
            (identical(other.pct, pct) || other.pct == pct));
  }

  @override
  int get hashCode => Object.hash(runtimeType, ratio, threshold, inTarget, pct);

  /// Create a copy of FeedbackInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$FeedbackInfoImplCopyWith<_$FeedbackInfoImpl> get copyWith =>
      __$$FeedbackInfoImplCopyWithImpl<_$FeedbackInfoImpl>(this, _$identity);
}

abstract class _FeedbackInfo implements FeedbackInfo {
  const factory _FeedbackInfo({
    required final double ratio,
    required final double threshold,
    required final bool inTarget,
    required final double pct,
  }) = _$FeedbackInfoImpl;

  @override
  double get ratio;
  @override
  double get threshold;
  @override
  bool get inTarget;
  @override
  double get pct;

  /// Create a copy of FeedbackInfo
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$FeedbackInfoImplCopyWith<_$FeedbackInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$GuardrailInfo {
  double get sleepDir => throw _privateConstructorUsedError;
  double get clarity => throw _privateConstructorUsedError;
  bool get warning => throw _privateConstructorUsedError;
  double get delta => throw _privateConstructorUsedError;

  /// Create a copy of GuardrailInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $GuardrailInfoCopyWith<GuardrailInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $GuardrailInfoCopyWith<$Res> {
  factory $GuardrailInfoCopyWith(
    GuardrailInfo value,
    $Res Function(GuardrailInfo) then,
  ) = _$GuardrailInfoCopyWithImpl<$Res, GuardrailInfo>;
  @useResult
  $Res call({double sleepDir, double clarity, bool warning, double delta});
}

/// @nodoc
class _$GuardrailInfoCopyWithImpl<$Res, $Val extends GuardrailInfo>
    implements $GuardrailInfoCopyWith<$Res> {
  _$GuardrailInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of GuardrailInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sleepDir = null,
    Object? clarity = null,
    Object? warning = null,
    Object? delta = null,
  }) {
    return _then(
      _value.copyWith(
            sleepDir: null == sleepDir
                ? _value.sleepDir
                : sleepDir // ignore: cast_nullable_to_non_nullable
                      as double,
            clarity: null == clarity
                ? _value.clarity
                : clarity // ignore: cast_nullable_to_non_nullable
                      as double,
            warning: null == warning
                ? _value.warning
                : warning // ignore: cast_nullable_to_non_nullable
                      as bool,
            delta: null == delta
                ? _value.delta
                : delta // ignore: cast_nullable_to_non_nullable
                      as double,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$GuardrailInfoImplCopyWith<$Res>
    implements $GuardrailInfoCopyWith<$Res> {
  factory _$$GuardrailInfoImplCopyWith(
    _$GuardrailInfoImpl value,
    $Res Function(_$GuardrailInfoImpl) then,
  ) = __$$GuardrailInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double sleepDir, double clarity, bool warning, double delta});
}

/// @nodoc
class __$$GuardrailInfoImplCopyWithImpl<$Res>
    extends _$GuardrailInfoCopyWithImpl<$Res, _$GuardrailInfoImpl>
    implements _$$GuardrailInfoImplCopyWith<$Res> {
  __$$GuardrailInfoImplCopyWithImpl(
    _$GuardrailInfoImpl _value,
    $Res Function(_$GuardrailInfoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of GuardrailInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? sleepDir = null,
    Object? clarity = null,
    Object? warning = null,
    Object? delta = null,
  }) {
    return _then(
      _$GuardrailInfoImpl(
        sleepDir: null == sleepDir
            ? _value.sleepDir
            : sleepDir // ignore: cast_nullable_to_non_nullable
                  as double,
        clarity: null == clarity
            ? _value.clarity
            : clarity // ignore: cast_nullable_to_non_nullable
                  as double,
        warning: null == warning
            ? _value.warning
            : warning // ignore: cast_nullable_to_non_nullable
                  as bool,
        delta: null == delta
            ? _value.delta
            : delta // ignore: cast_nullable_to_non_nullable
                  as double,
      ),
    );
  }
}

/// @nodoc

class _$GuardrailInfoImpl implements _GuardrailInfo {
  const _$GuardrailInfoImpl({
    required this.sleepDir,
    required this.clarity,
    required this.warning,
    required this.delta,
  });

  @override
  final double sleepDir;
  @override
  final double clarity;
  @override
  final bool warning;
  @override
  final double delta;

  @override
  String toString() {
    return 'GuardrailInfo(sleepDir: $sleepDir, clarity: $clarity, warning: $warning, delta: $delta)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$GuardrailInfoImpl &&
            (identical(other.sleepDir, sleepDir) ||
                other.sleepDir == sleepDir) &&
            (identical(other.clarity, clarity) || other.clarity == clarity) &&
            (identical(other.warning, warning) || other.warning == warning) &&
            (identical(other.delta, delta) || other.delta == delta));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, sleepDir, clarity, warning, delta);

  /// Create a copy of GuardrailInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$GuardrailInfoImplCopyWith<_$GuardrailInfoImpl> get copyWith =>
      __$$GuardrailInfoImplCopyWithImpl<_$GuardrailInfoImpl>(this, _$identity);
}

abstract class _GuardrailInfo implements GuardrailInfo {
  const factory _GuardrailInfo({
    required final double sleepDir,
    required final double clarity,
    required final bool warning,
    required final double delta,
  }) = _$GuardrailInfoImpl;

  @override
  double get sleepDir;
  @override
  double get clarity;
  @override
  bool get warning;
  @override
  double get delta;

  /// Create a copy of GuardrailInfo
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$GuardrailInfoImplCopyWith<_$GuardrailInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$MovementRecord {
  double get timestamp => throw _privateConstructorUsedError;
  double get score => throw _privateConstructorUsedError;

  /// Create a copy of MovementRecord
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $MovementRecordCopyWith<MovementRecord> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MovementRecordCopyWith<$Res> {
  factory $MovementRecordCopyWith(
    MovementRecord value,
    $Res Function(MovementRecord) then,
  ) = _$MovementRecordCopyWithImpl<$Res, MovementRecord>;
  @useResult
  $Res call({double timestamp, double score});
}

/// @nodoc
class _$MovementRecordCopyWithImpl<$Res, $Val extends MovementRecord>
    implements $MovementRecordCopyWith<$Res> {
  _$MovementRecordCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MovementRecord
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? timestamp = null, Object? score = null}) {
    return _then(
      _value.copyWith(
            timestamp: null == timestamp
                ? _value.timestamp
                : timestamp // ignore: cast_nullable_to_non_nullable
                      as double,
            score: null == score
                ? _value.score
                : score // ignore: cast_nullable_to_non_nullable
                      as double,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$MovementRecordImplCopyWith<$Res>
    implements $MovementRecordCopyWith<$Res> {
  factory _$$MovementRecordImplCopyWith(
    _$MovementRecordImpl value,
    $Res Function(_$MovementRecordImpl) then,
  ) = __$$MovementRecordImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double timestamp, double score});
}

/// @nodoc
class __$$MovementRecordImplCopyWithImpl<$Res>
    extends _$MovementRecordCopyWithImpl<$Res, _$MovementRecordImpl>
    implements _$$MovementRecordImplCopyWith<$Res> {
  __$$MovementRecordImplCopyWithImpl(
    _$MovementRecordImpl _value,
    $Res Function(_$MovementRecordImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of MovementRecord
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? timestamp = null, Object? score = null}) {
    return _then(
      _$MovementRecordImpl(
        timestamp: null == timestamp
            ? _value.timestamp
            : timestamp // ignore: cast_nullable_to_non_nullable
                  as double,
        score: null == score
            ? _value.score
            : score // ignore: cast_nullable_to_non_nullable
                  as double,
      ),
    );
  }
}

/// @nodoc

class _$MovementRecordImpl implements _MovementRecord {
  const _$MovementRecordImpl({required this.timestamp, required this.score});

  @override
  final double timestamp;
  @override
  final double score;

  @override
  String toString() {
    return 'MovementRecord(timestamp: $timestamp, score: $score)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MovementRecordImpl &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            (identical(other.score, score) || other.score == score));
  }

  @override
  int get hashCode => Object.hash(runtimeType, timestamp, score);

  /// Create a copy of MovementRecord
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MovementRecordImplCopyWith<_$MovementRecordImpl> get copyWith =>
      __$$MovementRecordImplCopyWithImpl<_$MovementRecordImpl>(
        this,
        _$identity,
      );
}

abstract class _MovementRecord implements MovementRecord {
  const factory _MovementRecord({
    required final double timestamp,
    required final double score,
  }) = _$MovementRecordImpl;

  @override
  double get timestamp;
  @override
  double get score;

  /// Create a copy of MovementRecord
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MovementRecordImplCopyWith<_$MovementRecordImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$PeakAlphaInfo {
  double get freq => throw _privateConstructorUsedError;
  double get power => throw _privateConstructorUsedError;

  /// Create a copy of PeakAlphaInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PeakAlphaInfoCopyWith<PeakAlphaInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PeakAlphaInfoCopyWith<$Res> {
  factory $PeakAlphaInfoCopyWith(
    PeakAlphaInfo value,
    $Res Function(PeakAlphaInfo) then,
  ) = _$PeakAlphaInfoCopyWithImpl<$Res, PeakAlphaInfo>;
  @useResult
  $Res call({double freq, double power});
}

/// @nodoc
class _$PeakAlphaInfoCopyWithImpl<$Res, $Val extends PeakAlphaInfo>
    implements $PeakAlphaInfoCopyWith<$Res> {
  _$PeakAlphaInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PeakAlphaInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? freq = null, Object? power = null}) {
    return _then(
      _value.copyWith(
            freq: null == freq
                ? _value.freq
                : freq // ignore: cast_nullable_to_non_nullable
                      as double,
            power: null == power
                ? _value.power
                : power // ignore: cast_nullable_to_non_nullable
                      as double,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$PeakAlphaInfoImplCopyWith<$Res>
    implements $PeakAlphaInfoCopyWith<$Res> {
  factory _$$PeakAlphaInfoImplCopyWith(
    _$PeakAlphaInfoImpl value,
    $Res Function(_$PeakAlphaInfoImpl) then,
  ) = __$$PeakAlphaInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double freq, double power});
}

/// @nodoc
class __$$PeakAlphaInfoImplCopyWithImpl<$Res>
    extends _$PeakAlphaInfoCopyWithImpl<$Res, _$PeakAlphaInfoImpl>
    implements _$$PeakAlphaInfoImplCopyWith<$Res> {
  __$$PeakAlphaInfoImplCopyWithImpl(
    _$PeakAlphaInfoImpl _value,
    $Res Function(_$PeakAlphaInfoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PeakAlphaInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? freq = null, Object? power = null}) {
    return _then(
      _$PeakAlphaInfoImpl(
        freq: null == freq
            ? _value.freq
            : freq // ignore: cast_nullable_to_non_nullable
                  as double,
        power: null == power
            ? _value.power
            : power // ignore: cast_nullable_to_non_nullable
                  as double,
      ),
    );
  }
}

/// @nodoc

class _$PeakAlphaInfoImpl implements _PeakAlphaInfo {
  const _$PeakAlphaInfoImpl({required this.freq, required this.power});

  @override
  final double freq;
  @override
  final double power;

  @override
  String toString() {
    return 'PeakAlphaInfo(freq: $freq, power: $power)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PeakAlphaInfoImpl &&
            (identical(other.freq, freq) || other.freq == freq) &&
            (identical(other.power, power) || other.power == power));
  }

  @override
  int get hashCode => Object.hash(runtimeType, freq, power);

  /// Create a copy of PeakAlphaInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PeakAlphaInfoImplCopyWith<_$PeakAlphaInfoImpl> get copyWith =>
      __$$PeakAlphaInfoImplCopyWithImpl<_$PeakAlphaInfoImpl>(this, _$identity);
}

abstract class _PeakAlphaInfo implements PeakAlphaInfo {
  const factory _PeakAlphaInfo({
    required final double freq,
    required final double power,
  }) = _$PeakAlphaInfoImpl;

  @override
  double get freq;
  @override
  double get power;

  /// Create a copy of PeakAlphaInfo
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PeakAlphaInfoImplCopyWith<_$PeakAlphaInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$PeakAlphaRecord {
  double get timestamp => throw _privateConstructorUsedError;
  double get frequency => throw _privateConstructorUsedError;
  double get power => throw _privateConstructorUsedError;

  /// Create a copy of PeakAlphaRecord
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PeakAlphaRecordCopyWith<PeakAlphaRecord> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PeakAlphaRecordCopyWith<$Res> {
  factory $PeakAlphaRecordCopyWith(
    PeakAlphaRecord value,
    $Res Function(PeakAlphaRecord) then,
  ) = _$PeakAlphaRecordCopyWithImpl<$Res, PeakAlphaRecord>;
  @useResult
  $Res call({double timestamp, double frequency, double power});
}

/// @nodoc
class _$PeakAlphaRecordCopyWithImpl<$Res, $Val extends PeakAlphaRecord>
    implements $PeakAlphaRecordCopyWith<$Res> {
  _$PeakAlphaRecordCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PeakAlphaRecord
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? timestamp = null,
    Object? frequency = null,
    Object? power = null,
  }) {
    return _then(
      _value.copyWith(
            timestamp: null == timestamp
                ? _value.timestamp
                : timestamp // ignore: cast_nullable_to_non_nullable
                      as double,
            frequency: null == frequency
                ? _value.frequency
                : frequency // ignore: cast_nullable_to_non_nullable
                      as double,
            power: null == power
                ? _value.power
                : power // ignore: cast_nullable_to_non_nullable
                      as double,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$PeakAlphaRecordImplCopyWith<$Res>
    implements $PeakAlphaRecordCopyWith<$Res> {
  factory _$$PeakAlphaRecordImplCopyWith(
    _$PeakAlphaRecordImpl value,
    $Res Function(_$PeakAlphaRecordImpl) then,
  ) = __$$PeakAlphaRecordImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double timestamp, double frequency, double power});
}

/// @nodoc
class __$$PeakAlphaRecordImplCopyWithImpl<$Res>
    extends _$PeakAlphaRecordCopyWithImpl<$Res, _$PeakAlphaRecordImpl>
    implements _$$PeakAlphaRecordImplCopyWith<$Res> {
  __$$PeakAlphaRecordImplCopyWithImpl(
    _$PeakAlphaRecordImpl _value,
    $Res Function(_$PeakAlphaRecordImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PeakAlphaRecord
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? timestamp = null,
    Object? frequency = null,
    Object? power = null,
  }) {
    return _then(
      _$PeakAlphaRecordImpl(
        timestamp: null == timestamp
            ? _value.timestamp
            : timestamp // ignore: cast_nullable_to_non_nullable
                  as double,
        frequency: null == frequency
            ? _value.frequency
            : frequency // ignore: cast_nullable_to_non_nullable
                  as double,
        power: null == power
            ? _value.power
            : power // ignore: cast_nullable_to_non_nullable
                  as double,
      ),
    );
  }
}

/// @nodoc

class _$PeakAlphaRecordImpl implements _PeakAlphaRecord {
  const _$PeakAlphaRecordImpl({
    required this.timestamp,
    required this.frequency,
    required this.power,
  });

  @override
  final double timestamp;
  @override
  final double frequency;
  @override
  final double power;

  @override
  String toString() {
    return 'PeakAlphaRecord(timestamp: $timestamp, frequency: $frequency, power: $power)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PeakAlphaRecordImpl &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            (identical(other.frequency, frequency) ||
                other.frequency == frequency) &&
            (identical(other.power, power) || other.power == power));
  }

  @override
  int get hashCode => Object.hash(runtimeType, timestamp, frequency, power);

  /// Create a copy of PeakAlphaRecord
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PeakAlphaRecordImplCopyWith<_$PeakAlphaRecordImpl> get copyWith =>
      __$$PeakAlphaRecordImplCopyWithImpl<_$PeakAlphaRecordImpl>(
        this,
        _$identity,
      );
}

abstract class _PeakAlphaRecord implements PeakAlphaRecord {
  const factory _PeakAlphaRecord({
    required final double timestamp,
    required final double frequency,
    required final double power,
  }) = _$PeakAlphaRecordImpl;

  @override
  double get timestamp;
  @override
  double get frequency;
  @override
  double get power;

  /// Create a copy of PeakAlphaRecord
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PeakAlphaRecordImplCopyWith<_$PeakAlphaRecordImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$PulseRecord {
  double get timestamp => throw _privateConstructorUsedError;
  double get bpm => throw _privateConstructorUsedError;
  double get confidence => throw _privateConstructorUsedError;

  /// Create a copy of PulseRecord
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PulseRecordCopyWith<PulseRecord> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PulseRecordCopyWith<$Res> {
  factory $PulseRecordCopyWith(
    PulseRecord value,
    $Res Function(PulseRecord) then,
  ) = _$PulseRecordCopyWithImpl<$Res, PulseRecord>;
  @useResult
  $Res call({double timestamp, double bpm, double confidence});
}

/// @nodoc
class _$PulseRecordCopyWithImpl<$Res, $Val extends PulseRecord>
    implements $PulseRecordCopyWith<$Res> {
  _$PulseRecordCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PulseRecord
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? timestamp = null,
    Object? bpm = null,
    Object? confidence = null,
  }) {
    return _then(
      _value.copyWith(
            timestamp: null == timestamp
                ? _value.timestamp
                : timestamp // ignore: cast_nullable_to_non_nullable
                      as double,
            bpm: null == bpm
                ? _value.bpm
                : bpm // ignore: cast_nullable_to_non_nullable
                      as double,
            confidence: null == confidence
                ? _value.confidence
                : confidence // ignore: cast_nullable_to_non_nullable
                      as double,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$PulseRecordImplCopyWith<$Res>
    implements $PulseRecordCopyWith<$Res> {
  factory _$$PulseRecordImplCopyWith(
    _$PulseRecordImpl value,
    $Res Function(_$PulseRecordImpl) then,
  ) = __$$PulseRecordImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double timestamp, double bpm, double confidence});
}

/// @nodoc
class __$$PulseRecordImplCopyWithImpl<$Res>
    extends _$PulseRecordCopyWithImpl<$Res, _$PulseRecordImpl>
    implements _$$PulseRecordImplCopyWith<$Res> {
  __$$PulseRecordImplCopyWithImpl(
    _$PulseRecordImpl _value,
    $Res Function(_$PulseRecordImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PulseRecord
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? timestamp = null,
    Object? bpm = null,
    Object? confidence = null,
  }) {
    return _then(
      _$PulseRecordImpl(
        timestamp: null == timestamp
            ? _value.timestamp
            : timestamp // ignore: cast_nullable_to_non_nullable
                  as double,
        bpm: null == bpm
            ? _value.bpm
            : bpm // ignore: cast_nullable_to_non_nullable
                  as double,
        confidence: null == confidence
            ? _value.confidence
            : confidence // ignore: cast_nullable_to_non_nullable
                  as double,
      ),
    );
  }
}

/// @nodoc

class _$PulseRecordImpl implements _PulseRecord {
  const _$PulseRecordImpl({
    required this.timestamp,
    required this.bpm,
    required this.confidence,
  });

  @override
  final double timestamp;
  @override
  final double bpm;
  @override
  final double confidence;

  @override
  String toString() {
    return 'PulseRecord(timestamp: $timestamp, bpm: $bpm, confidence: $confidence)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PulseRecordImpl &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            (identical(other.bpm, bpm) || other.bpm == bpm) &&
            (identical(other.confidence, confidence) ||
                other.confidence == confidence));
  }

  @override
  int get hashCode => Object.hash(runtimeType, timestamp, bpm, confidence);

  /// Create a copy of PulseRecord
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PulseRecordImplCopyWith<_$PulseRecordImpl> get copyWith =>
      __$$PulseRecordImplCopyWithImpl<_$PulseRecordImpl>(this, _$identity);
}

abstract class _PulseRecord implements PulseRecord {
  const factory _PulseRecord({
    required final double timestamp,
    required final double bpm,
    required final double confidence,
  }) = _$PulseRecordImpl;

  @override
  double get timestamp;
  @override
  double get bpm;
  @override
  double get confidence;

  /// Create a copy of PulseRecord
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PulseRecordImplCopyWith<_$PulseRecordImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$SessionData {
  List<BandsRecord> get bands => throw _privateConstructorUsedError;
  List<PulseRecord> get pulses => throw _privateConstructorUsedError;
  List<SpO2Record> get spo2S => throw _privateConstructorUsedError;
  List<MovementRecord> get movements => throw _privateConstructorUsedError;
  List<PeakAlphaRecord> get peakAlphas => throw _privateConstructorUsedError;
  BigInt get eegSamples => throw _privateConstructorUsedError;
  List<EegSampleRecord> get eeg => throw _privateConstructorUsedError;

  /// Create a copy of SessionData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SessionDataCopyWith<SessionData> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SessionDataCopyWith<$Res> {
  factory $SessionDataCopyWith(
    SessionData value,
    $Res Function(SessionData) then,
  ) = _$SessionDataCopyWithImpl<$Res, SessionData>;
  @useResult
  $Res call({
    List<BandsRecord> bands,
    List<PulseRecord> pulses,
    List<SpO2Record> spo2S,
    List<MovementRecord> movements,
    List<PeakAlphaRecord> peakAlphas,
    BigInt eegSamples,
    List<EegSampleRecord> eeg,
  });
}

/// @nodoc
class _$SessionDataCopyWithImpl<$Res, $Val extends SessionData>
    implements $SessionDataCopyWith<$Res> {
  _$SessionDataCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SessionData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? bands = null,
    Object? pulses = null,
    Object? spo2S = null,
    Object? movements = null,
    Object? peakAlphas = null,
    Object? eegSamples = null,
    Object? eeg = null,
  }) {
    return _then(
      _value.copyWith(
            bands: null == bands
                ? _value.bands
                : bands // ignore: cast_nullable_to_non_nullable
                      as List<BandsRecord>,
            pulses: null == pulses
                ? _value.pulses
                : pulses // ignore: cast_nullable_to_non_nullable
                      as List<PulseRecord>,
            spo2S: null == spo2S
                ? _value.spo2S
                : spo2S // ignore: cast_nullable_to_non_nullable
                      as List<SpO2Record>,
            movements: null == movements
                ? _value.movements
                : movements // ignore: cast_nullable_to_non_nullable
                      as List<MovementRecord>,
            peakAlphas: null == peakAlphas
                ? _value.peakAlphas
                : peakAlphas // ignore: cast_nullable_to_non_nullable
                      as List<PeakAlphaRecord>,
            eegSamples: null == eegSamples
                ? _value.eegSamples
                : eegSamples // ignore: cast_nullable_to_non_nullable
                      as BigInt,
            eeg: null == eeg
                ? _value.eeg
                : eeg // ignore: cast_nullable_to_non_nullable
                      as List<EegSampleRecord>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$SessionDataImplCopyWith<$Res>
    implements $SessionDataCopyWith<$Res> {
  factory _$$SessionDataImplCopyWith(
    _$SessionDataImpl value,
    $Res Function(_$SessionDataImpl) then,
  ) = __$$SessionDataImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    List<BandsRecord> bands,
    List<PulseRecord> pulses,
    List<SpO2Record> spo2S,
    List<MovementRecord> movements,
    List<PeakAlphaRecord> peakAlphas,
    BigInt eegSamples,
    List<EegSampleRecord> eeg,
  });
}

/// @nodoc
class __$$SessionDataImplCopyWithImpl<$Res>
    extends _$SessionDataCopyWithImpl<$Res, _$SessionDataImpl>
    implements _$$SessionDataImplCopyWith<$Res> {
  __$$SessionDataImplCopyWithImpl(
    _$SessionDataImpl _value,
    $Res Function(_$SessionDataImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SessionData
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? bands = null,
    Object? pulses = null,
    Object? spo2S = null,
    Object? movements = null,
    Object? peakAlphas = null,
    Object? eegSamples = null,
    Object? eeg = null,
  }) {
    return _then(
      _$SessionDataImpl(
        bands: null == bands
            ? _value._bands
            : bands // ignore: cast_nullable_to_non_nullable
                  as List<BandsRecord>,
        pulses: null == pulses
            ? _value._pulses
            : pulses // ignore: cast_nullable_to_non_nullable
                  as List<PulseRecord>,
        spo2S: null == spo2S
            ? _value._spo2S
            : spo2S // ignore: cast_nullable_to_non_nullable
                  as List<SpO2Record>,
        movements: null == movements
            ? _value._movements
            : movements // ignore: cast_nullable_to_non_nullable
                  as List<MovementRecord>,
        peakAlphas: null == peakAlphas
            ? _value._peakAlphas
            : peakAlphas // ignore: cast_nullable_to_non_nullable
                  as List<PeakAlphaRecord>,
        eegSamples: null == eegSamples
            ? _value.eegSamples
            : eegSamples // ignore: cast_nullable_to_non_nullable
                  as BigInt,
        eeg: null == eeg
            ? _value._eeg
            : eeg // ignore: cast_nullable_to_non_nullable
                  as List<EegSampleRecord>,
      ),
    );
  }
}

/// @nodoc

class _$SessionDataImpl implements _SessionData {
  const _$SessionDataImpl({
    required final List<BandsRecord> bands,
    required final List<PulseRecord> pulses,
    required final List<SpO2Record> spo2S,
    required final List<MovementRecord> movements,
    required final List<PeakAlphaRecord> peakAlphas,
    required this.eegSamples,
    required final List<EegSampleRecord> eeg,
  }) : _bands = bands,
       _pulses = pulses,
       _spo2S = spo2S,
       _movements = movements,
       _peakAlphas = peakAlphas,
       _eeg = eeg;

  final List<BandsRecord> _bands;
  @override
  List<BandsRecord> get bands {
    if (_bands is EqualUnmodifiableListView) return _bands;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_bands);
  }

  final List<PulseRecord> _pulses;
  @override
  List<PulseRecord> get pulses {
    if (_pulses is EqualUnmodifiableListView) return _pulses;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_pulses);
  }

  final List<SpO2Record> _spo2S;
  @override
  List<SpO2Record> get spo2S {
    if (_spo2S is EqualUnmodifiableListView) return _spo2S;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_spo2S);
  }

  final List<MovementRecord> _movements;
  @override
  List<MovementRecord> get movements {
    if (_movements is EqualUnmodifiableListView) return _movements;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_movements);
  }

  final List<PeakAlphaRecord> _peakAlphas;
  @override
  List<PeakAlphaRecord> get peakAlphas {
    if (_peakAlphas is EqualUnmodifiableListView) return _peakAlphas;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_peakAlphas);
  }

  @override
  final BigInt eegSamples;
  final List<EegSampleRecord> _eeg;
  @override
  List<EegSampleRecord> get eeg {
    if (_eeg is EqualUnmodifiableListView) return _eeg;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_eeg);
  }

  @override
  String toString() {
    return 'SessionData(bands: $bands, pulses: $pulses, spo2S: $spo2S, movements: $movements, peakAlphas: $peakAlphas, eegSamples: $eegSamples, eeg: $eeg)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SessionDataImpl &&
            const DeepCollectionEquality().equals(other._bands, _bands) &&
            const DeepCollectionEquality().equals(other._pulses, _pulses) &&
            const DeepCollectionEquality().equals(other._spo2S, _spo2S) &&
            const DeepCollectionEquality().equals(
              other._movements,
              _movements,
            ) &&
            const DeepCollectionEquality().equals(
              other._peakAlphas,
              _peakAlphas,
            ) &&
            (identical(other.eegSamples, eegSamples) ||
                other.eegSamples == eegSamples) &&
            const DeepCollectionEquality().equals(other._eeg, _eeg));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    const DeepCollectionEquality().hash(_bands),
    const DeepCollectionEquality().hash(_pulses),
    const DeepCollectionEquality().hash(_spo2S),
    const DeepCollectionEquality().hash(_movements),
    const DeepCollectionEquality().hash(_peakAlphas),
    eegSamples,
    const DeepCollectionEquality().hash(_eeg),
  );

  /// Create a copy of SessionData
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SessionDataImplCopyWith<_$SessionDataImpl> get copyWith =>
      __$$SessionDataImplCopyWithImpl<_$SessionDataImpl>(this, _$identity);
}

abstract class _SessionData implements SessionData {
  const factory _SessionData({
    required final List<BandsRecord> bands,
    required final List<PulseRecord> pulses,
    required final List<SpO2Record> spo2S,
    required final List<MovementRecord> movements,
    required final List<PeakAlphaRecord> peakAlphas,
    required final BigInt eegSamples,
    required final List<EegSampleRecord> eeg,
  }) = _$SessionDataImpl;

  @override
  List<BandsRecord> get bands;
  @override
  List<PulseRecord> get pulses;
  @override
  List<SpO2Record> get spo2S;
  @override
  List<MovementRecord> get movements;
  @override
  List<PeakAlphaRecord> get peakAlphas;
  @override
  BigInt get eegSamples;
  @override
  List<EegSampleRecord> get eeg;

  /// Create a copy of SessionData
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SessionDataImplCopyWith<_$SessionDataImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$SpO2Record {
  double get timestamp => throw _privateConstructorUsedError;
  double get spo2 => throw _privateConstructorUsedError;
  double get confidence => throw _privateConstructorUsedError;

  /// Create a copy of SpO2Record
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $SpO2RecordCopyWith<SpO2Record> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $SpO2RecordCopyWith<$Res> {
  factory $SpO2RecordCopyWith(
    SpO2Record value,
    $Res Function(SpO2Record) then,
  ) = _$SpO2RecordCopyWithImpl<$Res, SpO2Record>;
  @useResult
  $Res call({double timestamp, double spo2, double confidence});
}

/// @nodoc
class _$SpO2RecordCopyWithImpl<$Res, $Val extends SpO2Record>
    implements $SpO2RecordCopyWith<$Res> {
  _$SpO2RecordCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of SpO2Record
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? timestamp = null,
    Object? spo2 = null,
    Object? confidence = null,
  }) {
    return _then(
      _value.copyWith(
            timestamp: null == timestamp
                ? _value.timestamp
                : timestamp // ignore: cast_nullable_to_non_nullable
                      as double,
            spo2: null == spo2
                ? _value.spo2
                : spo2 // ignore: cast_nullable_to_non_nullable
                      as double,
            confidence: null == confidence
                ? _value.confidence
                : confidence // ignore: cast_nullable_to_non_nullable
                      as double,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$SpO2RecordImplCopyWith<$Res>
    implements $SpO2RecordCopyWith<$Res> {
  factory _$$SpO2RecordImplCopyWith(
    _$SpO2RecordImpl value,
    $Res Function(_$SpO2RecordImpl) then,
  ) = __$$SpO2RecordImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double timestamp, double spo2, double confidence});
}

/// @nodoc
class __$$SpO2RecordImplCopyWithImpl<$Res>
    extends _$SpO2RecordCopyWithImpl<$Res, _$SpO2RecordImpl>
    implements _$$SpO2RecordImplCopyWith<$Res> {
  __$$SpO2RecordImplCopyWithImpl(
    _$SpO2RecordImpl _value,
    $Res Function(_$SpO2RecordImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of SpO2Record
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? timestamp = null,
    Object? spo2 = null,
    Object? confidence = null,
  }) {
    return _then(
      _$SpO2RecordImpl(
        timestamp: null == timestamp
            ? _value.timestamp
            : timestamp // ignore: cast_nullable_to_non_nullable
                  as double,
        spo2: null == spo2
            ? _value.spo2
            : spo2 // ignore: cast_nullable_to_non_nullable
                  as double,
        confidence: null == confidence
            ? _value.confidence
            : confidence // ignore: cast_nullable_to_non_nullable
                  as double,
      ),
    );
  }
}

/// @nodoc

class _$SpO2RecordImpl implements _SpO2Record {
  const _$SpO2RecordImpl({
    required this.timestamp,
    required this.spo2,
    required this.confidence,
  });

  @override
  final double timestamp;
  @override
  final double spo2;
  @override
  final double confidence;

  @override
  String toString() {
    return 'SpO2Record(timestamp: $timestamp, spo2: $spo2, confidence: $confidence)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SpO2RecordImpl &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            (identical(other.spo2, spo2) || other.spo2 == spo2) &&
            (identical(other.confidence, confidence) ||
                other.confidence == confidence));
  }

  @override
  int get hashCode => Object.hash(runtimeType, timestamp, spo2, confidence);

  /// Create a copy of SpO2Record
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$SpO2RecordImplCopyWith<_$SpO2RecordImpl> get copyWith =>
      __$$SpO2RecordImplCopyWithImpl<_$SpO2RecordImpl>(this, _$identity);
}

abstract class _SpO2Record implements SpO2Record {
  const factory _SpO2Record({
    required final double timestamp,
    required final double spo2,
    required final double confidence,
  }) = _$SpO2RecordImpl;

  @override
  double get timestamp;
  @override
  double get spo2;
  @override
  double get confidence;

  /// Create a copy of SpO2Record
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$SpO2RecordImplCopyWith<_$SpO2RecordImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$V5Header {
  BigInt get thumbnailOffset => throw _privateConstructorUsedError;
  BigInt get thumbnailLength => throw _privateConstructorUsedError;
  BigInt get metadataOffset => throw _privateConstructorUsedError;
  BigInt get metadataLength => throw _privateConstructorUsedError;
  BigInt get computedOffset => throw _privateConstructorUsedError;
  BigInt get computedLength => throw _privateConstructorUsedError;
  BigInt get rawOffset => throw _privateConstructorUsedError;

  /// Create a copy of V5Header
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $V5HeaderCopyWith<V5Header> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $V5HeaderCopyWith<$Res> {
  factory $V5HeaderCopyWith(V5Header value, $Res Function(V5Header) then) =
      _$V5HeaderCopyWithImpl<$Res, V5Header>;
  @useResult
  $Res call({
    BigInt thumbnailOffset,
    BigInt thumbnailLength,
    BigInt metadataOffset,
    BigInt metadataLength,
    BigInt computedOffset,
    BigInt computedLength,
    BigInt rawOffset,
  });
}

/// @nodoc
class _$V5HeaderCopyWithImpl<$Res, $Val extends V5Header>
    implements $V5HeaderCopyWith<$Res> {
  _$V5HeaderCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of V5Header
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? thumbnailOffset = null,
    Object? thumbnailLength = null,
    Object? metadataOffset = null,
    Object? metadataLength = null,
    Object? computedOffset = null,
    Object? computedLength = null,
    Object? rawOffset = null,
  }) {
    return _then(
      _value.copyWith(
            thumbnailOffset: null == thumbnailOffset
                ? _value.thumbnailOffset
                : thumbnailOffset // ignore: cast_nullable_to_non_nullable
                      as BigInt,
            thumbnailLength: null == thumbnailLength
                ? _value.thumbnailLength
                : thumbnailLength // ignore: cast_nullable_to_non_nullable
                      as BigInt,
            metadataOffset: null == metadataOffset
                ? _value.metadataOffset
                : metadataOffset // ignore: cast_nullable_to_non_nullable
                      as BigInt,
            metadataLength: null == metadataLength
                ? _value.metadataLength
                : metadataLength // ignore: cast_nullable_to_non_nullable
                      as BigInt,
            computedOffset: null == computedOffset
                ? _value.computedOffset
                : computedOffset // ignore: cast_nullable_to_non_nullable
                      as BigInt,
            computedLength: null == computedLength
                ? _value.computedLength
                : computedLength // ignore: cast_nullable_to_non_nullable
                      as BigInt,
            rawOffset: null == rawOffset
                ? _value.rawOffset
                : rawOffset // ignore: cast_nullable_to_non_nullable
                      as BigInt,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$V5HeaderImplCopyWith<$Res>
    implements $V5HeaderCopyWith<$Res> {
  factory _$$V5HeaderImplCopyWith(
    _$V5HeaderImpl value,
    $Res Function(_$V5HeaderImpl) then,
  ) = __$$V5HeaderImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    BigInt thumbnailOffset,
    BigInt thumbnailLength,
    BigInt metadataOffset,
    BigInt metadataLength,
    BigInt computedOffset,
    BigInt computedLength,
    BigInt rawOffset,
  });
}

/// @nodoc
class __$$V5HeaderImplCopyWithImpl<$Res>
    extends _$V5HeaderCopyWithImpl<$Res, _$V5HeaderImpl>
    implements _$$V5HeaderImplCopyWith<$Res> {
  __$$V5HeaderImplCopyWithImpl(
    _$V5HeaderImpl _value,
    $Res Function(_$V5HeaderImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of V5Header
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? thumbnailOffset = null,
    Object? thumbnailLength = null,
    Object? metadataOffset = null,
    Object? metadataLength = null,
    Object? computedOffset = null,
    Object? computedLength = null,
    Object? rawOffset = null,
  }) {
    return _then(
      _$V5HeaderImpl(
        thumbnailOffset: null == thumbnailOffset
            ? _value.thumbnailOffset
            : thumbnailOffset // ignore: cast_nullable_to_non_nullable
                  as BigInt,
        thumbnailLength: null == thumbnailLength
            ? _value.thumbnailLength
            : thumbnailLength // ignore: cast_nullable_to_non_nullable
                  as BigInt,
        metadataOffset: null == metadataOffset
            ? _value.metadataOffset
            : metadataOffset // ignore: cast_nullable_to_non_nullable
                  as BigInt,
        metadataLength: null == metadataLength
            ? _value.metadataLength
            : metadataLength // ignore: cast_nullable_to_non_nullable
                  as BigInt,
        computedOffset: null == computedOffset
            ? _value.computedOffset
            : computedOffset // ignore: cast_nullable_to_non_nullable
                  as BigInt,
        computedLength: null == computedLength
            ? _value.computedLength
            : computedLength // ignore: cast_nullable_to_non_nullable
                  as BigInt,
        rawOffset: null == rawOffset
            ? _value.rawOffset
            : rawOffset // ignore: cast_nullable_to_non_nullable
                  as BigInt,
      ),
    );
  }
}

/// @nodoc

class _$V5HeaderImpl implements _V5Header {
  const _$V5HeaderImpl({
    required this.thumbnailOffset,
    required this.thumbnailLength,
    required this.metadataOffset,
    required this.metadataLength,
    required this.computedOffset,
    required this.computedLength,
    required this.rawOffset,
  });

  @override
  final BigInt thumbnailOffset;
  @override
  final BigInt thumbnailLength;
  @override
  final BigInt metadataOffset;
  @override
  final BigInt metadataLength;
  @override
  final BigInt computedOffset;
  @override
  final BigInt computedLength;
  @override
  final BigInt rawOffset;

  @override
  String toString() {
    return 'V5Header(thumbnailOffset: $thumbnailOffset, thumbnailLength: $thumbnailLength, metadataOffset: $metadataOffset, metadataLength: $metadataLength, computedOffset: $computedOffset, computedLength: $computedLength, rawOffset: $rawOffset)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$V5HeaderImpl &&
            (identical(other.thumbnailOffset, thumbnailOffset) ||
                other.thumbnailOffset == thumbnailOffset) &&
            (identical(other.thumbnailLength, thumbnailLength) ||
                other.thumbnailLength == thumbnailLength) &&
            (identical(other.metadataOffset, metadataOffset) ||
                other.metadataOffset == metadataOffset) &&
            (identical(other.metadataLength, metadataLength) ||
                other.metadataLength == metadataLength) &&
            (identical(other.computedOffset, computedOffset) ||
                other.computedOffset == computedOffset) &&
            (identical(other.computedLength, computedLength) ||
                other.computedLength == computedLength) &&
            (identical(other.rawOffset, rawOffset) ||
                other.rawOffset == rawOffset));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    thumbnailOffset,
    thumbnailLength,
    metadataOffset,
    metadataLength,
    computedOffset,
    computedLength,
    rawOffset,
  );

  /// Create a copy of V5Header
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$V5HeaderImplCopyWith<_$V5HeaderImpl> get copyWith =>
      __$$V5HeaderImplCopyWithImpl<_$V5HeaderImpl>(this, _$identity);
}

abstract class _V5Header implements V5Header {
  const factory _V5Header({
    required final BigInt thumbnailOffset,
    required final BigInt thumbnailLength,
    required final BigInt metadataOffset,
    required final BigInt metadataLength,
    required final BigInt computedOffset,
    required final BigInt computedLength,
    required final BigInt rawOffset,
  }) = _$V5HeaderImpl;

  @override
  BigInt get thumbnailOffset;
  @override
  BigInt get thumbnailLength;
  @override
  BigInt get metadataOffset;
  @override
  BigInt get metadataLength;
  @override
  BigInt get computedOffset;
  @override
  BigInt get computedLength;
  @override
  BigInt get rawOffset;

  /// Create a copy of V5Header
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$V5HeaderImplCopyWith<_$V5HeaderImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$V5ParsedHead {
  V5Header get header => throw _privateConstructorUsedError;
  Uint8List get thumbnail => throw _privateConstructorUsedError;
  Uint8List get metadataJson => throw _privateConstructorUsedError;

  /// Create a copy of V5ParsedHead
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $V5ParsedHeadCopyWith<V5ParsedHead> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $V5ParsedHeadCopyWith<$Res> {
  factory $V5ParsedHeadCopyWith(
    V5ParsedHead value,
    $Res Function(V5ParsedHead) then,
  ) = _$V5ParsedHeadCopyWithImpl<$Res, V5ParsedHead>;
  @useResult
  $Res call({V5Header header, Uint8List thumbnail, Uint8List metadataJson});

  $V5HeaderCopyWith<$Res> get header;
}

/// @nodoc
class _$V5ParsedHeadCopyWithImpl<$Res, $Val extends V5ParsedHead>
    implements $V5ParsedHeadCopyWith<$Res> {
  _$V5ParsedHeadCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of V5ParsedHead
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? header = null,
    Object? thumbnail = null,
    Object? metadataJson = null,
  }) {
    return _then(
      _value.copyWith(
            header: null == header
                ? _value.header
                : header // ignore: cast_nullable_to_non_nullable
                      as V5Header,
            thumbnail: null == thumbnail
                ? _value.thumbnail
                : thumbnail // ignore: cast_nullable_to_non_nullable
                      as Uint8List,
            metadataJson: null == metadataJson
                ? _value.metadataJson
                : metadataJson // ignore: cast_nullable_to_non_nullable
                      as Uint8List,
          )
          as $Val,
    );
  }

  /// Create a copy of V5ParsedHead
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $V5HeaderCopyWith<$Res> get header {
    return $V5HeaderCopyWith<$Res>(_value.header, (value) {
      return _then(_value.copyWith(header: value) as $Val);
    });
  }
}

/// @nodoc
abstract class _$$V5ParsedHeadImplCopyWith<$Res>
    implements $V5ParsedHeadCopyWith<$Res> {
  factory _$$V5ParsedHeadImplCopyWith(
    _$V5ParsedHeadImpl value,
    $Res Function(_$V5ParsedHeadImpl) then,
  ) = __$$V5ParsedHeadImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({V5Header header, Uint8List thumbnail, Uint8List metadataJson});

  @override
  $V5HeaderCopyWith<$Res> get header;
}

/// @nodoc
class __$$V5ParsedHeadImplCopyWithImpl<$Res>
    extends _$V5ParsedHeadCopyWithImpl<$Res, _$V5ParsedHeadImpl>
    implements _$$V5ParsedHeadImplCopyWith<$Res> {
  __$$V5ParsedHeadImplCopyWithImpl(
    _$V5ParsedHeadImpl _value,
    $Res Function(_$V5ParsedHeadImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of V5ParsedHead
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? header = null,
    Object? thumbnail = null,
    Object? metadataJson = null,
  }) {
    return _then(
      _$V5ParsedHeadImpl(
        header: null == header
            ? _value.header
            : header // ignore: cast_nullable_to_non_nullable
                  as V5Header,
        thumbnail: null == thumbnail
            ? _value.thumbnail
            : thumbnail // ignore: cast_nullable_to_non_nullable
                  as Uint8List,
        metadataJson: null == metadataJson
            ? _value.metadataJson
            : metadataJson // ignore: cast_nullable_to_non_nullable
                  as Uint8List,
      ),
    );
  }
}

/// @nodoc

class _$V5ParsedHeadImpl implements _V5ParsedHead {
  const _$V5ParsedHeadImpl({
    required this.header,
    required this.thumbnail,
    required this.metadataJson,
  });

  @override
  final V5Header header;
  @override
  final Uint8List thumbnail;
  @override
  final Uint8List metadataJson;

  @override
  String toString() {
    return 'V5ParsedHead(header: $header, thumbnail: $thumbnail, metadataJson: $metadataJson)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$V5ParsedHeadImpl &&
            (identical(other.header, header) || other.header == header) &&
            const DeepCollectionEquality().equals(other.thumbnail, thumbnail) &&
            const DeepCollectionEquality().equals(
              other.metadataJson,
              metadataJson,
            ));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    header,
    const DeepCollectionEquality().hash(thumbnail),
    const DeepCollectionEquality().hash(metadataJson),
  );

  /// Create a copy of V5ParsedHead
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$V5ParsedHeadImplCopyWith<_$V5ParsedHeadImpl> get copyWith =>
      __$$V5ParsedHeadImplCopyWithImpl<_$V5ParsedHeadImpl>(this, _$identity);
}

abstract class _V5ParsedHead implements V5ParsedHead {
  const factory _V5ParsedHead({
    required final V5Header header,
    required final Uint8List thumbnail,
    required final Uint8List metadataJson,
  }) = _$V5ParsedHeadImpl;

  @override
  V5Header get header;
  @override
  Uint8List get thumbnail;
  @override
  Uint8List get metadataJson;

  /// Create a copy of V5ParsedHead
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$V5ParsedHeadImplCopyWith<_$V5ParsedHeadImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
