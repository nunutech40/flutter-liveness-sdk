package com.nunutech40.flutter_liveness_sdk

import kotlin.math.abs

/** Face signals provided by ML Kit; no camera or Flutter dependency. */
internal data class FaceSignals(
    val yaw: Float,
    val smile: Float?,
    val leftEyeOpen: Float?,
    val rightEyeOpen: Float?,
    val trackingId: Int?,
)

internal data class ChallengeUpdate(val passedStep: String? = null, val finalReady: Boolean = false)

/** Ordered actions require a neutral starting observation and temporal transition. */
internal class ChallengeEngine(private val steps: List<String>) {
    private var stepIndex = 0
    private var baselineSeen = false
    private var stableFrames = 0
    private var blinkPhase = 0
    private var trackingId: Int? = null

    val currentStep: String? get() = steps.getOrNull(stepIndex)

    fun resetTransient() {
        baselineSeen = false
        stableFrames = 0
        blinkPhase = 0
        trackingId = null
    }

    fun update(face: FaceSignals): ChallengeUpdate {
        if (trackingId != null && face.trackingId != null && trackingId != face.trackingId) {
            resetTransient()
        }
        trackingId = face.trackingId

        if (stepIndex >= steps.size) {
            stableFrames = if (abs(face.yaw) < 10f) stableFrames + 1 else 0
            return ChallengeUpdate(finalReady = stableFrames >= 2)
        }
        val step = steps[stepIndex]
        val frontal = abs(face.yaw) < 15f
        val passed = when (step) {
            "lookLeft" -> transition(abs(face.yaw) < 12f, face.yaw > 35f)
            "lookRight" -> transition(abs(face.yaw) < 12f, face.yaw < -35f)
            "smile" -> transition(frontal && (face.smile ?: 1f) < 0.4f,
                frontal && (face.smile ?: 0f) > 0.7f)
            "blink" -> {
                val left = face.leftEyeOpen
                val right = face.rightEyeOpen
                if (!frontal || left == null || right == null) false
                else when (blinkPhase) {
                    0 -> { if (left > 0.7f && right > 0.7f) blinkPhase = 1; false }
                    1 -> { if (left < 0.4f && right < 0.4f) blinkPhase = 2; false }
                    else -> left > 0.7f && right > 0.7f
                }
            }
            else -> false
        }
        if (!passed) return ChallengeUpdate()
        stepIndex++
        baselineSeen = false
        stableFrames = 0
        blinkPhase = 0
        return ChallengeUpdate(passedStep = step)
    }

    private fun transition(isBaseline: Boolean, isTarget: Boolean): Boolean {
        if (isBaseline) baselineSeen = true
        stableFrames = if (baselineSeen && isTarget) stableFrames + 1 else 0
        return stableFrames >= 2
    }
}
