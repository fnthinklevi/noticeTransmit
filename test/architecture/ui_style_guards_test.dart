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

  /// 按正则扫 —— `AlertDialog(` 必须带词边界：`CupertinoAlertDialog(` 里也含这三词。
  List<String> hittingRe(RegExp re) =>
      codeByPath.entries
          .where((e) => re.hasMatch(e.value))
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

    test('CupertinoSliverRefreshControl 只有一个装配点（PullToRefreshList）', () {
      expect(
        hitting('CupertinoSliverRefreshControl('),
        const <String>['lib/widgets/pull_to_refresh_list.dart'],
        reason: '各页自己搭 sliver ⇒ 「哪一页用的是哪一件」重新散落（T05/T06 同一条理由）',
      );
    });

    test('用户点名的那几页都接了自己的下拉入口', () {
      // 三个族页 + 状态页自己写处理函数；首页那张卡的 onRefresh 是**注入**的
      // （由 main_page 传下来），所以它的落点分两处断：页面里有壳、装配处给了作者。
      for (final page in const [
        'lib/pages/webhook_channel_list_page.dart',
        'lib/pages/app_channel_list_page.dart',
        'lib/pages/email_settings_page.dart',
        'lib/pages/channel_status_page.dart',
      ]) {
        final src = codeByPath[page];
        expect(src, isNotNull, reason: '$page 不在了 ⇒ 这条断言在空转');
        expect(
          src!,
          contains('onRefresh: _pullToRefresh'),
          reason: '$page 的下拉没接到 PullToRefreshList 的 onRefresh（手势没作者）',
        );
      }
      expect(
        codeByPath['lib/pages/notification_page.dart'],
        contains('onRefresh: onRefresh'),
        reason: '首页那张卡没接进下拉壳（用户点名的第一项就是这里）',
      );
      expect(
        librarySource(root, 'lib/pages/main_page.dart'),
        contains('onRefresh: _pullToRefreshHome'),
        reason: '首页的 onRefresh 仍指向旧作者 ⇒ 下拉只重读权限，不重探通道',
      );
    });

    test('下拉那一发是 force，回前台那一轮仍是 stale-only', () {
      // 两件事不能互相带跑：下拉是用户显式要"现在就重探"，回前台是顺手检查。
      // 前者不 force ⇒ 刚探过的一个请求都不发（手势成装饰品）；后者被改成 force ⇒
      // 每次切回 App 都对着三个通道服务商发一轮请求。
      for (final page in const [
        'lib/pages/webhook_channel_list_page.dart',
        'lib/pages/app_channel_list_page.dart',
        'lib/pages/email_settings_page.dart',
      ]) {
        expect(
          codeByPath[page]!,
          contains('_prober.probeNow('),
          reason: '$page 的下拉走的是 stale-only ⇒ 拉了等于没拉',
        );
      }
      final homeAndStatus =
          '${librarySource(root, 'lib/pages/main_page.dart')}\n'
          '${codeByPath['lib/pages/channel_status_page.dart']}';
      expect(
        homeAndStatus,
        contains('force: true'),
        reason: '首页/状态页的下拉没走 force（全族那一发同上）',
      );
      expect(
        homeAndStatus,
        contains('unawaited(probeChannelsAcrossFamilies());'),
        reason: '回前台那一轮被改成 force ⇒ 每次切回 App 对三族各发一轮请求',
      );
    });
  });

  group('确认框台账（Material AlertDialog）', () {
    // 不是一条「禁止」，而是一本**只许变薄的账**：这三条强约束之外，历史页面上的
    // Material 对话框还很多（22 个文件），一次性换完的风险远大于收益 —— 于是新增一律红，
    // 换完一屏就在台账里划掉一屏（#184 逐屏推进的可核对进度）。
    final materialDialogs = RegExp(r'(^|[^A-Za-z0-9_])AlertDialog\(');

    test('没有文件在台账之外新增长对话框', () {
      expect(
        hittingRe(
          materialDialogs,
        ).toSet().difference(kPendingMaterialDialogSites),
        isEmpty,
        reason:
            '新一处 Material AlertDialog ⇒ 与 Cupertino 风格不一致；确认框请用 IosDialogActions',
      );
    });

    test('台账里的文件都还长着一枚（划掉之前先真换掉）', () {
      expect(
        kPendingMaterialDialogSites.difference(
          hittingRe(materialDialogs).toSet(),
        ),
        isEmpty,
        reason: '台账与实际不符 ⇒ 这本账不能再当作剩余工作量',
      );
    });
  });
}

/// 还没换成 `CupertinoSliverRefreshControl` 的历史落点（T83/#182 逐屏清）。
/// 只许缩短：新增一律红，清完一条就要在这里删掉一条。
const Set<String> kPendingRefreshIndicatorSites = <String>{
  'lib/pages/battery_page.dart',
  'lib/pages/device_state_page.dart',
  'lib/pages/permission_settings_page.dart',
  'lib/pages/temperature_page.dart',
};

/// 还长着 Material `AlertDialog` 的文件（T83 逐屏换的台账，同上只许缩短）。
const Set<String> kPendingMaterialDialogSites = <String>{
  'lib/pages/app_filter_page.dart',
  'lib/pages/backup_restore_page.dart',
  'lib/pages/battery_page.dart',
  'lib/pages/device_state_page.dart',
  'lib/pages/fnthink_push_page.dart',
  'lib/pages/history_page.dart',
  'lib/pages/main_page_actions.dart',
  'lib/pages/main_page_dialogs.dart',
  'lib/pages/main_page_update.dart',
  'lib/pages/more_page.dart',
  'lib/pages/rule_edit_page.dart',
  'lib/pages/rule_edit_widgets.dart',
  'lib/pages/rule_list_page.dart',
  'lib/pages/rule_tester_page.dart',
  'lib/pages/sms_monitor_settings_page.dart',
  'lib/pages/temperature_page.dart',
  'lib/pages/webhook_settings_item.dart',
  'lib/pages/widget_guide_page.dart',
  // #176 片3 新增的一枚：与下面那枚是同一个形态（多字段输入弹层），#184 换那一屏时一起换。
  // 输入弹层刻意不用 `IosDialogActions`：那是**确认框**（一问一答），这里要的是三个输入项 + 选档。
  'lib/widgets/fnthink_pair_dialog.dart',
  'lib/widgets/fnthink_send_dialog.dart',
  'lib/widgets/icon_picker_tile.dart',
  'lib/widgets/rule_template_sheet.dart',
};

List<File> _dartFiles(String root) => Directory('$root/lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// 相对仓库根、正斜杠的路径（Windows 下 listSync 给反斜杠，登记表按正斜杠写）。
String _relative(String root, String path) =>
    path.substring(root.length + 1).replaceAll(r'\', '/');
