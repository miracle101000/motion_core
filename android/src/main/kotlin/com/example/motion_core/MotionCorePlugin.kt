package com.example.motion_core

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MotionCorePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, EventChannel.StreamHandler, SensorEventListener {
    private lateinit var context: Context
    private var sensorManager: SensorManager? = null

    private var rotationSensor: Sensor? = null
    private var gravitySensor: Sensor? = null
    private var linearAccelSensor: Sensor? = null

    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    private val rotationVector = FloatArray(5)  // [x, y, z, w, accuracy]
    private val gravity = FloatArray(3)
    private val linearAcceleration = FloatArray(3)

    private var rotationVectorInitialized = false
    private var gravityInitialized = false
    private var linearAccelerationInitialized = false
    private var rotationAccuracy = SensorManager.SENSOR_STATUS_UNRELIABLE

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        sensorManager = context.getSystemService(Context.SENSOR_SERVICE) as SensorManager

        rotationSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        gravitySensor = sensorManager?.getDefaultSensor(Sensor.TYPE_GRAVITY)
        linearAccelSensor = sensorManager?.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)

        methodChannel = MethodChannel(binding.binaryMessenger, "dev.flutter/motion_core_method_channel")
        methodChannel?.setMethodCallHandler(this)

        eventChannel = EventChannel(binding.binaryMessenger, "dev.flutter/motion_core_event_channel")
        eventChannel?.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
    }

    // Handle method channel calls
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "isAvailable") {
            val isAvailable = rotationSensor != null && gravitySensor != null && linearAccelSensor != null
            result.success(isAvailable)
        } else {
            result.notImplemented()
        }
    }

    // Start listening to sensor updates
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (rotationSensor == null || gravitySensor == null || linearAccelSensor == null) {
            events?.error("UNAVAILABLE", "Required sensors not available.", null)
            return
        }
        eventSink = events
        sensorManager?.registerListener(this, rotationSensor, SensorManager.SENSOR_DELAY_GAME)
        sensorManager?.registerListener(this, gravitySensor, SensorManager.SENSOR_DELAY_GAME)
        sensorManager?.registerListener(this, linearAccelSensor, SensorManager.SENSOR_DELAY_GAME)
    }

    // Stop listening
    override fun onCancel(arguments: Any?) {
        sensorManager?.unregisterListener(this)
        eventSink = null
    }

    // Track sensor accuracy
    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        if (sensor?.type == Sensor.TYPE_ROTATION_VECTOR) {
            rotationAccuracy = accuracy
        }
    }

    override fun onSensorChanged(event: SensorEvent?) {
        event ?: return

        when (event.sensor.type) {
            Sensor.TYPE_ROTATION_VECTOR -> {
                System.arraycopy(event.values, 0, rotationVector, 0, event.values.size)
                rotationVectorInitialized = true
            }
            Sensor.TYPE_GRAVITY -> {
                System.arraycopy(event.values, 0, gravity, 0, event.values.size)
                gravityInitialized = true
            }
            Sensor.TYPE_LINEAR_ACCELERATION -> {
                System.arraycopy(event.values, 0, linearAcceleration, 0, event.values.size)
                linearAccelerationInitialized = true
            }
        }

        // Only send when we have all sensors and rotation accuracy is high
        if (event.sensor.type == Sensor.TYPE_ROTATION_VECTOR &&
            gravityInitialized &&
            linearAccelerationInitialized &&
            rotationAccuracy == SensorManager.SENSOR_STATUS_ACCURACY_HIGH) {
            sendCombinedSensorData()
        }
    }

    // Build and send the combined payload
    private fun sendCombinedSensorData() {
        val quaternion = FloatArray(4)
        SensorManager.getQuaternionFromVector(quaternion, rotationVector)

        val headingAccuracy = if (rotationVector.size >= 5) rotationVector[4].toDouble() else -1.0

        val data = doubleArrayOf(
            quaternion[1].toDouble(), // qx
            quaternion[2].toDouble(), // qy
            quaternion[3].toDouble(), // qz
            quaternion[0].toDouble(), // qw
            gravity[0].toDouble(),    // gx
            gravity[1].toDouble(),    // gy
            gravity[2].toDouble(),    // gz
            linearAcceleration[0].toDouble(), // ax
            linearAcceleration[1].toDouble(), // ay
            linearAcceleration[2].toDouble(), // az
            headingAccuracy
        )

        eventSink?.success(data.toList())
    }
}
