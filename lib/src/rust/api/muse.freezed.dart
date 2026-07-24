// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'muse.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$BandsDto {
  int get electrode => throw _privateConstructorUsedError;
  double get timestamp => throw _privateConstructorUsedError;
  double get delta => throw _privateConstructorUsedError;
  double get theta => throw _privateConstructorUsedError;
  double get alpha => throw _privateConstructorUsedError;
  double get beta => throw _privateConstructorUsedError;
  double get gamma => throw _privateConstructorUsedError;

  /// Create a copy of BandsDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $BandsDtoCopyWith<BandsDto> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $BandsDtoCopyWith<$Res> {
  factory $BandsDtoCopyWith(BandsDto value, $Res Function(BandsDto) then) =
      _$BandsDtoCopyWithImpl<$Res, BandsDto>;
  @useResult
  $Res call({
    int electrode,
    double timestamp,
    double delta,
    double theta,
    double alpha,
    double beta,
    double gamma,
  });
}

/// @nodoc
class _$BandsDtoCopyWithImpl<$Res, $Val extends BandsDto>
    implements $BandsDtoCopyWith<$Res> {
  _$BandsDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of BandsDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? electrode = null,
    Object? timestamp = null,
    Object? delta = null,
    Object? theta = null,
    Object? alpha = null,
    Object? beta = null,
    Object? gamma = null,
  }) {
    return _then(
      _value.copyWith(
            electrode: null == electrode
                ? _value.electrode
                : electrode // ignore: cast_nullable_to_non_nullable
                      as int,
            timestamp: null == timestamp
                ? _value.timestamp
                : timestamp // ignore: cast_nullable_to_non_nullable
                      as double,
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
abstract class _$$BandsDtoImplCopyWith<$Res>
    implements $BandsDtoCopyWith<$Res> {
  factory _$$BandsDtoImplCopyWith(
    _$BandsDtoImpl value,
    $Res Function(_$BandsDtoImpl) then,
  ) = __$$BandsDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    int electrode,
    double timestamp,
    double delta,
    double theta,
    double alpha,
    double beta,
    double gamma,
  });
}

/// @nodoc
class __$$BandsDtoImplCopyWithImpl<$Res>
    extends _$BandsDtoCopyWithImpl<$Res, _$BandsDtoImpl>
    implements _$$BandsDtoImplCopyWith<$Res> {
  __$$BandsDtoImplCopyWithImpl(
    _$BandsDtoImpl _value,
    $Res Function(_$BandsDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of BandsDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? electrode = null,
    Object? timestamp = null,
    Object? delta = null,
    Object? theta = null,
    Object? alpha = null,
    Object? beta = null,
    Object? gamma = null,
  }) {
    return _then(
      _$BandsDtoImpl(
        electrode: null == electrode
            ? _value.electrode
            : electrode // ignore: cast_nullable_to_non_nullable
                  as int,
        timestamp: null == timestamp
            ? _value.timestamp
            : timestamp // ignore: cast_nullable_to_non_nullable
                  as double,
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

class _$BandsDtoImpl implements _BandsDto {
  const _$BandsDtoImpl({
    required this.electrode,
    required this.timestamp,
    required this.delta,
    required this.theta,
    required this.alpha,
    required this.beta,
    required this.gamma,
  });

  @override
  final int electrode;
  @override
  final double timestamp;
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
    return 'BandsDto(electrode: $electrode, timestamp: $timestamp, delta: $delta, theta: $theta, alpha: $alpha, beta: $beta, gamma: $gamma)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$BandsDtoImpl &&
            (identical(other.electrode, electrode) ||
                other.electrode == electrode) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            (identical(other.delta, delta) || other.delta == delta) &&
            (identical(other.theta, theta) || other.theta == theta) &&
            (identical(other.alpha, alpha) || other.alpha == alpha) &&
            (identical(other.beta, beta) || other.beta == beta) &&
            (identical(other.gamma, gamma) || other.gamma == gamma));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    electrode,
    timestamp,
    delta,
    theta,
    alpha,
    beta,
    gamma,
  );

  /// Create a copy of BandsDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$BandsDtoImplCopyWith<_$BandsDtoImpl> get copyWith =>
      __$$BandsDtoImplCopyWithImpl<_$BandsDtoImpl>(this, _$identity);
}

abstract class _BandsDto implements BandsDto {
  const factory _BandsDto({
    required final int electrode,
    required final double timestamp,
    required final double delta,
    required final double theta,
    required final double alpha,
    required final double beta,
    required final double gamma,
  }) = _$BandsDtoImpl;

  @override
  int get electrode;
  @override
  double get timestamp;
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

  /// Create a copy of BandsDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$BandsDtoImplCopyWith<_$BandsDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$ConnectionStatus {
  bool get connected => throw _privateConstructorUsedError;
  String get name => throw _privateConstructorUsedError;
  String get id => throw _privateConstructorUsedError;
  String get firmware => throw _privateConstructorUsedError;

  /// Create a copy of ConnectionStatus
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ConnectionStatusCopyWith<ConnectionStatus> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ConnectionStatusCopyWith<$Res> {
  factory $ConnectionStatusCopyWith(
    ConnectionStatus value,
    $Res Function(ConnectionStatus) then,
  ) = _$ConnectionStatusCopyWithImpl<$Res, ConnectionStatus>;
  @useResult
  $Res call({bool connected, String name, String id, String firmware});
}

/// @nodoc
class _$ConnectionStatusCopyWithImpl<$Res, $Val extends ConnectionStatus>
    implements $ConnectionStatusCopyWith<$Res> {
  _$ConnectionStatusCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ConnectionStatus
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? connected = null,
    Object? name = null,
    Object? id = null,
    Object? firmware = null,
  }) {
    return _then(
      _value.copyWith(
            connected: null == connected
                ? _value.connected
                : connected // ignore: cast_nullable_to_non_nullable
                      as bool,
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            firmware: null == firmware
                ? _value.firmware
                : firmware // ignore: cast_nullable_to_non_nullable
                      as String,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ConnectionStatusImplCopyWith<$Res>
    implements $ConnectionStatusCopyWith<$Res> {
  factory _$$ConnectionStatusImplCopyWith(
    _$ConnectionStatusImpl value,
    $Res Function(_$ConnectionStatusImpl) then,
  ) = __$$ConnectionStatusImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({bool connected, String name, String id, String firmware});
}

/// @nodoc
class __$$ConnectionStatusImplCopyWithImpl<$Res>
    extends _$ConnectionStatusCopyWithImpl<$Res, _$ConnectionStatusImpl>
    implements _$$ConnectionStatusImplCopyWith<$Res> {
  __$$ConnectionStatusImplCopyWithImpl(
    _$ConnectionStatusImpl _value,
    $Res Function(_$ConnectionStatusImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ConnectionStatus
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? connected = null,
    Object? name = null,
    Object? id = null,
    Object? firmware = null,
  }) {
    return _then(
      _$ConnectionStatusImpl(
        connected: null == connected
            ? _value.connected
            : connected // ignore: cast_nullable_to_non_nullable
                  as bool,
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        firmware: null == firmware
            ? _value.firmware
            : firmware // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$ConnectionStatusImpl extends _ConnectionStatus {
  const _$ConnectionStatusImpl({
    required this.connected,
    required this.name,
    required this.id,
    required this.firmware,
  }) : super._();

  @override
  final bool connected;
  @override
  final String name;
  @override
  final String id;
  @override
  final String firmware;

  @override
  String toString() {
    return 'ConnectionStatus(connected: $connected, name: $name, id: $id, firmware: $firmware)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ConnectionStatusImpl &&
            (identical(other.connected, connected) ||
                other.connected == connected) &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.firmware, firmware) ||
                other.firmware == firmware));
  }

  @override
  int get hashCode => Object.hash(runtimeType, connected, name, id, firmware);

  /// Create a copy of ConnectionStatus
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ConnectionStatusImplCopyWith<_$ConnectionStatusImpl> get copyWith =>
      __$$ConnectionStatusImplCopyWithImpl<_$ConnectionStatusImpl>(
        this,
        _$identity,
      );
}

abstract class _ConnectionStatus extends ConnectionStatus {
  const factory _ConnectionStatus({
    required final bool connected,
    required final String name,
    required final String id,
    required final String firmware,
  }) = _$ConnectionStatusImpl;
  const _ConnectionStatus._() : super._();

  @override
  bool get connected;
  @override
  String get name;
  @override
  String get id;
  @override
  String get firmware;

  /// Create a copy of ConnectionStatus
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ConnectionStatusImplCopyWith<_$ConnectionStatusImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$ControlDto {
  String get raw => throw _privateConstructorUsedError;
  Map<String, String> get fields => throw _privateConstructorUsedError;

  /// Create a copy of ControlDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ControlDtoCopyWith<ControlDto> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ControlDtoCopyWith<$Res> {
  factory $ControlDtoCopyWith(
    ControlDto value,
    $Res Function(ControlDto) then,
  ) = _$ControlDtoCopyWithImpl<$Res, ControlDto>;
  @useResult
  $Res call({String raw, Map<String, String> fields});
}

/// @nodoc
class _$ControlDtoCopyWithImpl<$Res, $Val extends ControlDto>
    implements $ControlDtoCopyWith<$Res> {
  _$ControlDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ControlDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? raw = null, Object? fields = null}) {
    return _then(
      _value.copyWith(
            raw: null == raw
                ? _value.raw
                : raw // ignore: cast_nullable_to_non_nullable
                      as String,
            fields: null == fields
                ? _value.fields
                : fields // ignore: cast_nullable_to_non_nullable
                      as Map<String, String>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ControlDtoImplCopyWith<$Res>
    implements $ControlDtoCopyWith<$Res> {
  factory _$$ControlDtoImplCopyWith(
    _$ControlDtoImpl value,
    $Res Function(_$ControlDtoImpl) then,
  ) = __$$ControlDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String raw, Map<String, String> fields});
}

/// @nodoc
class __$$ControlDtoImplCopyWithImpl<$Res>
    extends _$ControlDtoCopyWithImpl<$Res, _$ControlDtoImpl>
    implements _$$ControlDtoImplCopyWith<$Res> {
  __$$ControlDtoImplCopyWithImpl(
    _$ControlDtoImpl _value,
    $Res Function(_$ControlDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ControlDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? raw = null, Object? fields = null}) {
    return _then(
      _$ControlDtoImpl(
        raw: null == raw
            ? _value.raw
            : raw // ignore: cast_nullable_to_non_nullable
                  as String,
        fields: null == fields
            ? _value._fields
            : fields // ignore: cast_nullable_to_non_nullable
                  as Map<String, String>,
      ),
    );
  }
}

/// @nodoc

class _$ControlDtoImpl implements _ControlDto {
  const _$ControlDtoImpl({
    required this.raw,
    required final Map<String, String> fields,
  }) : _fields = fields;

  @override
  final String raw;
  final Map<String, String> _fields;
  @override
  Map<String, String> get fields {
    if (_fields is EqualUnmodifiableMapView) return _fields;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableMapView(_fields);
  }

  @override
  String toString() {
    return 'ControlDto(raw: $raw, fields: $fields)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ControlDtoImpl &&
            (identical(other.raw, raw) || other.raw == raw) &&
            const DeepCollectionEquality().equals(other._fields, _fields));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    raw,
    const DeepCollectionEquality().hash(_fields),
  );

  /// Create a copy of ControlDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ControlDtoImplCopyWith<_$ControlDtoImpl> get copyWith =>
      __$$ControlDtoImplCopyWithImpl<_$ControlDtoImpl>(this, _$identity);
}

abstract class _ControlDto implements ControlDto {
  const factory _ControlDto({
    required final String raw,
    required final Map<String, String> fields,
  }) = _$ControlDtoImpl;

  @override
  String get raw;
  @override
  Map<String, String> get fields;

  /// Create a copy of ControlDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ControlDtoImplCopyWith<_$ControlDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$DeviceInfo {
  String get name => throw _privateConstructorUsedError;
  String get id => throw _privateConstructorUsedError;

  /// Create a copy of DeviceInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $DeviceInfoCopyWith<DeviceInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $DeviceInfoCopyWith<$Res> {
  factory $DeviceInfoCopyWith(
    DeviceInfo value,
    $Res Function(DeviceInfo) then,
  ) = _$DeviceInfoCopyWithImpl<$Res, DeviceInfo>;
  @useResult
  $Res call({String name, String id});
}

/// @nodoc
class _$DeviceInfoCopyWithImpl<$Res, $Val extends DeviceInfo>
    implements $DeviceInfoCopyWith<$Res> {
  _$DeviceInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of DeviceInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? name = null, Object? id = null}) {
    return _then(
      _value.copyWith(
            name: null == name
                ? _value.name
                : name // ignore: cast_nullable_to_non_nullable
                      as String,
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$DeviceInfoImplCopyWith<$Res>
    implements $DeviceInfoCopyWith<$Res> {
  factory _$$DeviceInfoImplCopyWith(
    _$DeviceInfoImpl value,
    $Res Function(_$DeviceInfoImpl) then,
  ) = __$$DeviceInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String name, String id});
}

/// @nodoc
class __$$DeviceInfoImplCopyWithImpl<$Res>
    extends _$DeviceInfoCopyWithImpl<$Res, _$DeviceInfoImpl>
    implements _$$DeviceInfoImplCopyWith<$Res> {
  __$$DeviceInfoImplCopyWithImpl(
    _$DeviceInfoImpl _value,
    $Res Function(_$DeviceInfoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of DeviceInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? name = null, Object? id = null}) {
    return _then(
      _$DeviceInfoImpl(
        name: null == name
            ? _value.name
            : name // ignore: cast_nullable_to_non_nullable
                  as String,
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$DeviceInfoImpl implements _DeviceInfo {
  const _$DeviceInfoImpl({required this.name, required this.id});

  @override
  final String name;
  @override
  final String id;

  @override
  String toString() {
    return 'DeviceInfo(name: $name, id: $id)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$DeviceInfoImpl &&
            (identical(other.name, name) || other.name == name) &&
            (identical(other.id, id) || other.id == id));
  }

  @override
  int get hashCode => Object.hash(runtimeType, name, id);

  /// Create a copy of DeviceInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$DeviceInfoImplCopyWith<_$DeviceInfoImpl> get copyWith =>
      __$$DeviceInfoImplCopyWithImpl<_$DeviceInfoImpl>(this, _$identity);
}

abstract class _DeviceInfo implements DeviceInfo {
  const factory _DeviceInfo({
    required final String name,
    required final String id,
  }) = _$DeviceInfoImpl;

  @override
  String get name;
  @override
  String get id;

  /// Create a copy of DeviceInfo
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$DeviceInfoImplCopyWith<_$DeviceInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$EegDto {
  int get index => throw _privateConstructorUsedError;
  int get electrode => throw _privateConstructorUsedError;
  double get timestamp => throw _privateConstructorUsedError;
  Float64List get samples => throw _privateConstructorUsedError;

  /// Create a copy of EegDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $EegDtoCopyWith<EegDto> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $EegDtoCopyWith<$Res> {
  factory $EegDtoCopyWith(EegDto value, $Res Function(EegDto) then) =
      _$EegDtoCopyWithImpl<$Res, EegDto>;
  @useResult
  $Res call({int index, int electrode, double timestamp, Float64List samples});
}

/// @nodoc
class _$EegDtoCopyWithImpl<$Res, $Val extends EegDto>
    implements $EegDtoCopyWith<$Res> {
  _$EegDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of EegDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? index = null,
    Object? electrode = null,
    Object? timestamp = null,
    Object? samples = null,
  }) {
    return _then(
      _value.copyWith(
            index: null == index
                ? _value.index
                : index // ignore: cast_nullable_to_non_nullable
                      as int,
            electrode: null == electrode
                ? _value.electrode
                : electrode // ignore: cast_nullable_to_non_nullable
                      as int,
            timestamp: null == timestamp
                ? _value.timestamp
                : timestamp // ignore: cast_nullable_to_non_nullable
                      as double,
            samples: null == samples
                ? _value.samples
                : samples // ignore: cast_nullable_to_non_nullable
                      as Float64List,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$EegDtoImplCopyWith<$Res> implements $EegDtoCopyWith<$Res> {
  factory _$$EegDtoImplCopyWith(
    _$EegDtoImpl value,
    $Res Function(_$EegDtoImpl) then,
  ) = __$$EegDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int index, int electrode, double timestamp, Float64List samples});
}

/// @nodoc
class __$$EegDtoImplCopyWithImpl<$Res>
    extends _$EegDtoCopyWithImpl<$Res, _$EegDtoImpl>
    implements _$$EegDtoImplCopyWith<$Res> {
  __$$EegDtoImplCopyWithImpl(
    _$EegDtoImpl _value,
    $Res Function(_$EegDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of EegDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? index = null,
    Object? electrode = null,
    Object? timestamp = null,
    Object? samples = null,
  }) {
    return _then(
      _$EegDtoImpl(
        index: null == index
            ? _value.index
            : index // ignore: cast_nullable_to_non_nullable
                  as int,
        electrode: null == electrode
            ? _value.electrode
            : electrode // ignore: cast_nullable_to_non_nullable
                  as int,
        timestamp: null == timestamp
            ? _value.timestamp
            : timestamp // ignore: cast_nullable_to_non_nullable
                  as double,
        samples: null == samples
            ? _value.samples
            : samples // ignore: cast_nullable_to_non_nullable
                  as Float64List,
      ),
    );
  }
}

/// @nodoc

class _$EegDtoImpl implements _EegDto {
  const _$EegDtoImpl({
    required this.index,
    required this.electrode,
    required this.timestamp,
    required this.samples,
  });

  @override
  final int index;
  @override
  final int electrode;
  @override
  final double timestamp;
  @override
  final Float64List samples;

  @override
  String toString() {
    return 'EegDto(index: $index, electrode: $electrode, timestamp: $timestamp, samples: $samples)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$EegDtoImpl &&
            (identical(other.index, index) || other.index == index) &&
            (identical(other.electrode, electrode) ||
                other.electrode == electrode) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            const DeepCollectionEquality().equals(other.samples, samples));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    index,
    electrode,
    timestamp,
    const DeepCollectionEquality().hash(samples),
  );

  /// Create a copy of EegDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$EegDtoImplCopyWith<_$EegDtoImpl> get copyWith =>
      __$$EegDtoImplCopyWithImpl<_$EegDtoImpl>(this, _$identity);
}

abstract class _EegDto implements EegDto {
  const factory _EegDto({
    required final int index,
    required final int electrode,
    required final double timestamp,
    required final Float64List samples,
  }) = _$EegDtoImpl;

  @override
  int get index;
  @override
  int get electrode;
  @override
  double get timestamp;
  @override
  Float64List get samples;

  /// Create a copy of EegDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$EegDtoImplCopyWith<_$EegDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$ImuDto {
  int get sequenceId => throw _privateConstructorUsedError;
  List<XyzDto> get samples => throw _privateConstructorUsedError;

  /// Create a copy of ImuDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $ImuDtoCopyWith<ImuDto> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $ImuDtoCopyWith<$Res> {
  factory $ImuDtoCopyWith(ImuDto value, $Res Function(ImuDto) then) =
      _$ImuDtoCopyWithImpl<$Res, ImuDto>;
  @useResult
  $Res call({int sequenceId, List<XyzDto> samples});
}

/// @nodoc
class _$ImuDtoCopyWithImpl<$Res, $Val extends ImuDto>
    implements $ImuDtoCopyWith<$Res> {
  _$ImuDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of ImuDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? sequenceId = null, Object? samples = null}) {
    return _then(
      _value.copyWith(
            sequenceId: null == sequenceId
                ? _value.sequenceId
                : sequenceId // ignore: cast_nullable_to_non_nullable
                      as int,
            samples: null == samples
                ? _value.samples
                : samples // ignore: cast_nullable_to_non_nullable
                      as List<XyzDto>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$ImuDtoImplCopyWith<$Res> implements $ImuDtoCopyWith<$Res> {
  factory _$$ImuDtoImplCopyWith(
    _$ImuDtoImpl value,
    $Res Function(_$ImuDtoImpl) then,
  ) = __$$ImuDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int sequenceId, List<XyzDto> samples});
}

/// @nodoc
class __$$ImuDtoImplCopyWithImpl<$Res>
    extends _$ImuDtoCopyWithImpl<$Res, _$ImuDtoImpl>
    implements _$$ImuDtoImplCopyWith<$Res> {
  __$$ImuDtoImplCopyWithImpl(
    _$ImuDtoImpl _value,
    $Res Function(_$ImuDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of ImuDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? sequenceId = null, Object? samples = null}) {
    return _then(
      _$ImuDtoImpl(
        sequenceId: null == sequenceId
            ? _value.sequenceId
            : sequenceId // ignore: cast_nullable_to_non_nullable
                  as int,
        samples: null == samples
            ? _value._samples
            : samples // ignore: cast_nullable_to_non_nullable
                  as List<XyzDto>,
      ),
    );
  }
}

/// @nodoc

class _$ImuDtoImpl implements _ImuDto {
  const _$ImuDtoImpl({
    required this.sequenceId,
    required final List<XyzDto> samples,
  }) : _samples = samples;

  @override
  final int sequenceId;
  final List<XyzDto> _samples;
  @override
  List<XyzDto> get samples {
    if (_samples is EqualUnmodifiableListView) return _samples;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_samples);
  }

  @override
  String toString() {
    return 'ImuDto(sequenceId: $sequenceId, samples: $samples)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$ImuDtoImpl &&
            (identical(other.sequenceId, sequenceId) ||
                other.sequenceId == sequenceId) &&
            const DeepCollectionEquality().equals(other._samples, _samples));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    sequenceId,
    const DeepCollectionEquality().hash(_samples),
  );

  /// Create a copy of ImuDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$ImuDtoImplCopyWith<_$ImuDtoImpl> get copyWith =>
      __$$ImuDtoImplCopyWithImpl<_$ImuDtoImpl>(this, _$identity);
}

abstract class _ImuDto implements ImuDto {
  const factory _ImuDto({
    required final int sequenceId,
    required final List<XyzDto> samples,
  }) = _$ImuDtoImpl;

  @override
  int get sequenceId;
  @override
  List<XyzDto> get samples;

  /// Create a copy of ImuDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$ImuDtoImplCopyWith<_$ImuDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$MuseEventDto {
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) connected,
    required TResult Function() disconnected,
    required TResult Function(EegDto field0) eeg,
    required TResult Function(BandsDto field0) bands,
    required TResult Function(PpgDto field0) ppg,
    required TResult Function(TelemetrySnapshot field0) telemetry,
    required TResult Function(ImuDto field0) accelerometer,
    required TResult Function(ImuDto field0) gyroscope,
    required TResult Function(ControlDto field0) control,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? connected,
    TResult? Function()? disconnected,
    TResult? Function(EegDto field0)? eeg,
    TResult? Function(BandsDto field0)? bands,
    TResult? Function(PpgDto field0)? ppg,
    TResult? Function(TelemetrySnapshot field0)? telemetry,
    TResult? Function(ImuDto field0)? accelerometer,
    TResult? Function(ImuDto field0)? gyroscope,
    TResult? Function(ControlDto field0)? control,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? connected,
    TResult Function()? disconnected,
    TResult Function(EegDto field0)? eeg,
    TResult Function(BandsDto field0)? bands,
    TResult Function(PpgDto field0)? ppg,
    TResult Function(TelemetrySnapshot field0)? telemetry,
    TResult Function(ImuDto field0)? accelerometer,
    TResult Function(ImuDto field0)? gyroscope,
    TResult Function(ControlDto field0)? control,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MuseEventDto_Connected value) connected,
    required TResult Function(MuseEventDto_Disconnected value) disconnected,
    required TResult Function(MuseEventDto_Eeg value) eeg,
    required TResult Function(MuseEventDto_Bands value) bands,
    required TResult Function(MuseEventDto_Ppg value) ppg,
    required TResult Function(MuseEventDto_Telemetry value) telemetry,
    required TResult Function(MuseEventDto_Accelerometer value) accelerometer,
    required TResult Function(MuseEventDto_Gyroscope value) gyroscope,
    required TResult Function(MuseEventDto_Control value) control,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MuseEventDto_Connected value)? connected,
    TResult? Function(MuseEventDto_Disconnected value)? disconnected,
    TResult? Function(MuseEventDto_Eeg value)? eeg,
    TResult? Function(MuseEventDto_Bands value)? bands,
    TResult? Function(MuseEventDto_Ppg value)? ppg,
    TResult? Function(MuseEventDto_Telemetry value)? telemetry,
    TResult? Function(MuseEventDto_Accelerometer value)? accelerometer,
    TResult? Function(MuseEventDto_Gyroscope value)? gyroscope,
    TResult? Function(MuseEventDto_Control value)? control,
  }) => throw _privateConstructorUsedError;
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MuseEventDto_Connected value)? connected,
    TResult Function(MuseEventDto_Disconnected value)? disconnected,
    TResult Function(MuseEventDto_Eeg value)? eeg,
    TResult Function(MuseEventDto_Bands value)? bands,
    TResult Function(MuseEventDto_Ppg value)? ppg,
    TResult Function(MuseEventDto_Telemetry value)? telemetry,
    TResult Function(MuseEventDto_Accelerometer value)? accelerometer,
    TResult Function(MuseEventDto_Gyroscope value)? gyroscope,
    TResult Function(MuseEventDto_Control value)? control,
    required TResult orElse(),
  }) => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $MuseEventDtoCopyWith<$Res> {
  factory $MuseEventDtoCopyWith(
    MuseEventDto value,
    $Res Function(MuseEventDto) then,
  ) = _$MuseEventDtoCopyWithImpl<$Res, MuseEventDto>;
}

