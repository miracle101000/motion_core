/// A unified stream of fused device-motion data backed by iOS Core Motion
/// (`CMDeviceMotion`) and Android's sensor-fusion virtual sensors
/// (`TYPE_ROTATION_VECTOR` / `TYPE_GAME_ROTATION_VECTOR`, `TYPE_GRAVITY`,
/// `TYPE_LINEAR_ACCELERATION`, `TYPE_GYROSCOPE`, `TYPE_MAGNETIC_FIELD`).
///
/// ## Conventions (identical on both platforms)
///
/// * **Device axes**: +X to the right of the screen (portrait), +Y toward the
///   top edge, +Z out of the screen toward the user. Right-handed.
/// * **World axes** (for [AttitudeReferenceFrame.magneticNorthZVertical] and
///   [AttitudeReferenceFrame.trueNorthZVertical]): East-North-Up. +X east,
///   +Y north, +Z up. For the arbitrary frames only +Z is fixed (up).
/// * **Attitude**: a unit quaternion that rotates device-frame vectors into
///   world-frame vectors. Identity means the device lies flat, face up, with
///   its top edge pointing north (ENU frames).
/// * **Gravity / user acceleration**: metres per second squared, in the
///   device frame, using the Android / `sensors_plus` sign convention. A device
///   lying flat, face up reports `gravity ≈ (0, 0, +9.81)`. `userAcceleration`
///   is positive in the direction the device is actually accelerating.
/// * **Rotation rate**: radians per second around the device axes, positive
///   counter-clockwise (right-hand rule).
/// * **Magnetic field**: microteslas in the device frame, hard-iron
///   calibrated.
/// * **Angles**: radians unless the name says otherwise ([MotionData.heading]
///   is degrees, like the platform compass APIs).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart';

/// The world (reference) frame the [MotionData.attitude] is expressed in.
///
/// Every frame has +Z pointing up. They differ in how the horizontal axes are
/// anchored and, consequently, in whether the magnetometer is used.
///
/// | Frame | iOS (`CMAttitudeReferenceFrame`) | Android sensor |
/// |---|---|---|
/// | [arbitraryZVertical] | `xArbitraryZVertical` | `TYPE_GAME_ROTATION_VECTOR` |
/// | [arbitraryCorrectedZVertical] | `xArbitraryCorrectedZVertical` | `TYPE_GAME_ROTATION_VECTOR` (no exact equivalent) |
/// | [magneticNorthZVertical] | `xMagneticNorthZVertical` | `TYPE_ROTATION_VECTOR` |
/// | [trueNorthZVertical] | `xTrueNorthZVertical` | `TYPE_ROTATION_VECTOR` (magnetic; declination is not applied) |
///
/// If the requested frame is not available the platform falls back to the
/// closest one it has. The frame actually in use is reported on every sample
/// as [MotionData.referenceFrame].
///
/// The enum order is part of the platform-channel protocol: the index is sent
/// to and received from native code.
enum AttitudeReferenceFrame {
  /// Yaw is relative to an arbitrary horizontal direction fixed when the
  /// stream starts. Uses only the accelerometer and gyroscope, so it is the
  /// most battery-friendly option and never triggers compass calibration.
  /// Yaw may drift slowly over time.
  arbitraryZVertical,

  /// Like [arbitraryZVertical], but on iOS the magnetometer is used to correct
  /// yaw drift without referencing yaw to north. Android has no equivalent
  /// and uses the game rotation vector, reporting [arbitraryZVertical].
  arbitraryCorrectedZVertical,

  /// Yaw is referenced to magnetic north (+Y north, +X east). Uses the
  /// magnetometer. [MotionData.heading] is available.
  magneticNorthZVertical,

  /// Yaw is referenced to true (geographic) north. On iOS this needs location
  /// services to be enabled (and typically location authorization) so Core
  /// Motion can apply magnetic declination; without it the result equals
  /// [magneticNorthZVertical]. Android reports [magneticNorthZVertical].
  trueNorthZVertical;

  /// Whether yaw and [MotionData.heading] are referenced to north.
  bool get isNorthReferenced =>
      this == magneticNorthZVertical || this == trueNorthZVertical;

  static AttitudeReferenceFrame _fromIndex(num index) {
    final i = index.toInt();
    if (i < 0 || i >= values.length) {
      throw ArgumentError.value(index, 'index', 'Unknown reference frame');
    }
    return values[i];
  }
}

