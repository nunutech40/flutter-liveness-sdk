import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_liveness_sdk/flutter_liveness_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.nunutech40.flutter_liveness_sdk/commands');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('rejects invalid challenge sessions before opening the camera', () {
    expect(() => LivenessConfig(steps: []), throwsArgumentError);
    expect(
      () => LivenessConfig(steps: [LivenessStep.blink, LivenessStep.blink]),
      throwsArgumentError,
    );
    expect(
      () => LivenessConfig(
        steps: [LivenessStep.blink],
        timeout: const Duration(seconds: 1),
      ),
      throwsArgumentError,
    );
  });

  test('serializes config and parses native result', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'capture');
      expect(call.arguments, {
        'steps': ['lookLeft', 'blink'],
        'auditMode': true,
        'timeoutMs': 30000,
      });
      return {
        'status': 'success',
        'selfiePath': '/tmp/selfie.jpg',
        'evidencePaths': {'blink': '/tmp/blink.jpg'},
      };
    });
    final result = await FlutterLivenessSdk.capture(
      LivenessConfig(
        steps: [LivenessStep.lookLeft, LivenessStep.blink],
        auditMode: true,
      ),
    );
    expect(result.isSuccess, isTrue);
    expect(result.selfiePath, '/tmp/selfie.jpg');
    expect(result.evidencePaths[LivenessStep.blink], '/tmp/blink.jpg');
  });
}