/// @nodoc
class _$MuseEventDtoCopyWithImpl<$Res, $Val extends MuseEventDto>
    implements $MuseEventDtoCopyWith<$Res> {
  _$MuseEventDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc
abstract class _$$MuseEventDto_ConnectedImplCopyWith<$Res> {
  factory _$$MuseEventDto_ConnectedImplCopyWith(
    _$MuseEventDto_ConnectedImpl value,
    $Res Function(_$MuseEventDto_ConnectedImpl) then,
  ) = __$$MuseEventDto_ConnectedImplCopyWithImpl<$Res>;
  @useResult
  $Res call({String field0});
}

/// @nodoc
class __$$MuseEventDto_ConnectedImplCopyWithImpl<$Res>
    extends _$MuseEventDtoCopyWithImpl<$Res, _$MuseEventDto_ConnectedImpl>
    implements _$$MuseEventDto_ConnectedImplCopyWith<$Res> {
  __$$MuseEventDto_ConnectedImplCopyWithImpl(
    _$MuseEventDto_ConnectedImpl _value,
    $Res Function(_$MuseEventDto_ConnectedImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$MuseEventDto_ConnectedImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$MuseEventDto_ConnectedImpl extends MuseEventDto_Connected {
  const _$MuseEventDto_ConnectedImpl(this.field0) : super._();

  @override
  final String field0;

  @override
  String toString() {
    return 'MuseEventDto.connected(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MuseEventDto_ConnectedImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MuseEventDto_ConnectedImplCopyWith<_$MuseEventDto_ConnectedImpl>
  get copyWith =>
      __$$MuseEventDto_ConnectedImplCopyWithImpl<_$MuseEventDto_ConnectedImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) connected,
    required TResult Function() disconnected,
    required TResult Function(EegDto field0) eeg,
    required TResult Function(BandsDto field0) bands,
    required TResult Function(PpgDto field0) ppg,
    required TResult Function(TelemetrySnapshot field0) telemetry,
    required TResult Function(ImuDto field0) accelerometer,
    required TResult Function(ImuDto field0) gyroscope,
    required TResult Function(ControlDto field0) control,
  }) {
    return connected(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? connected,
    TResult? Function()? disconnected,
    TResult? Function(EegDto field0)? eeg,
    TResult? Function(BandsDto field0)? bands,
    TResult? Function(PpgDto field0)? ppg,
    TResult? Function(TelemetrySnapshot field0)? telemetry,
    TResult? Function(ImuDto field0)? accelerometer,
    TResult? Function(ImuDto field0)? gyroscope,
    TResult? Function(ControlDto field0)? control,
  }) {
    return connected?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? connected,
    TResult Function()? disconnected,
    TResult Function(EegDto field0)? eeg,
    TResult Function(BandsDto field0)? bands,
    TResult Function(PpgDto field0)? ppg,
    TResult Function(TelemetrySnapshot field0)? telemetry,
    TResult Function(ImuDto field0)? accelerometer,
    TResult Function(ImuDto field0)? gyroscope,
    TResult Function(ControlDto field0)? control,
    required TResult orElse(),
  }) {
    if (connected != null) {
      return connected(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MuseEventDto_Connected value) connected,
    required TResult Function(MuseEventDto_Disconnected value) disconnected,
    required TResult Function(MuseEventDto_Eeg value) eeg,
    required TResult Function(MuseEventDto_Bands value) bands,
    required TResult Function(MuseEventDto_Ppg value) ppg,
    required TResult Function(MuseEventDto_Telemetry value) telemetry,
    required TResult Function(MuseEventDto_Accelerometer value) accelerometer,
    required TResult Function(MuseEventDto_Gyroscope value) gyroscope,
    required TResult Function(MuseEventDto_Control value) control,
  }) {
    return connected(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MuseEventDto_Connected value)? connected,
    TResult? Function(MuseEventDto_Disconnected value)? disconnected,
    TResult? Function(MuseEventDto_Eeg value)? eeg,
    TResult? Function(MuseEventDto_Bands value)? bands,
    TResult? Function(MuseEventDto_Ppg value)? ppg,
    TResult? Function(MuseEventDto_Telemetry value)? telemetry,
    TResult? Function(MuseEventDto_Accelerometer value)? accelerometer,
    TResult? Function(MuseEventDto_Gyroscope value)? gyroscope,
    TResult? Function(MuseEventDto_Control value)? control,
  }) {
    return connected?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MuseEventDto_Connected value)? connected,
    TResult Function(MuseEventDto_Disconnected value)? disconnected,
    TResult Function(MuseEventDto_Eeg value)? eeg,
    TResult Function(MuseEventDto_Bands value)? bands,
    TResult Function(MuseEventDto_Ppg value)? ppg,
    TResult Function(MuseEventDto_Telemetry value)? telemetry,
    TResult Function(MuseEventDto_Accelerometer value)? accelerometer,
    TResult Function(MuseEventDto_Gyroscope value)? gyroscope,
    TResult Function(MuseEventDto_Control value)? control,
    required TResult orElse(),
  }) {
    if (connected != null) {
      return connected(this);
    }
    return orElse();
  }
}

