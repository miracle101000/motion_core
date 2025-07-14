
# motion_core

[![Pub Version](https://img.shields.io/pub/v/motion_core?color=blue&style=for-the-badge)](https://pub.dev/packages/motion_core)
[![License: MIT](https://img.shields.io/badge/License-MIT-purple.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20Android-green.svg?style=for-the-badge)](https://flutter.dev)

A Flutter plugin that provides a simple, high-performance, and unified stream of fused device motion data from native platform APIs.

---

<p align="center">
  <!-- TODO: Add a GIF of the example app in action -->
  <img src="https://i.imgur.com/your-demo-gif.gif" alt="motion_core demo" width="300"/>
</p>

## Overview

While Flutter provides access to raw sensors (via plugins like `sensors_plus`), there is no out-of-the-box equivalent to **iOS Core Motion** or **Android's Fused Sensor APIs**. To get a device's true orientation (attitude), developers typically need to implement complex sensor fusion algorithms (like Madgwick or Mahony filters) in Dart or build a native bridge.

`motion_core` **is that bridge**. It does the native work for you, exposing a single, clean stream of calibrated motion data by leveraging the best available technology on each platform.

### Features

*   ✅ **Unified Stream**: Get a single `Stream<MotionData>` that works seamlessly on both iOS and Android.
*   🚀 **Native Performance**: Leverages iOS `CoreMotion` (CMDeviceMotion) and Android's `TYPE_ROTATION_VECTOR` for battery-efficient, low-latency, hardware-accelerated fusion.
*   📦 **Comprehensive Motion Data**: Provides the complete motion state in one object:
    *   **Attitude**: Device orientation as a `Quaternion`.
    *   **Gravity**: A `Vector3` representing the direction of gravity.
    *   **User Acceleration**: A `Vector3` of acceleration applied by the user, with gravity removed.
    *   **Heading Accuracy**: The estimated accuracy of the compass heading (in radians) on Android.
*   🛠️ **Sensor Availability Check**: A simple async utility (`MotionCore.isAvailable()`) to check if the device has the necessary hardware.

## Getting Started

### 1. Add to `pubspec.yaml`

Add `motion_core` and `vector_math` to your project's dependencies.

```yaml
dependencies:
  flutter:
    sdk: flutter
  motion_core: ^1.0.0 # Use the latest version from pub.dev
  vector_math: ^2.1.4
```

### 2. Install

Run the following command in your terminal:

```sh
flutter pub get
```

## Platform Specific Setup

This plugin requires platform-specific configuration to access motion data.

### iOS (Mandatory)

You **must** add a usage description to your `ios/Runner/Info.plist` file. Without this, your app will crash on recent iOS versions when trying to access motion data and will be rejected by the App Store.

Open `ios/Runner/Info.plist` and add the following:

```xml
<key>NSMotionUsageDescription</key>
<string>This app requires access to motion data to determine device orientation and movement.</string>
```

> **Warning**
> Failure to add the `NSMotionUsageDescription` key will result in a runtime crash. This is not optional.

### Android

**No permissions are required.**

Access to the standard motion sensors (accelerometer, gyroscope, etc.) on Android does not require any special permissions in your `AndroidManifest.xml`.

## Usage

Here is a complete example demonstrating how to use the plugin.

### Basic Example

```dart
import 'dart:async';
import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:motion_core/motion_core.dart';
import 'package:vector_math/vector_math_64.dart' as v;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: MotionDemoScreen(),
      theme: ThemeData.dark(),
    );
  }
}

class MotionDemoScreen extends StatefulWidget {
  const MotionDemoScreen({super.key});

  @override
  State<MotionDemoScreen> createState() => _MotionDemoScreenState();
}

class _MotionDemoScreenState extends State<MotionDemoScreen> {
  MotionData? _motionData;
  StreamSubscription? _motionSubscription;
  bool _isAvailable = false;

  @override
  void initState() {
    super.initState();
    _checkAvailabilityAndStart();
  }

  Future<void> _checkAvailabilityAndStart() async {
    bool available = await MotionCore.isAvailable();
    if (!mounted) return;

    setState(() {
      _isAvailable = available;
    });

    if (_isAvailable) {
      _startListening();
    }
  }

  void _startListening() {
    _motionSubscription = MotionCore.motionStream.listen((MotionData data) {
      if (mounted) {
        setState(() {
          _motionData = data;
        });
      }
    });
  }

  @override
  void dispose() {
    _motionSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Motion Core Demo')),
      body: Center(
        child: !_isAvailable
            ? const Text('Required motion sensors are not available.')
            : _motionData == null
                ? const CircularProgressIndicator()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // 3D Box visualizer
                      Transform(
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.001) // perspective
                          ..multiply(v.Matrix4.fromQuaternion(_motionData!.attitude)),
                        alignment: FractionalOffset.center,
                        child: Container(
                          width: 150,
                          height: 150,
                          decoration: BoxDecoration(
                            color: Colors.blueAccent.withOpacity(0.8),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                          child: const Center(child: Text('FRONT', style: TextStyle(fontWeight: FontWeight.bold))),
                        ),
                      ),
                      const SizedBox(height: 30),
                      // Data table
                      Text('Pitch: ${(_motionData!.pitch * 180 / pi).toStringAsFixed(1)}°'),
                      Text('Roll: ${(_motionData!.roll * 180 / pi).toStringAsFixed(1)}°'),
                      Text('Yaw: ${(_motionData!.yaw * 180 / pi).toStringAsFixed(1)}°'),
                    ],
                  ),
      ),
    );
  }
}
```

### Managing the Stream

The `motionStream` is a **broadcast stream**. It is important to manage your subscription according to your widget's lifecycle.

```dart
// Pause updates when the widget is not visible
_motionSubscription?.pause();

// Resume updates when the widget is visible again
_motionSubscription?.resume();

// Stop listening completely to prevent memory leaks
_motionSubscription?.cancel();
```

## API Details

### The `MotionData` Object

The stream provides `MotionData` objects, which contain the following properties:

| Property           | Type          | Description                                                                    |
| ------------------ | ------------- | ------------------------------------------------------------------------------ |
| `attitude`         | `Quaternion`  | The device's orientation in 3D space.                                          |
| `gravity`          | `Vector3`     | The gravity vector, indicating the direction of gravity relative to the device.|
| `userAcceleration` | `Vector3`     | The acceleration applied by the user, with the effect of gravity removed.      |
| `headingAccuracy`  | `double?`     | **Android only.** The estimated accuracy of the heading in radians. `null` on iOS. |
| `pitch`            | `double`      | A convenience getter for the pitch angle (in radians) from the attitude.       |
| `roll`             | `double`      | A convenience getter for the roll angle (in radians) from the attitude.        |
| `yaw`              | `double`      | A convenience getter for the yaw angle (in radians) from the attitude.         |

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.