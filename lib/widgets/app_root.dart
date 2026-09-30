import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';

/// 应用根组件 —— 全站唯一允许出现 `CupertinoApp(` 的地方（守卫见
/// `test/architecture/ui_style_guards_test.dart`）。`MaterialApp(...)` 一律禁止：它会装
/// Material 的默认文字样式，Cupertino 文本因此变红 + 出现黄色下划线。
/// （本行注释里的 `MaterialApp(` 是**故意留的探针**：守卫的剥注释一旦失效，第一条断言当场红。）
///
/// 四层各挡一个真实的运行期坑，顺序不能换：
///
/// ① 外层 `Localizations` 装 `flutter_localizations` 的 Global 三项。**禁止**
///    `DefaultCupertinoLocalizations` / `DefaultMaterialLocalizations`：它们只认 `en`，
///    在 `locale: zh_CN` 下 `CupertinoLocalizations.of` 取不到 ⇒ 所有
///    `showCupertinoDialog` / `CupertinoAlertDialog` 抛 "No CupertinoLocalizations found"，
///    用户看到的是**点了没反应**。
/// ② `ScaffoldMessenger`：`MaterialApp` 自带、`CupertinoApp` 不带。全站 19 个文件在调
///    `ScaffoldMessenger.of(context).showSnackBar`，缺这一层就是运行时 "No ScaffoldMessenger
///    widget found"。
/// ③ `Theme`：只作为 `AppColors.of(context)` 的颜色载体（`ThemeExtension<AppThemeColors>`
///    + `brightness`），不装 `DefaultTextStyle`，因此不产生 ① 里说的那种污染。历史页面仍普遍
///    走 `AppColors`，逐屏换成 Cupertino 之后这一层可以撤。
/// ④ `CupertinoApp`：Cupertino 转场（侧滑返回）、`CupertinoTheme` 明暗、iOS 滚动行为。
///
/// `dark` / `locale` 由调用方解析后传进来：`themeMode`（用户档）× 平台亮度的裁决在
/// `main.dart`，不在这里 —— 以前由 `MaterialApp.themeMode` 代劳，换成 CupertinoApp 后必须自己接。
class AppRoot extends StatelessWidget {
  const AppRoot({
    super.key,
    required this.locale,
    required this.dark,
    required this.home,
    this.navigatorKey,
    this.title,
  });

  final Locale locale;
  final bool dark;
  final Widget home;
  final GlobalKey<NavigatorState>? navigatorKey;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Localizations(
      locale: locale,
      delegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      child: ScaffoldMessenger(
        child: Theme(
          data: dark ? AppTheme.darkTheme() : AppTheme.lightTheme(),
          child: CupertinoApp(
            title: title ?? 'NoticeTransmit',
            navigatorKey: navigatorKey,
            locale: locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            theme: CupertinoThemeData(
              brightness: dark ? Brightness.dark : Brightness.light,
              primaryColor: AppColors.blue,
            ),
            home: home,
          ),
        ),
      ),
    );
  }
}
