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

  // ── T90 补册（2026-10-05）：另两族从未被纳入，也从没有守卫 ──────────────
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
      final arb =
          jsonDecode(File('$root/lib/l10n/arb/app_zh.arb').readAsStringSync())
              as Map<String, dynamic>;
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
        RegExp(
          r'probe\.health\.record\(\s*kFnthinkChannelSlug,\s*channel\.id,',
        ).hasMatch(page),
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

    test('那三页的成段说明：边界句只许走「底部圆点行」那一形状', () {
      // 判据③ 2026-10-07 的分桶结论：remote 三页 37 处 _Note 里，绝大多数是状态原话／
      // 字段标签／弹窗正文（§1 明说不许按'美化'去动），唯一一条成段说明是历史页那句边界；
      // 它的去处定成底部圆点行（与设置页 fnthink-boundary 同一个做法）。这条钉住那个形状，
      // 改回裸小字就是让'成段说明'重新长回页面里。
      final src = codeByPath['lib/pages/remote_history_page.dart']!;
      // ⚠ 这一条第一版只断「至少有一处带圆点」—— 反证 D1 当场证伪：那句在页面里**有两处**
      //   （空列表态与有列表态各一），只改回其中一处照样绿。现在两处都要圆点，且裸写法零处。
      const bullet = "'\u2022 \${l10n.remoteHistoryBoundary}'";
      expect(
        bullet.allMatches(src).length,
        2,
        reason: '边界句必须两处（空态 / 有货态）都走底部圆点行',
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
      expect(
        hitting('class FnthinkEntryRow'),
        const <String>['lib/widgets/fnthink_card.dart'],
        reason: '形状①的装配点必须唯一 —— 两份抄本正是 T100 要收的东西',
      );

      int n(String path, String needle) =>
          needle.allMatches(codeByPath[path]!).length;

      // hub 那三行在 `_entry` 里共用一个调用；远程控制页那三行是三次直调
      // （T97 片C 从接收页搬过去 —— 守卫跟着主语走，不是留在旧文件上收一份假账）。
      expect(
        n('lib/pages/notification_engine_page.dart', 'FnthinkEntryRow('),
        greaterThanOrEqualTo(1),
      );
      expect(n('lib/pages/fnthink_remote_page.dart', 'FnthinkEntryRow('), 3);
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
      expect(
        n('lib/pages/fnthink_settings_page.dart', 'FnthinkInlineAction('),
        7,
      );
      expect(
        n('lib/pages/fnthink_endpoint_page.dart', 'FnthinkInlineAction('),
        greaterThanOrEqualTo(1),
      );
      expect(n('lib/pages/fnthink_peers_page.dart', 'FnthinkInlineAction('), 4);
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
      ]) {
        expect(
          n(p, 'PrimaryActionButton('),
          greaterThanOrEqualTo(1),
          reason: '$p 的主操作没有走公共件 ⇒ 形状又分叉了',
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
        RegExp(
          r"""FnthinkNote\(\s*keyName:\s*'fnthink-channel-note'""",
        ).hasMatch(src),
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
        hittingRe(
          materialDialogs,
        ).toSet().difference(kMaterialDialogSites.keys.toSet()),
        isEmpty,
        reason:
            '新一处 Material AlertDialog ⇒ 与 Cupertino 风格不一致；确认框请用 IosDialogActions',
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
        'lib/widgets/fnthink_send_dialog.dart': ['IosFormDialog('],
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

List<File> _dartFilesIn(String root, String dir) => Directory('$root/$dir')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

/// 相对仓库根、正斜杠的路径（Windows 下 listSync 给反斜杠，登记表按正斜杠写）。
String _relative(String root, String path) =>
    path.substring(root.length + 1).replaceAll(r'\', '/');