abstract class MuseEventDto_Connected extends MuseEventDto {
  const factory MuseEventDto_Connected(final String field0) =
      _$MuseEventDto_ConnectedImpl;
  const MuseEventDto_Connected._() : super._();

  String get field0;

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MuseEventDto_ConnectedImplCopyWith<_$MuseEventDto_ConnectedImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MuseEventDto_DisconnectedImplCopyWith<$Res> {
  factory _$$MuseEventDto_DisconnectedImplCopyWith(
    _$MuseEventDto_DisconnectedImpl value,
    $Res Function(_$MuseEventDto_DisconnectedImpl) then,
  ) = __$$MuseEventDto_DisconnectedImplCopyWithImpl<$Res>;
}

/// @nodoc
class __$$MuseEventDto_DisconnectedImplCopyWithImpl<$Res>
    extends _$MuseEventDtoCopyWithImpl<$Res, _$MuseEventDto_DisconnectedImpl>
    implements _$$MuseEventDto_DisconnectedImplCopyWith<$Res> {
  __$$MuseEventDto_DisconnectedImplCopyWithImpl(
    _$MuseEventDto_DisconnectedImpl _value,
    $Res Function(_$MuseEventDto_DisconnectedImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
}

/// @nodoc

class _$MuseEventDto_DisconnectedImpl extends MuseEventDto_Disconnected {
  const _$MuseEventDto_DisconnectedImpl() : super._();

  @override
  String toString() {
    return 'MuseEventDto.disconnected()';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MuseEventDto_DisconnectedImpl);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) connected,
    required TResult Function() disconnected,
    required TResult Function(EegDto field0) eeg,
    required TResult Function(BandsDto field0) bands,
    required TResult Function(PpgDto field0) ppg,
    required TResult Function(TelemetrySnapshot field0) telemetry,
    required TResult Function(ImuDto field0) accelerometer,
    required TResult Function(ImuDto field0) gyroscope,
    required TResult Function(ControlDto field0) control,
  }) {
    return disconnected();
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? connected,
    TResult? Function()? disconnected,
    TResult? Function(EegDto field0)? eeg,
    TResult? Function(BandsDto field0)? bands,
    TResult? Function(PpgDto field0)? ppg,
    TResult? Function(TelemetrySnapshot field0)? telemetry,
    TResult? Function(ImuDto field0)? accelerometer,
    TResult? Function(ImuDto field0)? gyroscope,
    TResult? Function(ControlDto field0)? control,
  }) {
    return disconnected?.call();
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? connected,
    TResult Function()? disconnected,
    TResult Function(EegDto field0)? eeg,
    TResult Function(BandsDto field0)? bands,
    TResult Function(PpgDto field0)? ppg,
    TResult Function(TelemetrySnapshot field0)? telemetry,
    TResult Function(ImuDto field0)? accelerometer,
    TResult Function(ImuDto field0)? gyroscope,
    TResult Function(ControlDto field0)? control,
    required TResult orElse(),
  }) {
    if (disconnected != null) {
      return disconnected();
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MuseEventDto_Connected value) connected,
    required TResult Function(MuseEventDto_Disconnected value) disconnected,
    required TResult Function(MuseEventDto_Eeg value) eeg,
    required TResult Function(MuseEventDto_Bands value) bands,
    required TResult Function(MuseEventDto_Ppg value) ppg,
    required TResult Function(MuseEventDto_Telemetry value) telemetry,
    required TResult Function(MuseEventDto_Accelerometer value) accelerometer,
    required TResult Function(MuseEventDto_Gyroscope value) gyroscope,
    required TResult Function(MuseEventDto_Control value) control,
  }) {
    return disconnected(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MuseEventDto_Connected value)? connected,
    TResult? Function(MuseEventDto_Disconnected value)? disconnected,
    TResult? Function(MuseEventDto_Eeg value)? eeg,
    TResult? Function(MuseEventDto_Bands value)? bands,
    TResult? Function(MuseEventDto_Ppg value)? ppg,
    TResult? Function(MuseEventDto_Telemetry value)? telemetry,
    TResult? Function(MuseEventDto_Accelerometer value)? accelerometer,
    TResult? Function(MuseEventDto_Gyroscope value)? gyroscope,
    TResult? Function(MuseEventDto_Control value)? control,
  }) {
    return disconnected?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MuseEventDto_Connected value)? connected,
    TResult Function(MuseEventDto_Disconnected value)? disconnected,
    TResult Function(MuseEventDto_Eeg value)? eeg,
    TResult Function(MuseEventDto_Bands value)? bands,
    TResult Function(MuseEventDto_Ppg value)? ppg,
    TResult Function(MuseEventDto_Telemetry value)? telemetry,
    TResult Function(MuseEventDto_Accelerometer value)? accelerometer,
    TResult Function(MuseEventDto_Gyroscope value)? gyroscope,
    TResult Function(MuseEventDto_Control value)? control,
    required TResult orElse(),
  }) {
    if (disconnected != null) {
      return disconnected(this);
    }
    return orElse();
  }
}

