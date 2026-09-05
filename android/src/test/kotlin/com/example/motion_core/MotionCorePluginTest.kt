package com.example.motion_core

import android.hardware.SensorManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.math.abs
import kotlin.math.sqrt
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.mockito.ArgumentMatchers.anyString
import org.mockito.ArgumentMatchers.eq
import org.mockito.ArgumentMatchers.isNull
import org.mockito.Mockito

/*
 * Plain JVM unit tests for the Kotlin side of the plugin. Run them with
 * `./gradlew :motion_core:testDebugUnitTest` from `example/android/` after the
 * example app has been built once.
 */
internal class MotionCorePluginTest {

    private fun assertClose(expected: Double, actual: Double, tolerance: Double = 1e-6) {
        assertTrue(abs(expected - actual) <= tolerance, "expected $expected but was $actual")
    }

    // region Method channel

    @Test
    fun isAvailable_beforeAttachingToEngine_isFalse() {
        val plugin = MotionCorePlugin()
        val result: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(MethodCall("isAvailable", null), result)

        Mockito.verify(result).success(false)
    }

    @Test
    fun availableReferenceFrames_beforeAttachingToEngine_isEmpty() {
        val plugin = MotionCorePlugin()
        val result: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(MethodCall("availableReferenceFrames", null), result)

        Mockito.verify(result).success(emptyList<Int>())
    }

    @Test
    fun unknownMethod_isNotImplemented() {
        val plugin = MotionCorePlugin()
        val result: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(MethodCall("getPlatformVersion", null), result)

        Mockito.verify(result).notImplemented()
    }

    @Test
    fun configure_withoutArguments_isRejected() {
        val plugin = MotionCorePlugin()
        val result: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(MethodCall("configure", null), result)

        Mockito.verify(result).error(eq("INVALID_ARGUMENT"), anyString(), isNull())
    }

    @Test
    fun configure_withUnknownReferenceFrame_isRejected() {
        val plugin = MotionCorePlugin()
        val result: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(MethodCall("configure", mapOf("referenceFrame" to 7)), result)

        Mockito.verify(result).error(eq("INVALID_ARGUMENT"), anyString(), isNull())
    }

    @Test
    fun configure_withNonPositiveInterval_isRejected() {
        val plugin = MotionCorePlugin()
        val result: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        plugin.onMethodCall(MethodCall("configure", mapOf("updateIntervalMicros" to 0)), result)

        Mockito.verify(result).error(eq("INVALID_ARGUMENT"), anyString(), isNull())
    }

    @Test
    fun configure_withValidOptions_succeeds() {
        val plugin = MotionCorePlugin()
        val result: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)

        val options = mapOf(
            "updateIntervalMicros" to 20_000L,
            "referenceFrame" to MotionCorePlugin.FRAME_ARBITRARY_Z_VERTICAL,
            "showsCalibrationDisplay" to false,
        )
        plugin.onMethodCall(MethodCall("configure", options), result)

