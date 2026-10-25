package com.nunutech40.flutter_liveness_sdk

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID

/** Flutter bridge. Camera frames are handled entirely by the native Activity. */
class FlutterLivenessSdkPlugin : FlutterPlugin, ActivityAware,
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private lateinit var commands: MethodChannel
    private lateinit var events: EventChannel
    private var activity: Activity? = null
    private var eventSink: EventChannel.EventSink? = null
    private var activeId: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        commands = MethodChannel(binding.binaryMessenger, "com.nunutech40.flutter_liveness_sdk/commands")
        events = EventChannel(binding.binaryMessenger, "com.nunutech40.flutter_liveness_sdk/events")
        commands.setMethodCallHandler(this)
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        activeId?.let { LivenessSessions.cancel(it) }
        activeId = null
        eventSink = null
        commands.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivityForConfigChanges() { activity = null }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onDetachedFromActivity() { activity = null }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) { eventSink = sink }
    override fun onCancel(arguments: Any?) { eventSink = null }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capture" -> startCapture(call.arguments, result)
            "cancel" -> {
                activeId?.let { LivenessSessions.cancel(it) }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun startCapture(arguments: Any?, result: MethodChannel.Result) {
        val host = activity ?: run {
            result.error("no_activity", "Liveness requires a foreground Activity", null)
            return
        }
        if (activeId != null) {
            result.error("session_active", "A liveness session is already active", null)
            return
        }
        val config = arguments as? Map<*, *> ?: run {
            result.error("invalid_config", "Expected configuration map", null)
            return
        }
        val steps = (config["steps"] as? List<*>)?.filterIsInstance<String>()
        val allowed = setOf("lookLeft", "lookRight", "smile", "blink")
        val timeoutMs = (config["timeoutMs"] as? Number)?.toLong() ?: 30000L
        if (steps.isNullOrEmpty() || steps.size != steps.distinct().size ||
            steps.any { it !in allowed } || timeoutMs !in 5000L..120000L) {
            result.error("invalid_config", "Invalid steps or timeout", null)
            return
        }
        val id = UUID.randomUUID().toString()
        activeId = id
        LivenessSessions.register(id, { event -> eventSink?.success(event) }) { outcome ->
            if (activeId == id) activeId = null
            result.success(outcome)
        }
        try {
            val intent = Intent(host, LivenessActivity::class.java)
                .putExtra(LivenessActivity.EXTRA_SESSION_ID, id)
                .putStringArrayListExtra(LivenessActivity.EXTRA_STEPS, ArrayList(steps))
                .putExtra(LivenessActivity.EXTRA_AUDIT, config["auditMode"] == true)
                .putExtra(LivenessActivity.EXTRA_TIMEOUT_MS, timeoutMs)
            host.startActivity(intent)
        } catch (error: Exception) {
            LivenessSessions.complete(id, "failed", "launch_failed")
        }
    }
}
