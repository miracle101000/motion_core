
# motion_core

[![Pub Version](https://img.shields.io/pub/v/motion_core?color=blue&style=for-the-badge)](https://pub.dev/packages/motion_core)
[![License: MIT](https://img.shields.io/badge/License-MIT-purple.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20Android-green.svg?style=for-the-badge)](https://flutter.dev)

A Flutter plugin that provides a simple, high-performance, and unified stream of fused device motion data from native platform APIs.

---

## Overview

While Flutter provides access to raw sensors (via plugins like `sensors_plus`), there is no out-of-the-box equivalent to **iOS Core Motion** or **Android's fused sensor APIs**. To get a device's true orientation (attitude), developers typically need to implement complex sensor fusion algorithms (like Madgwick or Mahony filters) in Dart or build a native bridge.

`motion_core` **is that bridge**. It does the native work for you, exposing a single, clean stream of calibrated motion data by leveraging the best available technology on each platform, and it normalises the axes, units and reference frames so the numbers mean the same thing on iOS and Android.

### Features

*   ✅ **Unified Stream**: One `Stream<MotionData>` with identical conventions on both platforms.
*   🚀 **Native Performance**: iOS `CMDeviceMotion`; Android `TYPE_ROTATION_VECTOR` / `TYPE_GAME_ROTATION_VECTOR` plus the gravity, linear-acceleration, gyroscope and magnetometer sensors. Hardware-accelerated, battery-efficient fusion, no Dart-side filtering.
*   📦 **Complete Motion State** in one object:
    *   **Attitude** as a `Quaternion` (device → world).
    *   **Gravity** and **user acceleration** in m/s².
    *   **Rotation rate** (bias-corrected gyroscope, rad/s).
    *   **Calibrated magnetic field** (µT) with calibration accuracy.
    *   **Heading** in degrees, **heading accuracy** (Android), timestamp, and the reference frame in use.
    *   Convenience `pitch`, `roll`, `yaw` getters.
*   🧭 **Reference frame selection**: arbitrary (no compass, no drift correction), magnetic north or true north, mirroring `CMAttitudeReferenceFrame`.
*   ⏱️ **Configurable update rate**.
*   🛠️ `MotionCore.isAvailable()` and `MotionCore.availableReferenceFrames()` to check hardware support.

## Getting Started

### 1. Add to `pubspec.yaml`

```yaml
dependencies:
  flutter:
    sdk: flutter
  motion_core: ^0.1.0
  vector_math: ^2.1.4   # for Quaternion / Vector3
```

### 2. Install

```sh
flutter pub get
```

## Platform Specific Setup

### iOS

*   iOS 12 or later. Works with Swift Package Manager (Flutter 3.24+) and CocoaPods.
*   `CMMotionManager` itself does not need a permission, but adding `NSMotionUsageDescription` to `ios/Runner/Info.plist` is recommended (it is required as soon as your app touches any other Core Motion API such as the pedometer or activity manager):

    ```xml
    <key>NSMotionUsageDescription</key>
    <string>This app uses motion data to determine device orientation and movement.</string>
    ```
*   `AttitudeReferenceFrame.trueNorthZVertical` needs location services (and usually location authorization) so Core Motion can apply magnetic declination. Without it the result equals magnetic north.
*   The magnetic frames may show the system compass-calibration prompt; disable it with `configure(showsCalibrationDisplay: false)`.

### Android

*   Minimum API 21. **No permissions are required.**
*   Requires Flutter 3.44 or newer. The plugin does not apply the Kotlin Gradle Plugin, so it is ready for Android Gradle Plugin 9's built-in Kotlin (see Flutter's [migration guide](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers)).
*   Requesting more than 200 Hz on Android 12+ requires the `HIGH_SAMPLING_RATE_SENSORS` permission; otherwise the system silently caps the rate.

## Usage

```dart
import 'dart:async';
import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:motion_core/motion_core.dart';
import 'package:vector_math/vector_math_64.dart' as v;

class MotionDemoScreen extends StatefulWidget {
  const MotionDemoScreen({super.key});

  @override
  State<MotionDemoScreen> createState() => _MotionDemoScreenState();
}

class _MotionDemoScreenState extends State<MotionDemoScreen> {
  MotionData? _motionData;
  StreamSubscription<MotionData>? _subscription;
  bool _isAvailable = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final available = await MotionCore.isAvailable();
    if (!mounted) return;
    setState(() => _isAvailable = available);
    if (!available) return;

    // Optional: pick a frame and rate before listening.
    await MotionCore.configure(
      referenceFrame: AttitudeReferenceFrame.magneticNorthZVertical,
      updateInterval: const Duration(milliseconds: 16),
    );

    _subscription = MotionCore.motionStream.listen(
      (data) => setState(() => _motionData = data),
      onError: (Object e) => debugPrint('motion error: $e'),
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = _motionData;
    if (!_isAvailable) return const Center(child: Text('No motion sensors'));
    if (data == null) return const Center(child: CircularProgressIndicator());

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..multiply(v.Matrix4.fromQuaternion(data.attitude)),
          alignment: FractionalOffset.center,
          child: const SizedBox(width: 150, height: 150, child: ColoredBox(color: Colors.blue)),
        ),
        Text('Pitch: ${(data.pitch * 180 / pi).toStringAsFixed(1)}°'),
        Text('Roll: ${(data.roll * 180 / pi).toStringAsFixed(1)}°'),
        Text('Yaw: ${(data.yaw * 180 / pi).toStringAsFixed(1)}°'),
        Text('Heading: ${data.heading?.toStringAsFixed(0) ?? 'n/a'}°'),
      ],
    );
  }
}
```

### Managing the Stream

`motionStream` is a **broadcast stream**. The native sensors start when the first listener subscribes and stop when the last one cancels, so always cancel subscriptions you no longer need.

```dart
_subscription?.pause();   // stop receiving (sensors keep running)
_subscription?.resume();
_subscription?.cancel();  // last cancel releases the sensors
```

If the device lacks the required sensors the stream emits a `PlatformException` with code `UNAVAILABLE` and closes. Check `MotionCore.isAvailable()` first to avoid that.

### Configuration

```dart
await MotionCore.configure(
  updateInterval: const Duration(milliseconds: 10),          // hint, ~100 Hz
  referenceFrame: AttitudeReferenceFrame.arbitraryZVertical,  // no magnetometer
  showsCalibrationDisplay: false,                             // iOS only
);
```

`configure` can be called before or while listening; the sensors restart with the new settings. Only the parameters you pass are changed. The configuration lives in the native plugin, so it persists for the life of the Flutter engine.

| Frame | iOS `CMAttitudeReferenceFrame` | Android sensor | Heading |
| --- | --- | --- | --- |
| `arbitraryZVertical` | `xArbitraryZVertical` | `TYPE_GAME_ROTATION_VECTOR` | `null` |
| `arbitraryCorrectedZVertical` | `xArbitraryCorrectedZVertical` | `TYPE_GAME_ROTATION_VECTOR` (reports `arbitraryZVertical`) | `null` |
| `magneticNorthZVertical` (default) | `xMagneticNorthZVertical` | `TYPE_ROTATION_VECTOR` (`TYPE_GEOMAGNETIC_ROTATION_VECTOR` fallback) | ✅ |
| `trueNorthZVertical` | `xTrueNorthZVertical` | `TYPE_ROTATION_VECTOR` (reports `magneticNorthZVertical`) | ✅ |

If the requested frame is not available the platform falls back to the closest one and reports the frame actually used in `MotionData.referenceFrame`. `MotionCore.availableReferenceFrames()` lists what the device supports natively.

## Conventions

These are identical on both platforms.

*   **Device axes**: +X to the right of the screen (portrait), +Y toward the top edge, +Z out of the screen toward the user. Right-handed.
*   **World axes** (north-referenced frames): East-North-Up. +X east, +Y north, +Z up. The arbitrary frames only fix +Z.
*   **Attitude**: unit quaternion that rotates device-frame vectors into the world frame. Identity = flat, face up, top edge pointing north. Use `Matrix4.fromQuaternion(data.attitude)` from `vector_math` to render it.
*   **Gravity / user acceleration**: m/s², device frame, Android / `sensors_plus` sign convention. Flat face-up device: `gravity ≈ (0, 0, +9.81)`. `userAcceleration` is positive in the direction the device is moving. (Core Motion's G-unit, opposite-sign values are converted natively.)
*   **Rotation rate**: rad/s about the device axes, positive counter-clockwise (right-hand rule).
*   **Magnetic field**: µT, device frame, hard-iron calibrated.
*   **Euler angles** (`pitch`, `roll`, `yaw`, radians): Tait-Bryan Z-Y'-X''. `pitch` = rotation about device X (+π/2 when the phone is held upright in portrait, range ±π), `roll` = rotation about device Y (range ±π/2, gimbal lock when the device is on its side), `yaw` = rotation about Z (positive counter-clockwise from above; 0 = top edge pointing north for north-referenced frames). Prefer the quaternion for anything that needs full orientation.
*   **Heading**: degrees clockwise from north of the device's +Y axis projected onto the horizontal plane, `[0, 360)`. Ill-defined when the device is upright in portrait.

## API Details

### `MotionData`

| Property | Type | Description |
| --- | --- | --- |
| `attitude` | `Quaternion` | Device orientation, device → world. |
| `gravity` | `Vector3` | Gravity in m/s², device frame. |
| `userAcceleration` | `Vector3` | Acceleration imparted by the user in m/s², gravity removed. |
| `rotationRate` | `Vector3?` | Bias-corrected angular velocity in rad/s. `null` only on Android devices without a gyroscope. |
| `magneticField` | `CalibratedMagneticField?` | Field in µT plus `MagneticFieldCalibrationAccuracy` (`uncalibrated`, `low`, `medium`, `high`). `null` for arbitrary frames or without a magnetometer. |
| `heading` | `double?` | Compass heading in degrees `[0, 360)`. `null` for arbitrary frames. |
| `headingAccuracy` | `double?` | **Android only.** Estimated heading accuracy in radians (smaller is better). `null` on iOS and on devices that do not estimate it. |
| `referenceFrame` | `AttitudeReferenceFrame` | The frame actually in use for this sample. |
| `timestamp` | `double` | Seconds since boot (monotonic). Use differences between samples. |
| `pitch`, `roll`, `yaw` | `double` | Euler angles in radians, see [Conventions](#conventions). |
| `eulerAngles` | `Vector3` | `(pitch, roll, yaw)`. |

### `MotionCore`

| Member | Description |
| --- | --- |
| `motionStream` | Broadcast `Stream<MotionData>`. |
| `isAvailable()` | Whether fused device motion is available. `false` on unsupported platforms. |
| `availableReferenceFrames()` | Frames the device supports natively. |
| `configure(...)` | Update rate, reference frame, iOS calibration prompt. |
| `defaultUpdateInterval` | ≈ 60 Hz. |

### Platform mapping

| `MotionData` | iOS (`CMDeviceMotion`) | Android |
| --- | --- | --- |
| `attitude` | `attitude.quaternion`, rotated into ENU | `TYPE_ROTATION_VECTOR` / `TYPE_GAME_ROTATION_VECTOR` / `TYPE_GEOMAGNETIC_ROTATION_VECTOR` |
| `gravity` | `gravity` × −9.80665 | `TYPE_GRAVITY` |
| `userAcceleration` | `userAcceleration` × −9.80665 | `TYPE_LINEAR_ACCELERATION` |
| `rotationRate` | `rotationRate` | `TYPE_GYROSCOPE` |
| `magneticField` | `magneticField` | `TYPE_MAGNETIC_FIELD` + sensor accuracy |
| `headingAccuracy` | — | rotation vector `values[4]` |
| `timestamp` | `timestamp` | `SensorEvent.timestamp` |
| update interval | `deviceMotionUpdateInterval` | `registerListener` sampling period |

## Migrating from 0.0.x

*   Gravity and user acceleration on **iOS** are now in m/s² with the opposite sign (multiply your old values by −9.80665). Android values are unchanged.
*   Yaw on **iOS** is now north-referenced by default and rotated so that `yaw == 0` means "top edge pointing north" on both platforms. Use `AttitudeReferenceFrame.arbitraryZVertical` to get the old battery-friendly behaviour.
*   `pitch` and `roll` were swapped; if you relied on the old getters, swap them back in your code. `eulerAngles.x/.y/.z` are unchanged.
*   `headingAccuracy` is nullable (`null` instead of `-1.0`).
*   Android now emits data as soon as the sensors report, instead of waiting for high compass accuracy. Inspect `headingAccuracy` / `magneticField.accuracy` if you need to gate on quality.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Author

Built by **Miracle Okolo** · [LinkedIn](https://www.linkedin.com/in/miracle-okolo-bb2133183/) · [GitHub](https://github.com/miracle101000)