/// Calibration quality of a [CalibratedMagneticField].
///
/// Mirrors iOS `CMMagneticFieldCalibrationAccuracy` and Android's
/// `SENSOR_STATUS_*` values (`UNRELIABLE`/`NO_CONTACT` → [uncalibrated]).
enum MagneticFieldCalibrationAccuracy {
  /// The field has not been calibrated; hard-iron distortion may be present.
  uncalibrated(-1),
  low(0),
  medium(1),
  high(2);

  const MagneticFieldCalibrationAccuracy(this.rawValue);

  /// The value used by both native APIs (-1, 0, 1, 2).
  final int rawValue;

  static MagneticFieldCalibrationAccuracy fromRawValue(num raw) {
    for (final v in values) {
      if (v.rawValue == raw.toInt()) return v;
    }
    return uncalibrated;
  }
}

/// A calibrated magnetic-field reading in the device frame.
@immutable
class CalibratedMagneticField {
  const CalibratedMagneticField({required this.field, required this.accuracy});

  /// Magnetic field in microteslas along the device X, Y and Z axes.
  final Vector3 field;

  /// How well calibrated [field] is.
  final MagneticFieldCalibrationAccuracy accuracy;

  @override
  String toString() =>
      'CalibratedMagneticField(field: $field, accuracy: ${accuracy.name})';
}

/// One fused motion sample.
///
/// See the library documentation for the axis, unit and sign conventions.
@immutable
class MotionData {
  const MotionData({
    required this.attitude,
    required this.gravity,
    required this.userAcceleration,
    this.rotationRate,
    this.magneticField,
    this.headingAccuracy,
    this.referenceFrame = AttitudeReferenceFrame.magneticNorthZVertical,
    this.timestamp = 0,
  });

  /// Number of doubles in the native payload. Kept in sync with the Kotlin
  /// and Swift implementations.
  static const int payloadLength = 20;

  /// Decodes the flat native payload:
  ///
  /// ```
  /// [0..3]   attitude quaternion x, y, z, w
  /// [4..6]   gravity x, y, z                (m/s²)
  /// [7..9]   user acceleration x, y, z      (m/s²)
  /// [10]     heading accuracy (radians, <= 0 when unavailable)
  /// [11..13] rotation rate x, y, z          (rad/s, NaN when unavailable)
  /// [14..16] magnetic field x, y, z         (µT, NaN when unavailable)
  /// [17]     magnetic field calibration accuracy (-1, 0, 1, 2)
  /// [18]     reference frame index
  /// [19]     timestamp (seconds since boot)
  /// ```
  ///
  /// Payloads shorter than [payloadLength] (the 11-element layout used by
  /// motion_core 0.0.x) are accepted; the missing values are treated as
  /// unavailable.
  factory MotionData.fromList(List<double> data) {
    if (data.length < 11) {
      throw ArgumentError.value(
        data.length,
        'data.length',
        'MotionData payload must contain at least 11 elements.',
      );
    }
    double at(int i, [double fallback = double.nan]) =>
        i < data.length ? data[i] : fallback;

    final headingAccuracy = at(10, -1);
    final rx = at(11), ry = at(12), rz = at(13);
    final mx = at(14), my = at(15), mz = at(16);
    final frameIndex = at(18, 2);

    return MotionData(
      attitude: Quaternion(data[0], data[1], data[2], data[3]),
      gravity: Vector3(data[4], data[5], data[6]),
      userAcceleration: Vector3(data[7], data[8], data[9]),
      // Some devices report 0 instead of -1 when they do not estimate it; an
      // accuracy of exactly zero radians is not a real estimate.
      headingAccuracy: headingAccuracy > 0 ? headingAccuracy : null,
      rotationRate: rx.isNaN || ry.isNaN || rz.isNaN ? null : Vector3(rx, ry, rz),
      magneticField: mx.isNaN || my.isNaN || mz.isNaN
          ? null
          : CalibratedMagneticField(
              field: Vector3(mx, my, mz),
              accuracy: MagneticFieldCalibrationAccuracy.fromRawValue(
                at(17, -1).isNaN ? -1 : at(17, -1),
              ),
            ),
      referenceFrame: frameIndex.isNaN
          ? AttitudeReferenceFrame.magneticNorthZVertical
          : AttitudeReferenceFrame._fromIndex(frameIndex),
      timestamp: at(19, 0).isNaN ? 0 : at(19, 0),
    );
  }

  /// Device orientation as a unit quaternion rotating device-frame vectors
  /// into the world frame described by [referenceFrame].
  final Quaternion attitude;

