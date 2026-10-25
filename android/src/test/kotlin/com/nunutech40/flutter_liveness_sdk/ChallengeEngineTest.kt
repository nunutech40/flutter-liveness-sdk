package com.nunutech40.flutter_liveness_sdk

import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.Assertions.assertFalse
import org.junit.jupiter.api.Assertions.assertTrue
import org.junit.jupiter.api.Test

internal class ChallengeEngineTest {
    @Test
    fun turnNeedsNeutralStartAndTwoTargetFrames() {
        val engine = ChallengeEngine(listOf("lookLeft"))
        fun face(yaw: Float) = FaceSignals(yaw, null, null, null, 1)
        assertEquals(null, engine.update(face(40f)).passedStep)
        engine.update(face(0f))
        assertEquals(null, engine.update(face(40f)).passedStep)
        assertEquals("lookLeft", engine.update(face(40f)).passedStep)
        assertFalse(engine.update(face(20f)).finalReady)
        assertFalse(engine.update(face(0f)).finalReady)
        assertTrue(engine.update(face(0f)).finalReady)
    }

    @Test
    fun blinkNeedsBothEyesToCloseAndReopen() {
        val engine = ChallengeEngine(listOf("blink"))
        fun face(left: Float, right: Float) = FaceSignals(0f, null, left, right, 1)
        engine.update(face(0.9f, 0.9f))
        assertEquals(null, engine.update(face(0.1f, 0.9f)).passedStep)
        assertEquals(null, engine.update(face(0.1f, 0.1f)).passedStep)
        assertEquals("blink", engine.update(face(0.9f, 0.9f)).passedStep)
    }
}