abstract class MuseEventDto_Disconnected extends MuseEventDto {
  const factory MuseEventDto_Disconnected() = _$MuseEventDto_DisconnectedImpl;
  const MuseEventDto_Disconnected._() : super._();
}

/// @nodoc
abstract class _$$MuseEventDto_EegImplCopyWith<$Res> {
  factory _$$MuseEventDto_EegImplCopyWith(
    _$MuseEventDto_EegImpl value,
    $Res Function(_$MuseEventDto_EegImpl) then,
  ) = __$$MuseEventDto_EegImplCopyWithImpl<$Res>;
  @useResult
  $Res call({EegDto field0});

  $EegDtoCopyWith<$Res> get field0;
}

/// @nodoc
class __$$MuseEventDto_EegImplCopyWithImpl<$Res>
    extends _$MuseEventDtoCopyWithImpl<$Res, _$MuseEventDto_EegImpl>
    implements _$$MuseEventDto_EegImplCopyWith<$Res> {
  __$$MuseEventDto_EegImplCopyWithImpl(
    _$MuseEventDto_EegImpl _value,
    $Res Function(_$MuseEventDto_EegImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$MuseEventDto_EegImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                  as EegDto,
      ),
    );
  }

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $EegDtoCopyWith<$Res> get field0 {
    return $EegDtoCopyWith<$Res>(_value.field0, (value) {
      return _then(_value.copyWith(field0: value));
    });
  }
}

/// @nodoc

class _$MuseEventDto_EegImpl extends MuseEventDto_Eeg {
  const _$MuseEventDto_EegImpl(this.field0) : super._();

  @override
  final EegDto field0;

  @override
  String toString() {
    return 'MuseEventDto.eeg(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MuseEventDto_EegImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MuseEventDto_EegImplCopyWith<_$MuseEventDto_EegImpl> get copyWith =>
      __$$MuseEventDto_EegImplCopyWithImpl<_$MuseEventDto_EegImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) connected,
    required TResult Function() disconnected,
    required TResult Function(EegDto field0) eeg,
    required TResult Function(BandsDto field0) bands,
    required TResult Function(PpgDto field0) ppg,
    required TResult Function(TelemetrySnapshot field0) telemetry,
    required TResult Function(ImuDto field0) accelerometer,
    required TResult Function(ImuDto field0) gyroscope,
    required TResult Function(ControlDto field0) control,
  }) {
    return eeg(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? connected,
    TResult? Function()? disconnected,
    TResult? Function(EegDto field0)? eeg,
    TResult? Function(BandsDto field0)? bands,
    TResult? Function(PpgDto field0)? ppg,
    TResult? Function(TelemetrySnapshot field0)? telemetry,
    TResult? Function(ImuDto field0)? accelerometer,
    TResult? Function(ImuDto field0)? gyroscope,
    TResult? Function(ControlDto field0)? control,
  }) {
    return eeg?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? connected,
    TResult Function()? disconnected,
    TResult Function(EegDto field0)? eeg,
    TResult Function(BandsDto field0)? bands,
    TResult Function(PpgDto field0)? ppg,
    TResult Function(TelemetrySnapshot field0)? telemetry,
    TResult Function(ImuDto field0)? accelerometer,
    TResult Function(ImuDto field0)? gyroscope,
    TResult Function(ControlDto field0)? control,
    required TResult orElse(),
  }) {
    if (eeg != null) {
      return eeg(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MuseEventDto_Connected value) connected,
    required TResult Function(MuseEventDto_Disconnected value) disconnected,
    required TResult Function(MuseEventDto_Eeg value) eeg,
    required TResult Function(MuseEventDto_Bands value) bands,
    required TResult Function(MuseEventDto_Ppg value) ppg,
    required TResult Function(MuseEventDto_Telemetry value) telemetry,
    required TResult Function(MuseEventDto_Accelerometer value) accelerometer,
    required TResult Function(MuseEventDto_Gyroscope value) gyroscope,
    required TResult Function(MuseEventDto_Control value) control,
  }) {
    return eeg(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MuseEventDto_Connected value)? connected,
    TResult? Function(MuseEventDto_Disconnected value)? disconnected,
    TResult? Function(MuseEventDto_Eeg value)? eeg,
    TResult? Function(MuseEventDto_Bands value)? bands,
    TResult? Function(MuseEventDto_Ppg value)? ppg,
    TResult? Function(MuseEventDto_Telemetry value)? telemetry,
    TResult? Function(MuseEventDto_Accelerometer value)? accelerometer,
    TResult? Function(MuseEventDto_Gyroscope value)? gyroscope,
    TResult? Function(MuseEventDto_Control value)? control,
  }) {
    return eeg?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MuseEventDto_Connected value)? connected,
    TResult Function(MuseEventDto_Disconnected value)? disconnected,
    TResult Function(MuseEventDto_Eeg value)? eeg,
    TResult Function(MuseEventDto_Bands value)? bands,
    TResult Function(MuseEventDto_Ppg value)? ppg,
    TResult Function(MuseEventDto_Telemetry value)? telemetry,
    TResult Function(MuseEventDto_Accelerometer value)? accelerometer,
    TResult Function(MuseEventDto_Gyroscope value)? gyroscope,
    TResult Function(MuseEventDto_Control value)? control,
    required TResult orElse(),
  }) {
    if (eeg != null) {
      return eeg(this);
    }
    return orElse();
  }
}

abstract class MuseEventDto_Eeg extends MuseEventDto {
  const factory MuseEventDto_Eeg(final EegDto field0) = _$MuseEventDto_EegImpl;
  const MuseEventDto_Eeg._() : super._();

  EegDto get field0;

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MuseEventDto_EegImplCopyWith<_$MuseEventDto_EegImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MuseEventDto_BandsImplCopyWith<$Res> {
  factory _$$MuseEventDto_BandsImplCopyWith(
    _$MuseEventDto_BandsImpl value,
    $Res Function(_$MuseEventDto_BandsImpl) then,
  ) = __$$MuseEventDto_BandsImplCopyWithImpl<$Res>;
  @useResult
  $Res call({BandsDto field0});

  $BandsDtoCopyWith<$Res> get field0;
}

/// @nodoc
class __$$MuseEventDto_BandsImplCopyWithImpl<$Res>
    extends _$MuseEventDtoCopyWithImpl<$Res, _$MuseEventDto_BandsImpl>
    implements _$$MuseEventDto_BandsImplCopyWith<$Res> {
  __$$MuseEventDto_BandsImplCopyWithImpl(
    _$MuseEventDto_BandsImpl _value,
    $Res Function(_$MuseEventDto_BandsImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$MuseEventDto_BandsImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                  as BandsDto,
      ),
    );
  }

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $BandsDtoCopyWith<$Res> get field0 {
    return $BandsDtoCopyWith<$Res>(_value.field0, (value) {
      return _then(_value.copyWith(field0: value));
    });
  }
}

/// @nodoc

class _$MuseEventDto_BandsImpl extends MuseEventDto_Bands {
  const _$MuseEventDto_BandsImpl(this.field0) : super._();

  @override
  final BandsDto field0;