        Mockito.verify(result).success(isNull())
    }

    // endregion

    // region Quaternion

    @Test
    fun quaternionFromRotationVector_usesProvidedScalarPart() {
        val q = MotionCorePlugin.quaternionFromRotationVector(floatArrayOf(0f, 0f, 0f, 1f, -1f), 5)

        assertEquals(listOf(0.0, 0.0, 0.0, 1.0), q.toList())
    }

    @Test
    fun quaternionFromRotationVector_reconstructsMissingScalarPart() {
        // 90° about Z: (0, 0, sin45°, cos45°)
        val s = sqrt(0.5).toFloat()
        val q = MotionCorePlugin.quaternionFromRotationVector(floatArrayOf(0f, 0f, s), 3)

        assertClose(0.0, q[0])
        assertClose(0.0, q[1])
        assertClose(sqrt(0.5), q[2])
        assertClose(sqrt(0.5), q[3])
    }

    @Test
    fun quaternionFromRotationVector_normalisesNonUnitInput() {
        val q = MotionCorePlugin.quaternionFromRotationVector(floatArrayOf(0f, 0f, 2f, 2f), 4)

        assertClose(1.0, sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3]))
        assertClose(sqrt(0.5), q[2])
        assertClose(sqrt(0.5), q[3])
    }

    @Test
    fun quaternionFromRotationVector_fallsBackToIdentityForZeroInput() {
        val q = MotionCorePlugin.quaternionFromRotationVector(floatArrayOf(0f, 0f, 0f, 0f), 4)

        assertEquals(listOf(0.0, 0.0, 0.0, 1.0), q.toList())
    }

    // endregion

    // region Payload

    @Test
    fun magneticAccuracy_mapsToCoreMotionScale() {
        assertEquals(2.0, MotionCorePlugin.magneticAccuracyFromSensorStatus(SensorManager.SENSOR_STATUS_ACCURACY_HIGH))
        assertEquals(1.0, MotionCorePlugin.magneticAccuracyFromSensorStatus(SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM))
        assertEquals(0.0, MotionCorePlugin.magneticAccuracyFromSensorStatus(SensorManager.SENSOR_STATUS_ACCURACY_LOW))
        assertEquals(-1.0, MotionCorePlugin.magneticAccuracyFromSensorStatus(SensorManager.SENSOR_STATUS_UNRELIABLE))
        assertEquals(-1.0, MotionCorePlugin.magneticAccuracyFromSensorStatus(SensorManager.SENSOR_STATUS_NO_CONTACT))
    }

    @Test
    fun buildPayload_withAllSensors_usesDocumentedLayout() {
        val payload = MotionCorePlugin.buildPayload(
            rotationVector = floatArrayOf(0f, 0f, 0f, 1f, 0.25f),
            rotationVectorLength = 5,
            gravity = floatArrayOf(0f, 0f, 9.81f),
            linearAcceleration = floatArrayOf(0.1f, 0.2f, 0.3f),
            rotationRate = floatArrayOf(1f, 2f, 3f),
            magneticField = floatArrayOf(10f, 20f, 30f),
            magneticAccuracyStatus = SensorManager.SENSOR_STATUS_ACCURACY_MEDIUM,
            frame = MotionCorePlugin.FRAME_MAGNETIC_NORTH_Z_VERTICAL,
            timestampNanos = 1_500_000_000L,
        )

        assertEquals(MotionCorePlugin.PAYLOAD_LENGTH, payload.size)
        assertEquals(listOf(0.0, 0.0, 0.0, 1.0), payload.slice(0..3))
        assertClose(9.81, payload[6], 1e-5)
        assertClose(0.1, payload[7], 1e-6)
        assertClose(0.2, payload[8], 1e-6)
        assertClose(0.3, payload[9], 1e-6)
        assertClose(0.25, payload[10])
        assertEquals(listOf(1.0, 2.0, 3.0), payload.slice(11..13))
        assertEquals(listOf(10.0, 20.0, 30.0), payload.slice(14..16))
        assertEquals(1.0, payload[17])
        assertEquals(2.0, payload[18])
        assertClose(1.5, payload[19])
    }

    @Test
    fun buildPayload_withoutOptionalSensors_usesNaN() {
        val payload = MotionCorePlugin.buildPayload(
            rotationVector = floatArrayOf(0f, 0f, 0f, 1f),
            rotationVectorLength = 4,
            gravity = floatArrayOf(0f, 0f, 9.81f),
            linearAcceleration = floatArrayOf(0f, 0f, 0f),
            rotationRate = null,
            magneticField = null,
            magneticAccuracyStatus = SensorManager.SENSOR_STATUS_UNRELIABLE,
            frame = MotionCorePlugin.FRAME_ARBITRARY_Z_VERTICAL,
            timestampNanos = 0L,
        )

        // No fifth rotation-vector value: heading accuracy unavailable.
        assertEquals(-1.0, payload[10])
        for (i in 11..17) {
            assertTrue(payload[i].isNaN(), "payload[$i] should be NaN")
        }
        assertEquals(0.0, payload[18])
    }

    @Test
    fun buildPayload_headingAccuracyIsUnavailableForArbitraryFrames() {
        val payload = MotionCorePlugin.buildPayload(
            rotationVector = floatArrayOf(0f, 0f, 0f, 1f, 0.25f),
            rotationVectorLength = 5,
            gravity = floatArrayOf(0f, 0f, 9.81f),
            linearAcceleration = floatArrayOf(0f, 0f, 0f),
            rotationRate = null,
            magneticField = null,
            magneticAccuracyStatus = SensorManager.SENSOR_STATUS_UNRELIABLE,
            frame = MotionCorePlugin.FRAME_ARBITRARY_Z_VERTICAL,
            timestampNanos = 0L,
        )

        assertEquals(-1.0, payload[10])
    }

    // endregion
}
