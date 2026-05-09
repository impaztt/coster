import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:sw_clicker/app.dart';

void main() {
  testWidgets('app boots without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: SwClickerApp()));
    await tester.pump();
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
