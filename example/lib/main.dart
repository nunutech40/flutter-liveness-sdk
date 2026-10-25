import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_liveness_sdk/flutter_liveness_sdk.dart';

void main() => runApp(const MaterialApp(home: Demo()));

class Demo extends StatefulWidget {
  const Demo({super.key});

  @override
  State<Demo> createState() => _DemoState();
}

class _DemoState extends State<Demo> {
  StreamSubscription<LivenessEvent>? subscription;
  String status = 'Ready';
  bool busy = false;

  @override
  void initState() {
    super.initState();
    subscription = FlutterLivenessSdk.events.listen((event) {
      if (mounted) setState(() => status = event.code ?? event.step?.name ?? event.type);
    });
  }

  @override
  void dispose() {
    subscription?.cancel();
    super.dispose();
  }

  Future<void> capture() async {
    setState(() => busy = true);
    try {
      final result = await FlutterLivenessSdk.capture(LivenessConfig(
        steps: [LivenessStep.lookLeft, LivenessStep.smile, LivenessStep.blink],
        auditMode: true,
      ));
      if (mounted) setState(() => status = '${result.status.name}: ${result.selfiePath ?? result.errorCode ?? ''}');
    } catch (error) {
      if (mounted) setState(() => status = '$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Flutter Liveness SDK')),
    body: Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(padding: const EdgeInsets.all(24), child: Text(status, textAlign: TextAlign.center)),
        FilledButton(onPressed: busy ? null : capture, child: const Text('Start liveness capture')),
        if (busy) TextButton(onPressed: FlutterLivenessSdk.cancel, child: const Text('Cancel')),
      ],
    )),
  );
}
