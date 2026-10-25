package com.nunutech40.flutter_liveness_sdk

import android.Manifest
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Size
import android.view.Gravity
import android.view.ViewGroup
import android.widget.Button
import android.widget.FrameLayout
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetector
import com.google.mlkit.vision.face.FaceDetectorOptions
import java.io.File
import java.io.FileOutputStream
import java.util.UUID
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/** Full-screen native capture screen. It never sends image frames over Flutter channels. */
class LivenessActivity : ComponentActivity() {
    companion object {
        const val EXTRA_SESSION_ID = "session_id"
        const val EXTRA_STEPS = "steps"
        const val EXTRA_AUDIT = "audit"
        const val EXTRA_TIMEOUT_MS = "timeout_ms"
        private const val CAMERA_REQUEST = 8401
    }

    private lateinit var sessionId: String
    private lateinit var statusText: TextView
    private lateinit var previewView: PreviewView
    private lateinit var engine: ChallengeEngine
    private var provider: ProcessCameraProvider? = null
    private var preview: Preview? = null
    private var analysis: ImageAnalysis? = null
    private var imageCapture: ImageCapture? = null
    private var detector: FaceDetector? = null
    private var terminal = false
    private var capturing = false
    private val mainHandler = Handler(Looper.getMainLooper())
    private val cameraExecutor: ExecutorService = Executors.newSingleThreadExecutor()
    private val evidence = mutableMapOf<String, String>()
    private var lastGuidance: String? = null
    private val timeoutAction = Runnable { finishSession("timedOut", "timeout") }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        sessionId = intent.getStringExtra(EXTRA_SESSION_ID) ?: run { finish(); return }
        if (!LivenessSessions.has(sessionId)) { finish(); return }
        val steps = intent.getStringArrayListExtra(EXTRA_STEPS) ?: run { finishSession("failed", "invalid_config"); return }
        engine = ChallengeEngine(steps)
        LivenessSessions.attachCancel(sessionId) { runOnUiThread { finishSession("cancelled") } }
        buildScreen()
        val timeout = intent.getLongExtra(EXTRA_TIMEOUT_MS, 30000L)
        mainHandler.postDelayed(timeoutAction, timeout)
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            openCamera()
        } else {
            requestPermissions(arrayOf(Manifest.permission.CAMERA), CAMERA_REQUEST)
        }
    }

    private fun buildScreen() {
        window.statusBarColor = Color.BLACK
        window.navigationBarColor = Color.BLACK
        val root = FrameLayout(this).apply { setBackgroundColor(Color.BLACK) }
        previewView = PreviewView(this).apply { scaleType = PreviewView.ScaleType.FILL_CENTER }
        root.addView(previewView, FrameLayout.LayoutParams(-1, -1))
        val overlay = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER_HORIZONTAL
            setPadding(32, 64, 32, 48)
            setBackgroundColor(0x66000000)
        }
        statusText = TextView(this).apply {
            text = "Preparing camera…"
            textSize = 23f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }
        overlay.addView(statusText, LinearLayout.LayoutParams(-1, 0, 1f))
        val cancel = Button(this).apply {
            text = "Cancel"
            setOnClickListener { finishSession("cancelled") }
        }
        overlay.addView(cancel, LinearLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT))
        root.addView(overlay, FrameLayout.LayoutParams(-1, -1))
        setContentView(root)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == CAMERA_REQUEST) {
            if (grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED) openCamera()
            else finishSession("failed", "camera_permission_denied")
        }
    }

    private fun openCamera() {
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            if (terminal) return@addListener
            try {
                val readyProvider = future.get()
                if (!readyProvider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA)) {
                    finishSession("failed", "front_camera_unavailable")
                    return@addListener
                }
                provider = readyProvider
                bindCamera(readyProvider)
            } catch (error: Exception) {
                finishSession("failed", "camera_initialization_failed")
            }
        }, ContextCompat.getMainExecutor(this))
    }

    private fun bindCamera(readyProvider: ProcessCameraProvider) {
        val lowEnd = (getSystemService(ACTIVITY_SERVICE) as android.app.ActivityManager).let { manager ->
            val info = android.app.ActivityManager.MemoryInfo()
            manager.getMemoryInfo(info)
            manager.isLowRamDevice || info.totalMem < 2L * 1024L * 1024L * 1024L
        }
        val options = FaceDetectorOptions.Builder()
            .setPerformanceMode(if (lowEnd) FaceDetectorOptions.PERFORMANCE_MODE_FAST else FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
            .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
            .setClassificationMode(FaceDetectorOptions.CLASSIFICATION_MODE_ALL)
            .enableTracking()
            .build()
        detector = FaceDetection.getClient(options)
        preview = Preview.Builder().build().also { it.setSurfaceProvider(previewView.surfaceProvider) }
        imageCapture = ImageCapture.Builder().setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY).build()
        val analysisBuilder = ImageAnalysis.Builder().setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
        if (lowEnd) analysisBuilder.setTargetResolution(Size(480, 640))
        analysis = analysisBuilder.build().also { imageAnalysis ->
            imageAnalysis.setAnalyzer(cameraExecutor) { proxy -> analyze(proxy) }
        }
        try {
            readyProvider.bindToLifecycle(this, CameraSelector.DEFAULT_FRONT_CAMERA, preview, analysis, imageCapture)
            statusText.text = instruction(engine.currentStep)
            emit(mapOf("type" to "ready", "step" to engine.currentStep))
        } catch (error: Exception) {
            finishSession("failed", "camera_bind_failed")
        }
    }

    private fun analyze(proxy: ImageProxy) {
        if (terminal || capturing) { proxy.close(); return }
        val image = proxy.image ?: run { proxy.close(); return }
        val input = InputImage.fromMediaImage(image, proxy.imageInfo.rotationDegrees)
        detector?.process(input)
            ?.addOnSuccessListener(ContextCompat.getMainExecutor(this)) { faces ->
                if (terminal || capturing) return@addOnSuccessListener
                when {
                    faces.isEmpty() -> { engine.resetTransient(); guide("no_face") }
                    faces.size > 1 -> { engine.resetTransient(); guide("multiple_faces") }
                    else -> {
                        val face = faces[0]
                        if (lastGuidance != null) {
                            lastGuidance = null
                            statusText.text = instruction(engine.currentStep)
                        }
                        val update = engine.update(FaceSignals(
                            face.headEulerAngleY,
                            face.smilingProbability,
                            face.leftEyeOpenProbability,
                            face.rightEyeOpenProbability,
                            face.trackingId,
                        ))
                        if (update.passedStep != null) {
                            if (intent.getBooleanExtra(EXTRA_AUDIT, false)) saveEvidence(update.passedStep, proxy)
                            emit(mapOf("type" to "stepPassed", "step" to update.passedStep))
                            statusText.text = instruction(engine.currentStep)
                        }
                        if (update.finalReady) captureFinal()
                    }
                }
            }
            ?.addOnFailureListener(ContextCompat.getMainExecutor(this)) { finishSession("failed", "face_detection_failed") }
            ?.addOnCompleteListener(ContextCompat.getMainExecutor(this)) { proxy.close() }
            ?: proxy.close()
    }

    private fun saveEvidence(step: String, proxy: ImageProxy) {
        try {
            val file = File(cacheDir, "liveness_${UUID.randomUUID()}_$step.jpg")
            val bitmap = proxy.toBitmap()
            val matrix = android.graphics.Matrix().apply { postRotate(proxy.imageInfo.rotationDegrees.toFloat()) }
            val oriented = android.graphics.Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            FileOutputStream(file).use { oriented.compress(android.graphics.Bitmap.CompressFormat.JPEG, 85, it) }
            if (oriented !== bitmap) oriented.recycle()
            bitmap.recycle()
            evidence[step] = file.absolutePath
        } catch (_: Exception) {
            finishSession("failed", "evidence_capture_failed")
        }
    }

    private fun captureFinal() {
        if (capturing || terminal) return
        capturing = true
        statusText.text = "Capturing selfie…"
        val capture = imageCapture ?: run { finishSession("failed", "camera_unavailable"); return }
        val file = File(cacheDir, "liveness_${UUID.randomUUID()}_selfie.jpg")
        val metadata = ImageCapture.Metadata().apply { isReversedHorizontal = true }
        val output = ImageCapture.OutputFileOptions.Builder(file).setMetadata(metadata).build()
        capture.takePicture(output, ContextCompat.getMainExecutor(this), object : ImageCapture.OnImageSavedCallback {
            override fun onImageSaved(result: ImageCapture.OutputFileResults) {
                finishSession("success", selfiePath = file.absolutePath)
            }
            override fun onError(exception: ImageCaptureException) {
                file.delete()
                finishSession("failed", "selfie_capture_failed")
            }
        })
    }

    private fun guide(code: String) {
        if (lastGuidance == code) return
        lastGuidance = code
        emit(mapOf("type" to "guidance", "code" to code))
        statusText.text = if (code == "no_face") "Show your face" else "Only one face in frame"
    }

    private fun instruction(step: String?): String = when (step) {
        "lookLeft" -> "Look left"
        "lookRight" -> "Look right"
        "smile" -> "Start neutral, then smile"
        "blink" -> "Open your eyes, then blink"
        else -> "Face forward for the final photo"
    }

    private fun emit(event: Map<String, Any?>) = LivenessSessions.emit(sessionId, event)

    private fun finishSession(status: String, errorCode: String? = null, selfiePath: String? = null) {
        if (terminal) return
        terminal = true
        mainHandler.removeCallbacks(timeoutAction)
        LivenessSessions.complete(sessionId, status, errorCode, selfiePath, evidence.toMap())
        finish()
    }

    override fun onStop() {
        super.onStop()
        if (!isFinishing && !isChangingConfigurations && !terminal) finishSession("cancelled", "interrupted")
    }

    override fun onDestroy() {
        mainHandler.removeCallbacks(timeoutAction)
        if (!terminal && ::sessionId.isInitialized) finishSession("cancelled", "dismissed")
        val bound = listOfNotNull(preview, analysis, imageCapture)
        if (bound.isNotEmpty()) provider?.unbind(*bound.toTypedArray())
        detector?.close()
        cameraExecutor.shutdown()
        super.onDestroy()
    }
}
