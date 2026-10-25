import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_liveness_sdk_example/main.dart';

void main() {
  testWidgets('testing page disables capture when no actions are selected', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: Demo()));
    expect(find.text('Aksi wajah'), findsOneWidget);

    for (final name in ['Lihat kiri', 'Lihat kanan', 'Senyum', 'Kedip']) {
      await tester.scrollUntilVisible(find.text(name), 100);
      await tester.tap(find.text(name));
      await tester.pump();
    }
    expect(find.text('Pilih minimal satu aksi.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Mulai tes liveness'), 100);
    expect(find.text('Audit mode'), findsOneWidget);
    expect(find.text('Timeout: 30 detik'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
  });
}
