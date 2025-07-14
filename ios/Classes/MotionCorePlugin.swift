// ios/Classes/SwiftMotionCorePlugin.swift

import Flutter
import UIKit
import CoreMotion

public class MotionCorePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private let motionManager = CMMotionManager()
    private var eventSink: FlutterEventSink?

    public static func register(with registrar: FlutterPluginRegistrar) {
        // Register the Method Channel for utility functions
        let methodChannel = FlutterMethodChannel(name: "dev.flutter/motion_core_method_channel", binaryMessenger: registrar.messenger())
        
        // Register the Event Channel for the motion data stream
        let eventChannel = FlutterEventChannel(name: "dev.flutter/motion_core_event_channel", binaryMessenger: registrar.messenger())
        
        let instance = MotionCorePlugin()
        methodChannel.setMethodCallHandler(instance.handle)
        eventChannel.setStreamHandler(instance)
    }

    // Method Channel handler for one-off calls like availability check
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "isAvailable":
            result(motionManager.isDeviceMotionAvailable)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - FlutterStreamHandler

    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        self.eventSink = events
        if !motionManager.isDeviceMotionAvailable {
            eventSink?(FlutterError(code: "UNAVAILABLE", message: "Device motion is not available on this device.", details: nil))
            return nil
        }
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
        // An update interval of 0.016 seconds provides data at approximately 60Hz.
        motionManager.deviceMotionUpdateInterval = 1.0 / 60.0
        motionManager.showsDeviceMovementDisplay = true // Optional: for calibration UI
        
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (motion, error) in
            guard let self = self, let motion = motion, error == nil else {
                return
            }
            
            // Extract all relevant data from CMDeviceMotion
            let attitude = motion.attitude.quaternion
            let gravity = motion.gravity
            let userAccel = motion.userAcceleration
            
            // Construct the data payload array in the agreed-upon order.
            // [qx, qy, qz, qw, gx, gy, gz, ax, ay, az, accuracy]
            // iOS does not provide a direct heading accuracy value, so send -1.0 as a placeholder.
            let data: [Double] = [
                attitude.x, attitude.y, attitude.z, attitude.w, // Attitude Quaternion
                gravity.x, gravity.y, gravity.z,               // Gravity Vector
                userAccel.x, userAccel.y, userAccel.z,         // User Acceleration
                -1.0                                           // Heading Accuracy (N/A)
            ]
            
            self.eventSink?(data)
        }
    }
    
    private func stopDeviceMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }
}