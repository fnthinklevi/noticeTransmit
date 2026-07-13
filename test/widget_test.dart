import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notice_transmit/pages/main_page.dart';
import 'package:notice_transmit/di/service_locator.dart';

void main() {
  setUp(() {
    setupLocator();
  });

  testWidgets('MainPage shows navigation bar with three destinations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: MainPage()));
    await tester.pump();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('通知'), findsOneWidget);
    expect(find.text('电量'), findsOneWidget);
    expect(find.text('更多'), findsOneWidget);
  });
}