  @override
  String toString() {
    return 'MuseEventDto.bands(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MuseEventDto_BandsImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MuseEventDto_BandsImplCopyWith<_$MuseEventDto_BandsImpl> get copyWith =>
      __$$MuseEventDto_BandsImplCopyWithImpl<_$MuseEventDto_BandsImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) connected,
    required TResult Function() disconnected,
    required TResult Function(EegDto field0) eeg,
    required TResult Function(BandsDto field0) bands,
    required TResult Function(PpgDto field0) ppg,
    required TResult Function(TelemetrySnapshot field0) telemetry,
    required TResult Function(ImuDto field0) accelerometer,
    required TResult Function(ImuDto field0) gyroscope,
    required TResult Function(ControlDto field0) control,
  }) {
    return bands(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? connected,
    TResult? Function()? disconnected,
    TResult? Function(EegDto field0)? eeg,
    TResult? Function(BandsDto field0)? bands,
    TResult? Function(PpgDto field0)? ppg,
    TResult? Function(TelemetrySnapshot field0)? telemetry,
    TResult? Function(ImuDto field0)? accelerometer,
    TResult? Function(ImuDto field0)? gyroscope,
    TResult? Function(ControlDto field0)? control,
  }) {
    return bands?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? connected,
    TResult Function()? disconnected,
    TResult Function(EegDto field0)? eeg,
    TResult Function(BandsDto field0)? bands,
    TResult Function(PpgDto field0)? ppg,
    TResult Function(TelemetrySnapshot field0)? telemetry,
    TResult Function(ImuDto field0)? accelerometer,
    TResult Function(ImuDto field0)? gyroscope,
    TResult Function(ControlDto field0)? control,
    required TResult orElse(),
  }) {
    if (bands != null) {
      return bands(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MuseEventDto_Connected value) connected,
    required TResult Function(MuseEventDto_Disconnected value) disconnected,
    required TResult Function(MuseEventDto_Eeg value) eeg,
    required TResult Function(MuseEventDto_Bands value) bands,
    required TResult Function(MuseEventDto_Ppg value) ppg,
    required TResult Function(MuseEventDto_Telemetry value) telemetry,
    required TResult Function(MuseEventDto_Accelerometer value) accelerometer,
    required TResult Function(MuseEventDto_Gyroscope value) gyroscope,
    required TResult Function(MuseEventDto_Control value) control,
  }) {
    return bands(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MuseEventDto_Connected value)? connected,
    TResult? Function(MuseEventDto_Disconnected value)? disconnected,
    TResult? Function(MuseEventDto_Eeg value)? eeg,
    TResult? Function(MuseEventDto_Bands value)? bands,
    TResult? Function(MuseEventDto_Ppg value)? ppg,
    TResult? Function(MuseEventDto_Telemetry value)? telemetry,
    TResult? Function(MuseEventDto_Accelerometer value)? accelerometer,
    TResult? Function(MuseEventDto_Gyroscope value)? gyroscope,
    TResult? Function(MuseEventDto_Control value)? control,
  }) {
    return bands?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MuseEventDto_Connected value)? connected,
    TResult Function(MuseEventDto_Disconnected value)? disconnected,
    TResult Function(MuseEventDto_Eeg value)? eeg,
    TResult Function(MuseEventDto_Bands value)? bands,
    TResult Function(MuseEventDto_Ppg value)? ppg,
    TResult Function(MuseEventDto_Telemetry value)? telemetry,
    TResult Function(MuseEventDto_Accelerometer value)? accelerometer,
    TResult Function(MuseEventDto_Gyroscope value)? gyroscope,
    TResult Function(MuseEventDto_Control value)? control,
    required TResult orElse(),
  }) {
    if (bands != null) {
      return bands(this);
    }
    return orElse();
  }
}

abstract class MuseEventDto_Bands extends MuseEventDto {
  const factory MuseEventDto_Bands(final BandsDto field0) =
      _$MuseEventDto_BandsImpl;
  const MuseEventDto_Bands._() : super._();

  BandsDto get field0;

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MuseEventDto_BandsImplCopyWith<_$MuseEventDto_BandsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MuseEventDto_PpgImplCopyWith<$Res> {
  factory _$$MuseEventDto_PpgImplCopyWith(
    _$MuseEventDto_PpgImpl value,
    $Res Function(_$MuseEventDto_PpgImpl) then,
  ) = __$$MuseEventDto_PpgImplCopyWithImpl<$Res>;
  @useResult
  $Res call({PpgDto field0});

  $PpgDtoCopyWith<$Res> get field0;
}

/// @nodoc
class __$$MuseEventDto_PpgImplCopyWithImpl<$Res>
    extends _$MuseEventDtoCopyWithImpl<$Res, _$MuseEventDto_PpgImpl>
    implements _$$MuseEventDto_PpgImplCopyWith<$Res> {
  __$$MuseEventDto_PpgImplCopyWithImpl(
    _$MuseEventDto_PpgImpl _value,
    $Res Function(_$MuseEventDto_PpgImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$MuseEventDto_PpgImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                  as PpgDto,
      ),
    );
  }

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $PpgDtoCopyWith<$Res> get field0 {
    return $PpgDtoCopyWith<$Res>(_value.field0, (value) {
      return _then(_value.copyWith(field0: value));
    });
  }
}

/// @nodoc

class _$MuseEventDto_PpgImpl extends MuseEventDto_Ppg {
  const _$MuseEventDto_PpgImpl(this.field0) : super._();

  @override
  final PpgDto field0;

  @override
  String toString() {
    return 'MuseEventDto.ppg(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MuseEventDto_PpgImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MuseEventDto_PpgImplCopyWith<_$MuseEventDto_PpgImpl> get copyWith =>
      __$$MuseEventDto_PpgImplCopyWithImpl<_$MuseEventDto_PpgImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) connected,
    required TResult Function() disconnected,
    required TResult Function(EegDto field0) eeg,
    required TResult Function(BandsDto field0) bands,
    required TResult Function(PpgDto field0) ppg,
    required TResult Function(TelemetrySnapshot field0) telemetry,
    required TResult Function(ImuDto field0) accelerometer,
    required TResult Function(ImuDto field0) gyroscope,
    required TResult Function(ControlDto field0) control,
  }) {
    return ppg(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? connected,
    TResult? Function()? disconnected,
    TResult? Function(EegDto field0)? eeg,
    TResult? Function(BandsDto field0)? bands,
    TResult? Function(PpgDto field0)? ppg,
    TResult? Function(TelemetrySnapshot field0)? telemetry,
    TResult? Function(ImuDto field0)? accelerometer,
    TResult? Function(ImuDto field0)? gyroscope,
    TResult? Function(ControlDto field0)? control,
  }) {
    return ppg?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? connected,
    TResult Function()? disconnected,
    TResult Function(EegDto field0)? eeg,
    TResult Function(BandsDto field0)? bands,
    TResult Function(PpgDto field0)? ppg,
    TResult Function(TelemetrySnapshot field0)? telemetry,
    TResult Function(ImuDto field0)? accelerometer,
    TResult Function(ImuDto field0)? gyroscope,
    TResult Function(ControlDto field0)? control,
    required TResult orElse(),
  }) {
    if (ppg != null) {
      return ppg(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MuseEventDto_Connected value) connected,
    required TResult Function(MuseEventDto_Disconnected value) disconnected,
    required TResult Function(MuseEventDto_Eeg value) eeg,
    required TResult Function(MuseEventDto_Bands value) bands,
    required TResult Function(MuseEventDto_Ppg value) ppg,
    required TResult Function(MuseEventDto_Telemetry value) telemetry,
    required TResult Function(MuseEventDto_Accelerometer value) accelerometer,
    required TResult Function(MuseEventDto_Gyroscope value) gyroscope,
    required TResult Function(MuseEventDto_Control value) control,
  }) {
    return ppg(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MuseEventDto_Connected value)? connected,
    TResult? Function(MuseEventDto_Disconnected value)? disconnected,
    TResult? Function(MuseEventDto_Eeg value)? eeg,
    TResult? Function(MuseEventDto_Bands value)? bands,
    TResult? Function(MuseEventDto_Ppg value)? ppg,
    TResult? Function(MuseEventDto_Telemetry value)? telemetry,
    TResult? Function(MuseEventDto_Accelerometer value)? accelerometer,
    TResult? Function(MuseEventDto_Gyroscope value)? gyroscope,
    TResult? Function(MuseEventDto_Control value)? control,
  }) {
    return ppg?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MuseEventDto_Connected value)? connected,
    TResult Function(MuseEventDto_Disconnected value)? disconnected,
    TResult Function(MuseEventDto_Eeg value)? eeg,
    TResult Function(MuseEventDto_Bands value)? bands,
    TResult Function(MuseEventDto_Ppg value)? ppg,
    TResult Function(MuseEventDto_Telemetry value)? telemetry,
    TResult Function(MuseEventDto_Accelerometer value)? accelerometer,
    TResult Function(MuseEventDto_Gyroscope value)? gyroscope,
    TResult Function(MuseEventDto_Control value)? control,
    required TResult orElse(),
  }) {
    if (ppg != null) {
      return ppg(this);
    }
    return orElse();
  }
}

abstract class MuseEventDto_Ppg extends MuseEventDto {
  const factory MuseEventDto_Ppg(final PpgDto field0) = _$MuseEventDto_PpgImpl;
  const MuseEventDto_Ppg._() : super._();

  PpgDto get field0;

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MuseEventDto_PpgImplCopyWith<_$MuseEventDto_PpgImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MuseEventDto_TelemetryImplCopyWith<$Res> {
  factory _$$MuseEventDto_TelemetryImplCopyWith(
    _$MuseEventDto_TelemetryImpl value,
    $Res Function(_$MuseEventDto_TelemetryImpl) then,
  ) = __$$MuseEventDto_TelemetryImplCopyWithImpl<$Res>;
  @useResult
  $Res call({TelemetrySnapshot field0});

  $TelemetrySnapshotCopyWith<$Res> get field0;
}

/// @nodoc
class __$$MuseEventDto_TelemetryImplCopyWithImpl<$Res>
    extends _$MuseEventDtoCopyWithImpl<$Res, _$MuseEventDto_TelemetryImpl>
    implements _$$MuseEventDto_TelemetryImplCopyWith<$Res> {
  __$$MuseEventDto_TelemetryImplCopyWithImpl(
    _$MuseEventDto_TelemetryImpl _value,
    $Res Function(_$MuseEventDto_TelemetryImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$MuseEventDto_TelemetryImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                  as TelemetrySnapshot,
      ),
    );
  }

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $TelemetrySnapshotCopyWith<$Res> get field0 {
    return $TelemetrySnapshotCopyWith<$Res>(_value.field0, (value) {
      return _then(_value.copyWith(field0: value));
    });
  }
}

/// @nodoc

class _$MuseEventDto_TelemetryImpl extends MuseEventDto_Telemetry {
  const _$MuseEventDto_TelemetryImpl(this.field0) : super._();

  @override
  final TelemetrySnapshot field0;

