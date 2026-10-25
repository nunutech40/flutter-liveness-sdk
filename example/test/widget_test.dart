import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_liveness_sdk_example/main.dart';

void main() {
  testWidgets('shows capture action', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Demo()));
    expect(find.text('Start liveness capture'), findsOneWidget);
  });
}
