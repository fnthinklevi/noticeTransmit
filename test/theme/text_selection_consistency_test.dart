import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/theme/app_colors.dart';
import 'package:notice_transmit/theme/app_theme.dart';

/// 文本选择/复制粘贴的**多机型一致性**守卫。
///
/// 背景：Flutter 的文本选择工具栏是**应用自绘**（不走厂商系统样式），但其
/// 文案与容器色由「本地化 + 主题」驱动——本地化解析失败（部分 ROM 上报非常规
/// locale）或主题未覆盖时，会出现英文菜单或与 iOS 风格不符的原生样式。
void main() {
  Widget host(Locale? locale) => MaterialApp(
    theme: AppTheme.lightTheme(),
    locale: locale,
    supportedLocales: const [Locale('zh'), Locale('en')],
    localizationsDelegates: const [
      ...AppLocalizations.localizationsDelegates,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: Scaffold(
      body: Center(
        child: TextField(controller: TextEditingController(text: '待选择文本')),
      ),
    ),
  );

  group('文本选择工具栏 – 多机型 locale 归一（防英文菜单）', () {
    // 厂商 ROM 可能上报这些非常规 locale（base.md §1.3 实测记录），
    // basicResolution 若失败会 fallback 英文（Copy/Paste）。
    for (final entry in {
      const Locale('zh'): '复制',
      const Locale('zh', 'CN'): '复制',
      const Locale('zh', 'TW'): '复制', // 繁体 ROM 也归一到简体中文
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'): '复制',
    }.entries) {
      testWidgets('locale ${entry.key} → 中文菜单', (tester) async {
        await tester.pumpWidget(host(entry.key));
        // 长按触发选择 → 弹出 Flutter 自绘工具栏
        await tester.longPress(find.text('待选择文本'));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));

        expect(
          find.text('全选'),
          findsOneWidget,
          reason: 'locale ${entry.key} 的选择工具栏应为中文（否则会显示 Select all）',
        );
        expect(find.textContaining('Select'), findsNothing);
        expect(find.textContaining('Copy'), findsNothing);
      });
    }
  });

  group('文本选择 – 主题一致性（应用蓝，各机型一致）', () {
    test('light/dark 主题均声明 textSelectionTheme', () {
      for (final theme in [AppTheme.lightTheme(), AppTheme.darkTheme()]) {
        expect(theme.textSelectionTheme.selectionColor, isNotNull);
        expect(theme.textSelectionTheme.cursorColor, isNotNull);
        expect(theme.textSelectionTheme.selectionHandleColor, isNotNull);
      }
    });

    test('工具栏容器色 = 应用卡片色（取 colorScheme.surface，实测 Flutter 源码）', () {
      // ⚠ 关键依据：_TextSelectionToolbarContainer._getColor 取 colorScheme.surface
      //（不是 surfaceContainerHighest）——改错字段会导致深色模式工具栏偏黑
      //（#111318）与卡片色（#1C1C1E）不一致。
      for (final theme in [AppTheme.lightTheme(), AppTheme.darkTheme()]) {
        final colors = theme.extension<AppThemeColors>() as AppThemeColors;
        expect(
          theme.colorScheme.surface,
          colors.cardBg,
          reason: '文本选择工具栏容器色应为应用卡片色（亮/暗两套）',
        );
      }
    });
  });
}
