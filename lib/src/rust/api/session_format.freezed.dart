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
    required final List<MovementRecord> movements,
    required final List<PeakAlphaRecord> peakAlphas,
    required this.eegSamples,
    required final List<EegSampleRecord> eeg,
  }) : _bands = bands,
       _pulses = pulses,
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
    return 'SessionData(bands: $bands, pulses: $pulses, movements: $movements, peakAlphas: $peakAlphas, eegSamples: $eegSamples, eeg: $eeg)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$SessionDataImpl &&
            const DeepCollectionEquality().equals(other._bands, _bands) &&
            const DeepCollectionEquality().equals(other._pulses, _pulses) &&
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