  /// Gravity in m/s² in the device frame (flat, face up ≈ `(0, 0, 9.81)`).
  final Vector3 gravity;

  /// Acceleration the user imparts to the device in m/s², device frame,
  /// gravity removed. Positive in the direction of motion.
  final Vector3 userAcceleration;

  /// Bias-corrected angular velocity in rad/s around the device axes.
  ///
  /// `null` only on Android devices without a gyroscope.
  final Vector3? rotationRate;

  /// Calibrated magnetic field. `null` for the arbitrary reference frames
  /// (the magnetometer is not used) and on devices without a magnetometer.
  final CalibratedMagneticField? magneticField;

  /// Estimated accuracy of the heading in radians (smaller is better).
  ///
  /// Android only (`TYPE_ROTATION_VECTOR` `values[4]`), and only for
  /// north-referenced frames. `null` on iOS and when unavailable, including
  /// devices that report `0` because they do not estimate it.
  final double? headingAccuracy;

  /// The reference frame actually in use for this sample. May differ from
  /// the configured frame if the device lacks the required sensors.
  final AttitudeReferenceFrame referenceFrame;

  /// Sample time in seconds since device boot (monotonic, not wall-clock).
  /// Use differences between samples, not absolute values.
  final double timestamp;

  /// Compass heading of the device's +Y axis (its top edge) projected onto the
  /// horizontal plane, in degrees clockwise from north in `[0, 360)`.
  ///
  /// `null` unless [referenceFrame] is north-referenced. Ill-defined when the
  /// +Y axis is nearly vertical (device held upright in portrait); use
  /// [attitude] directly for augmented-reality style use cases.
  double? get heading {
    if (!referenceFrame.isNorthReferenced) return null;
    final x = attitude.x, y = attitude.y, z = attitude.z, w = attitude.w;
    // Second column of the rotation matrix: the device +Y axis in world (ENU).
    final east = 2 * (x * y - w * z);
    final north = 1 - 2 * (x * x + z * z);
    if (east == 0 && north == 0) return null;
    final degrees = math.atan2(east, north) * 180 / math.pi;
    return (degrees + 360) % 360;
  }

  /// Tait-Bryan angles `(pitch, roll, yaw)` in radians, i.e. the rotation
  /// about the device X, Y and Z axes respectively. See [pitch], [roll] and
  /// [yaw] for the exact conventions.
  Vector3 get eulerAngles => _eulerFromQuaternion(attitude);

  /// Rotation about the device X axis (side to side), range `(-π, π]`.
  ///
  /// Positive when the top edge tilts up toward the user; holding the phone
  /// upright in portrait gives ≈ +π/2.
  double get pitch => eulerAngles.x;

  /// Rotation about the device Y axis (top to bottom), range `[-π/2, π/2]`.
  ///
  /// Positive when the right edge tilts down. Gimbal lock occurs at ±π/2
  /// (device on its side, e.g. landscape held upright): use [attitude] there.
  double get roll => eulerAngles.y;

  /// Rotation about the device Z axis (through the screen), range `(-π, π]`.
  ///
  /// Positive counter-clockwise when viewed from above. For north-referenced
  /// frames yaw is 0 when the top edge points north and
  /// `heading ≈ (-yaw in degrees) mod 360`.
  double get yaw => eulerAngles.z;

  @override
  String toString() =>
      'MotionData(attitude: $attitude, gravity: $gravity, '
      'userAcceleration: $userAcceleration, rotationRate: $rotationRate, '
      'magneticField: $magneticField, heading: $heading, '
      'headingAccuracy: $headingAccuracy, referenceFrame: ${referenceFrame.name}, '
      'timestamp: $timestamp)';
}

/// Entry point of the plugin.
class MotionCore {
  MotionCore._();

  static const MethodChannel _methodChannel =
      MethodChannel('dev.flutter/motion_core_method_channel');

  static const EventChannel _eventChannel =
      EventChannel('dev.flutter/motion_core_event_channel');

  /// The update interval used unless [configure] changes it (≈60 Hz, the
  /// Core Motion default used by this plugin on both platforms).
  static const Duration defaultUpdateInterval = Duration(microseconds: 16667);

  static Stream<MotionData>? _motionStream;

  /// A broadcast stream of fused [MotionData] samples.
  ///
  /// Sensors start when the first listener subscribes and stop when the last
  /// one cancels, so cancel subscriptions you no longer need. If the device
  /// lacks the required sensors the stream emits a [PlatformException] with
  /// code `UNAVAILABLE` and closes; check [isAvailable] first to avoid that.
  ///
  /// Call [configure] before (or while) listening to change the reference
  /// frame or update rate.
  static Stream<MotionData> get motionStream {
    return _motionStream ??=
        _eventChannel.receiveBroadcastStream().map(_decodeEvent);
  }

