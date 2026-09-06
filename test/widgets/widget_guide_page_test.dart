import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/widget_guide_page.dart';

Widget _buildApp(Widget home) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('zh'), Locale('en')],
    locale: const Locale('zh'),
    home: home,
  );
}

void main() {
  group('WidgetGuidePage – 品牌适配', () {
    testWidgets('已知品牌：当前设备路径置顶并带「当前设备」标记', (tester) async {
      await tester.pumpWidget(
        _buildApp(const WidgetGuidePage(manufacturer: 'Xiaomi')),
      );
      await tester.pumpAndSettle();

      final contentFinder = find.textContaining('【当前设备】');
      expect(contentFinder, findsOneWidget);
      // 当前品牌的文本确实包含小米路径
      final text = tester.widget<Text>(contentFinder).data ?? '';
      expect(text.contains('小米'), isTrue);
    });

    testWidgets('未知品牌：不显示「当前设备」标记', (tester) async {
      await tester.pumpWidget(
        _buildApp(const WidgetGuidePage(manufacturer: 'SomethingElse')),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('【当前设备】'), findsNothing);
      expect(find.textContaining('小米 / 红米'), findsOneWidget);
    });

    testWidgets('华为品牌正确识别（huawei/honor）', (tester) async {
      await tester.pumpWidget(
        _buildApp(const WidgetGuidePage(manufacturer: 'HONOR')),
      );
      await tester.pumpAndSettle();

      final contentFinder = find.textContaining('【当前设备】');
      expect(contentFinder, findsOneWidget);
      final text = tester.widget<Text>(contentFinder).data ?? '';
      expect(text.contains('华为'), isTrue);
    });
  });
}
