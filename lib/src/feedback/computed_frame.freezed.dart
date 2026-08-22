// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'computed_frame.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

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
mixin _$ComputedFrame {
  double get t => throw _privateConstructorUsedError;
  List<List<double>> get bands => throw _privateConstructorUsedError;
  double? get pulse => throw _privateConstructorUsedError;
  double? get movement => throw _privateConstructorUsedError;
  PeakAlphaInfo? get peakAlpha => throw _privateConstructorUsedError;
  double? get spo2 => throw _privateConstructorUsedError;
  List<double> get lineNoise => throw _privateConstructorUsedError;
  List<int> get signalQuality => throw _privateConstructorUsedError;
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
    List<List<double>> bands,
    double? pulse,
    double? movement,
    PeakAlphaInfo? peakAlpha,
    double? spo2,
    List<double> lineNoise,
    List<int> signalQuality,
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
                      as List<List<double>>,
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
                      as List<double>,
            signalQuality: null == signalQuality
                ? _value.signalQuality
                : signalQuality // ignore: cast_nullable_to_non_nullable
                      as List<int>,
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
    List<List<double>> bands,
    double? pulse,
    double? movement,
    PeakAlphaInfo? peakAlpha,
    double? spo2,
    List<double> lineNoise,
    List<int> signalQuality,
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
                  as List<List<double>>,
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
            ? _value._lineNoise
            : lineNoise // ignore: cast_nullable_to_non_nullable
                  as List<double>,
        signalQuality: null == signalQuality
            ? _value._signalQuality
            : signalQuality // ignore: cast_nullable_to_non_nullable
                  as List<int>,
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

class _$ComputedFrameImpl implements _ComputedFrame {
  const _$ComputedFrameImpl({
    required this.t,
    required final List<List<double>> bands,
    this.pulse,
    this.movement,
    this.peakAlpha,
    this.spo2,
    required final List<double> lineNoise,
    required final List<int> signalQuality,
    required this.guardrail,
    required this.feedback,
    required final List<String> gestures,
  }) : _bands = bands,
       _lineNoise = lineNoise,
       _signalQuality = signalQuality,
       _gestures = gestures;

  @override
  final double t;
  final List<List<double>> _bands;
  @override
  List<List<double>> get bands {
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
  final List<double> _lineNoise;
  @override
  List<double> get lineNoise {
    if (_lineNoise is EqualUnmodifiableListView) return _lineNoise;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_lineNoise);
  }

  final List<int> _signalQuality;
  @override
  List<int> get signalQuality {
    if (_signalQuality is EqualUnmodifiableListView) return _signalQuality;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_signalQuality);
  }

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
            const DeepCollectionEquality().equals(
              other._lineNoise,
              _lineNoise,
            ) &&
            const DeepCollectionEquality().equals(
              other._signalQuality,
              _signalQuality,
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
    const DeepCollectionEquality().hash(_lineNoise),
    const DeepCollectionEquality().hash(_signalQuality),
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

abstract class _ComputedFrame implements ComputedFrame {
  const factory _ComputedFrame({
    required final double t,
    required final List<List<double>> bands,
    final double? pulse,
    final double? movement,
    final PeakAlphaInfo? peakAlpha,
    final double? spo2,
    required final List<double> lineNoise,
    required final List<int> signalQuality,
    required final GuardrailInfo guardrail,
    required final FeedbackInfo feedback,
    required final List<String> gestures,
  }) = _$ComputedFrameImpl;

  @override
  double get t;
  @override
  List<List<double>> get bands;
  @override
  double? get pulse;
  @override
  double? get movement;
  @override
  PeakAlphaInfo? get peakAlpha;
  @override
  double? get spo2;
  @override
  List<double> get lineNoise;
  @override
  List<int> get signalQuality;
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
