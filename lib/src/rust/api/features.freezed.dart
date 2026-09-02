// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'features.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$FeatureDto {
  String get id => throw _privateConstructorUsedError;
  double get timestamp => throw _privateConstructorUsedError;
  double get value => throw _privateConstructorUsedError;

  /// Create a copy of FeatureDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $FeatureDtoCopyWith<FeatureDto> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FeatureDtoCopyWith<$Res> {
  factory $FeatureDtoCopyWith(
    FeatureDto value,
    $Res Function(FeatureDto) then,
  ) = _$FeatureDtoCopyWithImpl<$Res, FeatureDto>;
  @useResult
  $Res call({String id, double timestamp, double value});
}

/// @nodoc
class _$FeatureDtoCopyWithImpl<$Res, $Val extends FeatureDto>
    implements $FeatureDtoCopyWith<$Res> {
  _$FeatureDtoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of FeatureDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? timestamp = null,
    Object? value = null,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            timestamp: null == timestamp
                ? _value.timestamp
                : timestamp // ignore: cast_nullable_to_non_nullable
                      as double,
            value: null == value
                ? _value.value
                : value // ignore: cast_nullable_to_non_nullable
                      as double,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$FeatureDtoImplCopyWith<$Res>
    implements $FeatureDtoCopyWith<$Res> {
  factory _$$FeatureDtoImplCopyWith(
    _$FeatureDtoImpl value,
    $Res Function(_$FeatureDtoImpl) then,
  ) = __$$FeatureDtoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({String id, double timestamp, double value});
}

/// @nodoc
class __$$FeatureDtoImplCopyWithImpl<$Res>
    extends _$FeatureDtoCopyWithImpl<$Res, _$FeatureDtoImpl>
    implements _$$FeatureDtoImplCopyWith<$Res> {
  __$$FeatureDtoImplCopyWithImpl(
    _$FeatureDtoImpl _value,
    $Res Function(_$FeatureDtoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of FeatureDto
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? timestamp = null,
    Object? value = null,
  }) {
    return _then(
      _$FeatureDtoImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        timestamp: null == timestamp
            ? _value.timestamp
            : timestamp // ignore: cast_nullable_to_non_nullable
                  as double,
        value: null == value
            ? _value.value
            : value // ignore: cast_nullable_to_non_nullable
                  as double,
      ),
    );
  }
}

/// @nodoc

class _$FeatureDtoImpl implements _FeatureDto {
  const _$FeatureDtoImpl({
    required this.id,
    required this.timestamp,
    required this.value,
  });

  @override
  final String id;
  @override
  final double timestamp;
  @override
  final double value;

  @override
  String toString() {
    return 'FeatureDto(id: $id, timestamp: $timestamp, value: $value)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FeatureDtoImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.timestamp, timestamp) ||
                other.timestamp == timestamp) &&
            (identical(other.value, value) || other.value == value));
  }

  @override
  int get hashCode => Object.hash(runtimeType, id, timestamp, value);

  /// Create a copy of FeatureDto
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$FeatureDtoImplCopyWith<_$FeatureDtoImpl> get copyWith =>
      __$$FeatureDtoImplCopyWithImpl<_$FeatureDtoImpl>(this, _$identity);
}

abstract class _FeatureDto implements FeatureDto {
  const factory _FeatureDto({
    required final String id,
    required final double timestamp,
    required final double value,
  }) = _$FeatureDtoImpl;

  @override
  String get id;
  @override
  double get timestamp;
  @override
  double get value;

