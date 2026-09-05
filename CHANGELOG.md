## 0.1.0

Bug-fix and feature-parity release. The native payload changed, so upgrade the
plugin as a whole (a hot restart is enough during development).

### Fixed

* **Android emitted nothing on many devices.** Samples were held back until the
  rotation vector reported `SENSOR_STATUS_ACCURACY_HIGH`, which many phones
  never do. Samples are now delivered as soon as the fused sensors have data.
* **Units and signs differed between platforms.** iOS sent G with gravity
  pointing down, Android sent m/s² with gravity pointing up. Both now report
  m/s² with the Android / `sensors_plus` sign convention (flat, face-up device
  ≈ `(0, 0, +9.81)`; `userAcceleration` positive in the direction of motion).
* **Yaw was not comparable between platforms.** iOS used the arbitrary
  reference frame while Android used the north-referenced rotation vector, and
  Core Motion's north frame puts +X on north where Android puts +Y. Both
  platforms now use a north-referenced East-North-Up frame by default.
* **`pitch` and `roll` were swapped** relative to the phone conventions used
  by both platform APIs. `pitch` is now the rotation about the device X axis
  (top edge up/down) and `roll` the rotation about the Y axis. `eulerAngles`
  is unchanged: `(x, y, z)` are still the angles about the device X, Y, Z axes.
* Sensors were never released when the Flutter engine was destroyed while a
  subscription was active (both platforms). The iOS plugin was not published
  to the registrar, so `detachFromEngine` could never run.
* Android read the heading accuracy from a fixed-size buffer instead of the
  event, so devices reporting fewer than five rotation-vector values produced
  `0.0` instead of "unavailable"; the quaternion could also be wrong when the
  scalar part was not reported.
* An unsupported platform (web, desktop) made `isAvailable()` throw
  `MissingPluginException`; it now returns `false`.
* The Android unit test targeted a method that does not exist; replaced with
  real tests for the method channel and payload encoding.
* Removed the deprecated `package` attribute from the Android manifest,
  fixed the Podspec metadata and bundled the iOS privacy manifest.

### Added

* `MotionCore.configure(updateInterval:, referenceFrame:, showsCalibrationDisplay:)`
  to pick the sample rate (both platforms) and the attitude reference frame:
  `arbitraryZVertical`, `arbitraryCorrectedZVertical`,
  `magneticNorthZVertical` (default) or `trueNorthZVertical`. Maps to
  `CMAttitudeReferenceFrame` on iOS and to `TYPE_GAME_ROTATION_VECTOR` /
  `TYPE_ROTATION_VECTOR` (with `TYPE_GEOMAGNETIC_ROTATION_VECTOR` as a
  fallback) on Android.
* `MotionCore.availableReferenceFrames()`.
* `MotionData.rotationRate` (bias-corrected gyroscope, rad/s).
* `MotionData.magneticField` (calibrated magnetometer in µT with
  `MagneticFieldCalibrationAccuracy`).
* `MotionData.heading` (degrees clockwise from north, computed identically on
  both platforms; `null` for arbitrary frames).
* `MotionData.referenceFrame` (the frame actually in use) and
  `MotionData.timestamp` (seconds since boot).
* Swift Package Manager support (`ios/motion_core/Package.swift`); CocoaPods
  keeps working.
* Dart unit tests.

### Changed (breaking)

* `MotionData.headingAccuracy` is now `double?` (as the README always said)
  and is `null` instead of `-1.0` when unavailable.
* Euler getters moved from the `MotionDataEuler` extension into `MotionData`.
* Samples are sent as a `Float64List` of 20 values; `MotionData.fromList`
  still accepts the old 11-value layout.

## 0.0.5

* Added new example.dart

## 0.0.4

* Update readme

## 0.0.3

* Update Github link

## 0.0.2

* Update Readme.

## 0.0.1

* Initial release.
