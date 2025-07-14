### `README.md`

```markdown
# motion_core

[![Pub Version](https://img.shields.io/pub/v/motion_core?color=blue&style=for-the-badge)](https://pub.dev/packages/motion_core)
[![License: MIT](https://img.shields.io/badge/License-MIT-purple.svg?style=for-the-badge)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/Platform-iOS%20%7C%20Android-green.svg?style=for-the-badge)](https://flutter.dev)

A Flutter plugin that provides a simple, high-performance, and unified stream of fused device motion data from native platform APIs.

## Why `motion_core`?

While Flutter provides access to raw sensors (via plugins like `sensors_plus`), there is no out-of-the-box equivalent to **iOS Core Motion** or **Android's Fused Sensor APIs**. To get a device's true orientation (attitude), you either need to implement complex sensor fusion algorithms (like Madgwick or Mahony filters) in Dart or build a native bridge.

`motion_core` **is that bridge**. It does the native work for you, exposing a single, clean stream of calibrated motion data by leveraging the best available technology on each platform.

### Features

*   **Unified Stream**: Get a single `Stream<MotionData>` that works seamlessly on both iOS and Android.
*   **Native Performance**: Leverages iOS `CoreMotion` (CMDeviceMotion) and Android's `TYPE_ROTATION_VECTOR`, `TYPE_GRAVITY`, and `TYPE_LINEAR_ACCELERATION` sensors for battery-efficient, low-latency, hardware-accelerated fusion.
*   **Rich Data Payload**: Provides the complete motion state in one object:
    *   **Attitude**: Device orientation as a `Quaternion`.
    *   **Gravity**: A `Vector3` representing the direction of gravity.
    *   **User Acceleration**: A `Vector3` of acceleration applied by the user, with gravity removed.
    *   **Heading Accuracy**: The estimated accuracy of the compass heading (in radians) on Android.
*   **Sensor Availability Check**: A simple async utility (`MotionCore.isAvailable()`) to check if the device has the necessary hardware.

---

## Getting Started

### 1. Installation

Add `motion_core` and `vector_math` to your `pubspec.yaml` dependencies.

```yaml
dependencies:
  flutter:
    sdk: flutter
  motion_core: ^1.0.0 # Replace with the latest version
  vector_math: ^2.1.4
```

Then, run `flutter pub get`.

---

## Required Native Permissions & Setup

This plugin requires platform-specific configuration to access motion data.

### iOS (Mandatory)

You **must** add a usage description to your `ios/Runner/Info.plist` file. Without this key, your app will crash at runtime on newer iOS versions when trying to access motion data, and it will be rejected by the App Store during review.

Open `ios/Runner/Info.plist` and add the following keys and strings:

```xml
<key>NSMotionUsageDescription</key>
<string>This app requires access to motion data to determine device orientation and movement.</string>
```



### Android

**No permissions are required.**

Access to the standard motion sensors (accelerometer, gyroscope, etc.) on Android does not require any special permissions in `AndroidManifest.xml`. The system grants access by default. You do not need to add anything for this plugin to work.

---

## Usage

Here is a full example of how to use the plugin in a Flutter widget.

```dart
import 'dart:async';
import 'dart:math' show pi;
import 'package:flutter/material.dart';
import 'package:motion_core/motion_core.dart';
import 'package:vector_math/vector_math_64.dart' as v;

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: MotionDemoScreen(),
      theme: ThemeData.dark(),
    );
  }
}

class MotionDemoScreen extends StatefulWidget {
  const MotionDemoScreen({Key? key}) : super(key: key);

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

The `motionStream` is a broadcast stream. You can control your subscription to pause, resume, or cancel updates as needed.

```dart
// Pause updates
_motionSubscription?.pause();

// Resume updates
_motionSubscription?.resume();

// Stop listening completely (usually in dispose)
_motionSubscription?.cancel();
```