  @override
  String toString() {
    return 'MuseEventDto.telemetry(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MuseEventDto_TelemetryImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MuseEventDto_TelemetryImplCopyWith<_$MuseEventDto_TelemetryImpl>
  get copyWith =>
      __$$MuseEventDto_TelemetryImplCopyWithImpl<_$MuseEventDto_TelemetryImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) connected,
    required TResult Function() disconnected,
    required TResult Function(EegDto field0) eeg,
    required TResult Function(BandsDto field0) bands,
    required TResult Function(PpgDto field0) ppg,
    required TResult Function(TelemetrySnapshot field0) telemetry,
    required TResult Function(ImuDto field0) accelerometer,
    required TResult Function(ImuDto field0) gyroscope,
    required TResult Function(ControlDto field0) control,
  }) {
    return telemetry(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? connected,
    TResult? Function()? disconnected,
    TResult? Function(EegDto field0)? eeg,
    TResult? Function(BandsDto field0)? bands,
    TResult? Function(PpgDto field0)? ppg,
    TResult? Function(TelemetrySnapshot field0)? telemetry,
    TResult? Function(ImuDto field0)? accelerometer,
    TResult? Function(ImuDto field0)? gyroscope,
    TResult? Function(ControlDto field0)? control,
  }) {
    return telemetry?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? connected,
    TResult Function()? disconnected,
    TResult Function(EegDto field0)? eeg,
    TResult Function(BandsDto field0)? bands,
    TResult Function(PpgDto field0)? ppg,
    TResult Function(TelemetrySnapshot field0)? telemetry,
    TResult Function(ImuDto field0)? accelerometer,
    TResult Function(ImuDto field0)? gyroscope,
    TResult Function(ControlDto field0)? control,
    required TResult orElse(),
  }) {
    if (telemetry != null) {
      return telemetry(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MuseEventDto_Connected value) connected,
    required TResult Function(MuseEventDto_Disconnected value) disconnected,
    required TResult Function(MuseEventDto_Eeg value) eeg,
    required TResult Function(MuseEventDto_Bands value) bands,
    required TResult Function(MuseEventDto_Ppg value) ppg,
    required TResult Function(MuseEventDto_Telemetry value) telemetry,
    required TResult Function(MuseEventDto_Accelerometer value) accelerometer,
    required TResult Function(MuseEventDto_Gyroscope value) gyroscope,
    required TResult Function(MuseEventDto_Control value) control,
  }) {
    return telemetry(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MuseEventDto_Connected value)? connected,
    TResult? Function(MuseEventDto_Disconnected value)? disconnected,
    TResult? Function(MuseEventDto_Eeg value)? eeg,
    TResult? Function(MuseEventDto_Bands value)? bands,
    TResult? Function(MuseEventDto_Ppg value)? ppg,
    TResult? Function(MuseEventDto_Telemetry value)? telemetry,
    TResult? Function(MuseEventDto_Accelerometer value)? accelerometer,
    TResult? Function(MuseEventDto_Gyroscope value)? gyroscope,
    TResult? Function(MuseEventDto_Control value)? control,
  }) {
    return telemetry?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MuseEventDto_Connected value)? connected,
    TResult Function(MuseEventDto_Disconnected value)? disconnected,
    TResult Function(MuseEventDto_Eeg value)? eeg,
    TResult Function(MuseEventDto_Bands value)? bands,
    TResult Function(MuseEventDto_Ppg value)? ppg,
    TResult Function(MuseEventDto_Telemetry value)? telemetry,
    TResult Function(MuseEventDto_Accelerometer value)? accelerometer,
    TResult Function(MuseEventDto_Gyroscope value)? gyroscope,
    TResult Function(MuseEventDto_Control value)? control,
    required TResult orElse(),
  }) {
    if (telemetry != null) {
      return telemetry(this);
    }
    return orElse();
  }
}

abstract class MuseEventDto_Telemetry extends MuseEventDto {
  const factory MuseEventDto_Telemetry(final TelemetrySnapshot field0) =
      _$MuseEventDto_TelemetryImpl;
  const MuseEventDto_Telemetry._() : super._();

  TelemetrySnapshot get field0;

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MuseEventDto_TelemetryImplCopyWith<_$MuseEventDto_TelemetryImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MuseEventDto_AccelerometerImplCopyWith<$Res> {
  factory _$$MuseEventDto_AccelerometerImplCopyWith(
    _$MuseEventDto_AccelerometerImpl value,
    $Res Function(_$MuseEventDto_AccelerometerImpl) then,
  ) = __$$MuseEventDto_AccelerometerImplCopyWithImpl<$Res>;
  @useResult
  $Res call({ImuDto field0});

  $ImuDtoCopyWith<$Res> get field0;
}

/// @nodoc
class __$$MuseEventDto_AccelerometerImplCopyWithImpl<$Res>
    extends _$MuseEventDtoCopyWithImpl<$Res, _$MuseEventDto_AccelerometerImpl>
    implements _$$MuseEventDto_AccelerometerImplCopyWith<$Res> {
  __$$MuseEventDto_AccelerometerImplCopyWithImpl(
    _$MuseEventDto_AccelerometerImpl _value,
    $Res Function(_$MuseEventDto_AccelerometerImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$MuseEventDto_AccelerometerImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                  as ImuDto,
      ),
    );
  }

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ImuDtoCopyWith<$Res> get field0 {
    return $ImuDtoCopyWith<$Res>(_value.field0, (value) {
      return _then(_value.copyWith(field0: value));
    });
  }
}

/// @nodoc

class _$MuseEventDto_AccelerometerImpl extends MuseEventDto_Accelerometer {
  const _$MuseEventDto_AccelerometerImpl(this.field0) : super._();

  @override
  final ImuDto field0;

  @override
  String toString() {
    return 'MuseEventDto.accelerometer(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MuseEventDto_AccelerometerImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MuseEventDto_AccelerometerImplCopyWith<_$MuseEventDto_AccelerometerImpl>
  get copyWith =>
      __$$MuseEventDto_AccelerometerImplCopyWithImpl<
        _$MuseEventDto_AccelerometerImpl
      >(this, _$identity);

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) connected,
    required TResult Function() disconnected,
    required TResult Function(EegDto field0) eeg,
    required TResult Function(BandsDto field0) bands,
    required TResult Function(PpgDto field0) ppg,
    required TResult Function(TelemetrySnapshot field0) telemetry,
    required TResult Function(ImuDto field0) accelerometer,
    required TResult Function(ImuDto field0) gyroscope,
    required TResult Function(ControlDto field0) control,
  }) {
    return accelerometer(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? connected,
    TResult? Function()? disconnected,
    TResult? Function(EegDto field0)? eeg,
    TResult? Function(BandsDto field0)? bands,
    TResult? Function(PpgDto field0)? ppg,
    TResult? Function(TelemetrySnapshot field0)? telemetry,
    TResult? Function(ImuDto field0)? accelerometer,
    TResult? Function(ImuDto field0)? gyroscope,
    TResult? Function(ControlDto field0)? control,
  }) {
    return accelerometer?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? connected,
    TResult Function()? disconnected,
    TResult Function(EegDto field0)? eeg,
    TResult Function(BandsDto field0)? bands,
    TResult Function(PpgDto field0)? ppg,
    TResult Function(TelemetrySnapshot field0)? telemetry,
    TResult Function(ImuDto field0)? accelerometer,
    TResult Function(ImuDto field0)? gyroscope,
    TResult Function(ControlDto field0)? control,
    required TResult orElse(),
  }) {
    if (accelerometer != null) {
      return accelerometer(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MuseEventDto_Connected value) connected,
    required TResult Function(MuseEventDto_Disconnected value) disconnected,
    required TResult Function(MuseEventDto_Eeg value) eeg,
    required TResult Function(MuseEventDto_Bands value) bands,
    required TResult Function(MuseEventDto_Ppg value) ppg,
    required TResult Function(MuseEventDto_Telemetry value) telemetry,
    required TResult Function(MuseEventDto_Accelerometer value) accelerometer,
    required TResult Function(MuseEventDto_Gyroscope value) gyroscope,
    required TResult Function(MuseEventDto_Control value) control,
  }) {
    return accelerometer(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MuseEventDto_Connected value)? connected,
    TResult? Function(MuseEventDto_Disconnected value)? disconnected,
    TResult? Function(MuseEventDto_Eeg value)? eeg,
    TResult? Function(MuseEventDto_Bands value)? bands,
    TResult? Function(MuseEventDto_Ppg value)? ppg,
    TResult? Function(MuseEventDto_Telemetry value)? telemetry,
    TResult? Function(MuseEventDto_Accelerometer value)? accelerometer,
    TResult? Function(MuseEventDto_Gyroscope value)? gyroscope,
    TResult? Function(MuseEventDto_Control value)? control,
  }) {
    return accelerometer?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MuseEventDto_Connected value)? connected,
    TResult Function(MuseEventDto_Disconnected value)? disconnected,
    TResult Function(MuseEventDto_Eeg value)? eeg,
    TResult Function(MuseEventDto_Bands value)? bands,
    TResult Function(MuseEventDto_Ppg value)? ppg,
    TResult Function(MuseEventDto_Telemetry value)? telemetry,
    TResult Function(MuseEventDto_Accelerometer value)? accelerometer,
    TResult Function(MuseEventDto_Gyroscope value)? gyroscope,
    TResult Function(MuseEventDto_Control value)? control,
    required TResult orElse(),
  }) {
    if (accelerometer != null) {
      return accelerometer(this);
    }
    return orElse();
  }
}

abstract class MuseEventDto_Accelerometer extends MuseEventDto {
  const factory MuseEventDto_Accelerometer(final ImuDto field0) =
      _$MuseEventDto_AccelerometerImpl;
  const MuseEventDto_Accelerometer._() : super._();

  ImuDto get field0;

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MuseEventDto_AccelerometerImplCopyWith<_$MuseEventDto_AccelerometerImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MuseEventDto_GyroscopeImplCopyWith<$Res> {
  factory _$$MuseEventDto_GyroscopeImplCopyWith(
    _$MuseEventDto_GyroscopeImpl value,
    $Res Function(_$MuseEventDto_GyroscopeImpl) then,
  ) = __$$MuseEventDto_GyroscopeImplCopyWithImpl<$Res>;
  @useResult
  $Res call({ImuDto field0});

  $ImuDtoCopyWith<$Res> get field0;
}

/// @nodoc
class __$$MuseEventDto_GyroscopeImplCopyWithImpl<$Res>
    extends _$MuseEventDtoCopyWithImpl<$Res, _$MuseEventDto_GyroscopeImpl>
    implements _$$MuseEventDto_GyroscopeImplCopyWith<$Res> {
  __$$MuseEventDto_GyroscopeImplCopyWithImpl(
    _$MuseEventDto_GyroscopeImpl _value,
    $Res Function(_$MuseEventDto_GyroscopeImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$MuseEventDto_GyroscopeImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                  as ImuDto,
      ),
    );
  }

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ImuDtoCopyWith<$Res> get field0 {
    return $ImuDtoCopyWith<$Res>(_value.field0, (value) {
      return _then(_value.copyWith(field0: value));
    });
  }
}

/// @nodoc

class _$MuseEventDto_GyroscopeImpl extends MuseEventDto_Gyroscope {
  const _$MuseEventDto_GyroscopeImpl(this.field0) : super._();

  @override
  final ImuDto field0;

