import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// 本文件相对仓库根的路径 —— harness 台账要排除自己（原因见 `harnessByPath`）。
const String _self = 'test/architecture/ui_style_guards_test.dart';

/// UI 风格守卫（base.md §6「UI 强约束」那三条的静态那半）。
///
/// 三条各断一个**运行期会炸**的契约，不断某版行形状：
/// ① 根组件：`MaterialApp` 会装 Material 默认文字样式 ⇒ Cupertino 文本变红 + 黄下划线；
///    `CupertinoApp` 缺 `GlobalCupertinoLocalizations` ⇒ 弹窗直接抛 "No CupertinoLocalizations
///    found"（表现为点了没反应）；缺 `ScaffoldMessenger` ⇒ 全站 `showSnackBar` 运行时抛。
/// ② 返回件：`CupertinoNavigationBarBackButton` 带本地化「返回」文字，中文下挤爆 leading。
/// ③ 下拉刷新：`RefreshIndicator` 依赖 `MaterialLocalizations`，纯 Cupertino 树里红屏。
///
/// ⚠ 本守卫对 `lib/` 是**禁止**，对 `test/` 是一本**只许缩短的台账**（
///   `kPendingMaterialAppTestHarnesses`）：历史 harness 各自 pump `MaterialApp`，
///   那验的不是真机上的那棵树 —— 片9 把第一批 12 个换成真根 `AppRoot`，当场撞出
///   `CardActionSheet` 的 18px 溢出（假根下靠 Material 那套文字尺寸刚好躲过）。
void main() {
  final root = projectRoot();
  final codeByPath = <String, String>{
    for (final file in _dartFilesIn(root, 'lib'))
      _relative(root, file.path): stripComments(file.readAsStringSync()),
  };
  // `test/` 侧同一套口径。⚠ 排除本文件自己：下面那些 needle 是**故意留在代码里的探针**
  // （`'MaterialApp('` 作为字符串字面量出现），剥注释不会剥掉它们，留着就成自指。
  final harnessByPath = <String, String>{
    for (final file in _dartFilesIn(root, 'test'))
      if (_relative(root, file.path) != _self)
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
    test('lib/ 不用 Material 的 RefreshIndicator（台账已清零 ⇒ 硬断）', () {
      expect(
        hitting('RefreshIndicator('),
        isEmpty,
        reason:
            '它依赖 MaterialLocalizations、画的还是 Material 那枚转圈 ⇒ 改用 CustomScrollView '
            '+ CupertinoSliverRefreshControl（唯一装配点 = PullToRefreshList）。'
            'T90 台账最后四处在 battery/device_state/permission_settings/temperature 页，'
            '2026-10-02 换完 ⇒ 这里不再是登记表，新增一律直接红',
      );
    });

    test('CupertinoSliverRefreshControl 只有一个装配点（PullToRefreshList）', () {
      expect(
        hitting('CupertinoSliverRefreshControl('),
        const <String>['lib/widgets/pull_to_refresh_list.dart'],
        reason: '各页自己搭 sliver ⇒ 「哪一页用的是哪一件」重新散落（T05/T06 同一条理由）',
      );
    });

    test('台账清零那四页确实换上了下拉壳（否则上一条会假绿）', () {
      // 只断「lib/ 里没有 RefreshIndicator」是不够的：把那四页的壳整块删掉同样绿。
      // 这一条钉的是另一半 —— 每一页的下拉手势都得有作者，而且只能由 PullToRefreshList 给。
      for (final page in const [
        'lib/pages/battery_page.dart',
        'lib/pages/device_state_page.dart',
        'lib/pages/permission_settings_page.dart',
        'lib/pages/temperature_page.dart',
      ]) {
        final src = codeByPath[page];
        expect(src, isNotNull, reason: '$page 不在了 ⇒ 这条断言在空转');
        expect(
          src!,
          contains('body: PullToRefreshList('),
          reason: '$page 的页面主体不再挂下拉壳 ⇒ 上一条「台账清零」就变成了「下拉没了」',
        );
        // 壳接上了还不算：这一发必须有作者。不看缩进（format 会动它），只看壳后面那一段参数表。
        final tail = src.split('body: PullToRefreshList(').last;
        final shellArgs = tail.length > 200 ? tail.substring(0, 200) : tail;
        expect(
          shellArgs,
          contains('onRefresh:'),
          reason: '$page 的下拉壳没接到本页的重读函数 ⇒ 拉一下什么都不做',
        );
      }
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
    // Material 对话框还很多（片8 之后剩 16 个文件），一次性换完的风险远大于收益 —— 于是新增一律红，
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

    test('已划掉的每一屏走的是 helper，不是自己手搭一枚 Cupertino 的', () {
      // 划掉台账有两条路：真的走共享件（`IosDialogActions` / `showIosOptionPicker`），
      // 或者把 `AlertDialog(` 就地改成 `CupertinoAlertDialog(`。后者让上面两条守卫都绿
      // （Material 那件确实没了），但标题字号 / 按钮色 / 可关性重新各页一份 ——
      // 与换根组件之前那种散落是同一样东西。所以这一条钉的是"走哪条路"（T90 片5/片6）。
      const migrated = <String, String>{
        'lib/pages/main_page_actions.dart': 'IosDialogActions.askConfirm(',
        'lib/pages/sms_monitor_settings_page.dart':
            'IosDialogActions.showInfo(',
        'lib/pages/widget_guide_page.dart': 'IosDialogActions.showInfo(',
        'lib/pages/more_page.dart': 'showIosOptionPicker<',
        'lib/pages/fnthink_push_page.dart': 'showIosInputDialog(',
        'lib/widgets/rule_template_sheet.dart': 'showIosInputDialog(',
      };
      for (final entry in migrated.entries) {
        final src = codeByPath[entry.key];
        expect(src, isNotNull, reason: '${entry.key} 不在了 ⇒ 本条在空转');
        expect(
          src!,
          contains(entry.value),
          reason: '${entry.key} 的弹层没接到共享件（${entry.value}）⇒ 形状又要各页一份',
        );
        expect(
          src,
          isNot(contains('CupertinoAlertDialog(')),
          reason:
              '${entry.key} 自己手搭了一枚 Cupertino 的 ⇒ 台账划掉了，但散落的还是散落的；'
              '请改走 ${entry.value}',
        );
      }
    });

    test('手搭 CupertinoAlertDialog 的文件是一本只许缩短的台账', () {
      // 上一条只管"已划掉的那几屏"；这一条管全 lib —— 不然新写一屏时可以绕过共享件
      // 直接搭 Cupertino 的弹层，风格闸一声不响（它禁的是 Material 那一件）。
      final handRolled = hittingRe(
        RegExp(r'(^|[^A-Za-z0-9_])CupertinoAlertDialog\('),
      ).toSet();
      expect(
        handRolled.difference(kHandRolledCupertinoDialogSites),
        isEmpty,
        reason:
            '又一处自己搭弹层 ⇒ 确认框走 `IosDialogActions.askConfirm` / `showInfo`，'
            '选档走 `showIosOptionPicker`；这两件是全站唯一装配点',
      );
      expect(
        kHandRolledCupertinoDialogSites.difference(handRolled),
        isEmpty,
        reason: '登记表里那一处已经不手搭了却没从台账划掉 ⇒ 这本账不能再当剩余工作量',
      );
    });
  });

  group('测试 harness 的根组件（T90 片9）', () {
    final fakeRoot = harnessByPath.entries
        .where((e) => e.value.contains('MaterialApp('))
        .map((e) => e.key)
        .toSet();

    test('test/ 里不得在台账之外再 pump MaterialApp(', () {
      expect(
        fakeRoot.difference(kPendingMaterialAppTestHarnesses),
        isEmpty,
        reason:
            '又一个 harness 用假根 ⇒ 它验的不是真机上那棵树（页面在 CupertinoApp 下'
            '的尺寸、文字样式、可关性都不同 —— 片9 就是这样漏掉一次溢出的）。'
            '请换成 `AppRoot(locale: …, dark: …, home: …)`',
      );
    });

    test('台账里那些 harness 都还 pump 着 MaterialApp（划掉之前先真换掉）', () {
      expect(
        kPendingMaterialAppTestHarnesses.difference(fakeRoot),
        isEmpty,
        reason: '台账与实际不符 ⇒ 这本账不能再当作剩余工作量',
      );
    });

    test('已划掉的那批 harness 走的是真根，不是自己再搭一枚壳', () {
      // 与「已划掉的每一屏走的是 helper」同一条道理：台账能靠"换个写法"划掉，
      // 也能靠"删掉那一句"划掉 —— 后者会让这条用例什么都验不到却仍是绿。
      const migrated = <String>[
        'test/widgets/card_action_sheet_test.dart',
        'test/widgets/temperature_page_test.dart',
        'test/widgets/device_state_page_test.dart',
        'test/widgets/permission_settings_page_test.dart',
        'test/widgets/sms_monitor_settings_page_test.dart',
        'test/widgets/widget_guide_page_test.dart',
        'test/widgets/fnthink_push_page_test.dart',
        'test/widgets/rule_edit_page_test.dart',
        'test/widgets/history_page_all_tab_test.dart',
        'test/widgets/history_page_backup_chip_test.dart',
        'test/widgets/history_page_fnthink_inbox_test.dart',
        'test/widgets/history_offline_drop_test.dart',
        // 片10：这一批页面里已没有 Material 弹层（不在 AlertDialog 台账上），
        // 换根的代价只有 import 面，收益是"页面上任何受根组件影响的行为"从此真被验到。
        'test/widgets/app_channel_list_page_test.dart',
        'test/widgets/app_channel_settings_page_test.dart',
        'test/widgets/channel_health_badge_test.dart',
        'test/widgets/channel_status_page_test.dart',
        'test/widgets/device_snapshot_page_test.dart',
        'test/widgets/email_settings_page_test.dart',
        'test/widgets/notification_engine_page_test.dart',
        'test/widgets/notification_page_channels_test.dart',
        'test/widgets/notification_page_fnthink_inbox_test.dart',
        'test/widgets/webhook_channel_list_page_test.dart',
      ];
      for (final path in migrated) {
        final src = harnessByPath[path];
        expect(src, isNotNull, reason: '$path 不在了 ⇒ 本条在空转（文件改名也要一起改这里）');
        expect(
          src!,
          contains("widgets/app_root.dart'"),
          reason: '$path 划掉了台账却没接上真根 AppRoot',
        );
        expect(
          src,
          contains('AppRoot('),
          reason: '$path import 了 AppRoot 却没用 ⇒ 大概又搭了一枚壳',
        );
        expect(
          src,
          isNot(contains('MaterialApp(')),
          reason: '$path 假根与真根并存 ⇒ 台账划得不干净',
        );
      }
    });
  });
}

/// 仍 pump `MaterialApp` 的 widget harness（T90 片9 起的台账，只许缩短）。
/// 不含本文件自己：这里那些 needle 是故意留在代码里的探针，见 `harnessByPath` 的排除。
const Set<String> kPendingMaterialAppTestHarnesses = <String>{
  'test/theme/text_selection_consistency_test.dart',
  'test/widgets/app_filter_page_test.dart',
  'test/widgets/webhook_settings_page_test.dart',
};

/// 仍在自己搭 `CupertinoAlertDialog` 的文件（T90 片6 起的台账，只许缩短）。
/// - `ios_dialog_actions.dart` / `ios_option_picker.dart` / `ios_input_dialog.dart` 是**装配点本身**
///   （确认框与说明框、选档、单字段输入）；
/// - `main.dart` 那两枚是 T56 的隐私同意门（要读两个勾选态、不可 barrier 关闭），
///   形状与"确认框"不同族，等它自己那片再收 —— 但新增一处就不许了。
const Set<String> kHandRolledCupertinoDialogSites = <String>{
  'lib/main.dart',
  'lib/widgets/ios_dialog_actions.dart',
  'lib/widgets/ios_option_picker.dart',
  'lib/widgets/ios_input_dialog.dart',
};

/// 还长着 Material `AlertDialog` 的文件（T83 逐屏换的台账，同上只许缩短）。
const Set<String> kPendingMaterialDialogSites = <String>{
  'lib/pages/app_filter_page.dart',
  'lib/pages/backup_restore_page.dart',
  'lib/pages/battery_page.dart',
  'lib/pages/device_state_page.dart',
  'lib/pages/history_page.dart',
  'lib/pages/main_page_dialogs.dart',
  'lib/pages/main_page_update.dart',
  'lib/pages/rule_edit_page.dart',
  'lib/pages/rule_edit_widgets.dart',
  'lib/pages/rule_list_page.dart',
  'lib/pages/rule_tester_page.dart',
  'lib/pages/temperature_page.dart',
  'lib/pages/webhook_settings_item.dart',
  // #176 片3 新增的一枚：与下面那枚是同一个形态（多字段输入弹层），#184 换那一屏时一起换。
  // 输入弹层刻意不用 `IosDialogActions`：那是**确认框**（一问一答），这里要的是三个输入项 + 选档。
  'lib/widgets/fnthink_pair_dialog.dart',
  'lib/widgets/fnthink_send_dialog.dart',
  'lib/widgets/icon_picker_tile.dart',
};

List<File> _dartFilesIn(String root, String dir) => Directory('$root/$dir')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// 相对仓库根、正斜杠的路径（Windows 下 listSync 给反斜杠，登记表按正斜杠写）。
String _relative(String root, String path) =>
    path.substring(root.length + 1).replaceAll(r'\', '/');
