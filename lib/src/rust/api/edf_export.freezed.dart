// coverage:ignore-file
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'edf_export.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

T _$identity<T>(T value) => value;

final _privateConstructorUsedError = UnsupportedError(
  'It seems like you constructed your class using `MyClass._()`. This constructor is only meant to be used by freezed and you are not supposed to need it nor use it.\nPlease check the documentation here for more information: https://github.com/rrousselGit/freezed#adding-getters-and-methods-to-our-models',
);

/// @nodoc
mixin _$EdfExportAnnotation {
  double get onsetSeconds => throw _privateConstructorUsedError;
  String get text => throw _privateConstructorUsedError;

  /// Create a copy of EdfExportAnnotation
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $EdfExportAnnotationCopyWith<EdfExportAnnotation> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $EdfExportAnnotationCopyWith<$Res> {
  factory $EdfExportAnnotationCopyWith(
    EdfExportAnnotation value,
    $Res Function(EdfExportAnnotation) then,
  ) = _$EdfExportAnnotationCopyWithImpl<$Res, EdfExportAnnotation>;
  @useResult
  $Res call({double onsetSeconds, String text});
}

/// @nodoc
class _$EdfExportAnnotationCopyWithImpl<$Res, $Val extends EdfExportAnnotation>
    implements $EdfExportAnnotationCopyWith<$Res> {
  _$EdfExportAnnotationCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of EdfExportAnnotation
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? onsetSeconds = null, Object? text = null}) {
    return _then(
      _value.copyWith(
            onsetSeconds: null == onsetSeconds
                ? _value.onsetSeconds
                : onsetSeconds // ignore: cast_nullable_to_non_nullable
                      as double,
            text: null == text
                ? _value.text
                : text // ignore: cast_nullable_to_non_nullable
                      as String,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$EdfExportAnnotationImplCopyWith<$Res>
    implements $EdfExportAnnotationCopyWith<$Res> {
  factory _$$EdfExportAnnotationImplCopyWith(
    _$EdfExportAnnotationImpl value,
    $Res Function(_$EdfExportAnnotationImpl) then,
  ) = __$$EdfExportAnnotationImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({double onsetSeconds, String text});
}

/// @nodoc
class __$$EdfExportAnnotationImplCopyWithImpl<$Res>
    extends _$EdfExportAnnotationCopyWithImpl<$Res, _$EdfExportAnnotationImpl>
    implements _$$EdfExportAnnotationImplCopyWith<$Res> {
  __$$EdfExportAnnotationImplCopyWithImpl(
    _$EdfExportAnnotationImpl _value,
    $Res Function(_$EdfExportAnnotationImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of EdfExportAnnotation
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({Object? onsetSeconds = null, Object? text = null}) {
    return _then(
      _$EdfExportAnnotationImpl(
        onsetSeconds: null == onsetSeconds
            ? _value.onsetSeconds
            : onsetSeconds // ignore: cast_nullable_to_non_nullable
                  as double,
        text: null == text
            ? _value.text
            : text // ignore: cast_nullable_to_non_nullable
                  as String,
      ),
    );
  }
}

/// @nodoc

class _$EdfExportAnnotationImpl implements _EdfExportAnnotation {
  const _$EdfExportAnnotationImpl({
    required this.onsetSeconds,
    required this.text,
  });

  @override
  final double onsetSeconds;
  @override
  final String text;

  @override
  String toString() {
    return 'EdfExportAnnotation(onsetSeconds: $onsetSeconds, text: $text)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$EdfExportAnnotationImpl &&
            (identical(other.onsetSeconds, onsetSeconds) ||
                other.onsetSeconds == onsetSeconds) &&
            (identical(other.text, text) || other.text == text));
  }

  @override
  int get hashCode => Object.hash(runtimeType, onsetSeconds, text);

  /// Create a copy of EdfExportAnnotation
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$EdfExportAnnotationImplCopyWith<_$EdfExportAnnotationImpl> get copyWith =>
      __$$EdfExportAnnotationImplCopyWithImpl<_$EdfExportAnnotationImpl>(
        this,
        _$identity,
      );
}

abstract class _EdfExportAnnotation implements EdfExportAnnotation {
  const factory _EdfExportAnnotation({
    required final double onsetSeconds,
    required final String text,
  }) = _$EdfExportAnnotationImpl;

  @override
  double get onsetSeconds;
  @override
  String get text;

  /// Create a copy of EdfExportAnnotation
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$EdfExportAnnotationImplCopyWith<_$EdfExportAnnotationImpl> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
mixin _$EdfExportParams {
  String get patientId => throw _privateConstructorUsedError;
  String get recordingId => throw _privateConstructorUsedError;
  int get year => throw _privateConstructorUsedError;
  int get month => throw _privateConstructorUsedError;
  int get day => throw _privateConstructorUsedError;
  int get hour => throw _privateConstructorUsedError;
  int get minute => throw _privateConstructorUsedError;
  int get second => throw _privateConstructorUsedError;
  List<EdfExportAnnotation> get annotations =>
      throw _privateConstructorUsedError;

  /// Create a copy of EdfExportParams
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  $EdfExportParamsCopyWith<EdfExportParams> get copyWith =>
      throw _privateConstructorUsedError;
}

/// @nodoc
abstract class $EdfExportParamsCopyWith<$Res> {
  factory $EdfExportParamsCopyWith(
    EdfExportParams value,
    $Res Function(EdfExportParams) then,
  ) = _$EdfExportParamsCopyWithImpl<$Res, EdfExportParams>;
  @useResult
  $Res call({
    String patientId,
    String recordingId,
    int year,
    int month,
    int day,
    int hour,
    int minute,
    int second,
    List<EdfExportAnnotation> annotations,
  });
}

/// @nodoc
class _$EdfExportParamsCopyWithImpl<$Res, $Val extends EdfExportParams>
    implements $EdfExportParamsCopyWith<$Res> {
  _$EdfExportParamsCopyWithImpl(this._value, this._then);

  // ignore: unused_field
  final $Val _value;
  // ignore: unused_field
  final $Res Function($Val) _then;

  /// Create a copy of EdfExportParams
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? patientId = null,
    Object? recordingId = null,
    Object? year = null,
    Object? month = null,
    Object? day = null,
    Object? hour = null,
    Object? minute = null,
    Object? second = null,
    Object? annotations = null,
  }) {
    return _then(
      _value.copyWith(
            patientId: null == patientId
                ? _value.patientId
                : patientId // ignore: cast_nullable_to_non_nullable
                      as String,
            recordingId: null == recordingId
                ? _value.recordingId
                : recordingId // ignore: cast_nullable_to_non_nullable
                      as String,
            year: null == year
                ? _value.year
                : year // ignore: cast_nullable_to_non_nullable
                      as int,
            month: null == month
                ? _value.month
                : month // ignore: cast_nullable_to_non_nullable
                      as int,
            day: null == day
                ? _value.day
                : day // ignore: cast_nullable_to_non_nullable
                      as int,
            hour: null == hour
                ? _value.hour
                : hour // ignore: cast_nullable_to_non_nullable
                      as int,
            minute: null == minute
                ? _value.minute
                : minute // ignore: cast_nullable_to_non_nullable
                      as int,
            second: null == second
                ? _value.second
                : second // ignore: cast_nullable_to_non_nullable
                      as int,
            annotations: null == annotations
                ? _value.annotations
                : annotations // ignore: cast_nullable_to_non_nullable
                      as List<EdfExportAnnotation>,
          )
          as $Val,
    );
  }
}

/// @nodoc
abstract class _$$EdfExportParamsImplCopyWith<$Res>
    implements $EdfExportParamsCopyWith<$Res> {
  factory _$$EdfExportParamsImplCopyWith(
    _$EdfExportParamsImpl value,
    $Res Function(_$EdfExportParamsImpl) then,
  ) = __$$EdfExportParamsImplCopyWithImpl<$Res>;
  @override
  @useResult
  $Res call({
    String patientId,
    String recordingId,
    int year,
    int month,
    int day,
    int hour,
    int minute,
    int second,
    List<EdfExportAnnotation> annotations,
  });
}

/// @nodoc
class __$$EdfExportParamsImplCopyWithImpl<$Res>
    extends _$EdfExportParamsCopyWithImpl<$Res, _$EdfExportParamsImpl>
    implements _$$EdfExportParamsImplCopyWith<$Res> {
  __$$EdfExportParamsImplCopyWithImpl(
    _$EdfExportParamsImpl _value,
    $Res Function(_$EdfExportParamsImpl) _then,
  ) : super(_value, _then);

  /// Create a copy of EdfExportParams
  /// with the given fields replaced by the non-null parameter values.
  @pragma('vm:prefer-inline')
  @override
  $Res call({
    Object? patientId = null,
    Object? recordingId = null,
    Object? year = null,
    Object? month = null,
    Object? day = null,
    Object? hour = null,
    Object? minute = null,
    Object? second = null,
    Object? annotations = null,
  }) {
    return _then(
      _$EdfExportParamsImpl(
        patientId: null == patientId
            ? _value.patientId
            : patientId // ignore: cast_nullable_to_non_nullable
                  as String,
        recordingId: null == recordingId
            ? _value.recordingId
            : recordingId // ignore: cast_nullable_to_non_nullable
                  as String,
        year: null == year
            ? _value.year
            : year // ignore: cast_nullable_to_non_nullable
                  as int,
        month: null == month
            ? _value.month
            : month // ignore: cast_nullable_to_non_nullable
                  as int,
        day: null == day
            ? _value.day
            : day // ignore: cast_nullable_to_non_nullable
                  as int,
        hour: null == hour
            ? _value.hour
            : hour // ignore: cast_nullable_to_non_nullable
                  as int,
        minute: null == minute
            ? _value.minute
            : minute // ignore: cast_nullable_to_non_nullable
                  as int,
        second: null == second
            ? _value.second
            : second // ignore: cast_nullable_to_non_nullable
                  as int,
        annotations: null == annotations
            ? _value._annotations
            : annotations // ignore: cast_nullable_to_non_nullable
                  as List<EdfExportAnnotation>,
      ),
    );
  }
}

/// @nodoc

class _$EdfExportParamsImpl implements _EdfExportParams {
  const _$EdfExportParamsImpl({
    required this.patientId,
    required this.recordingId,
    required this.year,
    required this.month,
    required this.day,
    required this.hour,
    required this.minute,
    required this.second,
    required final List<EdfExportAnnotation> annotations,
  }) : _annotations = annotations;

  @override
  final String patientId;
  @override
  final String recordingId;
  @override
  final int year;
  @override
  final int month;
  @override
  final int day;
  @override
  final int hour;
  @override
  final int minute;
  @override
  final int second;
  final List<EdfExportAnnotation> _annotations;
  @override
  List<EdfExportAnnotation> get annotations {
    if (_annotations is EqualUnmodifiableListView) return _annotations;
    // ignore: implicit_dynamic_type
    return EqualUnmodifiableListView(_annotations);
  }

  @override
  String toString() {
    return 'EdfExportParams(patientId: $patientId, recordingId: $recordingId, year: $year, month: $month, day: $day, hour: $hour, minute: $minute, second: $second, annotations: $annotations)';
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other.runtimeType == runtimeType &&
            other is _$EdfExportParamsImpl &&
            (identical(other.patientId, patientId) ||
                other.patientId == patientId) &&
            (identical(other.recordingId, recordingId) ||
                other.recordingId == recordingId) &&
            (identical(other.year, year) || other.year == year) &&
            (identical(other.month, month) || other.month == month) &&
            (identical(other.day, day) || other.day == day) &&
            (identical(other.hour, hour) || other.hour == hour) &&
            (identical(other.minute, minute) || other.minute == minute) &&
            (identical(other.second, second) || other.second == second) &&
            const DeepCollectionEquality().equals(
              other._annotations,
              _annotations,
            ));
  }

  @override
  int get hashCode => Object.hash(
    runtimeType,
    patientId,
    recordingId,
    year,
    month,
    day,
    hour,
    minute,
    second,
    const DeepCollectionEquality().hash(_annotations),
  );

  /// Create a copy of EdfExportParams
  /// with the given fields replaced by the non-null parameter values.
  @JsonKey(includeFromJson: false, includeToJson: false)
  @override
  @pragma('vm:prefer-inline')
  _$$EdfExportParamsImplCopyWith<_$EdfExportParamsImpl> get copyWith =>
      __$$EdfExportParamsImplCopyWithImpl<_$EdfExportParamsImpl>(
        this,
        _$identity,
      );
}

abstract class _EdfExportParams implements EdfExportParams {
  const factory _EdfExportParams({
    required final String patientId,
    required final String recordingId,
    required final int year,
    required final int month,
    required final int day,
    required final int hour,
    required final int minute,
    required final int second,
    required final List<EdfExportAnnotation> annotations,
  }) = _$EdfExportParamsImpl;

  @override
  String get patientId;
  @override
  String get recordingId;
  @override
  int get year;
  @override
  int get month;
  @override
  int get day;
  @override
  int get hour;
  @override
  int get minute;
  @override
  int get second;
  @override
  List<EdfExportAnnotation> get annotations;

  /// Create a copy of EdfExportParams
  /// with the given fields replaced by the non-null parameter values.
  @override
  @JsonKey(includeFromJson: false, includeToJson: false)
  _$$EdfExportParamsImplCopyWith<_$EdfExportParamsImpl> get copyWith =>
      throw _privateConstructorUsedError;
}
