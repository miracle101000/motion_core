import 'dart:math';

import 'dart:async';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart';

/// A data class to hold the full set of fused motion data.
///
/// This includes the device's orientation (attitude) as a quaternion,
/// the isolated gravity vector, the user-generated acceleration (free from gravity),
/// and the heading accuracy from the underlying sensor.
class MotionData {
  /// The orientation of the device as a Quaternion.
  final Quaternion attitude;

  /// The gravity vector, indicating the direction and magnitude of gravity.
  final Vector3 gravity;

  /// The acceleration applied by the user to the device, isolated from gravity.
  final Vector3 userAcceleration;

  /// The accuracy of the heading value, primarily from Android's ROTATION_VECTOR.
  ///
  /// On Android, this corresponds to `SensorEvent.values[4]` and is given in radians.
  /// A lower number indicates better accuracy.
  /// On iOS, this value is not directly provided and will be a placeholder (-1.0).
  final double headingAccuracy;

  MotionData({
    required this.attitude,
    required this.gravity,
    required this.userAcceleration,
    required this.headingAccuracy,
  });

  /// Creates a MotionData object from a list of 11 doubles.
  /// The expected order is [q_x, q_y, q_z, q_w, g_x, g_y, g_z, a_x, a_y, a_z, accuracy].
  factory MotionData.fromList(List<double> data) {
    assert(data.length == 11, "Input list for MotionData must have 11 elements.");
    return MotionData(
      attitude: Quaternion(data[0], data[1], data[2], data[3]),
      gravity: Vector3(data[4], data[5], data[6]),
      userAcceleration: Vector3(data[7], data[8], data[9]),
      headingAccuracy: data[10],
    );
  }

  @override
  String toString() {
    return 'MotionData(attitude: $attitude, gravity: $gravity, userAcceleration: $userAcceleration, headingAccuracy: $headingAccuracy)';
  }
}

/// The main class for accessing the `motion_core` plugin.
class MotionCore {
  /// The method channel used to call utility functions on the native side.
  static const MethodChannel _methodChannel =
      MethodChannel('dev.flutter/motion_core_method_channel');

  /// The event channel used to receive fused sensor data from the native side.
  static const EventChannel _eventChannel =
      EventChannel('dev.flutter/motion_core_event_channel');

  /// A broadcast stream of [MotionData] events.
  static Stream<MotionData>? _motionStream;

  static Stream<MotionData> get motionStream {
    _motionStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((dynamic event) => MotionData.fromList(event.cast<double>()));
    return _motionStream!;
  }

  /// Checks if the necessary sensors for fusion are available on the device.
  static Future<bool> isAvailable() async {
    final bool? available = await _methodChannel.invokeMethod('isAvailable');
    return available ?? false;
  }
}

/// Extension to expose yaw, pitch, roll from the fused quaternion.
extension MotionDataEuler on MotionData {
  Vector3 get eulerAngles => _eulerFromQuaternion(attitude);

  /// Roll = rotation around X-axis
  double get roll => eulerAngles.x;

  /// Pitch = rotation around Y-axis
  double get pitch => eulerAngles.y;

  /// Yaw = rotation around Z-axis
  double get yaw => eulerAngles.z;
}

/// Converts a quaternion to Euler angles (roll, pitch, yaw) in radians.
Vector3 _eulerFromQuaternion(Quaternion q) {
  final w = q.w, x = q.x, y = q.y, z = q.z;

  final sinrCosp = 2 * (w * x + y * z);
  final cosrCosp = 1 - 2 * (x * x + y * y);
  final roll = atan2(sinrCosp, cosrCosp);

  var sinp = 2 * (w * y - z * x);
  sinp = sinp.clamp(-1.0, 1.0); // prevent NaN in asin
  final pitch = asin(sinp);

  final sinyCosp = 2 * (w * z + x * y);
  final cosyCosp = 1 - 2 * (y * y + z * z);
  final yaw = atan2(sinyCosp, cosyCosp);

  return Vector3(roll, pitch, yaw);
}