  static MotionData _decodeEvent(dynamic event) {
    final List<double> values = event is List<double>
        ? event
        : (event as List<Object?>).cast<double>();
    return MotionData.fromList(values);
  }

  /// Whether fused device motion is available on this device.
  ///
  /// iOS: `CMMotionManager.isDeviceMotionAvailable`. Android: a rotation
  /// vector sensor (game, geomagnetic or full) plus gravity and linear
  /// acceleration sensors exist. Returns `false` on platforms without a
  /// native implementation instead of throwing.
  static Future<bool> isAvailable() async {
    try {
      return await _methodChannel.invokeMethod<bool>('isAvailable') ?? false;
    } on MissingPluginException {
      return false;
    }
  }

  /// The reference frames natively supported by this device.
  ///
  /// iOS: `CMMotionManager.availableAttitudeReferenceFrames()`. Android:
  /// [AttitudeReferenceFrame.arbitraryZVertical] when a game rotation vector
  /// exists and [AttitudeReferenceFrame.magneticNorthZVertical] when a
  /// (geomagnetic) rotation vector exists. Requesting an unlisted frame in
  /// [configure] is allowed; the platform falls back to the closest one.
  static Future<List<AttitudeReferenceFrame>> availableReferenceFrames() async {
    try {
      final raw = await _methodChannel
          .invokeListMethod<Object?>('availableReferenceFrames');
      return [
        for (final v in raw ?? const <Object?>[])
          if (v is num) AttitudeReferenceFrame._fromIndex(v),
      ];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Changes how motion data is produced. Only the parameters you pass are
  /// changed; the others keep their current value.
  ///
  /// * [updateInterval]: requested time between samples. This is a hint;
  ///   iOS caps device motion at about 100 Hz and Android 12+ caps at 200 Hz
  ///   unless the app holds `HIGH_SAMPLING_RATE_SENSORS`. Defaults to
  ///   [defaultUpdateInterval].
  /// * [referenceFrame]: see [AttitudeReferenceFrame]. Defaults to
  ///   [AttitudeReferenceFrame.magneticNorthZVertical].
  /// * [showsCalibrationDisplay]: iOS only. Whether Core Motion may show the
  ///   system compass-calibration prompt when a magnetic frame needs it.
  ///   Defaults to `true`. Ignored on Android.
  ///
  /// Takes effect immediately, restarting the sensors if the stream is
  /// active. The configuration lives in the native plugin, so it persists
  /// for the lifetime of the Flutter engine (including across hot restarts).
  static Future<void> configure({
    Duration? updateInterval,
    AttitudeReferenceFrame? referenceFrame,
    bool? showsCalibrationDisplay,
  }) async {
    if (updateInterval != null && updateInterval <= Duration.zero) {
      throw ArgumentError.value(
        updateInterval,
        'updateInterval',
        'must be greater than zero',
      );
    }
    final args = <String, Object?>{
      if (updateInterval != null)
        'updateIntervalMicros': updateInterval.inMicroseconds,
      if (referenceFrame != null) 'referenceFrame': referenceFrame.index,
      if (showsCalibrationDisplay != null)
        'showsCalibrationDisplay': showsCalibrationDisplay,
    };
    if (args.isEmpty) return;
    await _methodChannel.invokeMethod<void>('configure', args);
  }
}

/// Converts a device→world quaternion to Tait-Bryan angles about the device
/// X (pitch), Y (roll) and Z (yaw) axes, using the Z-Y'-X'' sequence
/// (`R = Rz(yaw) · Ry(roll) · Rx(pitch)`).
Vector3 _eulerFromQuaternion(Quaternion q) {
  final w = q.w, x = q.x, y = q.y, z = q.z;

  final sinpCosr = 2 * (w * x + y * z);
  final cospCosr = 1 - 2 * (x * x + y * y);
  final pitch = math.atan2(sinpCosr, cospCosr);

  final sinr = (2 * (w * y - z * x)).clamp(-1.0, 1.0);
  final roll = math.asin(sinr);

  final sinyCosr = 2 * (w * z + x * y);
  final cosyCosr = 1 - 2 * (y * y + z * z);
  final yaw = math.atan2(sinyCosr, cosyCosr);

  return Vector3(pitch, roll, yaw);
}
