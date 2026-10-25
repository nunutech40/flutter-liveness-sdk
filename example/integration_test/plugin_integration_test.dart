import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:flutter_liveness_sdk/flutter_liveness_sdk.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('configuration is available on device', (tester) async {
    final config = LivenessConfig(steps: [LivenessStep.blink]);
    expect(config.toMap()['steps'], ['blink']);
  });
}
