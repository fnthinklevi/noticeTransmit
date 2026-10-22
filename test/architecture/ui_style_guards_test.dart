import 'dart:convert';
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

  /// 同一个口径但**逐文件数枚数**：台账记的是「这个文件几枚」，不是「这个文件有没有」。
  Map<String, int> countingRe(RegExp re) => {
    for (final e in codeByPath.entries)
      if (re.hasMatch(e.value)) e.key: re.allMatches(e.value).length,
  };

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
      expect(hitting('CupertinoSliverRefreshControl('), const <String>[
        'lib/widgets/pull_to_refresh_list.dart',
      ], reason: '各页自己搭 sliver ⇒ 「哪一页用的是哪一件」重新散落（T05/T06 同一条理由）');
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
        contains('probeChannelsAcrossFamilies(onUpdated: _onHealthRecorded)'),
        reason:
            '回前台那一轮被改成 force ⇒ 每次切回 App 对三族各发一轮请求。'
            '（T114 之后那一句的形状是「带 onUpdated、不带 force」—— '
            '这里断的是后一半，前一半的牙在 `channel_health_reprobe_guard_test` 那一组）',
      );
    });
  });

  // ── T90 补册（2026-10-05）：另两族从未被纳入，也从没有守卫 ──────────────
  // ── T148 片4（差异⑧ 的实话）──────────────────────────────────────────────
  // 上面那本「裸 TextButton」台账与下面那条「自搭 CupertinoButton 清零」的扫描口径都是
  // `lib/pages/fnthink_*`（判据原话是"幻念这六张页归零"，不是全库）。⇒ T148 的判据要的是
  // 「**所有**历史页照推送历史那一形状长」，而两张历史页（转发行 + 远程执行历史）里的动作
  // 按钮**一枚都不在册**：在那儿新写一枚裸 `TextButton(` 或自搭 `GestureDetector(`，
  // 不会有任何一条守卫红。这册先把现状钉成数字（只许变薄），下一步换形状时按格往下减。
  // ⚠ 这本账**不是**"这些形状合法"的背书：它记的是欠账，与 T90 那两本同一条纪律。
  group('两张历史页里的动作形状（T148 差异⑧ 的台账）', () {
    // 现测（2026-10-12 片4 立账，剥注释后逐枚数）：每一格都是一笔要还的债，不是合法形状名单。
    //   · `history_page.dart` 裸 `TextButton(` 原 4 枚 ＝ 收件详情弹层「回复／重发」+ 筛选面板
    //     「重置」+ 批量底栏「取消」；**片6 换掉前两枚、片7 换掉「重置」、片8 换掉「取消」** ⇒
    //     **清零，那一列从账上摘掉**（长回来键集不等当场红）。
    //     4 枚 `GestureDetector(` 原是行内那枚自搭「现在推送」蓝底小钮、chip 展开、档位芯片、筛选条清除；
    //     **片9 换掉「筛选条清除」**（行内文字动作 ⇒ 归件）⇒ 现 3 枚，且这三枚**不是同一族**：
    //       · 「现在推送」蓝底小钮 = **动作**，登记成因「行内填充式小钮没有对应公共件」的例外
    //         （`PrimaryActionButton` 是全宽主操作、`FnthinkInlineAction` 无底色 ⇒
    //          要统一必须先定"行内填充小钮"这个形状，并同批核它的同类，属另一件事）；
    //       · chip 展开 + 档位芯片 = **chip 族**（行内密度 10px/radius 3 与 13px/radius 8），
    //         与 `FnthinkChoiceChip`（13px/radius 10 的"一排可选项里的一枚"）不是同一族的密度 ——
    //         硬并会把行内 chip 放大一圈，那是重设计不是统一。
    //     ⇒ **差异⑧ 到这一片收口**：这条线只管**动作**；动作四枚已是「三枚走件 + 一枚登记例外」，
    //       chip 族那两枚留在账上作为**另一笔账**（行内 chip 形状统一），不再算在"动作形状四种"里。
    //     7 枚 `IconButton(` ＝ AppBar／搜索后缀／离线横幅那一族（T90 片9 之后仍在 Material 侧）。
    //     ⚠ 片6 现读又补两列：这一页还有 **1 枚 `ElevatedButton(`（筛选面板「应用」）与
    //     1 枚 `FilledButton.icon(`（批量底栏「重推」）—— 两枚 Material 控件此前不在任何一本账里，
    //     连"别变多"都没人管；差异⑧ 说的"四种形状"实measure 出来是**五种**。
    //     ⚠ 片7 换掉「应用」⇒ `ElevatedButton(` **清零**，那一列就此从账上摘掉：本组的键集判据
    //     （实测形状集合 ⇄ 台账键集相等）会在它长回来当场红 ⇒ 摘列不等于放开，是"这一族已经没了"。
    //     ⚠ 片8 之后 `FilledButton.icon(` **刻意留着、记成已登记的例外**：公共件
    //     `PrimaryActionButton` 的公开签名只有 label／subtitle／onPressed，**没有图标槽**，而底栏那枚
    //     "把这 N 条再发一次"的信息量一半在 replay 图标上。给件加图标参数＝新增公共件能力，
    //     要同批核它 9 个既有调用点的形状一致性；丢图标＝用可读性换账面整齐。两条都比"留着并写明理由"贵。
    //     **这一格照样受管**：长第二枚 `FilledButton.icon(` 时上面那条枚数判据当场红。
    //   · `remote_history_page.dart` 的 2 枚自搭 `CupertinoButton(` ＝ 撤销那一枚与方向芯片。
    //     注意它**不在**幻念那六张页的口径里（文件名不是 `fnthink_` 前缀），所以「自搭按钮清零」
    //     那条一直管不到它 —— 这一格就是那条漏口的账面。
    //     ⚠ 片11 换掉「撤销」（它是**对这一行做一次动作**，与名单页／端点页／收件详情同一族）
    //     ⇒ 2 → **1**；剩那一枚是**方向芯片**（收/发/全部三档切换），属 chip 族那笔另立的账，
    //     不在"动作形状"这一列里 —— 拿它去凑"动作清零"会把两种不同的事混成一件。
    //     ⚠ 片12 把这一页的**方向条**也换进公共件 `FnthinkChoiceChip` ⇒ `CupertinoButton(`
    //     1 → **0**，那一列就此从账上摘掉（键集判据会在它长回来当场红 —— 摘列不是放开）。
    //     ⚠ 那一格清零之后**页路径仍留在册里**：这是那条漏口的账面，不是"这页已合规"的背书 ——
    //     它管的是"这一页别再长出自搭动作/芯片"。折叠那枚（`history-chip-fold-*`，10px/radius 3）
    //     **刻意没并**：它不是"可选项里的一枚"，是"还有 N 条"的展开提示，硬并会把行内放大一圈。
    //   · T148 片15（2026-10-14）：这一页那两枚**实心动作**（行内「现在推送」自搭 `GestureDetector`
    //     ＋底栏那枚 Material `FilledButton.icon`「补推」）一起归进新公共件 `FnthinkFilledAction`
    //     ⇒ `GestureDetector(` 1 → **0**、`FilledButton.icon(` 1 → **0**，两列都从账上摘掉。
    //     ⚠ 摘掉的是"这两族在这一页不再存在"，不是"这两族合法了"：`IconButton(` 那 7 枚仍是账
    //     （AppBar／搜索后缀／离线横幅那一族，T90 侧的债），而新增的边界由下面那两条钉 ——
    //     件不许长成全宽（那是 `PrimaryActionButton` 的活），全宽件不许长出图标槽（那才是片8 原路）。
    const kHistoryPages = <String, Map<String, int>>{
      'lib/pages/history_page.dart': {
        // T148 片13（2026-10-14）：那 13 枚筛选芯片换进公共件 `FnthinkChoiceChip` ⇒ 3 → 2。
        //   摘掉的那一枚是 `_filterChip` 自搭壳里的 `GestureDetector(`（现在那枚方法只转发）。
        // T148 片14（2026-10-14）：折叠那枚「还有 N 条／收起」归 `FnthinkInlineAction` ⇒ 2 → 1。
        //   ⚠ 它以前**冒充状态标记**（同行 chip 那身 10px/radius 3 的外衣），而它有 `onTap` ——
        //   屏上读不出点得动，与 T108 片②、片12 量到的是同一个病。
        // T148 片15（2026-10-14）：「现在推送」归 `FnthinkFilledAction` ⇒ 1 → **0**，那一列摘掉。
        //   剩这一列是 AppBar／搜索后缀／离线横幅那 7 枚 `IconButton(`：那是图标按钮族，
        //   与"行内那枚实心小钮"不同一层（尺寸、命中区、禁用态都不一样），别顺手一起搬。
        'IconButton(': 7,
      },
      'lib/pages/remote_history_page.dart': <String, int>{},
    };

    final shapeRe = {
      for (final k in const [
        'TextButton(',
        'CupertinoButton(',
        'GestureDetector(',
        'IconButton(',
        // Material 那一族只数**构造点**：`FilledButton.styleFrom` 与 `ElevatedButton.styleFrom`
        // 是同一个按钮的样式声明，不是第二个动作（数 occurrence 会把一枚算成两枚）。
        'ElevatedButton(',
        'FilledButton.icon(',
      ])
        k: RegExp('(^|[^A-Za-z0-9_])${RegExp.escape(k)}'),
    };

    Map<String, Map<String, int>> measure() => {
      for (final p in kHistoryPages.keys)
        p: {
          for (final e in shapeRe.entries)
            if (e.value.allMatches(codeByPath[p] ?? '').isNotEmpty)
              e.key: e.value.allMatches(codeByPath[p] ?? '').length,
        },
    };

    test('两张页都还在扫描口径里（漂了就整册成空转）', () {
      for (final p in kHistoryPages.keys) {
        expect(
          codeByPath.containsKey(p),
          isTrue,
          reason: '$p 读不到 ⇒ 下面几条对任何仓库都恒真，这本账是空的',
        );
      }
      final sum = kHistoryPages.values.fold<int>(
        0,
        (a, m) => a + m.values.fold<int>(0, (x, y) => x + y),
      );
      expect(sum, greaterThan(0), reason: '台账一枚都没登记 ⇒ "不许变多"等于没写（本仓不许空表当守卫）');
    });

    test('逐页逐形状：枚数与台账相等，账外多一枚就红', () {
      final got = measure();
      for (final p in kHistoryPages.keys) {
        expect(
          got[p]!.keys.toSet(),
          kHistoryPages[p]!.keys.toSet(),
          reason:
              '$p 里出现了台账之外的动作形状（或账上那一形状已经清零）⇒ '
              '换了形状要回来记账：实际 $got，台账 ${kHistoryPages[p]}',
        );
        for (final e in kHistoryPages[p]!.entries) {
          expect(
            got[p]![e.key] ?? 0,
            e.value,
            reason:
                '$p 的 ${e.key} 实际 ${got[p]![e.key] ?? 0} 枚、台账 ${e.value} 枚 ⇒ '
                '多一枚就是又长出一个动作形状（T148 差异⑧），少一枚就是真换掉了公共件',
          );
        }
      }
    });

    test('收件详情那两枚行内动作由公共件给出（差异⑧ 换形状的第一格）', () {
      final src = codeByPath['lib/pages/history_page.dart']!;
      for (final key in const ['fnthink-inbox-reply', 'fnthink-inbox-resend']) {
        expect(
          RegExp("FnthinkInlineAction\\(\\s*key: const ValueKey\\('$key'\\)")
              .hasMatch(src),
          isTrue,
          reason:
              '$key 不再由 `FnthinkInlineAction` 给出 ⇒ 这一族的字号与语义色又回到页面自己挑'
              '（颜色唯一作者是 `FnthinkInlineAction.colorOf`），'
              '收件详情那一格长回第五种形状（T148 差异⑧）',
        );
      }
      expect(
        RegExp("TextButton\\(\\s*key: const ValueKey\\('fnthink-inbox-")
            .hasMatch(src),
        isFalse,
        reason: '详情弹层里再出现裸 `TextButton` ⇒ 台账那一格 2 枚的读数就是它长回来的',
      );
    });
    test('筛选面板那一双「一实一虚」照页脚那一对同形（片7）', () {
      final src = codeByPath['lib/pages/history_page.dart']!;
      expect(
        RegExp("SecondaryActionButton\\(\\s*keyName: 'history-filter-reset',")
            .hasMatch(src),
        isTrue,
        reason:
            '「重置」不再由 `SecondaryActionButton` 给出 ⇒ 这一对虚的那一枚又回到页面自挑配色'
            '（页脚那一对在通道设置页已经是同一形状，两处各搭各的迟早不一样）',
      );
      expect(
        RegExp(
          "PrimaryActionButton\\(\\s*key: const ValueKey\\('history-filter-apply'\\),",
        ).hasMatch(src),
        isTrue,
        reason: '「应用」不再由 `PrimaryActionButton` 给出 ⇒ 实心那一枚的圆角/内边距/禁用态又有一份自己的写法',
      );
      expect(
        RegExp(r"Expanded\(\s*child: ElevatedButton\(").hasMatch(src),
        isFalse,
        reason:
            '账上 `ElevatedButton(` 已清零（形状没了就该从账上摘掉）⇒ 这里再出现就是把它长回来了，'
            '而键集判据也会同时红 —— 两条各钉一维：这条钉装配点，那条钉枚数',
      );
    });

    test('批量底栏那枚「取消」走件、语义色取中性（片8）', () {
      final src = codeByPath['lib/pages/history_page.dart']!;
      expect(
        RegExp(
          "FnthinkInlineAction\\(\\s*key: const ValueKey\\('history-batch-cancel'\\),",
        ).hasMatch(src),
        isTrue,
        reason: '底栏那枚「取消」不再由件给出 ⇒ 裸 `TextButton` 那一列清零之后又长回来（键集判据也会红）',
      );
      expect(
        RegExp(r'FnthinkActionTone\.neutral').hasMatch(src),
        isTrue,
        reason:
            'tone 取默认的 action（蓝）⇒ 「只退出批量模式」这一枚看起来像"会改到某一批东西"；'
            '中性色是这一格的语义（差异④ 那条"会让东西从此不可用才配红"在这里不成立）',
      );
    });

    test('筛选条那枚「清除」走件（片9：差异⑧ 的动作线在这里收口）', () {
      final src = codeByPath['lib/pages/history_page.dart']!;
      expect(
        RegExp(
          "FnthinkInlineAction\\(\\s*key: const ValueKey\\('history-filter-clear'\\),",
        ).hasMatch(src),
        isTrue,
        reason:
            '筛选条那枚「清除」不再由件给出 ⇒ 它又长回"自搭 GestureDetector + ✕ 图标 + 12px 蓝字"'
            '（行内文字动作那一族的形状）',
      );
      expect(
        RegExp(r"GestureDetector\(\s*onTap: _clearAllFilters").hasMatch(src),
        isFalse,
        reason: '同一个动作又被搭了一遍 ⇒ 上面那条正则能过、这一格却在屏上长着第二份',
      );
    });

    test('远程执行历史那页的「撤销」走行内动作件（片11a）', () {
      final src = codeByPath['lib/pages/remote_history_page.dart']!;
      expect(
        RegExp(
          r"FnthinkInlineAction\(\s*key: ValueKey\('remote-history-cancel-\$\{row\.execId\}'\),",
        ).hasMatch(src),
        isTrue,
        reason:
            '「撤销」不再由 `FnthinkInlineAction` 给出 ⇒ 这一页又回到页面自挑字号与颜色'
            '（台账那一列 2→1 的读数也就是它长回来的）',
      );
      expect(
        RegExp(r"CupertinoButton\(\s*key: ValueKey\('remote-history-cancel-")
            .hasMatch(src),
        isFalse,
        reason: '同一个动作被搭了两遍（件在、自搭壳也在）⇒ 键集判据看不出，这一条才看得出',
      );
    });

    test('那一枚的 tone 不许被换成 destructive（片11b：换件不改配色）', () {
      final src = codeByPath['lib/pages/remote_history_page.dart']!;
      expect(
        RegExp(r'FnthinkActionTone\.destructive').hasMatch(src),
        isFalse,
        reason:
            '这一枚取**缺省的 action（蓝）**：统一形状那一片不该顺手改用户看到的颜色。'
            '红那一档在这套件上是"吊销一项长期存在的东西"（名单页那枚撤销＝断掉配对关系），'
            '而这里撤回的是一条还在窗口里的指令 —— 画红会把"取消一次动作"说成"销毁一条记录"。',
      );
    });

    test('方向条走公共件 `FnthinkChoiceChip`（片12：行内 chip 那笔账的第一格）', () {
      final src = codeByPath['lib/pages/remote_history_page.dart']!;
      for (final key in const ['in', 'out', 'all']) {
        expect(
          RegExp("FnthinkChoiceChip\\(\\s*keyName: 'remote-history-dir-$key'")
              .hasMatch(src),
          isTrue,
          reason:
              'remote-history-dir-$key 不再由 `FnthinkChoiceChip` 给出 ⇒ 这一族又回到页面自己搭，'
              '而公共件那两档（选中描边+底色／忙时置灰）就是它存在的理由',
        );
      }
      expect(
        RegExp(r'_DirectionChip\(').hasMatch(src),
        isFalse,
        reason: '同一个方向条被搭了两遍（件在、私有壳也在）⇒ 用量判据看不出，这一条才看得出',
      );
      expect(
        RegExp(r'active:').hasMatch(src),
        isFalse,
        reason: '公共件那一格叫 `selected`；这里再出现 `active:` 说明还留着旧签名的一处调用',
      );
    });

    test('私有 chip／徽标那一族只剩一个作者（全族扫描再对差集，片12 起、片16 扩口径）', () {
      // 判据**不写"不许出现 `_DirectionChip`"那种字面口径** —— 换名 `_MyChip` 就绕过，
      // 而那正是这一族会漂的方式（T100 片5 的 `_Note` 同一条纪律）。
      // ⚠ 片16 把认法从"名以 `Chip` 结尾"扩到 `Chip|Badge|Tag|Mark`：通道状态页那枚 `_RoleBadge`
      //   就是这么躲过原口径的 —— 它是私有的徽标壳，形状与 `FnthinkChoiceChip` 那族同一层，
      //   但扫描只认 `Chip` ⇒ "这一族别再长一份"对它根本不响（登记为漏口，不是"它合法"）。
      expect(
        privateMarkShells(codeByPath.values),
        isEmpty,
        reason:
            '${privateMarkShells(codeByPath.values)} —— 页里又长出私有的行内小形状壳 ⇒ '
            '「可选项里的一枚／徽标里的一格」有第二份画法：选中态怎么表达（底色？描边？只有字重？）'
            '会各写各的，而"只有字重差"那一档的病是**用户在屏上读不出自己选上了没有**'
            '（T108 片② 在发送页实测过那一发）',
      );
    });

    test('那把全族扫描的尺认得合成样本（防上一条退化成"一枚都没认出来＝恒绿"）', () {
      const sample = '''
class _MyChip extends StatelessWidget {
  const _MyChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Text(label);
}

class _MyRoleBadge extends StatelessWidget {
  const _MyRoleBadge({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Text(label);
}

class FnthinkChoiceChip extends StatelessWidget {
  const FnthinkChoiceChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Text(label);
}

class FnthinkStatusMark extends StatelessWidget {
  const FnthinkStatusMark({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Text(label);
}
''';
      expect(
        // ⚠ 两条各钉一维：`_MyChip` 钉"原名还在"，`_MyRoleBadge` 钉**扩出来的那半口径真的在认** ——
        //   只测前者的话，把 `Badge|Tag|Mark` 从正则里删掉这条照样绿（那就是 `_RoleBadge` 躲过去的老样子）。
        privateMarkShells([sample]),
        ['_MyChip', '_MyRoleBadge'],
        reason: '私有壳都抓不到 ⇒ 全族扫描那条绿只说明"正则没匹配到任何东西"',
      );
      // 反向：全是公共件时不许红（否则这条守卫拦的是不存在的事）。
      expect(
        privateMarkShells([
          sample
              .replaceAll('class _MyChip', 'class FnthinkOtherChip')
              .replaceAll('class _MyRoleBadge', 'class FnthinkOtherBadge'),
        ]),
        isEmpty,
        reason: '公共件被当成抄本 ⇒ 这本账红得没有信息量',
      );
    });

    /// 从 `class X` 取到下一个顶层 `class` 之前 —— 件的边界要按**类体**读。
    /// ⚠ 不用整文件搜：`fnthink_card.dart` 里 `FnthinkEntryRow` 就写着 `double.infinity`
    ///   的邻居形状，全文件搜会把两件事混成一件（本仓量过的"尺口径宽于被量之物"）。
    String classBody(String src, String className) {
      final start = src.indexOf('class $className');
      expect(
        start,
        greaterThan(-1),
        reason: '$className 不在那一份文件里了 ⇒ 下面几条断言全是空的（绿的没内容）',
      );
      final end = src.indexOf('\nclass ', start + className.length);
      return src.substring(start, end < 0 ? src.length : end);
    }

    /// 取一个**成员**（方法／顶层函数）的正文：从签名到下一个成员开头（或顶层函数的收尾 `}`）。
    /// ⚠ 同样不用 `blockAfter`：参数表里带 `{required …}` 时它会把参数表当函数体返回（假绿形状）。
    /// ⚠ 先归一 CRLF：`codeByPath` 是 `readAsStringSync()` 的原文，`history_page.dart` 这类文件
    ///   行尾是 `\r\n` ⇒ 拿 `'\n  Widget '` 去切会一段都切不到（本仓"同一批里两种 EOL 并存"那条坑）。
    String memberOf(String srcRaw, String signature) {
      final src = srcRaw.replaceAll('\r\n', '\n');
      final start = src.indexOf(signature);
      expect(
        start,
        greaterThan(-1),
        reason: '找不到 $signature ⇒ 它被改名或删掉了，下面这些断言会全空',
      );
      const cuts = [
        '\n  /// ',
        '\n  Widget ',
        '\n  String ',
        '\n  Future<',
        '\n  @override',
        '\nclass ',
        '\nenum ',
        '\n}\n',
      ];
      final ends = [
        for (final c in cuts)
          if (src.indexOf(c, start + signature.length) > start)
            src.indexOf(c, start + signature.length),
      ]..sort();
      expect(ends, isNotEmpty, reason: '$signature 之后找不到成员边界 ⇒ 页面形状变了');
      return src.substring(start, ends.first);
    }

    test('三处行内徽标都由 `FnthinkStatusMark` 给出（片16：一个作者、按主语分三档）', () {
      final hist = codeByPath['lib/pages/history_page.dart']!;
      final tag = memberOf(hist, 'Widget _tagBadge(');
      expect(
        tag.contains('FnthinkStatusMark(') &&
            tag.contains('FnthinkMarkRole.attribute'),
        isTrue,
        reason:
            '「高优／备用」这类属性徽标又回到页面自搭 ⇒ 同一行里三份壳各长各的（padding／圆角／淡底 α），'
            '下一枚徽标就会从这几份里挑一份抄',
      );
      for (final shell in const ['BoxDecoration(', 'BorderRadius.circular(']) {
        expect(
          tag.contains(shell),
          isFalse,
          reason: '换了件还留着 $shell ⇒ 件与自搭壳并存（两套形状同时在场，漂哪一套都没人喊）',
        );
      }
      final chip = memberOf(hist, 'Widget _buildChannelChip(');
      expect(
        chip.contains('FnthinkStatusMark(') &&
            chip.contains('FnthinkMarkRole.channel') &&
            chip.contains('FnthinkSubMark'),
        isTrue,
        reason:
            '通道 chip 的壳或它那两句次级字（「备用」／状态读数）回到页面自搭 ⇒ 9px 与 6px 圆点这两格'
            '又是各写各的，而它们是"这条走了哪条通道、发出去没有"的唯一读数',
      );
      final role = memberOf(
        codeByPath['lib/pages/channel_status_page.dart']!,
        'Widget _roleBadge(BuildContext context, String role)',
      );
      expect(
        role.contains('FnthinkStatusMark(') &&
            role.contains('FnthinkMarkRole.tier'),
        isTrue,
        reason:
            '角色徽标又自己搭壳 ⇒ 私有 `_RoleBadge` 那一格回到"扫描口径管不到"的老样子；'
            '页面这边只该留「角色→(词, 是否实心)」这一份判定',
      );
    });

    test('描边只绑 tier 那一档（片16：徽标族的三档不能长成一个样）', () {
      final mark = classBody(
        codeByPath['lib/widgets/fnthink_card.dart']!,
        'FnthinkStatusMark',
      );
      expect(
        mark.contains('Container(') && mark.contains('Text('),
        isTrue,
        reason: '这一件没在画东西 ⇒ 下面两条"含/不含某形状"全是空断言（绿的没内容）',
      );
      expect(
        RegExp(r'Border\.all\(').allMatches(mark).length,
        1,
        reason:
            '描边出现两处以上 ⇒ "这一项处在哪一档"与"这条有什么额外要标的"两种语义又混了：'
            '另两档画上线等于在说"这是可对照的档位"，而它不是',
      );
      expect(
        RegExp(r'role\s*==\s*FnthinkMarkRole\.tier').allMatches(mark).length,
        1,
        reason:
            '描边位不再唯一绑在 tier 那一档 ⇒ 属性徽标也会带框（或档位标记反而没框）：'
            '前者把附注说成档位，后者让"主／未设置"只剩颜色差 —— 两种都是读不出',
      );
    });

    test('徽标件本身不可点（片16：与"能点的那一枚"分界）', () {
      final mark = classBody(
        codeByPath['lib/widgets/fnthink_card.dart']!,
        'FnthinkStatusMark',
      );
      expect(
        mark.contains('Container('),
        isTrue,
        reason: '这一件不在画东西 ⇒ 下面那一串"全都不在"是空断言',
      );
      // ⚠ needle 用**词**而不是 `onTap:` —— 件的公开签名里只要出现"点击回调"这一格（`this.onTap`、
      //   `onPressed`…），它就已经在对外承诺"我能点"了；等它被写进 build 才红就晚了一步。
      for (final shape in const [
        'onTap',
        'onPressed',
        'GestureDetector(',
        'InkWell(',
        'CupertinoButton(',
      ]) {
        expect(
          mark.contains(shape),
          isFalse,
          reason:
              '徽标是**读数不是入口**（片14 那条族规矩：同一行里"能点的那一枚"与"只是状态的标记"'
              '不许互换形状）。要动作走 `FnthinkInlineAction`／`FnthinkFilledAction`；'
              '$shape 出现在这里就是那一行凭空多了一个入口',
        );
      }
    });

    test('两枚实心动作都由 `FnthinkFilledAction` 给出（片15：差异⑧ 最后两格收口）', () {
      final src = codeByPath['lib/pages/history_page.dart']!;
      expect(
        RegExp(r"FnthinkFilledAction\(\s*key: ValueKey\('history-push-now-")
            .hasMatch(src),
        isTrue,
        reason:
            '行内那枚「现在推送」不再由件给出 ⇒ 台账那一列（`GestureDetector(`）只看得见"多了一枚形状"，'
            '看不见"这一枚的形状由谁定"；换件的意义正在这一步',
      );
      expect(
        RegExp(
          r"FnthinkFilledAction\(\s*key: const ValueKey\('history-batch-push'\),",
        ).hasMatch(src),
        isTrue,
        reason:
            '底栏那枚「补推」不再由件给出 ⇒ Material `FilledButton.icon` 长回来，'
            '它的禁用态、圆角、图标尺寸都由 Material 定，而不是由这一族定',
      );
      expect(
        RegExp(r'FnthinkFilledAction\(').allMatches(src).length,
        2,
        reason:
            '这一页今天恰好两处调用点（行内 + 底栏）。第三处出现时要么改这条并写明它为什么同档，'
            '要么用现成的另一件 —— 与上面那两条枚数判据同一条纪律：账与代码一致',
      );
    });

    test('实心小钮不许长成"全宽主操作"（片15：两件分工的前一半）', () {
      final filled = classBody(
        codeByPath['lib/widgets/fnthink_card.dart']!,
        'FnthinkFilledAction',
      );
      expect(
        filled.contains('CupertinoButton('),
        isTrue,
        reason: '这一件没在画东西 ⇒ 下面那条"不含 double.infinity"是空断言（绿的没内容）',
      );
      expect(
        filled.contains('double.infinity'),
        isFalse,
        reason:
            '它一占满宽就和 `PrimaryActionButton` 是同一件事两个作者 —— '
            '而"一页最多一枚主操作"那条判据靠的就是这两件事分得开',
      );
    });

    test('全宽主操作今天不带图标（片15：后一半 —— 别把新形状并回老件）', () {
      final primary = classBody(
        codeByPath['lib/widgets/primary_action_button.dart']!,
        'PrimaryActionButton',
      );
      expect(
        primary.contains('label'),
        isTrue,
        reason: '那件读不到了 ⇒ 上面/下面这些断言全是空的（文件漂了要喊）',
      );
      expect(
        RegExp(r'IconData|\bicon\b').hasMatch(primary),
        isFalse,
        reason:
            '给全宽件加图标槽＝片8 那条原路，而它 9 个调用点一个都不带图标；这个需求已由 '
            '`FnthinkFilledAction` 接住。这条钉的是"今天不需要"：'
            '将来真要一枚全宽带图标的主操作，改它的人得先说清那一枚归哪一件',
      );
    });
  });

  group('转场与轻提示两族（T90 补册：防变多，不是「要换掉的清单」）', () {
    // ⚠ 这两族**从来没进过台账**：那 27 片换的是对话框 / 列表选择器 / 表单弹层 /
    //   下拉壳，而 `MaterialPageRoute` 与 `showSnackBar` 是另外两族。
    //   后果不是"风格不统一"这么轻 —— 它们**改坏了没有任何一条守卫会红**，
    //   而新增一处也不会有人知道多了一处。本册把它们钉成「只许变薄」。
    //
    // ⚠ **`showSnackBar` 的换法尚未定**：SnackBar 在 Cupertino 里**没有对应控件**
    //   （`CupertinoApp` 下它仍按 Material 样式渲染），换它要先有一个自己的
    //   轻提示装配点（`IosDialogActions` 那族已有 `showInfo`，但那是对话框不是轻提示）。
    //   在那之前，本册只管「别变多」—— 不假装"清零"就算完成。
    for (final spec in const [
      (
        name: 'MaterialPageRoute',
        pattern: r'(^|[^A-Za-z0-9_])MaterialPageRoute',
        sites: kMaterialRouteSites,
      ),
      (
        name: 'showSnackBar',
        pattern: r'(^|[^A-Za-z0-9_])showSnackBar',
        sites: kSnackBarSites,
      ),
    ]) {
      final pattern = RegExp(spec.pattern);

      test('${spec.name}：没有文件在台账之外新增', () {
        expect(
          hittingRe(pattern).toSet().difference(spec.sites.keys.toSet()),
          isEmpty,
          reason:
              '新一处 ${spec.name} ⇒ 这一族从 T90 补册起就不受任何守卫保护，'
              '而换法（尤其 SnackBar 没有 Cupertino 对应件）还没定 ⇒ '
              '先记账，不许悄悄加',
        );
      });

      test('${spec.name}：逐文件枚数与台账相等', () {
        final actual = countingRe(pattern);
        expect(
          actual.keys.toSet(),
          spec.sites.keys.toSet(),
          reason: '台账内外的文件对不上 ⇒ 这本账不能再当剩余工作量',
        );
        for (final entry in spec.sites.entries) {
          expect(
            actual[entry.key],
            entry.value,
            reason:
                '${entry.key} 实际 ${actual[entry.key] ?? 0} 枚、台账记 ${entry.value} 枚'
                '（多一枚红：账内加一枚没人喊；少一枚也红：顺手把账改小）',
          );
        }
      });
    }
  });

  group('幻念页里的裸 TextButton（T100 片2 的台账）', () {
    // 词边界与 AlertDialog 那条同因：`CupertinoButton(` 不含这三词，但 `_TextButton(` 之类的
    // 自定义件会 —— 判据要的是"裸的那一枚"，所以前一个字符不能是标识符字符。
    final rawTextButton = RegExp(r'(^|[^A-Za-z0-9_])TextButton\(');

    // 只扫幻念那几张页：§1 的判据②说的是"幻念这六张页里计数归零"，不是全库。
    Map<String, int> fnthinkOnly() => {
      for (final e in countingRe(rawTextButton).entries)
        if (e.key.startsWith('lib/pages/fnthink_')) e.key: e.value,
    };

    test('账内外的文件对得上（账外的页长出一枚就红）', () {
      expect(
        fnthinkOnly().keys.toSet(),
        kFnthinkRawTextButtons.keys.toSet(),
        reason:
            '幻念的某张页出现了台账之外的裸 TextButton ⇒ 变多。'
            '新写一枚请改走三种合法形状；真换掉一枚就把那一格改小、换到 0 就把这一格删掉',
      );
    });

    // 这里原本只有上面两条：口径是 `lib/pages/fnthink_*`，两张历史页**不在册**。
    // T148 片4 把口径的事实在下面那册里钉住（见「两张历史页里的动作形状」）。

    test('逐文件枚数与台账相等（这本账就是剩余工作量）', () {
      final actual = fnthinkOnly();
      for (final entry in kFnthinkRawTextButtons.entries) {
        expect(
          actual[entry.key] ?? 0,
          entry.value,
          reason:
              '${entry.key} 里裸 TextButton 实际 ${actual[entry.key] ?? 0} 枚、'
              '台账记 ${entry.value} 枚 ⇒ 换掉一枚就把账改小',
        );
      }
    });

    // T153 片6：**非幻念页**也有一本（口径互补，合起来才是"全库还剩几枚"）。
    // 判据扫两种写法：`TextButton(` **与** `TextButton.icon(` ——
    // 第一版只扫前者，`email_settings_page` 那枚 `TextButton.icon` 漏了，
    // 而它在屏上与 `TextButton` 长得一样（都是裸文字）。
    // ⚠ 口径限定 **`lib/pages/`**：这本账管的是"**页面自己搭的**按钮"。
    //   `lib/widgets/ios_dialog_actions.dart` 里那几枚 `TextButton` 是**件自身**的
    //   实现（`confirm` 给历史页面当 actions 构建器用），它不该入这本账 ——
    //   第一版没限定目录，把件自己扫进来了（当场红在"账外新增"）。
    bool isPage(String path) =>
        path.startsWith('lib/pages/') && !path.startsWith('lib/pages/fnthink_');
    Map<String, int> nonFnthink() => {
      for (final e in countingRe(rawTextButton).entries)
        if (isPage(e.key)) e.key: e.value,
    };
    Map<String, int> nonFnthinkWithIcon() => {
      for (final e in countingRe(
        RegExp(r'(^|[^A-Za-z0-9_])TextButton\.icon\('),
      ).entries)
        if (isPage(e.key)) e.key: e.value,
    };

    test('非幻念页：账外的文件长出一枚就红（含 TextButton.icon）', () {
      final all = <String, int>{};
      for (final m in [nonFnthink(), nonFnthinkWithIcon()]) {
        for (final e in m.entries) {
          all[e.key] = (all[e.key] ?? 0) + e.value;
        }
      }
      expect(
        all.keys.toSet().difference(kPlainTextButtons.keys.toSet()),
        isEmpty,
        reason:
            '某张非幻念页出现了台账之外的裸 TextButton ⇒ 变多。'
            '新写一枚请改走三种合法形状（PrimaryActionButton / FnthinkInlineAction / '
            'FnthinkEntryRow）；真换掉一枚就把那一格改小、换到 0 就把这一格删掉',
      );
    });

    test('非幻念页：逐文件枚数与台账相等（这本账就是剩余工作量）', () {
      final all = <String, int>{};
      for (final m in [nonFnthink(), nonFnthinkWithIcon()]) {
        for (final e in m.entries) {
          all[e.key] = (all[e.key] ?? 0) + e.value;
        }
      }
      for (final entry in kPlainTextButtons.entries) {
        expect(
          all[entry.key] ?? 0,
          entry.value,
          reason:
              '${entry.key} 里裸 TextButton 实际 ${all[entry.key] ?? 0} 枚、'
              '台账记 ${entry.value} 枚 ⇒ 换掉一枚就把账改小（这本只许减少）',
        );
      }
    });

    test('T98 片③：勾上那一支必须代建通道，且已有就不重复建', () {
      // 三段链（对方授权／本机勾选／一条目标=它的通道）缺一段就不发，而缺的是哪一段
      // 界面上看不出来 —— 这一片把'还差一段'变成'替你办了'。判据落在**触发条件**上：
      // 代建只在 value==true 那一支（取消勾选不连带删，服务层那条判据写着为什么）。
      final page = codeByPath['lib/pages/fnthink_peers_page.dart']!;
      expect(
        page.contains('if (value) await _ensureChannelFor(peer);'),
        isTrue,
      );
      expect(page.contains('if (!exists) {'), isTrue);
      final svc = codeByPath['lib/services/fnthink_channel_service.dart']!;
      expect(
        svc.contains(
          'Future<void> setForward(String peerAddress, bool forwards);',
        ),
        isTrue,
        reason: 'setForward 必须在接口上 —— 否则这一列勾选在测试里换不了替身',
      );
    });

    test('T98 片①：名单那一行必须报两个方向（两句都带方向箭头）', () {
      // 「两个方向」是这一行的信息契约：它 → 你（授到什么档）／你 → 它（能不能收到你转发的）。
      // 判据打在**方向箭头**上，不打在某句措辞上：措辞可以改，方向不许消失。
      final page = codeByPath['lib/pages/fnthink_peers_page.dart']!;
      expect(page.contains('l10n.fnthinkPeerLine('), isTrue);
      expect(page.contains('l10n.fnthinkPeerForwardToggle'), isTrue);
      final arb = jsonDecode(
        File('$root/lib/l10n/arb/app_zh.arb').readAsStringSync(),
      ) as Map<String, dynamic>;
      for (final k in const ['fnthinkPeerLine', 'fnthinkPeerForwardToggle']) {
        expect(
          (arb[k] as String).contains('→'),
          isTrue,
          reason: '$k 没报方向 —— 用户读不出这句话是谁对谁',
        );
      }
    });

    test('T97 #271：ok 是 accepted，账记在 (fnthink, 通道 id) 上', () {
      // 两条都是"今天恒为没测过"那个缺陷的另一半：徽标读的是
      // `ChannelHealthStore.of(kFnthinkChannelSlug, channel.id)`，所以写那一侧一旦换了键
      // （例如写 host），徽标会永远停在「没测过」——**假绿**，而界面上看不出任何异常。
      final page = codeByPath['lib/pages/fnthink_channel_settings_page.dart']!;
      expect(
        page.contains('return result.status == FnthinkSendStatus.accepted;'),
        isTrue,
        reason:
            'ok 的判据必须是 accepted：其余档位（含"对面没接"）都算没通，'
            '放宽成"没抛就算通"就是给一条没送到的通道发绿',
      );
      expect(
        RegExp(r'probe\.health\.record\(\s*kFnthinkChannelSlug,\s*channel\.id,')
            .hasMatch(page),
        isTrue,
        reason: '记账键必须是 (kFnthinkChannelSlug, 通道 id) —— 与列表页徽标读的那一对逐字相同',
      );
    });

    test('T97 #271：给列表页的每个装配点都要装 probe', () {
      // 漏装那一个入口的后果很隐蔽：从它进去详情页就是**没有那一枚**，
      // 而另一个入口有 —— 用户从哪进决定了他有没有这个功能。
      const page = 'lib/pages/fnthink_channel_list_page.dart';
      final sites =
          codeByPath.entries
              .where(
                (e) =>
                    e.key != page &&
                    e.value.contains('FnthinkChannelListPage('),
              )
              .map((e) => e.key)
              .toList()
            ..sort();
      expect(sites, const <String>[
        'lib/pages/main_page_actions.dart',
        'lib/pages/notification_engine_page.dart',
      ], reason: '装配点变了就要回来改这一格，并给新的那一个装上 probe');
      for (final p in sites) {
        expect(
          RegExp(r'FnthinkChannelListPage\(\s*probe:').hasMatch(codeByPath[p]!),
          isTrue,
          reason: '$p 没给 probe ⇒ 从这条路进去详情页没有「测试这条通道」',
        );
      }
      // 依赖只在一处从 locator 装（main_page 的 State 上），两处引用同一份 ——
      // 各装各的就会一份读 prefs、另一份读到别的（本仓那条老判据）。
      expect(
        codeByPath['lib/pages/main_page.dart']!.contains(
          'FnthinkChannelProbeDeps.fromLocator()',
        ),
        isTrue,
        reason: '生产装配点必须有一处 fromLocator —— 否则那一枚在真机上永远不出现',
      );
    });

    test('T97 片6：那几段说明收进问号（长文进弹窗、短说留页面）', () {
      // 判据：**长文键在它那个文件里恰好出现一次** —— 就是弹窗正文那一处。
      // 出现两次 = 短说和长文一起画在页面上了（成段小字又长回来）；零次 = 搬丢了。
      // 每个文件再各钉一条"短说在"：只钉长文的话，"把长文删了、短说也没写"也是绿的。
      const pairs = <String, List<String>>{
        'lib/pages/backup_restore_page.dart': [
          'l10n.backupSectionDesc',
          'l10n.backupSectionShort',
        ],
        'lib/pages/channel_status_page.dart': [
          'l10n.channelStatusGuide',
          'l10n.channelStatusShort',
        ],
        'lib/pages/device_snapshot_page.dart': [
          'l10n.deviceStatusDesc',
          'l10n.deviceStatusShort',
          'l10n.pushDeviceInfoDesc',
          'l10n.pushDeviceInfoShort',
        ],
      };
      for (final e in pairs.entries) {
        final src = codeByPath[e.key]!;
        for (var i = 0; i < e.value.length; i += 2) {
          final long = e.value[i];
          final short = e.value[i + 1];
          expect(
            RegExp(long.replaceAll('.', r'\.')).allMatches(src).length,
            1,
            reason: '$long 不再恰好出现一次（${e.key}）⇒ 要么搬丢了，要么又画回页面上',
          );
          expect(
            src.contains(short),
            isTrue,
            reason: '$short 不在页面上 ⇒ 长文搬走之后那一格什么都不说了',
          );
        }
      }
      // 底部那一句（圆点行 = §1 的「底部无序列表」）：话一字未改，形状换了。
      expect(
        codeByPath['lib/pages/history_page.dart']!.contains(
          "'\u2022 \${l10n.fnthinkAllScopeNote}'",
        ),
        isTrue,
        reason: '全部档那句说明又变回裸小字 ⇒ 底部无序列表那一形状没挂住',
      );
    });

    test('那三页的成段说明：边界句两处都在、只许走「问号弹层」那一形状', () {
      // 判据③ 2026-10-07 的分桶结论：remote 三页 37 处 _Note 里，绝大多数是状态原话／
      // 字段标签／弹窗正文（§1 明说不许按'美化'去动），唯一一条成段说明是历史页那句边界。
      // 2026-10-12 T149 片1 把它从「底部圆点行」换成「问号弹层」—— 两种去处都在这条口径里
      // （维护者 2026-10-06：提醒文字只有底部无序列表／问号弹窗两种去处），换形状本身合法，
      // 但**这条要跟着改指向**：正文不许摊回页面，且两处（空态／有货态）一个都不能少。
      final src = codeByPath['lib/pages/remote_history_page.dart']!;
      // ⚠ 这一条第一版只断「至少有一处带圆点」—— 反证 D1 当场证伪：那句在页面里**有两处**
      //   （空列表态与有列表态各一），只改回其中一处照样绿。现在两处都必须在弹层里带全文。
      const popupBody = 'helpBody: l10n.remoteHistoryBoundary,';
      expect(
        popupBody.allMatches(src).length,
        2,
        reason: '边界句必须两处（空态 / 有货态）都原样进问号弹层，正文一句不许少',
      );
      expect(
        'text: l10n.remoteHistoryBoundaryShort,'.allMatches(src).length,
        2,
        reason: '弹层有正文，页面上那行短说也得两处都在 —— 否则读者根本找不到入口',
      );
      expect(
        src.contains('text: l10n.remoteHistoryBoundary,'),
        isFalse,
        reason: '还有一处是裸小字 ⇒ 成段说明又长回页面里了',
      );
    });

    test('这本账必须保持为空（清零之后牙全挂在这一条上）', () {
      expect(
        kFnthinkRawTextButtons,
        isEmpty,
        reason:
            'T100 判据② 已经四刀收完：幻念六页的裸 TextButton 归零。'
            '往这本账里加回一格，等于把「账外一律红」那道门重新打开 —— 而一行代码都没改错',
      );
    });

    test('尺认得合成样本（防判据退化成空集＝恒真）', () {
      // 本仓栽过两次：提取式收窄之后正则恒不匹配 ⇒ 差集恒空 ⇒ 全绿而什么都没量到。
      expect(
        rawTextButton.hasMatch('child: TextButton(onPressed: null)'),
        isTrue,
      );
      expect(rawTextButton.hasMatch('CupertinoButton('), isFalse);
      expect(rawTextButton.hasMatch('myTextButton('), isFalse);
      // ⚠ 判据② 收完之后匹配集合**按设计就是空的** ⇒ 空集不能再当"尺坏了"的信号。
      //   要防退化，得盯**语料**：那几张页必须真的在被扫的范围里。
      expect(
        codeByPath.keys.where((p) => p.startsWith('lib/pages/fnthink_')),
        isNotEmpty,
        reason: '一张幻念页都没进语料 ⇒ 上面那两条差集恒真',
      );
    });

    test('「进一页那一行」只有 FnthinkEntryRow 一个装配点', () {
      expect(hitting('class FnthinkEntryRow'), const <String>[
        'lib/widgets/fnthink_card.dart',
      ], reason: '形状①的装配点必须唯一 —— 两份抄本正是 T100 要收的东西');

      int n(String path, String needle) =>
          needle.allMatches(codeByPath[path]!).length;

      // hub 那三行在 `_entry` 里共用一个调用；远程控制页那三行是三次直调
      // （T97 片C 从接收页搬过去 —— 守卫跟着主语走，不是留在旧文件上收一份假账）。
      expect(
        n('lib/pages/notification_engine_page.dart', 'FnthinkEntryRow('),
        greaterThanOrEqualTo(1),
      );
      // T124 片B-4 起 4：远程页多了「可被远程打开的入口」那一行（app:launch 的本机那一半）。
      // T124 片C-1 起 5：多了「可被远程读取的内容」那一行（通话记录那一族的本机开关与权限入口）。
      expect(n('lib/pages/fnthink_remote_page.dart', 'FnthinkEntryRow('), 5);
      // 换件之后这几个文件里不该再留下自己搭的 Material 路由。
      for (final p in const [
        'lib/pages/notification_engine_page.dart',
        'lib/pages/fnthink_receive_page.dart',
        'lib/pages/fnthink_remote_page.dart',
      ]) {
        expect(
          n(p, 'MaterialPageRoute'),
          0,
          reason: '$p 里还有自己搭的 MaterialPageRoute ⇒ 转场没有跟着形状①走',
        );
      }
    });
    test('「行内次要动作」也只有 FnthinkInlineAction 一个装配点', () {
      expect(hitting('class FnthinkInlineAction'), const <String>[
        'lib/widgets/fnthink_card.dart',
      ], reason: '「对行里那个值做点什么」这一形状必须只有一处定义');

      int n(String path, String needle) =>
          needle.allMatches(codeByPath[path]!).length;

      // 第一刀收的是「复制」那一族：设置页两处（地址码／配对码）+ 端点页那枚按 key 的复制；
      // 第二刀收的是绑定页那四枚行内动作（批准／拒绝／撤销／发一条）—— 那一格已从台账删掉。
      // 第三刀之后设置页那一格也清了（复制×2 ＋ 重置地址码 ＋ 撤销口令 ＋ 改地址 ＋
      // 换服务器 ＋ 恢复默认 = 7 枚），所以它整格从台账里删掉。
      // T119 又加了第 8 枚：**撤销中转同意**（破坏性档）—— 台账跟着 +1，
      // 少一枚就是有人把它改回默认蓝或自己搭了个 TextButton。
      // T47 加了第 9 枚：**收件保留选档**（中性档；不走 l10n.edit，那一句是宿主行的）。
      expect(
        n('lib/pages/fnthink_settings_page.dart', 'FnthinkInlineAction('),
        9,
      );
      expect(
        n('lib/pages/fnthink_endpoint_page.dart', 'FnthinkInlineAction('),
        greaterThanOrEqualTo(1),
      );
      // T129 片2 加了第 5 枚：**问一次对面答了没**（挂在「我发起过的配对请求」那一格里）。
      // T128 片1 加了第 6 枚：**改名**（挂在名单每一行上；别名只给这一行，所以入口必须在行里）。
      // T152 片B 回到 **4**：名单行的「撤销」「改名」收进行尾那枚「⋯」的弹层（维护者 2026-10-15
      // 方案 阶段3），主操作「发一条」**留在行内**。少的那两枚不是删掉了功能，是换了宿主 ——
      // 颜色那一半的账在下面 T108 那条里跟着搬（`CardAction.danger`）。
      expect(n('lib/pages/fnthink_peers_page.dart', 'FnthinkInlineAction('), 4);
    });

    // T108 片①：那批"蓝色文字点击件"按功能语义分色，并把"谁还在自己搭按钮"记成一本账。
    test('T108：语义→颜色只有 colorOf 一处；页面自己搭的按钮与裸 Text 点击件各有台账', () {
      // ① 词表只有一处作者。抄第二处 = 页面可以自己决定"撤销"该是什么颜色，
      //    而这一条判据的内容正是"不可逆的事要看得出来"。
      expect(hitting('enum FnthinkActionTone'), const <String>[
        'lib/widgets/fnthink_card.dart',
      ], reason: '语义词表被抄到第二处 ⇒ 颜色口径开始分叉');

      // ② 破坏性（关掉／撤销／拒绝／换一把口令／重置地址码）逐文件枚数就是台账：
      //    少一枚 ⇒ 有人把它改回了默认蓝，而界面上"能不能反悔"这件事又看不出来了。
      const destructive = <String, int>{
        'lib/pages/fnthink_endpoint_page.dart': 2,
        // T152 片B：2 → 1。名单行那枚「撤销」搬进行尾「⋯」的弹层，本页只剩待确认那一条的
        // 「拒绝」还在行内上红。**红这一档没有少，是换了宿主** —— 下面那条 `danger: true`
        // 钉的就是搬过去的那一枚（少了它，撤销在弹层里就与"改个名字"同一个颜色）。
        'lib/pages/fnthink_peers_page.dart': 1,
        // T119 起设置页有 3 枚：重置地址码、撤销配对口令、**撤销中转同意**。
        'lib/pages/fnthink_settings_page.dart': 3,
      };
      const neutral = <String, int>{
        // T153 片3：2 → **1**。「读一次」那枚从中性行内动作换成了 `FnthinkEntryRow`
        // （入口行）—— 它本来就是这一页两个主要出口之一，一行灰字读不出点得动。
        // **中性这一档没有少，是换了宿主**：剩下那一枚是教程里的「复制」，
        // 它才是真正的"行内次要动作"（跟在某段命令旁边）。
        'lib/pages/fnthink_endpoint_page.dart': 1,
        'lib/pages/fnthink_settings_page.dart': 3,
      };
      for (final (table, needle) in const [
        (destructive, 'FnthinkActionTone.destructive'),
        (neutral, 'FnthinkActionTone.neutral'),
      ]) {
        for (final e in table.entries) {
          final actual = 'FnthinkActionTone.'
              .allMatches(codeByPath[e.key]!)
              .length; // 只为报错信息用，见下条 reason
          expect(
            needle.allMatches(codeByPath[e.key]!).length,
            e.value,
            reason:
                '${e.key} 里 $needle 实际 '
                '${needle.allMatches(codeByPath[e.key]!).length} 枚、台账 ${e.value} 枚 ⇒ '
                '要么改回了默认蓝（缺陷复活），要么换成了公共件之外的形状（该搬的没搬）。'
                '本页现在共有 $actual 处 tone 引用。',
          );
          expect(actual, greaterThanOrEqualTo(e.value));
        }
      }
      // T152 片B：那枚搬进弹层的「撤销」用的红是另一套词汇（`CardAction.danger`，由
      // `CardActionSheet` 把 label 与图标一起转红）。这一族"不可逆要看得出来"的口径因此是
      // **两处相加**，不是只看行内那一处 —— 少一枚就是"撤销现在看起来与改个名字一样"。
      expect(
        'danger: true'
            .allMatches(codeByPath['lib/pages/fnthink_peers_page.dart']!)
            .length,
        1,
        reason:
            '名单行尾「⋯」里那枚撤销不再带 danger ⇒ 弹层里它与"改名"同色，'
            '而这一发断掉的是配对关系（撤销之后要重新扫码才能再配上）',
      );
      // 判据自证：台账不许是空的（空表会让上面那一圈恒真 —— 本仓"不许变多"型台账的正解）。
      expect(
        destructive.values.reduce((a, b) => a + b),
        greaterThan(0),
        reason: '破坏性一枚都没登记 ⇒ 上面那条等于没写',
      );

      // ③ 验收 ③：页面里不许出现"裸 Text 直接挂 onTap"那种自搭点击件。
      //    GestureDetector／InkWell 一次都不该有（命中区与按压反馈都由公共件负责）。
      final fnthinkPages =
          codeByPath.keys
              .where((k) => k.startsWith('lib/pages/fnthink_'))
              .toList()
            ..sort();
      expect(
        fnthinkPages.length,
        greaterThanOrEqualTo(8),
        reason: '只扫到 ${fnthinkPages.length} 张幻念页 ⇒ 目录口径漂了，下面两条是摆设',
      );
      for (final p in fnthinkPages) {
        expect(
          'GestureDetector('.allMatches(codeByPath[p]!).length,
          0,
          reason: '$p 自己搭了 GestureDetector ⇒ 绕开装配点，命中区与按压反馈各是各的',
        );
        expect(
          'InkWell('.allMatches(codeByPath[p]!).length,
          0,
          reason: '$p 自己搭了 InkWell ⇒ 同上（T100 已把这一形状收进公共件）',
        );
      }

      // ④ 台账②：**清零**（T108 片②）。原先还剩七枚是页面自己搭的按钮
      //    （`CupertinoButton(` 直接写在页文件里：通道设置页的字段行与页脚次级、发送页的档位与
      //    三排选择件、接收页的恢复默认）。现在它们分别走 `FnthinkFieldTile` /
      //    `SecondaryActionButton` / `FnthinkChoiceChip` / `FnthinkInlineAction`。
      //    这本账清空之后**不许再长回来**（与 T90 那两本同一条纪律：账上的数字就是欠账本身）。
      const localButtons = <String, int>{};
      int local(String p) =>
          'CupertinoButton('.allMatches(codeByPath[p]!).length;
      final actualLocal = <String, int>{
        for (final p in fnthinkPages)
          if (local(p) > 0) p: local(p),
      };
      expect(
        actualLocal.keys.toSet(),
        localButtons.keys.toSet(),
        reason:
            '又有一张页自己搭按钮（${actualLocal.keys.toSet().difference(localButtons.keys.toSet())}）⇒ '
            '新写的那枚请走那四枚公共件之一；账上的每一格都是一笔要还的债',
      );
      for (final e in localButtons.entries) {
        expect(
          actualLocal[e.key] ?? 0,
          e.value,
          reason: '${e.key} 的自搭按钮枚数与台账不等 ⇒ 改了要回来记账',
        );
      }

      // ⑤ 那四枚公共件各自只有一处定义 —— 单独一条用例（见下一条 test），
      //    这样"页面又自己搭一枚"与"公共件长出第二份定义"两种回归各红各的用例。
    });

    test('T108 片②：那几枚公共件各只有一处定义，且确实有页在用', () {
      for (final w in const [
        'class FnthinkChoiceChip',
        'class FnthinkFieldTile',
        'class SecondaryActionButton',
      ]) {
        expect(hitting(w).length, 1, reason: '$w 有了第二处定义 ⇒ 形状又开始分叉');
      }
      // 反向自证：这三件确实被用着（没人用的公共件只是把耦合换了个地方放着）。
      for (final u in const [
        'FnthinkChoiceChip(',
        'FnthinkFieldTile(',
        'SecondaryActionButton(',
      ]) {
        expect(
          hitting(u),
          isNotEmpty,
          reason: '$u 一处都没被用 ⇒ 上面那条"只有一处定义"是在守一件不存在的事',
        );
      }
    });

    test('「主操作填充」也只有 PrimaryActionButton 一个装配点', () {
      expect(hitting('class PrimaryActionButton'), const <String>[
        'lib/widgets/primary_action_button.dart',
      ], reason: '形状③（一页最多一枚的全宽填充）必须只有一处定义');

      int n(String path, String needle) =>
          needle.allMatches(codeByPath[path]!).length;

      // 形状的出处（桌面小部件引导页那两枚）与幻念那几页的主操作都在用它。
      // 通道详情页那一枚是 2026-10-08 换过来的（原来是裸 `CupertinoButton.filled`）。
      for (final p in const [
        'lib/pages/widget_guide_page.dart',
        'lib/pages/fnthink_endpoint_page.dart',
        'lib/pages/fnthink_receive_page.dart',
        'lib/pages/fnthink_peers_page.dart',
        'lib/pages/fnthink_settings_page.dart',
        'lib/pages/fnthink_channel_settings_page.dart',
        // T98 片④：那张共用发送页两档各一枚主操作（同一时刻只画其中一档）。
        'lib/pages/fnthink_send_page.dart',
      ]) {
        expect(
          n(p, 'PrimaryActionButton('),
          greaterThanOrEqualTo(1),
          reason: '$p 的主操作没有走公共件 ⇒ 形状又分叉了',
        );
      }
      // 那张发送页尤其不许退回裸填充件：它的两枚主操作原来一枚是 `CupertinoButton.filled`
      // （远程指令那一档）、一枚是弹层里的 `CupertinoDialogAction`（纯文本那一档）。
      expect(
        codeByPath['lib/pages/fnthink_send_page.dart']!.contains(
          'CupertinoButton.filled',
        ),
        isFalse,
        reason: '主操作走 `PrimaryActionButton`（形状③唯一装配点），裸填充件不许回来',
      );
    });
  });

  // ── 裸文字点击件（T166 ③）──────────────────────────────────────────────
  group('非幻念页的裸文字点击件（T166 ③ 的台账）', () {
    // 认「`GestureDetector`/`InkWell` 的 child 直接是 `Text`」以及中间只隔排版件那一形
    // （`InkWell → Padding → Center → Text` 就是「知道了」动作行）。
    // 一旦中间出现 `Container`/`Row` 等有外观的件就不再算「裸文字」。
    const layout = r'(?:Padding|Center|Align|SizedBox|Expanded|Flexible)';
    final bareTextTap = RegExp(
      '(GestureDetector|InkWell)\\((?:(?!\\bchild:).){0,400}?child:\\s*'
      '(?:$layout\\((?:(?!\\bchild:).){0,200}?child:\\s*){0,3}Text\\(',
      dotAll: true,
    );

    bool isNonFnthinkPage(String path) =>
        path.startsWith('lib/pages/') && !path.startsWith('lib/pages/fnthink_');

    Map<String, int> actual() => {
      for (final e in countingRe(bareTextTap).entries)
        if (isNonFnthinkPage(e.key)) e.key: e.value,
    };

    test('账外的页长出裸文字点击件就红', () {
      expect(
        actual().keys.toSet().difference(kTextOnlyTapTargets.keys.toSet()),
        isEmpty,
        reason:
            '某张非幻念页出现了 `GestureDetector/InkWell + 裸 Text` ⇒ '
            '那一段在屏上读不出可点、按下也没反馈；改走公共件或自带外观的容器',
      );
    });

    test('逐文件枚数与台账相等（这本账就是剩余工作量）', () {
      final found = actual();
      for (final entry in kTextOnlyTapTargets.entries) {
        expect(
          found[entry.key] ?? 0,
          entry.value,
          reason:
              '${entry.key} 里裸文字点击件实际 ${found[entry.key] ?? 0} 枚、'
              '台账记 ${entry.value} 枚 ⇒ 换掉一枚就把账改小',
        );
      }
    });

    test('这把尺认得合成样本（防退化成恒绿）', () {
      expect(
        bareTextTap.hasMatch('GestureDetector(onTap: f, child: Text("x"))'),
        isTrue,
      );
      expect(
        bareTextTap.hasMatch(
          'InkWell(onTap: f, child: Padding(padding: p, child: Center(child: Text("x"))))',
        ),
        isTrue,
        reason: '只隔排版件的文字动作行也要算进来（「知道了」那一形）',
      );
      expect(
        bareTextTap.hasMatch(
          'GestureDetector(onTap: f, child: Container(child: Text("x")))',
        ),
        isFalse,
        reason: '自带外观的容器不该被这本账算进来',
      );
      expect(
        bareTextTap.hasMatch(
          'InkWell(onTap: f, child: Padding(padding: p, child: Row(children: [Text("x")])))',
        ),
        isFalse,
        reason: '中间有 Row 等有外观的件就不再是裸文字',
      );
    });

    test('T166 ③：无权限提示只有共用件一个作者', () {
      final pageHits = hitting('appFilterNoPermPrompt')
          .where((p) => p.startsWith('lib/pages/'))
          .toList();
      expect(
        pageHits,
        isEmpty,
        reason: '无权限提示的文案还在页面里 ⇒ 两页又各写一份；一律走 AppPermissionPrompt',
      );
      for (final p in const [
        'lib/pages/app_filter_page.dart',
        'lib/pages/remote_trigger_filter_page.dart',
      ]) {
        expect(
          codeByPath[p]!.contains('AppPermissionPrompt('),
          isTrue,
          reason: '$p 没接共用件 ⇒ 另一页改了它还停在旧形状',
        );
      }
    });
  });

  // ── 「新建幻念通道」那一页（维护者 2026-10-08 点名的四条）───────────────────
  // 页面级证据在 `test/widgets/fnthink_channel_page_test.dart`（六条新的）。这一册钉的是
  // 那四条的**形状**：红字挂在哪儿、保存默认带不带探测、那一档画的是译文还是 token。
  group('「新建幻念通道」那四条（各有牙）', () {
    const page = 'lib/pages/fnthink_channel_settings_page.dart';

    test('①必填那句挂在字段上，不是卡片底下那一行灰字', () {
      final src = codeByPath[page]!;
      expect(src.contains('errorText: _nameError'), isTrue);
      expect(src.contains('errorText: _targetError'), isTrue);
      // 红 = `AppColors.red`，与 widget 用例里那条 `paintedColor` 断的是同一个色值：
      // 谁把它换回 secondaryLabel，两条一起红（一条断屏幕上、一条断形状上）。
      expect(
        src.contains('errorStyle: const TextStyle(color: AppColors.red'),
        isTrue,
        reason: '维护者第 1 条要的就是"红字"：12px 灰字那一版说了等于没说',
      );
      expect(
        RegExp(r"""FnthinkNote\(\s*keyName:\s*'fnthink-channel-note'""")
            .hasMatch(src),
        isFalse,
        reason: '校验话又搬回卡片底下那行灰字 ⇒ 与"这条为什么没存上"混在一起',
      );
    });

    test('②保存默认带探测，两枚都是公共件', () {
      final src = codeByPath[page]!;
      expect(
        src.contains('if (_canProbe) await _probe();'),
        isTrue,
        reason: '「探测并保存」少了那一发就只是"保存"——按钮说两件事、做一件',
      );
      for (final key in const [
        'fnthinkChannelProbeOnly',
        'fnthinkChannelProbeAndSave',
      ]) {
        expect(
          RegExp('l10n\\.$key').allMatches(src).length,
          1,
          reason: '$key 的调用点应当恰好一处（两处＝页脚长成了两排）',
        );
      }
      expect(
        src.contains('CupertinoButton.filled'),
        isFalse,
        reason: '主操作走 `PrimaryActionButton`（形状③唯一装配点），裸填充件不许回来',
      );
      // 新建那一页也能记账的前提：id 在写库之前先发号（另三族 T04 的同一做法）。
      expect(
        src.contains("_id ??= 'fc_"),
        isTrue,
        reason: '没有稳定 id ⇒ 「探测并保存」那一发的账无处可挂，徽标还是"没测过"',
      );
    });

    test('③主备那一档画译文，token 只当 value', () {
      final src = codeByPath[page]!;
      for (final key in const ['rolePrimary', 'roleBackup', 'roleNone']) {
        expect(
          src.contains('label: l10n.$key'),
          isTrue,
          reason: '$key 没被当 label 用 ⇒ 那一格又画回英文 token（维护者第 3 条）',
        );
      }
      for (final token in const ['primary', 'backup', 'none', 'unset']) {
        expect(
          src.contains("label: '$token'"),
          isFalse,
          reason: "'$token' 是落库的跨语言字面量，不是画给用户看的那句人话",
        );
      }
      expect(
        src.contains('String _role = ChannelConfigCodec.roleUnset;'),
        isTrue,
        reason: '新建起点是「未设置」——与另三族 #105 一致：全停在「主」时同一条通知重复推送',
      );
    });

    test('④这一页与另三族同形：徽标在卡头、标签在上、不当场开弹窗改字段', () {
      final src = codeByPath[page]!;
      expect(
        src.contains('ChannelHealthBadge('),
        isTrue,
        reason: '另三族详情页卡头那件徽标 —— 没有它，这一页读起来不像同一家族',
      );
      expect(
        src.contains('_label(context, l10n.fnthinkChannelName)'),
        isTrue,
        reason: '标签在上（与 `_buildFieldLabel` 同一形状），不是"值挤在行尾"',
      );
      expect(
        RegExp(r'showIosInputDialog\(').allMatches(src).length,
        0,
        reason: '"点开弹窗改一行"那一套从这一页出账：同组另外三页都是当场输入',
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
        hittingRe(materialDialogs)
            .toSet()
            .difference(kMaterialDialogSites.keys.toSet()),
        isEmpty,
        reason: '新一处 Material AlertDialog ⇒ 与 Cupertino 风格不一致；确认框请用 IosDialogActions',
      );
    });

    // ⚠ 这条才是「剩余工作量」的真读数。旧的两条只问文件在不在账上，于是在**已入账的文件里
    //   再加一枚**对话框永远不会红（history_page 本来就挂着五枚 ⇒ 第六枚没人喊）。
    //   片13 划掉四枚之后把口径改成逐文件枚数：多一枚红、少一枚也红（少的那次要顺手把账改小）。
    test('逐文件枚数与台账相等（这本账就是剩余工作量）', () {
      final actual = countingRe(materialDialogs);
      expect(
        actual.keys.toSet(),
        kMaterialDialogSites.keys.toSet(),
        reason: '台账内外的文件对不上 ⇒ 这本账不能再当作剩余工作量',
      );
      for (final entry in kMaterialDialogSites.entries) {
        expect(
          actual[entry.key] ?? 0,
          entry.value,
          reason:
              '${entry.key} 里 Material AlertDialog 实际 '
              '${actual[entry.key] ?? 0} 枚、台账记 ${entry.value} 枚'
              ' ⇒ 真换掉一枚就把账改小，新写一枚不许',
        );
      }
    });

    // ⚠ 片28 反证（`outputs/_t90p28_falsify.report.txt` 的 **TP28-C**）抓到这一族的**真缺口**：
    // 账清零之后，上面那条「新增长对话框」的牙**全靠这份账** —— 而把一条写回账里，
    // 它就把那个文件重新变成"允许"：同一发植入（lib 塞一枚 ＋ 账里加回那一条，名数相等）
    // 实测 **exit 0**，两条守卫全绿。所以台账从"待办清单"退化成"**必须恒空**的常量"，
    // 由这一条钉住；否则"清零"只是一句当前的读数，下一个人加回一行就静默失效。
    test('这本账必须保持为空（新写一处 Material 对话框是缺陷，不是待办）', () {
      expect(
        kMaterialDialogSites,
        isEmpty,
        reason:
            '把某文件加回这本账＝把那处 Material 对话框重新变成"允许"；'
            '要留下就得先把它换成 Cupertino（反证 TP28-C：塞一枚＋加一条 ⇒ 当时 exit 0）',
      );
    });

    // T90 片12/14/16：这几屏的表单弹层（新增/编辑条件与动作、三页阈值框、聚合参数）
    // 都是「同一套外壳抄在各处」的历史，现在统一接 `IosFormDialog`。
    // 这一条钉的是「这一屏接没接到共享外壳」；
    // **还剩几枚 Material 的**由上面那本逐文件台账管 —— 同一件事不写两处。
    // ⚠ 这里原本还有一条"整屏不许有 Material AlertDialog"的负向断言，第一次跑就红了：
    //   温度页除了阈值框另有「试跑」那一枚不在本族 ⇒ 负向断言把正常状态判成缺陷，已删。
    // ⚠ `rule_edit_widgets.dart` 是 `rule_edit_page.dart` 的 part：按文件名 grep 会以为那四枚表单不在 lib 里。
    test('走 IosFormDialog 外壳的那几屏都真的接上了', () {
      const shells = <String>{
        'lib/pages/battery_page.dart',
        'lib/pages/temperature_page.dart',
        'lib/pages/device_state_page.dart',
        // 片16：聚合参数编辑框（本文件自己写的第五枚，不在 part 里）
        'lib/pages/rule_edit_page.dart',
        // 片12：四枚条件/动作表单（在 part 里）
        'lib/pages/rule_edit_widgets.dart',
      };
      for (final path in shells) {
        final src = codeByPath[path];
        expect(src, isNotNull, reason: '$path 不在了 ⇒ 本条在空转');
        expect(
          src!,
          contains('IosFormDialog('),
          reason: '$path 的表单弹层没接到共享外壳 ⇒ 形状又要各页一份',
        );
      }
    });

    test('已划掉的每一屏走的是 helper，不是自己手搭一枚 Cupertino 的', () {
      // 划掉台账有两条路：真的走共享件（`IosDialogActions` / `showIosOptionPicker`），
      // 或者把 `AlertDialog(` 就地改成 `CupertinoAlertDialog(`。后者让上面两条守卫都绿
      // （Material 那件确实没了），但标题字号 / 按钮色 / 可关性重新各页一份 ——
      // 与换根组件之前那种散落是同一样东西。所以这一条钉的是"走哪条路"（T90 片5/片6）。
      // ⚠ 值是**列表**不是一个字符串：一个文件可以接多个装配点（history_page 同时有
      //   确认框 askConfirm 与片17 的进度框 IosProgressDialog；rule_edit_page 同时有
      //   权限引导框与片16 的表单外壳）。早先用 String 时第二次登记同名键 ⇒ Dart 直接编译不过。
      const migrated = <String, List<String>>{
        'lib/pages/main_page_actions.dart': ['IosDialogActions.askConfirm('],
        'lib/pages/sms_monitor_settings_page.dart': [
          'IosDialogActions.showInfo(',
        ],
        'lib/pages/widget_guide_page.dart': ['IosDialogActions.showInfo('],
        'lib/pages/more_page.dart': ['showIosOptionPicker<'],
        // 片19：幻念 pair/send 这两枚**多字段**框（提交键按填全与否置灰 ⇒ 外壳补了
        //   submitEnabled / submitKey 两个口子，判据仍留各页）。
        'lib/widgets/fnthink_pair_dialog.dart': ['IosFormDialog('],
        // T98 片④：「发一条」那一枚弹层整屏退役了（换成一张共用页 `fnthink_send_page.dart`），
        //   所以它从这张"已接上共享外壳"的名单里**删掉**，而不是换成页名 —— 页不是弹层。
        'lib/pages/fnthink_settings_page.dart': ['showIosInputDialog('],
        'lib/widgets/rule_template_sheet.dart': ['showIosInputDialog('],
        // 片11：这两处原本是**逐字相同的两份**同一个权限引导框（连"允许"那颗
        // 请求的原生方法名都一样）⇒ 重复的代价不是行数，是两处以后各改各的。
        'lib/pages/app_filter_page.dart': [
          'IosDialogActions.showPermissionGuide(',
        ],
        'lib/pages/rule_edit_page.dart': [
          'IosDialogActions.showPermissionGuide(',
          // 片16：聚合参数编辑框（新增/编辑条件那四枚在 part 文件里）
          'IosFormDialog(',
        ],
        // 片12：新增/编辑条件、新增/编辑动作这四枚表单弹层的外壳原本是各写一遍的
        // （圆角、背景色、按钮顺序、字号存了四份），现在共用 `IosFormDialog`。
        'lib/pages/rule_edit_widgets.dart': ['IosFormDialog('],
        // 片13：这几枚的动作早就走 helper 了，只剩外壳还挂着 Material 那件 ⇒ 整枚收进装配点。
        'lib/pages/battery_page.dart': ['IosDialogActions.askConfirm('],
        // 片17：批量补推那枚进度框（形状与任何现有装配点都不同形 ⇒ 新装配点）。
        // 片18：图标网格弹层（第四种形状：标题 + 有上限的可滚网格、没有动作区）。
        'lib/widgets/icon_picker_tile.dart': ['IosGridPickerDialog('],
        'lib/pages/history_page.dart': [
          'IosDialogActions.askConfirm(',
          'IosProgressDialog(',
          // 片20：「清除记录」那枚四选一收进现成的选项装配点（不用新造一个）
          'showIosOptionPicker<',
        ],
        'lib/pages/main_page_dialogs.dart': [
          'IosDialogActions.showPermissionGuide(',
        ],
      };
      for (final entry in migrated.entries) {
        final src = codeByPath[entry.key];
        expect(src, isNotNull, reason: '${entry.key} 不在了 ⇒ 本条在空转');
        for (final helper in entry.value) {
          expect(
            src!,
            contains(helper),
            reason: '${entry.key} 的弹层没接到共享件（$helper）⇒ 形状又要各页一份',
          );
        }
        expect(
          src,
          isNot(contains('CupertinoAlertDialog(')),
          reason:
              '${entry.key} 自己手搭了一枚 Cupertino 的 ⇒ 台账划掉了，但散落的还是散落的；'
              '请改走 ${entry.value.join(" / ")}',
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

    test('test/ 里不得在台账之外再 pump MaterialApp（具名例外除外）', () {
      expect(
        fakeRoot.difference(<String>{
          ...kPendingMaterialAppTestHarnesses,
          ...kNamedMaterialAppTestHarnesses,
        }),
        isEmpty,
        reason:
            '又一个 harness 用假根 ⇒ 它验的不是真机上那棵树（页面在 CupertinoApp 下'
            '的尺寸、文字样式、可关性都不同 —— 片9 就是这样漏掉一次溢出的）。'
            '请换成 `AppRoot(locale: …, dark: …, home: …)`',
      );
    });

    // ⚠ 这一条今天**没有能编译的坏法**（如实登记，属纵深防御、不算已验证的闸）：
    //   想让那个文件不再 pump 假根，就得连 import 一起换成 Cupertino，
    //   而它传的是 `ThemeData`（`CupertinoApp.theme` 只吃 `CupertinoThemeData`）⇒ 两次试过都编译不过。
    //   真正会咬人的坏法是**把例外那一行从名单里删掉**（它于是变成账外 ⇒ 上一条断言当场红），
    //   那一条有可植入的坏法（反证 NE1）。
    test('具名例外必须真的还在场（把 Material 那套换掉 = 要验的东西没了）', () {
      for (final path in kNamedMaterialAppTestHarnesses) {
        expect(
          harnessByPath[path],
          contains('MaterialApp('),
          reason:
              '$path 是具名例外，它验的就是 Material 的行为；'
              '把它换成 Cupertino 根等于删掉被测对象（如实登记，不要悄悄改）',
        );
      }
    });

    test('台账里那些 harness 都还 pump 着 MaterialApp（划掉之前先真换掉）', () {
      expect(
        kPendingMaterialAppTestHarnesses.difference(fakeRoot),
        isEmpty,
        reason: '台账与实际不符 ⇒ 这本账不能再当作剩余工作量',
      );
    });

    // ⚠ 同 AlertDialog 那本账一样的教训（反证 TP28-C）：**账清零不等于闸变硬** ——
    //   「台账之外不许有假根」那条的牙全靠这份账，把一行加回来就把那个文件重新变成"允许"。
    //   所以这本账从"待办清单"退化成"**必须恒空**的常量"，由这一条钉住。
    test('假根 harness 台账必须保持为空（新 harness 一律走 AppRoot）', () {
      expect(
        kPendingMaterialAppTestHarnesses,
        isEmpty,
        reason:
            '把某文件加回这本账＝让那个 harness 继续验假根；要留下就得先真换成 '
            '`AppRoot(locale: …, dark: …, home: …)`（反证 TP28-C：'
            '塞一枚 ＋ 加一条 ⇒ 当时 exit 0）',
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
        'test/widgets/fnthink_settings_page_test.dart',
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

/// 仍 pump `MaterialApp` 的 widget harness（T90 片9 起的台账）。
/// ⚠ **片29（2026-10-05）这本账清零**：`app_filter_page_test` 与 `webhook_settings_page_test`
///   两份换真根 `AppRoot` ⇒ **test/ 下已无待换的假根 harness**。
///   ⚠ 当年把这两份留在账上的理由写着"这两页自己还长着 AlertDialog"——**那个理由已经过期**
///   （片11 收 `showPermissionGuide`、片23 收 `showIosOptionPicker`），而留在假根的真实代价是：
///   本页的真形态（尺寸／文字样式／弹层可关性）在测试里看不见，换壳时没人被它喊。
///   ⚠ webhook 那份换真根前量过一次：真根下 30 条全绿 —— `AppRoot` 装了
///   `GlobalMaterialLocalizations`（app_root.dart:52），本页 Material `Scaffold`/`AppBar`
///   的 `MaterialLocalizations` 依赖因此被满足，`AppBar` 自带 Material ⇒ 卡里的 Material 控件有祖先。
const Set<String> kPendingMaterialAppTestHarnesses = <String>{};

/// **具名例外**：故意留在假根（`MaterialApp`）下的 harness，不在"待换"账里。
/// - `text_selection_consistency_test.dart` 验的就是 **Material 文本选择工具栏的 locale 归一**
///   （真机上的那套控件就是 Material 的）⇒ 换成 Cupertino 根等于把要验的东西换掉，
///   它不是"忘了换"，是"换了就不成立"。
/// ⚠ 本书要的是**具名**：每个例外都得写清为什么；本列表之外的假根一律红（上一条断言）。
const Set<String> kNamedMaterialAppTestHarnesses = <String>{
  'test/theme/text_selection_consistency_test.dart',
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
  'lib/widgets/ios_form_dialog.dart',
  // 片17：进度框外壳（批量补推 / 更新下载那两枚的形状同源、用法不同）
  'lib/widgets/ios_progress_dialog.dart',
  // 片18：图标网格外壳（标题 + 高度上限的可滚网格）
  'lib/widgets/ios_grid_picker_dialog.dart',
};

/// MaterialPageRoute 的**现状台账**（片：T90 补册，2026-10-05）。
///
/// ⚠ **这不是「要换掉的清单」，是「不许变多的清单」**：这一类从来没有被纳入 T90 的
///   弹层那一族（那 27 片换的是对话框 / 列表选择器 / 表单弹层 / 下拉壳），
///   于是它们**既不在旧台账、也没有守卫** —— 加一处不会红，减一处也没人记。
///   本册把它钉成「只许变薄」：新增一律红，逐文件枚数相等。
///
/// ⚠ **换法尚未定**：SnackBar 在 Cupertino 里**没有对应控件**（`CupertinoApp` 下它仍走
///   Material 样式），所以换它要先有一个自己的轻提示装配点（`IosDialogActions`
///   那族已经有 `showInfo` 一类，但那是对话框不是轻提示）。在那之前，本册只管「别变多」。
const Map<String, int> kMaterialRouteSites = <String, int>{
  'lib/pages/app_channel_list_page.dart': 1,
  'lib/pages/email_settings_page.dart': 1,
  'lib/pages/fnthink_channel_list_page.dart': 1,
  // 这一格从台账里删掉，不是漏记：T100 第一刀把两枚入口行（接收入页 / 绑定入页）换成
  // `CupertinoPageRoute`、片2 又把远程执行那三行交给 `FnthinkEntryRow` ⇒ 该文件现在 0 枚。
  // 变薄，不是搬家。
  'lib/pages/main_page.dart': 1,
  // 4 而不是 5：幻念那一格改走注入回调（`main_page_actions.dart`），
  // more_page 里就地 Navigator.push 的那一枚随之消失（变薄，不是搬家）。
  'lib/pages/more_page.dart': 4,
  // 这一格同样是从台账里买断式删掉：hub 那三行（T100 片2）改走 `FnthinkEntryRow`，
  // 而这个文件里**没有第二处** MaterialPageRoute ⇒ 0 枚。
  'lib/pages/rule_edit_page.dart': 1,
  'lib/pages/rule_list_page.dart': 3,
  'lib/pages/webhook_channel_list_page.dart': 1,
};

/// 幻念那几张页里"蓝字无框"的裸 `TextButton` 台账（T100 片2 立，只许变薄）。
///
/// §1 已把这一族的合法形状收成三种：**行**（`FnthinkEntryRow`，进一页／改一个值）／
/// **弹层里的动作行**（`CardActionSheet`、IosFormDialog 内按钮）／**主操作填充**（一页最多一枚）。
/// 裸 `TextButton` 当页内动作用不再计入这三种 —— 但今天还剩 19 枚，一次换完的风险大于收益
/// ⇒ 照 T43 那本「不许长回来」的账写：**新增一律红、逐文件枚数相等**，换掉一枚就把账改小。
///
/// ⚠ **口径是"幻念那六张页"**（`lib/pages/fnthink_*.dart`），不是全库：别的页面不归这本账管，
///   把它们一并扫进来会把这份文档说的剩余工作量换成另一个数。
///
/// ⚠ 0 枚的文件**从账里删掉**（照 `kMaterialRouteSites` 的先例），不留 `: 0` ——
///   守卫断的是键集合相等，"留 0"与"没有这一格"在读数上是两件事。
const Map<String, int> kFnthinkRawTextButtons = <String, int>{};
// ⚠ **这本账今天必须是空的**（2026-10-07 判据② 四刀收完）—— 清零之后它的牙全挂在
// 「差集为空」那一条上：任何一张幻念页再长出一枚裸 TextButton 都会当场红。
// 与 T90 那两本台账同一条教训（台账清零不等于闸变硬，得另写一条'必须保持为空'）。

/// showSnackBar 的**现状台账**（片：T90 补册，2026-10-05）。
///
/// ⚠ **这不是「要换掉的清单」，是「不许变多的清单」**：这一类从来没有被纳入 T90 的
///   弹层那一族（那 27 片换的是对话框 / 列表选择器 / 表单弹层 / 下拉壳），
///   于是它们**既不在旧台账、也没有守卫** —— 加一处不会红，减一处也没人记。
///   本册把它钉成「只许变薄」：新增一律红，逐文件枚数相等。
///
/// ⚠ **换法尚未定**：SnackBar 在 Cupertino 里**没有对应控件**（`CupertinoApp` 下它仍走
///   Material 样式），所以换它要先有一个自己的轻提示装配点（`IosDialogActions`
///   那族已经有 `showInfo` 一类，但那是对话框不是轻提示）。在那之前，本册只管「别变多」。
const Map<String, int> kSnackBarSites = <String, int>{
  'lib/pages/app_channel_settings_page.dart': 1,
  'lib/pages/app_filter_page.dart': 1,
  'lib/pages/backup_restore_page.dart': 1,
  'lib/pages/channel_status_page.dart': 1,
  'lib/pages/device_snapshot_page.dart': 1,
  'lib/pages/email_settings_page.dart': 2,
  'lib/pages/fnthink_channel_list_page.dart': 1,
  'lib/pages/history_page.dart': 11,
  'lib/pages/main_page.dart': 1,
  'lib/pages/main_page_update.dart': 2,
  'lib/pages/more_page.dart': 2,
  'lib/pages/remote_credential_settings_page.dart': 1,
  // T153 片1：远程触发筛选页从 `AppFilterPage` 派生，那一枚「刷新失败」轻提示
  // 照搬过来（同一发刷新、同一句失败，两页各一枚 ⇒ 账 +1）。
  // ⚠ 这不是"新增一处没人管的轻提示"，而是把既有那一枚的形状复制到派生页；
  //    SnackBar 的换法仍未定（Cupertino 无对应件），所以照原样入账。
  'lib/pages/remote_trigger_filter_page.dart': 1,
  'lib/pages/rule_list_page.dart': 1,
  'lib/pages/webhook_settings_page.dart': 1,
  'lib/pages/widget_guide_page.dart': 3,
  // T97 片B：幻念那两页的「复制」各写一份 `_copy` ⇒ 搬一张页就多一处轻提示。
  // 收成 `fnthinkCopyNotice` 一处之后，这一格是从 `fnthink_settings_page` 那**同一枚**搬来的，
  // 总数没变；而换法定下来那天（SnackBar 在 Cupertino 下没有对应件）只有一处要改。
  'lib/widgets/fnthink_card.dart': 1,
  'lib/widgets/icon_picker_tile.dart': 1,
  'lib/widgets/rule_template_sheet.dart': 1,
};

/// 非幻念页的裸 `TextButton`（T153 片6 的台账，**只许减少**）。
///
/// 这一族与幻念那本（`kFnthinkRawTextButtons`，口径是 `lib/pages/fnthink_*.dart`）
/// 是**两本不同的账**：那本管幻念六页，这本管其余页面。2026-10-15 维护者反馈
/// 「应用内哪些地方还是用的这种纯文字无 widget 的按钮，必须改」时，两本都要看。
///
/// T153 片6 从 19 处换到 **3 处**（换掉 16 处：AppBar 顶栏动作 8、行内动作 5、
/// 空态创建 1、卡片三步 3 减…见 §6 T153 块逐处清单），剩下三处**各有保留理由**：
///
///  1. `webhook_settings_page` ×1 —— 那枚「测试并保存」带**内联 loading 槽**
///     （`_isSaving ? CircularProgressIndicator : Text(...)`），而公共件没有那个槽；
///     硬换会丢掉"正在保存"这个反馈。
///  2. `battery_page` ×1 与 3. `temperature_page` ×1 —— 那两枚是**行内 chip 族**
///     （`Container(height:32) + TextButton.styleFrom` 自搭的选中态芯片），
///     与 `FnthinkChoiceChip`（13px/radius 10 的"一排可选项里的一枚"）
///     **不是同一族的密度**。T90 片9 已把这一族登记成**另一笔账**（行内 chip 形状统一），
///     硬并会把行内 chip 放大一圈 —— 那是重设计不是统一。
///
/// ⚠ 两本账的**空值都合法**（清零之后守卫靠「账外不许新增」那一条继续有牙）。
/// ⚠ 判据同时扫 `TextButton(` 与 `TextButton.icon(`：**第一版只扫前者，漏了后者**
///   （`email_settings_page` 那枚「仅测试」就是 `TextButton.icon`，
///   而它被测试撞出来时，屏上看起来一切正常）。
const Map<String, int> kPlainTextButtons = <String, int>{
  'lib/pages/webhook_settings_page.dart': 1,
  'lib/pages/battery_page.dart': 1,
  'lib/pages/temperature_page.dart': 1,
};

/// 非幻念页的**裸文字点击件**（T166 ③ 的台账，只许减少）。
///
/// 判据认「child 直接是 `Text`」与「中间只隔 `Padding`/`Center` 等排版件」两形 ——
/// 那正是「屏上读不出可点、按下也没反馈」的那一种；包着 `Container` 的分段条／
/// 按钮不算（它们有自己的外观）。
/// 具名例外只有两处：`more_page` 的版本号连点 7 次（有意隐藏的诊断入口，`DiagLog`）
/// 与 `app_channel_settings_page` 浮层底部「知道了」（iOS 动作行）。其余页面必须清零。
const Map<String, int> kTextOnlyTapTargets = <String, int>{
  // 有意隐藏的诊断入口：版本号连点 7 次（`DiagLog`），不许换成按钮。
  'lib/pages/more_page.dart': 1,
  // 接入引导浮层底部「知道了」：iOS 动作行的标准形态（整行 `InkWell` + 纯文字，
  // 按压有反馈）。保留文字档；若浮层壳换掉，这一格跟着改。
  'lib/pages/app_channel_settings_page.dart': 1,
};

/// 还长着 Material `AlertDialog` 的文件与**各自的枚数**（T90 逐屏换的台账，只许缩短）。
/// 片13 起记枚数不记文件：文件级台账挡不住「在已入账的文件里再添一枚」。
///
/// ✅ **片28（2026-10-05）这本账清零**：`temperature_page` 那枚「试跑结果框」收进
///   `IosDialogActions.showExplainer`（形状 = 标题 + 可读正文 + 一颗「关闭」，与片26 的规则引导同族）
///   ⇒ **lib 下已无 Material `AlertDialog`**。
/// ⚠ 账**留着不删**（空账）：上面那两条守卫现在等于「整棵 lib 不许有 Material 对话框」——
///   删掉这个常量就把那两条守卫一起删了。新写一处会红在「没有文件在台账之外新增长对话框」。
const Map<String, int> kMaterialDialogSites = <String, int>{
  // 片27：`rule_tester_page` 那枚「选择应用」外壳收进 `IosDialogActions.showExplainer`
  // ⇒ **整屏出账**（选择器本体变成 `body`，带值的行仍然 `Navigator.pop(context, a)`）。
  // 片26：`rule_list_page` 那枚「规则引导」收进 `IosDialogActions.showExplainer` ⇒ **整屏出账**。
  // 片25：`backup_restore_page` 那枚「恢复冲突三选一」收进 `IosDialogActions.askThreeWay`
  // ⇒ **整屏出账**（该文件下屏的口令弹层早就是 `showIosInputDialog`，本版是最后一枚）。
  // 片24：`history_page` 那枚「自动保存路径」收进 `showIosOptionPicker`
  // ⇒ **整屏出账**（history 下屏的弹层从此全部走了装配点）。
  // 片22：`main_page_dialogs` 两枚全清（「关于」走 `showInfo`，语言切换走 `askEitherWay`）
  // ⇒ **整屏出账**。⚠ 它是 part 文件：按 `main_page.dart` grep 会以为它还在账上。
  // 片16：rule_edit_page 最后一枚（聚合参数编辑框）换进了 `IosFormDialog` ⇒ 整屏出账。
  // 四枚条件/动作表单在 part 文件 `rule_edit_widgets.dart`（片12 迁的），别按文件名 grep 漏掉。
  // 片23：`webhook_settings_item` 那枚「选择通道类型」收进**现成的** `showIosOptionPicker`
  // ⇒ 整屏出账。⚠ 它是 part 文件：按 `webhook_settings_page.dart` grep 会以为它还在账上。
  // 片21：`main_page_update` 那一枚「发现新版本」换进 `IosDialogActions.showUpdatePrompt` /
  // `showForceUpdatePrompt` ⇒ 整屏出账（下载进度框是片17 收的，不在本账里）。
  // ⚠ 这枚在 part 文件里：按 `main_page.dart` grep 会以为它不在账上。
  // #176 片3 新增的一枚：与下面那枚是同一个形态（多字段输入弹层），#184 换那一屏时一起换。
  // 输入弹层刻意不用 `IosDialogActions`：那是**确认框**（一问一答），这里要的是三个输入项 + 选档。
};

List<File> _dartFilesIn(String root, String dir) =>
    Directory('$root/$dir')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();

/// 相对仓库根、正斜杠的路径（Windows 下 listSync 给反斜杠，登记表按正斜杠写）。
String _relative(String root, String path) =>
    path.substring(root.length + 1).replaceAll(r'\', '/');

/// 全族扫描：给定若干**剥注释后**的库文件源码，返回页里私有的"行内小形状"壳类名。
///
/// 判据刻意不是"不许出现 `_DirectionChip`"那种字面口径 —— 换一个名字（`_HistoryDirChip`）
/// 就绕过，而那正是这一族会漂的方式（T100 片5 的 `_Note` 同一条纪律）。
/// 认法＝`class <名以下划线开头、以 Chip|Badge|Tag|Mark 结尾> extends StatelessWidget`
/// （公共件不带下划线，因此 `FnthinkChoiceChip`／`FnthinkStatusMark` 这类唯一作者不会被抓进来）。
/// ⚠ 片16 把口径从"只认 `Chip`"扩到这四词：`channel_status_page` 那枚 `_RoleBadge` 正是
///   靠"名字里不含 Chip"躲过原口径的 —— 同一层的东西，认法窄一格就等于不管它。
List<String> privateMarkShells(Iterable<String> sources) => [
  for (final src in sources)
    for (final m in RegExp(
      r'class\s+(_[A-Za-z0-9_]*(?:Chip|Badge|Tag|Mark))\s+extends\s+StatelessWidget',
    ).allMatches(src))
      m.group(1)!,
]..sort();
