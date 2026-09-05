package com.example.motion_core

import android.content.Context
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.min
import kotlin.math.sqrt

/**
 * Android implementation of motion_core.
 *
 * Sample payload (a Float64List of [PAYLOAD_LENGTH] doubles). Keep in sync with
 * `lib/motion_core.dart` and `ios/Classes/MotionCorePlugin.swift`:
 *
 * ```
 * [0..3]   attitude quaternion x, y, z, w   (device -> world, East-North-Up)
 * [4..6]   gravity x, y, z                  (m/s², TYPE_GRAVITY convention: flat face-up ≈ +9.81 on Z)
 * [7..9]   user acceleration x, y, z        (m/s², TYPE_LINEAR_ACCELERATION)
 * [10]     heading accuracy                 (radians, -1 when unavailable)
 * [11..13] rotation rate x, y, z            (rad/s, NaN when no gyroscope)
 * [14..16] magnetic field x, y, z           (µT, NaN when unavailable / arbitrary frame)
 * [17]     magnetic field calibration       (-1 uncalibrated, 0 low, 1 medium, 2 high)
 * [18]     effective reference frame index  (see FRAME_* constants)
 * [19]     timestamp                        (seconds since boot)
 * ```
 */
class MotionCorePlugin :
    FlutterPlugin,
    MethodChannel.MethodCallHandler,
    EventChannel.StreamHandler,
    SensorEventListener {

    companion object {
        const val METHOD_CHANNEL_NAME = "dev.flutter/motion_core_method_channel"
        const val EVENT_CHANNEL_NAME = "dev.flutter/motion_core_event_channel"

        const val PAYLOAD_LENGTH = 20

        /** ~60 Hz, the same default as the iOS implementation. */
        const val DEFAULT_SAMPLING_PERIOD_US = 16_667

        // Values of AttitudeReferenceFrame.index on the Dart side.
        const val FRAME_ARBITRARY_Z_VERTICAL = 0
        const val FRAME_ARBITRARY_CORRECTED_Z_VERTICAL = 1
        const val FRAME_MAGNETIC_NORTH_Z_VERTICAL = 2
        const val FRAME_TRUE_NORTH_Z_VERTICAL = 3

        fun isNorthReferenced(frame: Int): Boolean =
            frame == FRAME_MAGNETIC_NORTH_Z_VERTICAL || frame == FRAME_TRUE_NORTH_Z_VERTICAL

        /**
         * Pure-Kotlin equivalent of [SensorManager.getQuaternionFromVector] that also
         * normalises the result. Returns `[x, y, z, w]`.
         *
         * [length] is the number of meaningful entries in [rotationVector]; when it is
         * 3 the scalar part is reconstructed from the unit-length constraint.
         */
        internal fun quaternionFromRotationVector(rotationVector: FloatArray, length: Int): DoubleArray {
            val x = rotationVector[0].toDouble()
            val y = rotationVector[1].toDouble()
            val z = rotationVector[2].toDouble()
            val w = if (length >= 4) {
                rotationVector[3].toDouble()
            } else {
                val remainder = 1.0 - x * x - y * y - z * z
                if (remainder > 0) sqrt(remainder) else 0.0
            }
            val norm = sqrt(x * x + y * y + z * z + w * w)
            return if (norm > 0 && norm.isFinite()) {
                doubleArrayOf(x / norm, y / norm, z / norm, w / norm)
            } else {
                doubleArrayOf(0.0, 0.0, 0.0, 1.0)
            }
        }

        /** Maps SensorManager.SENSOR_STATUS_* to the iOS CMMagneticFieldCalibrationAccuracy scale. */
        internal fun magneticAccuracyFromSensorStatus(status: Int): Double = when (status) {
            SensorManager.SENSOR_STATUS_ACCURACY_HIGH -> 2.0
            SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM -> 1.0
            SensorManager.SENSOR_STATUS_ACCURACY_LOW -> 0.0
            else -> -1.0
        }

        /** Builds one sample. Pure function so it can be unit tested without Android. */
        internal fun buildPayload(
            rotationVector: FloatArray,
            rotationVectorLength: Int,
            gravity: FloatArray,
            linearAcceleration: FloatArray,
            rotationRate: FloatArray?,
            magneticField: FloatArray?,
            magneticAccuracyStatus: Int,
            frame: Int,
            timestampNanos: Long,
        ): DoubleArray {
            val payload = DoubleArray(PAYLOAD_LENGTH) { Double.NaN }

            val q = quaternionFromRotationVector(rotationVector, rotationVectorLength)
            payload[0] = q[0]
            payload[1] = q[1]
            payload[2] = q[2]
            payload[3] = q[3]

            payload[4] = gravity[0].toDouble()
            payload[5] = gravity[1].toDouble()
            payload[6] = gravity[2].toDouble()

            payload[7] = linearAcceleration[0].toDouble()
            payload[8] = linearAcceleration[1].toDouble()
            payload[9] = linearAcceleration[2].toDouble()

            // values[4] is only defined for the (geomagnetic) rotation vector and is -1
            // when the HAL cannot estimate it.
            payload[10] = if (rotationVectorLength >= 5 && isNorthReferenced(frame)) {
                rotationVector[4].toDouble()
            } else {
                -1.0
            }

            if (rotationRate != null) {
                payload[11] = rotationRate[0].toDouble()
                payload[12] = rotationRate[1].toDouble()
                payload[13] = rotationRate[2].toDouble()
            }

            if (magneticField != null) {
                payload[14] = magneticField[0].toDouble()
                payload[15] = magneticField[1].toDouble()
                payload[16] = magneticField[2].toDouble()
                payload[17] = magneticAccuracyFromSensorStatus(magneticAccuracyStatus)
            }

            payload[18] = frame.toDouble()
            payload[19] = timestampNanos / 1_000_000_000.0
            return payload
        }
    }

    private var sensorManager: SensorManager? = null
    private var methodChannel: MethodChannel? = null
    private var eventChannel: EventChannel? = null
    private var eventSink: EventChannel.EventSink? = null

    // Lazy so the class can be instantiated in plain JVM unit tests.
    private val mainHandler: Handler by lazy { Handler(Looper.getMainLooper()) }

    // Configuration (mutable through the "configure" method call).
    private var samplingPeriodUs = DEFAULT_SAMPLING_PERIOD_US
    private var requestedFrame = FRAME_MAGNETIC_NORTH_Z_VERTICAL

    // Sensors registered for the current stream.
    private var effectiveFrame = FRAME_MAGNETIC_NORTH_Z_VERTICAL
    private var rotationSensor: Sensor? = null
    private var gravitySensor: Sensor? = null
    private var linearAccelerationSensor: Sensor? = null
    private var gyroscopeSensor: Sensor? = null
    private var magnetometerSensor: Sensor? = null
    private var isStreaming = false

    // Latest samples. Sensor callbacks are delivered on the main thread (see mainHandler).
    private val rotationVector = FloatArray(5)
    private var rotationVectorLength = 0
    private val gravity = FloatArray(3)
    private val linearAcceleration = FloatArray(3)
    private val rotationRate = FloatArray(3)
    private val magneticField = FloatArray(3)
    private var hasGravity = false
    private var hasLinearAcceleration = false
    private var hasRotationRate = false
    private var hasMagneticField = false
    private var magneticAccuracyStatus = SensorManager.SENSOR_STATUS_UNRELIABLE

    // region FlutterPlugin

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        sensorManager =
            binding.applicationContext.getSystemService(Context.SENSOR_SERVICE) as? SensorManager

        methodChannel = MethodChannel(binding.binaryMessenger, METHOD_CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
        eventChannel = EventChannel(binding.binaryMessenger, EVENT_CHANNEL_NAME).also {
            it.setStreamHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        // Make sure sensors are released even if Dart never cancelled the stream
        // (e.g. the engine is destroyed while a subscription is active).
        stopSensors()
        eventSink = null
        methodChannel?.setMethodCallHandler(null)
        eventChannel?.setStreamHandler(null)
        methodChannel = null
        eventChannel = null
        sensorManager = null
    }

    // endregion

    // region MethodChannel

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(isDeviceMotionAvailable())
            "availableReferenceFrames" -> result.success(availableReferenceFrames())
            "configure" -> configure(call, result)
            else -> result.notImplemented()
        }
    }

    private fun configure(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        if (args == null) {
            result.error("INVALID_ARGUMENT", "configure expects a map of options.", null)
            return
        }
        val intervalMicros = (args["updateIntervalMicros"] as? Number)?.toLong()
        val frame = (args["referenceFrame"] as? Number)?.toInt()

        if (intervalMicros != null && intervalMicros <= 0) {
            result.error("INVALID_ARGUMENT", "updateIntervalMicros must be greater than zero.", null)
            return
        }
        if (frame != null && (frame < FRAME_ARBITRARY_Z_VERTICAL || frame > FRAME_TRUE_NORTH_Z_VERTICAL)) {
            result.error("INVALID_ARGUMENT", "referenceFrame must be between 0 and 3.", null)
            return
        }

        intervalMicros?.let { samplingPeriodUs = min(it, Int.MAX_VALUE.toLong()).toInt() }
        frame?.let { requestedFrame = it }
        // showsCalibrationDisplay is iOS-only and intentionally ignored.

        if (isStreaming) {
            stopSensors()
            startSensors()
        }
        result.success(null)
    }

    private fun isDeviceMotionAvailable(): Boolean {
        val sm = sensorManager ?: return false
        val hasRotationVector = sm.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR) != null ||
            sm.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR) != null ||
            sm.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR) != null
        return hasRotationVector &&
            sm.getDefaultSensor(Sensor.TYPE_GRAVITY) != null &&
            sm.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION) != null
    }

    private fun availableReferenceFrames(): List<Int> {
        val sm = sensorManager ?: return emptyList()
        val frames = mutableListOf<Int>()
        if (sm.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR) != null) {
            frames.add(FRAME_ARBITRARY_Z_VERTICAL)
        }
        if (sm.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR) != null ||
            sm.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR) != null
        ) {
            frames.add(FRAME_MAGNETIC_NORTH_Z_VERTICAL)
        }
        return frames
    }

    // endregion

    // region EventChannel

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (events == null) return
        if (!isDeviceMotionAvailable()) {
            events.error(
                "UNAVAILABLE",
                "Required motion sensors (rotation vector, gravity, linear acceleration) are not available on this device.",
                null,
            )
            events.endOfStream()
            return
        }
        eventSink = events
        startSensors()
    }

    override fun onCancel(arguments: Any?) {
        stopSensors()
        eventSink = null
    }

    // endregion

    // region Sensors

    private fun resolveSensors(sm: SensorManager) {
        val game = sm.getDefaultSensor(Sensor.TYPE_GAME_ROTATION_VECTOR)
        val full = sm.getDefaultSensor(Sensor.TYPE_ROTATION_VECTOR)
        val geomagnetic = sm.getDefaultSensor(Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR)

        // Candidate (sensor, frame it produces) pairs, most preferred first.
        val northReferenced = listOf(
            full to FRAME_MAGNETIC_NORTH_Z_VERTICAL,
            geomagnetic to FRAME_MAGNETIC_NORTH_Z_VERTICAL,
            game to FRAME_ARBITRARY_Z_VERTICAL,
        )
        val arbitrary = listOf(
            game to FRAME_ARBITRARY_Z_VERTICAL,
            full to FRAME_MAGNETIC_NORTH_Z_VERTICAL,
            geomagnetic to FRAME_MAGNETIC_NORTH_Z_VERTICAL,
        )
        val candidates = if (isNorthReferenced(requestedFrame)) northReferenced else arbitrary
        val chosen = candidates.firstOrNull { it.first != null }

        rotationSensor = chosen?.first
        effectiveFrame = chosen?.second ?: requestedFrame
        gravitySensor = sm.getDefaultSensor(Sensor.TYPE_GRAVITY)
        linearAccelerationSensor = sm.getDefaultSensor(Sensor.TYPE_LINEAR_ACCELERATION)
        gyroscopeSensor = sm.getDefaultSensor(Sensor.TYPE_GYROSCOPE)
        // Like Core Motion, only touch the magnetometer for north-referenced frames.
        magnetometerSensor = if (isNorthReferenced(effectiveFrame)) {
            sm.getDefaultSensor(Sensor.TYPE_MAGNETIC_FIELD)
        } else {
            null
        }
    }

    private fun resetSamples() {
        rotationVectorLength = 0
        hasGravity = false
        hasLinearAcceleration = false
        hasRotationRate = false
        hasMagneticField = false
        magneticAccuracyStatus = SensorManager.SENSOR_STATUS_UNRELIABLE
    }

    private fun startSensors() {
        val sm = sensorManager ?: return
        resolveSensors(sm)
        resetSamples()

        val handler = mainHandler
        listOfNotNull(
            rotationSensor,
            gravitySensor,
            linearAccelerationSensor,
            gyroscopeSensor,
            magnetometerSensor,
        ).forEach { sensor ->
            sm.registerListener(this, sensor, samplingPeriodUs, handler)
        }
        isStreaming = true
    }

    private fun stopSensors() {
        if (isStreaming) {
            sensorManager?.unregisterListener(this)
        }
        isStreaming = false
    }

    override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) {
        if (sensor?.type == Sensor.TYPE_MAGNETIC_FIELD) {
            magneticAccuracyStatus = accuracy
        }
    }

    override fun onSensorChanged(event: SensorEvent?) {
        event ?: return
        val values = event.values ?: return

        when (event.sensor.type) {
            Sensor.TYPE_ROTATION_VECTOR,
            Sensor.TYPE_GAME_ROTATION_VECTOR,
            Sensor.TYPE_GEOMAGNETIC_ROTATION_VECTOR,
            -> {
                if (event.sensor.type != rotationSensor?.type) return
                val n = min(values.size, rotationVector.size)
                System.arraycopy(values, 0, rotationVector, 0, n)
                rotationVectorLength = n
                if (hasGravity && hasLinearAcceleration) {
                    emitSample(event.timestamp)
                }
            }
            Sensor.TYPE_GRAVITY -> {
                copy3(values, gravity)
                hasGravity = true
            }
            Sensor.TYPE_LINEAR_ACCELERATION -> {
                copy3(values, linearAcceleration)
                hasLinearAcceleration = true
            }
            Sensor.TYPE_GYROSCOPE -> {
                copy3(values, rotationRate)
                hasRotationRate = true
            }
            Sensor.TYPE_MAGNETIC_FIELD -> {
                copy3(values, magneticField)
                magneticAccuracyStatus = event.accuracy
                hasMagneticField = true
            }
        }
    }

    private fun copy3(source: FloatArray, destination: FloatArray) {
        System.arraycopy(source, 0, destination, 0, min(3, source.size))
    }

    private fun emitSample(timestampNanos: Long) {
        val sink = eventSink ?: return
        if (rotationVectorLength < 3) return
        val payload = buildPayload(
            rotationVector = rotationVector,
            rotationVectorLength = rotationVectorLength,
            gravity = gravity,
            linearAcceleration = linearAcceleration,
            rotationRate = if (hasRotationRate) rotationRate else null,
            magneticField = if (hasMagneticField) magneticField else null,
            magneticAccuracyStatus = magneticAccuracyStatus,
            frame = effectiveFrame,
            timestampNanos = timestampNanos,
        )
        sink.success(payload)
    }

    // endregion
}