  /// Create a copy of FeatureDto
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$FeatureDtoImplCopyWith<_$FeatureDtoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$FeatureInfo {
  String get id => throw _privateConstructorUsedError;
  FeatureSource get source => throw _privateConstructorUsedError;
  List<FeatureLane> get usableFor => throw _privateConstructorUsedError;
  List<String> get defaultElectrodes => throw _privateConstructorUsedError;
  double get nativeRateHz => throw _privateConstructorUsedError;
  bool get available => throw _privateConstructorUsedError;
  String? get unavailableReason => throw _privateConstructorUsedError;

  /// Create a copy of FeatureInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $FeatureInfoCopyWith<FeatureInfo> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $FeatureInfoCopyWith<$Res> {
  factory $FeatureInfoCopyWith(
    FeatureInfo value,
    $Res Function(FeatureInfo) then,
  ) = _$FeatureInfoCopyWithImpl<$Res, FeatureInfo>;
  @useResult
  $Res call({
    String id,
    FeatureSource source,
    List<FeatureLane> usableFor,
    List<String> defaultElectrodes,
    double nativeRateHz,
    bool available,
    String? unavailableReason,
  });
}

/// @nodoc
class _$FeatureInfoCopyWithImpl<$Res, $Val extends FeatureInfo>
    implements $FeatureInfoCopyWith<$Res> {
  _$FeatureInfoCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of FeatureInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? source = null,
    Object? usableFor = null,
    Object? defaultElectrodes = null,
    Object? nativeRateHz = null,
    Object? available = null,
    Object? unavailableReason = freezed,
  }) {
    return _then(
      _value.copyWith(
            id: null == id
                ? _value.id
                : id // ignore: cast_nullable_to_non_nullable
                      as String,
            source: null == source
                ? _value.source
                : source // ignore: cast_nullable_to_non_nullable
                      as FeatureSource,
            usableFor: null == usableFor
                ? _value.usableFor
                : usableFor // ignore: cast_nullable_to_non_nullable
                      as List<FeatureLane>,
            defaultElectrodes: null == defaultElectrodes
                ? _value.defaultElectrodes
                : defaultElectrodes // ignore: cast_nullable_to_non_nullable
                      as List<String>,
            nativeRateHz: null == nativeRateHz
                ? _value.nativeRateHz
                : nativeRateHz // ignore: cast_nullable_to_non_nullable
                      as double,
            available: null == available
                ? _value.available
                : available // ignore: cast_nullable_to_non_nullable
                      as bool,
            unavailableReason: freezed == unavailableReason
                ? _value.unavailableReason
                : unavailableReason // ignore: cast_nullable_to_non_nullable
                      as String?,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$FeatureInfoImplCopyWith<$Res>
    implements $FeatureInfoCopyWith<$Res> {
  factory _$$FeatureInfoImplCopyWith(
    _$FeatureInfoImpl value,
    $Res Function(_$FeatureInfoImpl) then,
  ) = __$$FeatureInfoImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String id,
    FeatureSource source,
    List<FeatureLane> usableFor,
    List<String> defaultElectrodes,
    double nativeRateHz,
    bool available,
    String? unavailableReason,
  });
}

/// @nodoc
class __$$FeatureInfoImplCopyWithImpl<$Res>
    extends _$FeatureInfoCopyWithImpl<$Res, _$FeatureInfoImpl>
    implements _$$FeatureInfoImplCopyWith<$Res> {
  __$$FeatureInfoImplCopyWithImpl(
    _$FeatureInfoImpl _value,
    $Res Function(_$FeatureInfoImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of FeatureInfo
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? id = null,
    Object? source = null,
    Object? usableFor = null,
    Object? defaultElectrodes = null,
    Object? nativeRateHz = null,
    Object? available = null,
    Object? unavailableReason = freezed,
  }) {
    return _then(
      _$FeatureInfoImpl(
        id: null == id
            ? _value.id
            : id // ignore: cast_nullable_to_non_nullable
                  as String,
        source: null == source
            ? _value.source
            : source // ignore: cast_nullable_to_non_nullable
                  as FeatureSource,
        usableFor: null == usableFor
            ? _value._usableFor
            : usableFor // ignore: cast_nullable_to_non_nullable
                  as List<FeatureLane>,
        defaultElectrodes: null == defaultElectrodes
            ? _value._defaultElectrodes
            : defaultElectrodes // ignore: cast_nullable_to_non_nullable
                  as List<String>,
        nativeRateHz: null == nativeRateHz
            ? _value.nativeRateHz
            : nativeRateHz // ignore: cast_nullable_to_non_nullable
                  as double,
        available: null == available
            ? _value.available
            : available // ignore: cast_nullable_to_non_nullable
                  as bool,
        unavailableReason: freezed == unavailableReason
            ? _value.unavailableReason
            : unavailableReason // ignore: cast_nullable_to_non_nullable
                  as String?,
      ),
    );
  }
}

/// @nodoc

class _$FeatureInfoImpl implements _FeatureInfo {
  const _$FeatureInfoImpl({
    required this.id,
    required this.source,
    required final List<FeatureLane> usableFor,
    required final List<String> defaultElectrodes,
    required this.nativeRateHz,
    required this.available,
    this.unavailableReason,
  }) : _usableFor = usableFor,
       _defaultElectrodes = defaultElectrodes;

  @override
  final String id;
  @override
  final FeatureSource source;
  final List<FeatureLane> _usableFor;
  @override
  List<FeatureLane> get usableFor {
    if (_usableFor is EqualUnmodifiableListView) return _usableFor;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_usableFor);
  }

  final List<String> _defaultElectrodes;
  @override
  List<String> get defaultElectrodes {
    if (_defaultElectrodes is EqualUnmodifiableListView)
      return _defaultElectrodes;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_defaultElectrodes);
  }

  @override
  final double nativeRateHz;
  @override
  final bool available;
  @override
  final String? unavailableReason;

  @override
  String toString() {
    return 'FeatureInfo(id: $id, source: $source, usableFor: $usableFor, defaultElectrodes: $defaultElectrodes, nativeRateHz: $nativeRateHz, available: $available, unavailableReason: $unavailableReason)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$FeatureInfoImpl &&
            (identical(other.id, id) || other.id == id) &&
            (identical(other.source, source) || other.source == source) &&
            const DeepCollectionEquality().equals(
              other._usableFor,
              _usableFor,
            ) &&
            const DeepCollectionEquality().equals(
              other._defaultElectrodes,
              _defaultElectrodes,
            ) &&
            (identical(other.nativeRateHz, nativeRateHz) ||
                other.nativeRateHz == nativeRateHz) &&
            (identical(other.available, available) ||
                other.available == available) &&
            (identical(other.unavailableReason, unavailableReason) ||
                other.unavailableReason == unavailableReason));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    id,
    source,
    const DeepCollectionEquality().hash(_usableFor),
    const DeepCollectionEquality().hash(_defaultElectrodes),
    nativeRateHz,
    available,
    unavailableReason,
  );

  /// Create a copy of FeatureInfo
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$FeatureInfoImplCopyWith<_$FeatureInfoImpl> get copyWith =>
      __$$FeatureInfoImplCopyWithImpl<_$FeatureInfoImpl>(this, _$identity);
}

abstract class _FeatureInfo implements FeatureInfo {
  const factory _FeatureInfo({
    required final String id,
    required final FeatureSource source,
    required final List<FeatureLane> usableFor,
    required final List<String> defaultElectrodes,
    required final double nativeRateHz,
    required final bool available,
    final String? unavailableReason,
  }) = _$FeatureInfoImpl;

  @override
  String get id;
  @override
  FeatureSource get source;
  @override
  List<FeatureLane> get usableFor;
  @override
  List<String> get defaultElectrodes;
  @override
  double get nativeRateHz;
  @override
  bool get available;
  @override
  String? get unavailableReason;

  /// Create a copy of FeatureInfo
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$FeatureInfoImplCopyWith<_$FeatureInfoImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
