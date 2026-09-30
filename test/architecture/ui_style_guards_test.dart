import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// UI 风格守卫（base.md §6「UI 强约束」那三条的静态那半）。
///
/// 三条各断一个**运行期会炸**的契约，不断某版行形状：
/// ① 根组件：`MaterialApp` 会装 Material 默认文字样式 ⇒ Cupertino 文本变红 + 黄下划线；
///    `CupertinoApp` 缺 `GlobalCupertinoLocalizations` ⇒ 弹窗直接抛 "No CupertinoLocalizations
///    found"（表现为点了没反应）；缺 `ScaffoldMessenger` ⇒ 全站 `showSnackBar` 运行时抛。
/// ② 返回件：`CupertinoNavigationBarBackButton` 带本地化「返回」文字，中文下挤爆 leading。
/// ③ 下拉刷新：`RefreshIndicator` 依赖 `MaterialLocalizations`，纯 Cupertino 树里红屏。
///
/// ⚠ 本守卫只扫 `lib/`。`test/widgets/` 那 24 个 harness 仍各自 pump `MaterialApp` ——
///   它们验不出根组件的坑（roadmap T83 记为「harness 要跟着逐屏换成 AppRoot」）。
void main() {
  final root = projectRoot();
  final codeByPath = <String, String>{
    for (final file in _dartFiles(root))
      _relative(root, file.path): stripComments(file.readAsStringSync()),
  };

  /// 返回源码里含 [needle]（剥注释后）的文件相对路径。
  List<String> hitting(String needle) =>
      codeByPath.entries
          .where((e) => e.value.contains(needle))
          .map((e) => e.key)
          .toList()
        ..sort();

  group('根组件', () {
    test('lib/ 里不得出现 MaterialApp(', () {
      expect(
        hitting('MaterialApp('),
        isEmpty,
        reason: 'MaterialApp 污染 Cupertino 文字样式（变红 + 黄下划线）—— 根组件一律走 AppRoot',
      );
    });

    test('CupertinoApp 只有一个装配点（AppRoot）', () {
      expect(hitting('CupertinoApp('), const <String>[
        'lib/widgets/app_root.dart',
      ], reason: '长出第二个根 = 主题/本地化/ messenger 三件事各说各话');
    });

    test('AppRoot 装 Global* 三项与 ScaffoldMessenger，且不碰 Default*', () {
      final appRoot = codeByPath['lib/widgets/app_root.dart'];
      expect(appRoot, isNotNull, reason: 'AppRoot 没了 = 前两条断言全成空转');
      for (final delegate in const [
        'GlobalMaterialLocalizations.delegate',
        'GlobalWidgetsLocalizations.delegate',
        'GlobalCupertinoLocalizations.delegate',
      ]) {
        expect(
          appRoot,
          contains(delegate),
          reason: '少 $delegate ⇒ zh 环境下 Cupertino/Material 弹窗取不到本地化',
        );
      }
      expect(
        appRoot,
        contains('ScaffoldMessenger('),
        reason: 'CupertinoApp 不自带 ScaffoldMessenger，全站 showSnackBar 会在运行时抛',
      );
      for (final banned in const [
        'DefaultCupertinoLocalizations',
        'DefaultMaterialLocalizations',
      ]) {
        expect(
          appRoot,
          isNot(contains(banned)),
          reason: '$banned 只认 en，locale 为 zh 时弹窗直接抛',
        );
      }
    });

    test('明暗裁决点在 main.dart（MaterialApp 不再代劳）', () {
      final mainSource = codeByPath['lib/main.dart'];
      expect(mainSource, isNotNull);
      expect(
        mainSource!,
        contains('AppRoot('),
        reason: 'main.dart 不走 AppRoot ⇒ 上面三条对真机无效',
      );
      expect(
        mainSource,
        contains('didChangePlatformBrightness'),
        reason: '「跟随系统」档要在平台亮度变化时重解析，CupertinoApp 不代劳',
      );
    });
  });

  group('导航返回件', () {
    test('lib/ 不用 CupertinoNavigationBarBackButton', () {
      expect(
        hitting('CupertinoNavigationBarBackButton'),
        isEmpty,
        reason: '它带本地化「返回」文字，中文下把 leading 挤爆 ⇒ 一律用 SafeBackButton',
      );
    });

    test('SafeBackButton 在位且无路由可弹时不渲染', () {
      final button = codeByPath['lib/widgets/safe_back_button.dart'];
      expect(button, isNotNull, reason: 'SafeBackButton 被删 ⇒ base.md ② 无实现可指');
      expect(button!, contains('CupertinoIcons.back'));
      expect(
        button,
        contains('Navigator.maybeOf'),
        reason: '用 Navigator.of 会在根页（不可弹）上直接抛；必须 maybeOf + canPop 判定',
      );
    });
  });

  group('下拉刷新', () {
    test('RefreshIndicator 新增落点必须红（登记表只减不增）', () {
      final sites = hitting('RefreshIndicator(').toSet();
      expect(
        sites.difference(kPendingRefreshIndicatorSites),
        isEmpty,
        reason:
            '新增 Material 下拉刷新 ⇒ 纯 Cupertino 树里红屏；改用 CustomScrollView + CupertinoSliverRefreshControl',
      );
    });

    test('登记表里的落点必须都还在（换完一条就划掉一条）', () {
      final sites = hitting('RefreshIndicator(').toSet();
      expect(
        kPendingRefreshIndicatorSites.difference(sites),
        isEmpty,
        reason: '已换掉的落点没从登记表划掉 ⇒ 棘轮自己变陈旧，下一屏会误判为「还在」',
      );
    });
  });
}

/// 还没换成 `CupertinoSliverRefreshControl` 的历史落点（T83/#182 逐屏清）。
/// 只许缩短：新增一律红，清完一条就要在这里删掉一条。
const Set<String> kPendingRefreshIndicatorSites = <String>{
  'lib/pages/battery_page.dart',
  'lib/pages/device_state_page.dart',
  'lib/pages/notification_page.dart',
  'lib/pages/permission_settings_page.dart',
  'lib/pages/temperature_page.dart',
};

List<File> _dartFiles(String root) => Directory('$root/lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// 相对仓库根、正斜杠的路径（Windows 下 listSync 给反斜杠，登记表按正斜杠写）。
String _relative(String root, String path) =>
    path.substring(root.length + 1).replaceAll(r'\', '/');
