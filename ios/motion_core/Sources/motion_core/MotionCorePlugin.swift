import CoreMotion
import Flutter
import UIKit

/// iOS implementation of motion_core.
///
/// Sample payload (a Float64List of `payloadLength` doubles). Keep in sync with
/// `lib/motion_core.dart` and the Android plugin:
///
/// ```
/// [0..3]   attitude quaternion x, y, z, w   (device -> world, East-North-Up)
/// [4..6]   gravity x, y, z                  (m/s², flat face-up ≈ +9.81 on Z)
/// [7..9]   user acceleration x, y, z        (m/s², positive in the direction of motion)
/// [10]     heading accuracy                 (always -1: Core Motion does not expose it)
/// [11..13] rotation rate x, y, z            (rad/s)
/// [14..16] magnetic field x, y, z           (µT, NaN when unavailable / arbitrary frame)
/// [17]     magnetic field calibration       (-1 uncalibrated, 0 low, 1 medium, 2 high)
/// [18]     effective reference frame index  (see `ReferenceFrame`)
/// [19]     timestamp                        (seconds since boot)
/// ```
///
/// Core Motion reports gravity and user acceleration in G with the opposite sign of
/// Android (a device lying face up reads `(0, 0, -1)`), and its north-referenced frames
/// put +X on north. Both are converted here so Dart sees one convention.
public class MotionCorePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    static let methodChannelName = "dev.flutter/motion_core_method_channel"
    static let eventChannelName = "dev.flutter/motion_core_event_channel"
    static let payloadLength = 20
    static let standardGravity = 9.80665
    /// ~60 Hz, the same default as the Android implementation.
    static let defaultUpdateInterval: TimeInterval = 1.0 / 60.0

    /// Values of `AttitudeReferenceFrame.index` on the Dart side.
    enum ReferenceFrame: Int, CaseIterable {
        case arbitraryZVertical = 0
        case arbitraryCorrectedZVertical = 1
        case magneticNorthZVertical = 2
        case trueNorthZVertical = 3

        var coreMotion: CMAttitudeReferenceFrame {
            switch self {
            case .arbitraryZVertical: return .xArbitraryZVertical
            case .arbitraryCorrectedZVertical: return .xArbitraryCorrectedZVertical
            case .magneticNorthZVertical: return .xMagneticNorthZVertical
            case .trueNorthZVertical: return .xTrueNorthZVertical
            }
        }

        var isAvailable: Bool {
            CMMotionManager.availableAttitudeReferenceFrames().contains(coreMotion)
        }

        /// Fallback order when the requested frame is not supported: stay as close as
        /// possible to the requested semantics.
        var fallbackOrder: [ReferenceFrame] {
            switch self {
            case .trueNorthZVertical:
                return [.trueNorthZVertical, .magneticNorthZVertical, .arbitraryCorrectedZVertical, .arbitraryZVertical]
            case .magneticNorthZVertical:
                return [.magneticNorthZVertical, .arbitraryCorrectedZVertical, .arbitraryZVertical]
            case .arbitraryCorrectedZVertical:
                return [.arbitraryCorrectedZVertical, .arbitraryZVertical, .magneticNorthZVertical]
            case .arbitraryZVertical:
                return [.arbitraryZVertical, .arbitraryCorrectedZVertical, .magneticNorthZVertical]
            }
        }

        var resolved: ReferenceFrame {
            fallbackOrder.first { $0.isAvailable } ?? self
        }
    }

    private let motionManager = CMMotionManager()
    private var eventSink: FlutterEventSink?
    private var methodChannel: FlutterMethodChannel?
    private var eventChannel: FlutterEventChannel?

    // Configuration (mutable through the "configure" method call).
    private var updateInterval: TimeInterval = MotionCorePlugin.defaultUpdateInterval
    private var requestedFrame: ReferenceFrame = .magneticNorthZVertical
    private var showsCalibrationDisplay = true

    // MARK: - FlutterPlugin

    public static func register(with registrar: FlutterPluginRegistrar) {
        let instance = MotionCorePlugin()
        let methodChannel = FlutterMethodChannel(
            name: methodChannelName, binaryMessenger: registrar.messenger())
        let eventChannel = FlutterEventChannel(
            name: eventChannelName, binaryMessenger: registrar.messenger())
        instance.methodChannel = methodChannel
        instance.eventChannel = eventChannel

        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
        // Publishing is what makes the engine call detachFromEngine(for:) on teardown.
        registrar.publish(instance)
    }

    public func detachFromEngine(for registrar: FlutterPluginRegistrar) {
        // Release Core Motion even if Dart never cancelled the stream.
        stopDeviceMotionUpdates()
        eventSink = nil
        eventChannel?.setStreamHandler(nil)
        methodChannel?.setMethodCallHandler(nil)
        eventChannel = nil
        methodChannel = nil
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable":
            result(motionManager.isDeviceMotionAvailable)
        case "availableReferenceFrames":
            result(ReferenceFrame.allCases.filter { $0.isAvailable }.map { $0.rawValue })
        case "configure":
            configure(call.arguments, result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func configure(_ arguments: Any?, result: FlutterResult) {
        guard let args = arguments as? [String: Any] else {
            result(FlutterError(
                code: "INVALID_ARGUMENT", message: "configure expects a map of options.", details: nil))
            return
        }

        var newInterval = updateInterval
        var newFrame = requestedFrame
        var newShowsCalibrationDisplay = showsCalibrationDisplay

        if let micros = args["updateIntervalMicros"] as? NSNumber {
            let seconds = micros.doubleValue / 1_000_000
            guard seconds > 0 else {
                result(FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "updateIntervalMicros must be greater than zero.", details: nil))
                return
            }
            newInterval = seconds
        }
        if let rawFrame = args["referenceFrame"] as? NSNumber {
            guard let frame = ReferenceFrame(rawValue: rawFrame.intValue) else {
                result(FlutterError(
                    code: "INVALID_ARGUMENT",
                    message: "referenceFrame must be between 0 and 3.", details: nil))
                return
            }
            newFrame = frame
        }
        if let shows = args["showsCalibrationDisplay"] as? Bool {
            newShowsCalibrationDisplay = shows
        }

        updateInterval = newInterval
        requestedFrame = newFrame
        showsCalibrationDisplay = newShowsCalibrationDisplay

        if motionManager.isDeviceMotionActive {
            stopDeviceMotionUpdates()
            startDeviceMotionUpdates()
        }
        result(nil)
    }

    // MARK: - FlutterStreamHandler

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
        -> FlutterError?
    {
        guard motionManager.isDeviceMotionAvailable else {
            // Deliver the error through the sink so Dart listeners actually receive it,
            // then close the stream.
            events(FlutterError(
                code: "UNAVAILABLE",
                message: "Device motion is not available on this device.", details: nil))
            events(FlutterEndOfEventStream)
            return nil
        }
        eventSink = events
        startDeviceMotionUpdates()
        return nil
    }

    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        stopDeviceMotionUpdates()
        eventSink = nil
        return nil
    }

    // MARK: - Core Motion

    private func startDeviceMotionUpdates() {
        let frame = requestedFrame.resolved
        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.showsDeviceMovementDisplay = showsCalibrationDisplay

        // Deliver on the main queue: platform channels must be used from the platform thread.
        motionManager.startDeviceMotionUpdates(using: frame.coreMotion, to: .main) {
            [weak self] motion, error in
            guard let self = self, let sink = self.eventSink else { return }

            if let error = error as NSError? {
                // Core Motion reports this while it waits for the user to move the device
                // so the compass can calibrate; samples resume on their own afterwards.
                let requiresMovement = error.domain == CMErrorDomain
                    && error.code == Int(CMErrorDeviceRequiresMovement.rawValue)
                if !requiresMovement {
                    sink(FlutterError(
                        code: "MOTION_ERROR", message: error.localizedDescription,
                        details: error.domain + "/" + String(error.code)))
                }
                return
            }
            guard let motion = motion else { return }
            sink(FlutterStandardTypedData(float64: MotionCorePlugin.encode(motion, frame: frame)))
        }
    }

    private func stopDeviceMotionUpdates() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
    }

    /// Converts a `CMDeviceMotion` sample into the shared payload layout.
    static func encode(_ motion: CMDeviceMotion, frame: ReferenceFrame) -> Data {
        var payload = [Double](repeating: .nan, count: payloadLength)

        // Core Motion's north-referenced frames are X-north / Y-west / Z-up. Rotate the
        // world frame by +90° about Z so it becomes East-North-Up like Android:
        // q_enu = q_z(90°) ⊗ q_ios. For the arbitrary frames this only changes the
        // (already arbitrary) yaw origin, so it is applied uniformly.
        let q = motion.attitude.quaternion
        let c = (0.5).squareRoot()  // cos(45°) == sin(45°)
        payload[0] = c * (q.x - q.y)
        payload[1] = c * (q.x + q.y)
        payload[2] = c * (q.z + q.w)
        payload[3] = c * (q.w - q.z)

        // G -> m/s², and flip the sign to the Android / sensors_plus convention.
        let scale = -standardGravity
        payload[4] = motion.gravity.x * scale
        payload[5] = motion.gravity.y * scale
        payload[6] = motion.gravity.z * scale
        payload[7] = motion.userAcceleration.x * scale
        payload[8] = motion.userAcceleration.y * scale
        payload[9] = motion.userAcceleration.z * scale

        payload[10] = -1  // Heading accuracy is not exposed by Core Motion.

        payload[11] = motion.rotationRate.x
        payload[12] = motion.rotationRate.y
        payload[13] = motion.rotationRate.z

        // With the arbitrary frames Core Motion leaves the field at zero / uncalibrated.
        let magnetic = motion.magneticField
        let hasField = magnetic.accuracy != .uncalibrated
            || magnetic.field.x != 0 || magnetic.field.y != 0 || magnetic.field.z != 0
        if hasField {
            payload[14] = magnetic.field.x
            payload[15] = magnetic.field.y
            payload[16] = magnetic.field.z
            payload[17] = Double(magnetic.accuracy.rawValue)
        }

        payload[18] = Double(frame.rawValue)
        payload[19] = motion.timestamp

        return payload.withUnsafeBufferPointer { Data(buffer: $0) }
    }
}
