import 'dart:async';

import 'package:flutter/services.dart';

/// Supported ordered face actions.
enum LivenessStep { lookLeft, lookRight, smile, blink }

/// Terminal outcome of a capture session.
enum LivenessStatus { success, cancelled, timedOut, failed }

/// Configuration shared by the Android and iOS implementations.
class LivenessConfig {
  LivenessConfig({
    required List<LivenessStep> steps,
    this.auditMode = false,
    this.timeout = const Duration(seconds: 30),
  }) : steps = List.unmodifiable(steps) {
    if (steps.isEmpty || steps.toSet().length != steps.length) {
      throw ArgumentError.value(steps, 'steps', 'Use unique, nonempty steps');
    }
    if (timeout < const Duration(seconds: 5) ||
        timeout > const Duration(minutes: 2)) {
      throw ArgumentError.value(timeout, 'timeout', 'Use 5 to 120 seconds');
    }
  }

  final List<LivenessStep> steps;
  final bool auditMode;
  final Duration timeout;

  Map<String, Object> toMap() => {
        'steps': steps.map((step) => step.name).toList(),
        'auditMode': auditMode,
        'timeoutMs': timeout.inMilliseconds,
      };
}

/// A native progress or guidance event. This is informational, not a result.
class LivenessEvent {
  const LivenessEvent({
    required this.type,
    this.step,
    this.code,
    this.message,
  });

  final String type;
  final LivenessStep? step;
  final String? code;
  final String? message;

  factory LivenessEvent.fromMap(Map<Object?, Object?> map) => LivenessEvent(
        type: map['type'] as String? ?? 'unknown',
        step: _stepFromName(map['step'] as String?),
        code: map['code'] as String?,
        message: map['message'] as String?,
      );
}

/// Final session result. Files live in the application's temporary directory.
class LivenessResult {
  const LivenessResult({
    required this.status,
    this.selfiePath,
    this.evidencePaths = const {},
    this.errorCode,
  });

  final LivenessStatus status;
  final String? selfiePath;
  final Map<LivenessStep, String> evidencePaths;
  final String? errorCode;

  bool get isSuccess => status == LivenessStatus.success;

  factory LivenessResult.fromMap(Map<Object?, Object?> map) {
    final statusName = map['status'] as String? ?? 'failed';
    final status = LivenessStatus.values.firstWhere(
      (value) => value.name == statusName,
      orElse: () => LivenessStatus.failed,
    );
    final evidence = <LivenessStep, String>{};
    final rawEvidence = map['evidencePaths'];
    if (rawEvidence is Map) {
      for (final entry in rawEvidence.entries) {
        final step = _stepFromName(entry.key as String?);
        final path = entry.value;
        if (step != null && path is String) evidence[step] = path;
      }
    }
    return LivenessResult(
      status: status,
      selfiePath: map['selfiePath'] as String?,
      evidencePaths: Map.unmodifiable(evidence),
      errorCode: map['errorCode'] as String?,
    );
  }
}

LivenessStep? _stepFromName(String? name) {
  if (name == null) return null;
  for (final step in LivenessStep.values) {
    if (step.name == name) return step;
  }
  return null;
}

/// Entry point for a single native liveness session.
///
/// The native screen owns the camera. [events] carries low-volume progress
/// only; camera frames never cross the Flutter platform channel.
class FlutterLivenessSdk {
  FlutterLivenessSdk._();

  static const MethodChannel _commands =
      MethodChannel('com.nunutech40.flutter_liveness_sdk/commands');
  static const EventChannel _eventChannel =
      EventChannel('com.nunutech40.flutter_liveness_sdk/events');

  static final Stream<LivenessEvent> events = _eventChannel
      .receiveBroadcastStream()
      .map((value) => LivenessEvent.fromMap(value as Map<Object?, Object?>))
      .asBroadcastStream();

  /// Opens a native capture screen and completes once it closes.
  static Future<LivenessResult> capture(LivenessConfig config) async {
    final raw = await _commands.invokeMapMethod<Object?, Object?>(
      'capture',
      config.toMap(),
    );
    if (raw == null) {
      throw PlatformException(
        code: 'empty_result',
        message: 'The native liveness session returned no result',
      );
    }
    return LivenessResult.fromMap(raw);
  }

  /// Cancels the active session, if any.
  static Future<void> cancel() => _commands.invokeMethod<void>('cancel');
}
