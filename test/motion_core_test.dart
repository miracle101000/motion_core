import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:motion_core/motion_core.dart';
import 'package:vector_math/vector_math_64.dart';

/// Builds a full 20-double payload for a device->world quaternion.
Float64List payloadFor(
  Quaternion q, {
  int frame = 2,
  List<double> gravity = const [0, 0, 9.81],
  List<double> userAcceleration = const [0, 0, 0],
  double headingAccuracy = -1,
  List<double>? rotationRate = const [0, 0, 0],
  List<double>? magneticField,
  double magneticAccuracy = -1,
  double timestamp = 0,
}) {
  const nan = double.nan;
  return Float64List.fromList([
    q.x, q.y, q.z, q.w,
    ...gravity,
    ...userAcceleration,
    headingAccuracy,
    ...(rotationRate ?? const [nan, nan, nan]),
    ...(magneticField ?? const [nan, nan, nan]),
    magneticField == null ? nan : magneticAccuracy,
    frame.toDouble(),
    timestamp,
  ]);
}

Quaternion rotation(Vector3 axis, double degrees) =>
    Quaternion.axisAngle(axis, degrees * math.pi / 180);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MotionData.fromList', () {
    test('decodes the full payload', () {
      final data = MotionData.fromList(payloadFor(
        Quaternion.identity(),
        gravity: [0.1, 0.2, 9.7],
        userAcceleration: [1, 2, 3],
        headingAccuracy: 0.05,
        rotationRate: [4, 5, 6],
        magneticField: [10, 20, 30],
        magneticAccuracy: 1,
        frame: 2,
        timestamp: 12.5,
      ));

      expect(data.attitude.w, 1);
      expect(data.gravity, Vector3(0.1, 0.2, 9.7));
      expect(data.userAcceleration, Vector3(1, 2, 3));
      expect(data.headingAccuracy, 0.05);
      expect(data.rotationRate, Vector3(4, 5, 6));
      expect(data.magneticField!.field, Vector3(10, 20, 30));
      expect(
        data.magneticField!.accuracy,
        MagneticFieldCalibrationAccuracy.medium,
      );
      expect(data.referenceFrame, AttitudeReferenceFrame.magneticNorthZVertical);
      expect(data.timestamp, 12.5);
    });

    test('maps sentinels to null', () {
      final data = MotionData.fromList(payloadFor(
        Quaternion.identity(),
        headingAccuracy: -1,
        rotationRate: null,
        magneticField: null,
      ));

      expect(data.headingAccuracy, isNull);
      expect(data.rotationRate, isNull);
      expect(data.magneticField, isNull);
    });

    test('treats a zero heading accuracy as unavailable', () {
      // Some Android devices report 0 instead of -1 when not estimated.
      final data = MotionData.fromList(
        payloadFor(Quaternion.identity(), headingAccuracy: 0),
      );
      expect(data.headingAccuracy, isNull);
    });

    test('accepts the legacy 11-element payload', () {
      final data = MotionData.fromList(
        const [0, 0, 0, 1, 0, 0, 9.81, 0, 0, 0, -1],
      );

      expect(data.attitude.w, 1);
      expect(data.rotationRate, isNull);
      expect(data.magneticField, isNull);
      expect(data.headingAccuracy, isNull);
      expect(data.referenceFrame, AttitudeReferenceFrame.magneticNorthZVertical);
    });

    test('rejects payloads that are too short', () {
      expect(() => MotionData.fromList(const [1, 2, 3]), throwsArgumentError);
    });

    test('reports the effective reference frame', () {
      final data = MotionData.fromList(payloadFor(Quaternion.identity(), frame: 0));
      expect(data.referenceFrame, AttitudeReferenceFrame.arbitraryZVertical);
    });
  });

  group('heading', () {
    MotionData sample(Quaternion q, {int frame = 2}) =>
        MotionData.fromList(payloadFor(q, frame: frame));

    test('is 0 when the top edge points north', () {
      expect(sample(Quaternion.identity()).heading, closeTo(0, 1e-9));
    });

    test('is 90 when the top edge points east', () {
      // Turning the device clockwise (seen from above) is a negative rotation about Z.
      expect(sample(rotation(Vector3(0, 0, 1), -90)).heading, closeTo(90, 1e-9));
    });

    test('is 315 when the top edge points north-west', () {
      expect(sample(rotation(Vector3(0, 0, 1), 45)).heading, closeTo(315, 1e-9));
    });

    test('is stable when the device is tilted', () {
      // Tilt the top edge up 30° while pointing east.
      final q = rotation(Vector3(0, 0, 1), -90) * rotation(Vector3(1, 0, 0), 30);
      expect(sample(q).heading, closeTo(90, 1e-9));
    });

    test('is null for arbitrary frames', () {
      expect(sample(Quaternion.identity(), frame: 0).heading, isNull);
      expect(sample(Quaternion.identity(), frame: 1).heading, isNull);
    });

    test('is available for the true-north frame', () {
      expect(sample(Quaternion.identity(), frame: 3).heading, closeTo(0, 1e-9));
    });
  });

  group('euler angles', () {
    MotionData sample(Quaternion q) => MotionData.fromList(payloadFor(q));

    test('are zero for the identity attitude', () {
      final d = sample(Quaternion.identity());
      expect(d.pitch, closeTo(0, 1e-9));
      expect(d.roll, closeTo(0, 1e-9));
      expect(d.yaw, closeTo(0, 1e-9));
    });

    test('pitch is +90° when the phone is held upright in portrait', () {
      final d = sample(rotation(Vector3(1, 0, 0), 90));
      expect(d.pitch, closeTo(math.pi / 2, 1e-9));
      expect(d.roll, closeTo(0, 1e-9));
      expect(d.yaw, closeTo(0, 1e-9));
    });

    test('roll is the rotation about the device Y axis', () {
      final d = sample(rotation(Vector3(0, 1, 0), 30));
      expect(d.pitch, closeTo(0, 1e-9));
      expect(d.roll, closeTo(30 * math.pi / 180, 1e-9));
      expect(d.yaw, closeTo(0, 1e-9));
    });

    test('yaw is the rotation about the device Z axis', () {
      final d = sample(rotation(Vector3(0, 0, 1), 45));
      expect(d.yaw, closeTo(math.pi / 4, 1e-9));
      expect(d.pitch, closeTo(0, 1e-9));
      expect(d.roll, closeTo(0, 1e-9));
    });

    test('eulerAngles packs (pitch, roll, yaw)', () {
      final d = sample(rotation(Vector3(1, 0, 0), 10));
      expect(d.eulerAngles.x, d.pitch);
      expect(d.eulerAngles.y, d.roll);
      expect(d.eulerAngles.z, d.yaw);
    });

    test('roll is clamped instead of producing NaN at gimbal lock', () {
      final d = sample(rotation(Vector3(0, 1, 0), 90));
      expect(d.roll, closeTo(math.pi / 2, 1e-6));
      expect(d.pitch.isNaN, isFalse);
      expect(d.yaw.isNaN, isFalse);
    });
  });

  group('MotionCore', () {
    const methodChannel = MethodChannel('dev.flutter/motion_core_method_channel');
    const eventChannel = EventChannel('dev.flutter/motion_core_event_channel');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];

    setUp(calls.clear);

    tearDown(() {
      messenger.setMockMethodCallHandler(methodChannel, null);
      messenger.setMockStreamHandler(eventChannel, null);
    });

    test('isAvailable forwards the native answer', () async {
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        calls.add(call);
        return true;
      });

      expect(await MotionCore.isAvailable(), isTrue);
      expect(calls.single.method, 'isAvailable');
    });

    test('isAvailable is false when there is no native implementation',
        () async {
      // No handler registered: the channel throws MissingPluginException.
      expect(await MotionCore.isAvailable(), isFalse);
    });

    test('availableReferenceFrames decodes indices', () async {
      messenger.setMockMethodCallHandler(methodChannel, (call) async => [0, 2]);

      expect(await MotionCore.availableReferenceFrames(), [
        AttitudeReferenceFrame.arbitraryZVertical,
        AttitudeReferenceFrame.magneticNorthZVertical,
      ]);
    });

    test('availableReferenceFrames is empty without a native implementation',
        () async {
      expect(await MotionCore.availableReferenceFrames(), isEmpty);
    });

    test('configure sends only the provided options', () async {
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        calls.add(call);
        return null;
      });

      await MotionCore.configure(
        updateInterval: const Duration(milliseconds: 20),
        referenceFrame: AttitudeReferenceFrame.arbitraryZVertical,
      );

      expect(calls.single.method, 'configure');
      expect(calls.single.arguments, {
        'updateIntervalMicros': 20000,
        'referenceFrame': 0,
      });
    });

    test('configure with no options does not hit the platform', () async {
      messenger.setMockMethodCallHandler(methodChannel, (call) async {
        calls.add(call);
        return null;
      });

      await MotionCore.configure();

      expect(calls, isEmpty);
    });

    test('configure rejects non-positive intervals', () {
      expect(
        () => MotionCore.configure(updateInterval: Duration.zero),
        throwsArgumentError,
      );
    });

    test('motionStream decodes Float64List payloads', () async {
      final payload = payloadFor(
        rotation(Vector3(0, 0, 1), -90),
        gravity: [0, 0, 9.81],
        rotationRate: [0.1, 0.2, 0.3],
        timestamp: 3,
      );
      messenger.setMockStreamHandler(
        eventChannel,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success(payload);
            events.endOfStream();
          },
        ),
      );

      final samples = await MotionCore.motionStream.toList();

      expect(samples, hasLength(1));
      expect(samples.single.heading, closeTo(90, 1e-9));
      expect(samples.single.rotationRate, Vector3(0.1, 0.2, 0.3));
      expect(samples.single.timestamp, 3);
    });
  });
}