  @override
  String toString() {
    return 'MuseEventDto.gyroscope(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MuseEventDto_GyroscopeImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MuseEventDto_GyroscopeImplCopyWith<_$MuseEventDto_GyroscopeImpl>
  get copyWith =>
      __$$MuseEventDto_GyroscopeImplCopyWithImpl<_$MuseEventDto_GyroscopeImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) connected,
    required TResult Function() disconnected,
    required TResult Function(EegDto field0) eeg,
    required TResult Function(BandsDto field0) bands,
    required TResult Function(PpgDto field0) ppg,
    required TResult Function(TelemetrySnapshot field0) telemetry,
    required TResult Function(ImuDto field0) accelerometer,
    required TResult Function(ImuDto field0) gyroscope,
    required TResult Function(ControlDto field0) control,
  }) {
    return gyroscope(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? connected,
    TResult? Function()? disconnected,
    TResult? Function(EegDto field0)? eeg,
    TResult? Function(BandsDto field0)? bands,
    TResult? Function(PpgDto field0)? ppg,
    TResult? Function(TelemetrySnapshot field0)? telemetry,
    TResult? Function(ImuDto field0)? accelerometer,
    TResult? Function(ImuDto field0)? gyroscope,
    TResult? Function(ControlDto field0)? control,
  }) {
    return gyroscope?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? connected,
    TResult Function()? disconnected,
    TResult Function(EegDto field0)? eeg,
    TResult Function(BandsDto field0)? bands,
    TResult Function(PpgDto field0)? ppg,
    TResult Function(TelemetrySnapshot field0)? telemetry,
    TResult Function(ImuDto field0)? accelerometer,
    TResult Function(ImuDto field0)? gyroscope,
    TResult Function(ControlDto field0)? control,
    required TResult orElse(),
  }) {
    if (gyroscope != null) {
      return gyroscope(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MuseEventDto_Connected value) connected,
    required TResult Function(MuseEventDto_Disconnected value) disconnected,
    required TResult Function(MuseEventDto_Eeg value) eeg,
    required TResult Function(MuseEventDto_Bands value) bands,
    required TResult Function(MuseEventDto_Ppg value) ppg,
    required TResult Function(MuseEventDto_Telemetry value) telemetry,
    required TResult Function(MuseEventDto_Accelerometer value) accelerometer,
    required TResult Function(MuseEventDto_Gyroscope value) gyroscope,
    required TResult Function(MuseEventDto_Control value) control,
  }) {
    return gyroscope(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MuseEventDto_Connected value)? connected,
    TResult? Function(MuseEventDto_Disconnected value)? disconnected,
    TResult? Function(MuseEventDto_Eeg value)? eeg,
    TResult? Function(MuseEventDto_Bands value)? bands,
    TResult? Function(MuseEventDto_Ppg value)? ppg,
    TResult? Function(MuseEventDto_Telemetry value)? telemetry,
    TResult? Function(MuseEventDto_Accelerometer value)? accelerometer,
    TResult? Function(MuseEventDto_Gyroscope value)? gyroscope,
    TResult? Function(MuseEventDto_Control value)? control,
  }) {
    return gyroscope?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MuseEventDto_Connected value)? connected,
    TResult Function(MuseEventDto_Disconnected value)? disconnected,
    TResult Function(MuseEventDto_Eeg value)? eeg,
    TResult Function(MuseEventDto_Bands value)? bands,
    TResult Function(MuseEventDto_Ppg value)? ppg,
    TResult Function(MuseEventDto_Telemetry value)? telemetry,
    TResult Function(MuseEventDto_Accelerometer value)? accelerometer,
    TResult Function(MuseEventDto_Gyroscope value)? gyroscope,
    TResult Function(MuseEventDto_Control value)? control,
    required TResult orElse(),
  }) {
    if (gyroscope != null) {
      return gyroscope(this);
    }
    return orElse();
  }
}

abstract class MuseEventDto_Gyroscope extends MuseEventDto {
  const factory MuseEventDto_Gyroscope(final ImuDto field0) =
      _$MuseEventDto_GyroscopeImpl;
  const MuseEventDto_Gyroscope._() : super._();

  ImuDto get field0;

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MuseEventDto_GyroscopeImplCopyWith<_$MuseEventDto_GyroscopeImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class _$$MuseEventDto_ControlImplCopyWith<$Res> {
  factory _$$MuseEventDto_ControlImplCopyWith(
    _$MuseEventDto_ControlImpl value,
    $Res Function(_$MuseEventDto_ControlImpl) then,
  ) = __$$MuseEventDto_ControlImplCopyWithImpl<$Res>;
  @useResult
  $Res call({ControlDto field0});

  $ControlDtoCopyWith<$Res> get field0;
}

/// @nodoc
class __$$MuseEventDto_ControlImplCopyWithImpl<$Res>
    extends _$MuseEventDtoCopyWithImpl<$Res, _$MuseEventDto_ControlImpl>
    implements _$$MuseEventDto_ControlImplCopyWith<$Res> {
  __$$MuseEventDto_ControlImplCopyWithImpl(
    _$MuseEventDto_ControlImpl _value,
    $Res Function(_$MuseEventDto_ControlImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? field0 = null}) {
    return _then(
      _$MuseEventDto_ControlImpl(
        null == field0
            ? _value.field0
            : field0 // ignore: cast_nullable_to_non_nullable
                  as ControlDto,
      ),
    );
  }

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @pragma('vm:prefer-inline')
  $ControlDtoCopyWith<$Res> get field0 {
    return $ControlDtoCopyWith<$Res>(_value.field0, (value) {
      return _then(_value.copyWith(field0: value));
    });
  }
}

/// @nodoc

class _$MuseEventDto_ControlImpl extends MuseEventDto_Control {
  const _$MuseEventDto_ControlImpl(this.field0) : super._();

  @override
  final ControlDto field0;

  @override
  String toString() {
    return 'MuseEventDto.control(field0: $field0)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$MuseEventDto_ControlImpl &&
            (identical(other.field0, field0) || other.field0 == field0));
  }

  @override
  int get hashCode => Object.hash(runtimeType, field0);

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$MuseEventDto_ControlImplCopyWith<_$MuseEventDto_ControlImpl>
  get copyWith =>
      __$$MuseEventDto_ControlImplCopyWithImpl<_$MuseEventDto_ControlImpl>(
        this,
        _$identity,
      );

  @override
  @optionalTypeArgs
  TResult when<TResult extends Object?>({
    required TResult Function(String field0) connected,
    required TResult Function() disconnected,
    required TResult Function(EegDto field0) eeg,
    required TResult Function(BandsDto field0) bands,
    required TResult Function(PpgDto field0) ppg,
    required TResult Function(TelemetrySnapshot field0) telemetry,
    required TResult Function(ImuDto field0) accelerometer,
    required TResult Function(ImuDto field0) gyroscope,
    required TResult Function(ControlDto field0) control,
  }) {
    return control(field0);
  }

  @override
  @optionalTypeArgs
  TResult? whenOrNull<TResult extends Object?>({
    TResult? Function(String field0)? connected,
    TResult? Function()? disconnected,
    TResult? Function(EegDto field0)? eeg,
    TResult? Function(BandsDto field0)? bands,
    TResult? Function(PpgDto field0)? ppg,
    TResult? Function(TelemetrySnapshot field0)? telemetry,
    TResult? Function(ImuDto field0)? accelerometer,
    TResult? Function(ImuDto field0)? gyroscope,
    TResult? Function(ControlDto field0)? control,
  }) {
    return control?.call(field0);
  }

  @override
  @optionalTypeArgs
  TResult maybeWhen<TResult extends Object?>({
    TResult Function(String field0)? connected,
    TResult Function()? disconnected,
    TResult Function(EegDto field0)? eeg,
    TResult Function(BandsDto field0)? bands,
    TResult Function(PpgDto field0)? ppg,
    TResult Function(TelemetrySnapshot field0)? telemetry,
    TResult Function(ImuDto field0)? accelerometer,
    TResult Function(ImuDto field0)? gyroscope,
    TResult Function(ControlDto field0)? control,
    required TResult orElse(),
  }) {
    if (control != null) {
      return control(field0);
    }
    return orElse();
  }

  @override
  @optionalTypeArgs
  TResult map<TResult extends Object?>({
    required TResult Function(MuseEventDto_Connected value) connected,
    required TResult Function(MuseEventDto_Disconnected value) disconnected,
    required TResult Function(MuseEventDto_Eeg value) eeg,
    required TResult Function(MuseEventDto_Bands value) bands,
    required TResult Function(MuseEventDto_Ppg value) ppg,
    required TResult Function(MuseEventDto_Telemetry value) telemetry,
    required TResult Function(MuseEventDto_Accelerometer value) accelerometer,
    required TResult Function(MuseEventDto_Gyroscope value) gyroscope,
    required TResult Function(MuseEventDto_Control value) control,
  }) {
    return control(this);
  }

  @override
  @optionalTypeArgs
  TResult? mapOrNull<TResult extends Object?>({
    TResult? Function(MuseEventDto_Connected value)? connected,
    TResult? Function(MuseEventDto_Disconnected value)? disconnected,
    TResult? Function(MuseEventDto_Eeg value)? eeg,
    TResult? Function(MuseEventDto_Bands value)? bands,
    TResult? Function(MuseEventDto_Ppg value)? ppg,
    TResult? Function(MuseEventDto_Telemetry value)? telemetry,
    TResult? Function(MuseEventDto_Accelerometer value)? accelerometer,
    TResult? Function(MuseEventDto_Gyroscope value)? gyroscope,
    TResult? Function(MuseEventDto_Control value)? control,
  }) {
    return control?.call(this);
  }

  @override
  @optionalTypeArgs
  TResult maybeMap<TResult extends Object?>({
    TResult Function(MuseEventDto_Connected value)? connected,
    TResult Function(MuseEventDto_Disconnected value)? disconnected,
    TResult Function(MuseEventDto_Eeg value)? eeg,
    TResult Function(MuseEventDto_Bands value)? bands,
    TResult Function(MuseEventDto_Ppg value)? ppg,
    TResult Function(MuseEventDto_Telemetry value)? telemetry,
    TResult Function(MuseEventDto_Accelerometer value)? accelerometer,
    TResult Function(MuseEventDto_Gyroscope value)? gyroscope,
    TResult Function(MuseEventDto_Control value)? control,
    required TResult orElse(),
  }) {
    if (control != null) {
      return control(this);
    }
    return orElse();
  }
}

abstract class MuseEventDto_Control extends MuseEventDto {
  const factory MuseEventDto_Control(final ControlDto field0) =
      _$MuseEventDto_ControlImpl;
  const MuseEventDto_Control._() : super._();

  ControlDto get field0;

