import 'package:dartalive/landing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('landing page renders hero + sections', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(LandingApp());
    await tester.pumpAndSettle();
    expect(find.textContaining('DartAlive'), findsWidgets);
    expect(find.textContaining('free'), findsWidgets);
    // scroll to bottom to cover feature rows
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -3000));
    await tester.pumpAndSettle();
    expect(find.textContaining('.dal'), findsWidgets);
  });
}