  /// Create a copy of MuseEventDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$MuseEventDto_ControlImplCopyWith<_$MuseEventDto_ControlImpl>
  get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$PpgDto {
  int get index => throw _privateConstructorUsedError;
  int get channel => throw _privateConstructorUsedError;
  double get timestamp => throw _privateConstructorUsedError;
  Float64List get samples => throw _privateConstructorUsedError;

  /// Create a copy of PpgDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $PpgDtoCopyWith<PpgDto> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $PpgDtoCopyWith<$Res> {
  factory $PpgDtoCopyWith(PpgDto value, $Res Function(PpgDto) then) =
      _$PpgDtoCopyWithImpl<$Res, PpgDto>;
  @useResult
  $Res call({int index, int channel, double timestamp, Float64List samples});
}

/// @nodoc
class _$PpgDtoCopyWithImpl<$Res, $Val extends PpgDto>
    implements $PpgDtoCopyWith<$Res> {
  _$PpgDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of PpgDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? index = null,
    Object? channel = null,
    Object? timestamp = null,
    Object? samples = null,
  }) {
    return _then(
      _value.copyWith(
            index: null == index
                ? _value.index
                : index // ignore: cast_nullable_to_non_nullable
                      as int,
            channel: null == channel
                ? _value.channel
                : channel // ignore: cast_nullable_to_non_nullable
                      as int,
            timestamp: null == timestamp
                ? _value.timestamp
                : timestamp // ignore: cast_nullable_to_non_nullable
                      as double,
            samples: null == samples
                ? _value.samples
                : samples // ignore: cast_nullable_to_non_nullable
                      as Float64List,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$PpgDtoImplCopyWith<$Res> implements $PpgDtoCopyWith<$Res> {
  factory _$$PpgDtoImplCopyWith(
    _$PpgDtoImpl value,
    $Res Function(_$PpgDtoImpl) then,
  ) = __$$PpgDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({int index, int channel, double timestamp, Float64List samples});
}

/// @nodoc
class __$$PpgDtoImplCopyWithImpl<$Res>
    extends _$PpgDtoCopyWithImpl<$Res, _$PpgDtoImpl>
    implements _$$PpgDtoImplCopyWith<$Res> {
  __$$PpgDtoImplCopyWithImpl(
    _$PpgDtoImpl _value,
    $Res Function(_$PpgDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of PpgDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? index = null,
    Object? channel = null,
    Object? timestamp = null,
    Object? samples = null,
  }) {
    return _then(
      _$PpgDtoImpl(
        index: null == index
            ? _value.index
            : index // ignore: cast_nullable_to_non_nullable
                  as int,
        channel: null == channel
            ? _value.channel
            : channel // ignore: cast_nullable_to_non_nullable
                  as int,
        timestamp: null == timestamp
            ? _value.timestamp
            : timestamp // ignore: cast_nullable_to_non_nullable
                  as double,
        samples: null == samples
            ? _value.samples
            : samples // ignore: cast_nullable_to_non_nullable
                  as Float64List,
      ),
    );
  }
}

/// @nodoc

class _$PpgDtoImpl implements _PpgDto {
  const _$PpgDtoImpl({
    required this.index,
    required this.channel,
    required this.timestamp,
    required this.samples,
  });

  @override
  final int index;
  @override
  final int channel;
  @override
  final double timestamp;
  @override
  final Float64List samples;

  @override
  String toString() {
    return 'PpgDto(index: $index, channel: $channel, timestamp: $timestamp, samples: $samples)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$PpgDtoImpl &&
            (identical(other.index, index) || other.index == index) &&
            (identical(other.channel, channel) || other.channel == channel) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            const DeepCollectionEquality().equals(other.samples, samples));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    index,
    channel,
    timestamp,
    const DeepCollectionEquality().hash(samples),
  );

  /// Create a copy of PpgDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$PpgDtoImplCopyWith<_$PpgDtoImpl> get copyWith =>
      __$$PpgDtoImplCopyWithImpl<_$PpgDtoImpl>(this, _$identity);
}

abstract class _PpgDto implements PpgDto {
  const factory _PpgDto({
    required final int index,
    required final int channel,
    required final double timestamp,
    required final Float64List samples,
  }) = _$PpgDtoImpl;

  @override
  int get index;
  @override
  int get channel;
  @override
  double get timestamp;
  @override
  Float64List get samples;

  /// Create a copy of PpgDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$PpgDtoImplCopyWith<_$PpgDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$TelemetrySnapshot {
  double get batteryLevel => throw _privateConstructorUsedError;
  double get fuelGaugeVoltage => throw _privateConstructorUsedError;
  int get temperature => throw _privateConstructorUsedError;

  /// Create a copy of TelemetrySnapshot
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $TelemetrySnapshotCopyWith<TelemetrySnapshot> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $TelemetrySnapshotCopyWith<$Res> {
  factory $TelemetrySnapshotCopyWith(
    TelemetrySnapshot value,
    $Res Function(TelemetrySnapshot) then,
  ) = _$TelemetrySnapshotCopyWithImpl<$Res, TelemetrySnapshot>;
  @useResult
  $Res call({double batteryLevel, double fuelGaugeVoltage, int temperature});
}

/// @nodoc
class _$TelemetrySnapshotCopyWithImpl<$Res, $Val extends TelemetrySnapshot>
    implements $TelemetrySnapshotCopyWith<$Res> {
  _$TelemetrySnapshotCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of TelemetrySnapshot
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? batteryLevel = null,
    Object? fuelGaugeVoltage = null,
    Object? temperature = null,
  }) {
    return _then(
      _value.copyWith(
            batteryLevel: null == batteryLevel
                ? _value.batteryLevel
                : batteryLevel // ignore: cast_nullable_to_non_nullable
                      as double,
            fuelGaugeVoltage: null == fuelGaugeVoltage
                ? _value.fuelGaugeVoltage
                : fuelGaugeVoltage // ignore: cast_nullable_to_non_nullable
                      as double,
            temperature: null == temperature
                ? _value.temperature
                : temperature // ignore: cast_nullable_to_non_nullable
                      as int,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$TelemetrySnapshotImplCopyWith<$Res>
    implements $TelemetrySnapshotCopyWith<$Res> {
  factory _$$TelemetrySnapshotImplCopyWith(
    _$TelemetrySnapshotImpl value,
    $Res Function(_$TelemetrySnapshotImpl) then,
  ) = __$$TelemetrySnapshotImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double batteryLevel, double fuelGaugeVoltage, int temperature});
}

/// @nodoc
class __$$TelemetrySnapshotImplCopyWithImpl<$Res>
    extends _$TelemetrySnapshotCopyWithImpl<$Res, _$TelemetrySnapshotImpl>
    implements _$$TelemetrySnapshotImplCopyWith<$Res> {
  __$$TelemetrySnapshotImplCopyWithImpl(
    _$TelemetrySnapshotImpl _value,
    $Res Function(_$TelemetrySnapshotImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of TelemetrySnapshot
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? batteryLevel = null,
    Object? fuelGaugeVoltage = null,
    Object? temperature = null,
  }) {
    return _then(
      _$TelemetrySnapshotImpl(
        batteryLevel: null == batteryLevel
            ? _value.batteryLevel
            : batteryLevel // ignore: cast_nullable_to_non_nullable
                  as double,
        fuelGaugeVoltage: null == fuelGaugeVoltage
            ? _value.fuelGaugeVoltage
            : fuelGaugeVoltage // ignore: cast_nullable_to_non_nullable
                  as double,
        temperature: null == temperature
            ? _value.temperature
            : temperature // ignore: cast_nullable_to_non_nullable
                  as int,
      ),
    );
  }
}

/// @nodoc

class _$TelemetrySnapshotImpl extends _TelemetrySnapshot {
  const _$TelemetrySnapshotImpl({
    required this.batteryLevel,
    required this.fuelGaugeVoltage,
    required this.temperature,
  }) : super._();

  @override
  final double batteryLevel;
  @override
  final double fuelGaugeVoltage;
  @override
  final int temperature;

  @override
  String toString() {
    return 'TelemetrySnapshot(batteryLevel: $batteryLevel, fuelGaugeVoltage: $fuelGaugeVoltage, temperature: $temperature)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$TelemetrySnapshotImpl &&
            (identical(other.batteryLevel, batteryLevel) ||
                other.batteryLevel == batteryLevel) &&
            (identical(other.fuelGaugeVoltage, fuelGaugeVoltage) ||
                other.fuelGaugeVoltage == fuelGaugeVoltage) &&
            (identical(other.temperature, temperature) ||
                other.temperature == temperature));
  }

  @override
  int get hashCode =>
      Object.hash(runtimeType, batteryLevel, fuelGaugeVoltage, temperature);

  /// Create a copy of TelemetrySnapshot
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$TelemetrySnapshotImplCopyWith<_$TelemetrySnapshotImpl> get copyWith =>
      __$$TelemetrySnapshotImplCopyWithImpl<_$TelemetrySnapshotImpl>(
        this,
        _$identity,
      );
}

abstract class _TelemetrySnapshot extends TelemetrySnapshot {
  const factory _TelemetrySnapshot({
    required final double batteryLevel,
    required final double fuelGaugeVoltage,
    required final int temperature,
  }) = _$TelemetrySnapshotImpl;
  const _TelemetrySnapshot._() : super._();

  @override
  double get batteryLevel;
  @override
  double get fuelGaugeVoltage;
  @override
  int get temperature;

  /// Create a copy of TelemetrySnapshot
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$TelemetrySnapshotImplCopyWith<_$TelemetrySnapshotImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$XyzDto {
  double get x => throw _privateConstructorUsedError;
  double get y => throw _privateConstructorUsedError;
  double get z => throw _privateConstructorUsedError;

  /// Create a copy of XyzDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $XyzDtoCopyWith<XyzDto> get copyWith => throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $XyzDtoCopyWith<$Res> {
  factory $XyzDtoCopyWith(XyzDto value, $Res Function(XyzDto) then) =
      _$XyzDtoCopyWithImpl<$Res, XyzDto>;
  @useResult
  $Res call({double x, double y, double z});
}

/// @nodoc
class _$XyzDtoCopyWithImpl<$Res, $Val extends XyzDto>
    implements $XyzDtoCopyWith<$Res> {
  _$XyzDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of XyzDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? x = null, Object? y = null, Object? z = null}) {
    return _then(
      _value.copyWith(
            x: null == x
                ? _value.x
                : x // ignore: cast_nullable_to_non_nullable
                      as double,
            y: null == y
                ? _value.y
                : y // ignore: cast_nullable_to_non_nullable
                      as double,
            z: null == z
                ? _value.z
                : z // ignore: cast_nullable_to_non_nullable
                      as double,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$XyzDtoImplCopyWith<$Res> implements $XyzDtoCopyWith<$Res> {
  factory _$$XyzDtoImplCopyWith(
    _$XyzDtoImpl value,
    $Res Function(_$XyzDtoImpl) then,
  ) = __$$XyzDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double x, double y, double z});
}

/// @nodoc
class __$$XyzDtoImplCopyWithImpl<$Res>
    extends _$XyzDtoCopyWithImpl<$Res, _$XyzDtoImpl>
    implements _$$XyzDtoImplCopyWith<$Res> {
  __$$XyzDtoImplCopyWithImpl(
    _$XyzDtoImpl _value,
    $Res Function(_$XyzDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of XyzDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? x = null, Object? y = null, Object? z = null}) {
    return _then(
      _$XyzDtoImpl(
        x: null == x
            ? _value.x
            : x // ignore: cast_nullable_to_non_nullable
                  as double,
        y: null == y
            ? _value.y
            : y // ignore: cast_nullable_to_non_nullable
                  as double,
        z: null == z
            ? _value.z
            : z // ignore: cast_nullable_to_non_nullable
                  as double,
      ),
    );
  }
}

/// @nodoc

class _$XyzDtoImpl implements _XyzDto {
  const _$XyzDtoImpl({required this.x, required this.y, required this.z});

  @override
  final double x;
  @override
  final double y;
  @override
  final double z;

  @override
  String toString() {
    return 'XyzDto(x: $x, y: $y, z: $z)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$XyzDtoImpl &&
            (identical(other.x, x) || other.x == x) &&
            (identical(other.y, y) || other.y == y) &&
            (identical(other.z, z) || other.z == z));
  }

  @override
  int get hashCode => Object.hash(runtimeType, x, y, z);

  /// Create a copy of XyzDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$XyzDtoImplCopyWith<_$XyzDtoImpl> get copyWith =>
      __$$XyzDtoImplCopyWithImpl<_$XyzDtoImpl>(this, _$identity);
}

abstract class _XyzDto implements XyzDto {
  const factory _XyzDto({
    required final double x,
    required final double y,
    required final double z,
  }) = _$XyzDtoImpl;

  @override
  double get x;
  @override
  double get y;
  @override
  double get z;

  /// Create a copy of XyzDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$XyzDtoImplCopyWith<_$XyzDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
