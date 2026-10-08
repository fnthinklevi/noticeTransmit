import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/fnthink_channel.dart';
import 'package:notice_transmit/models/fnthink_peer.dart';
import 'package:notice_transmit/pages/fnthink_channel_list_page.dart';
import 'package:notice_transmit/pages/fnthink_channel_settings_page.dart';
import 'package:notice_transmit/services/channel_display.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:notice_transmit/services/fnthink_channel_service.dart';
import 'package:notice_transmit/theme/app_colors.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/channel_health_badge.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 幻念通道的两张页面（T94 片3）。
///
/// ⚠ 这里**不开真库**，页面拿的是一份内存替身 —— 理由不是省事：`testWidgets` 跑在 fake async 里，
/// 真库在那个时区里打不开，于是整个文件的用例会集体停在第 0 条（今日量到过 6/6 全红）。
/// 真库那一半在 `test/services/fnthink_channel_service_test.dart`（11 条，那里不在 fake async 里）。
/// 两边合起来才是"页面认口、服务认库"，只测一半就当完整会漏掉接线。
///
/// 钉的是三件"画出来但用不了"或"删错一条代价一样"的事：
///  ① **空库与读不到是两句话**：读不到时画「还没有通道」，界面就在替库说它没说过的话；
///  ② **设备那一支不许自由输入**（没勾选时那一格不可点，并说清去哪儿勾）；
///  ③ **删要走二次确认**：删掉之后这台就不再往那个目标转发了。
class _MemoryStore implements FnthinkChannelStore {
  _MemoryStore({this.failList = false, List<FnthinkPeer>? targets})
    : _targets = targets ?? <FnthinkPeer>[];

  bool failList;
  final List<FnthinkPeer> _targets;
  final List<FnthinkChannel> _rows = [];

  /// 名单那一列勾选（T98 片③ 把它挪进了接口）：这一页的用例不勾，留一条能编译又什么都不做的。
  @override
  Future<void> setForward(String peerAddress, bool forwards) async {}

  @override
  Future<List<FnthinkChannel>> list() async {
    if (failList) throw StateError('库打不开');
    return List<FnthinkChannel>.of(_rows);
  }

  @override
  Future<FnthinkChannel> create({
    required String id,
    required String name,
    required String target,
    required FnthinkChannelTarget targetKind,
    String role = 'primary',
  }) async {
    const now = 1780000000000;
    final channel = FnthinkChannel(
      id: id,
      name: name,
      target: target,
      targetKind: targetKind,
      role: role,
      createdAt: now,
      updatedAt: now,
    );
    _rows.add(channel);
    return channel;
  }

  @override
  Future<FnthinkChannel> save(FnthinkChannel channel) async {
    final i = _rows.indexWhere((c) => c.id == channel.id);
    if (i < 0) throw StateError('没有这一条：${channel.id}');
    _rows[i] = channel;
    return channel;
  }

  @override
  Future<void> delete(String id) async {
    _rows.removeWhere((c) => c.id == id);
  }

  @override
  Future<List<FnthinkPeer>> listForwardTargets() async => List.of(_targets);
}

FnthinkPeer _peer({String address = '8KMNPQRSTVWX999777'}) => FnthinkPeer(
  peerAddress: address,
  publicKey: 'AAAA',
  level: 'L1',
  grantedAt: 1780000111000,
  forwards: true,
);

/// 「测试这条通道」那一发的替身（#271）：记下每一次发出去的载荷，并让用例决定回什么。
class _ProbeSpy {
  final List<({String peer, String title, String text})> sent = [];

  /// 对面收下了没有（生产里这一位是 `status == accepted`）。
  bool ok = true;

  /// 非空 ⇒ 这一发抛这个（服务/网络层的原话）。
  Object? boom;

  Future<bool> send({
    required String peer,
    required String title,
    required String text,
  }) async {
    sent.add((peer: peer, title: title, text: text));
    final e = boom;
    if (e != null) throw e;
    return ok;
  }
}

/// 一条设备档通道（详情页那一枚只对设备档画）。
FnthinkChannel _deviceChannel({String id = 'fc_9'}) => FnthinkChannel(
  id: id,
  name: '给孩子',
  target: '8KMNPQRSTVWX999777',
  targetKind: FnthinkChannelTarget.device,
  createdAt: 1780000000000,
  updatedAt: 1780000000000,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 健康度缓存在测试里必须有 mock：`ChannelHealthStore.load()` 读 SharedPreferences，
    // 没 mock 时那一次 await 不会返回。页面已改成「列表先出、缓存后补」，
    // 这一行补上另一半 —— 别让用例跑去等一个永远不来的平台通道回信。
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppRoot(locale: const Locale('zh'), dark: false, home: page),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('一条都没有 ⇒ 说「还没有通道」，且那一下新增在（FAB，与另三族同一形状）', (tester) async {
    final store = _MemoryStore();
    await pump(
      tester,
      FnthinkChannelListPage(service: store, health: ChannelHealthStore()),
    );
    expect(find.byKey(const ValueKey('fnthink-channel-empty')), findsOneWidget);
    // 新增从"页面里一颗左对齐的按钮"换成了 FAB —— 与 webhook／自建应用两族一致：
    // 列表页的主行动是"再加一条"，它该在右下角，而不是跟在最后一行下面。
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.byKey(const ValueKey('fnthink-channel-add')), findsNothing);
  });

  testWidgets('库读不出来 ⇒ 说读不到，**不**说「还没有通道」', (tester) async {
    final store = _MemoryStore(failList: true);
    await pump(
      tester,
      FnthinkChannelListPage(service: store, health: ChannelHealthStore()),
    );
    expect(find.byKey(const ValueKey('fnthink-channel-error')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('fnthink-channel-empty')),
      findsNothing,
      reason: '读不到时画「还没有通道」，界面就在替库说它没说过的话',
    );
  });

  testWidgets('有一条 ⇒ 行上是名字与目标，点那一行进详情', (tester) async {
    final store = _MemoryStore();
    await store.create(
      id: 'fc_1',
      name: '给孩子',
      target: '8KMNPQRSTVWX999777',
      targetKind: FnthinkChannelTarget.device,
    );
    await pump(
      tester,
      FnthinkChannelListPage(service: store, health: ChannelHealthStore()),
    );

    final row = find.byKey(const ValueKey('fnthink-channel-row-fc_1'));
    expect(row, findsOneWidget, reason: '行的 key 挂在**通道 id** 上，不挂下标');
    expect(
      find.descendant(of: row, matching: find.text('给孩子')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: row, matching: find.text('8KMNPQRSTVWX999777')),
      findsOneWidget,
      reason: '地址码是这条通道"是谁"的身份，不是可省略的传输细节',
    );

    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.byType(FnthinkChannelSettingsPage), findsOneWidget);
  });

  testWidgets('还没测过的行 ⇒ 徽标带的是 null（"没测过"），不是一枚绿的', (tester) async {
    final store = _MemoryStore();
    await store.create(
      id: 'fc_5',
      name: '没测过',
      target: '8KMNPQRSTVWX999777',
      targetKind: FnthinkChannelTarget.device,
    );
    await pump(
      tester,
      FnthinkChannelListPage(service: store, health: ChannelHealthStore()),
    );

    final badges = find.descendant(
      of: find.byKey(const ValueKey('fnthink-channel-row-fc_5')),
      matching: find.byType(ChannelHealthBadge),
    );
    expect(badges, findsOneWidget);
    expect(
      tester.widget<ChannelHealthBadge>(badges).health,
      isNull,
      reason:
          '这一族没有非侵入探针，徽标只能记"最近一次测过"。从没测过的行画成绿，'
          '就是让一个没发生过的结论出现在屏幕上',
    );
    // ⚠ 但也不能**什么都不说**（维护者 2026-10-08：「幻念推送通道列表为什么没有通道健康度！」）。
    // 另三族没记录就闭嘴，因为它们过一轮非侵入探测就有数；这一族只能等用户进详情点那一枚，
    // 所以那一格要把"还没测过"讲出来 —— 空白读起来像"这一族没有健康度这个东西"。
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('fnthink-channel-row-fc_5')),
        matching: find.text('从未探测'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('设置不混在列表里：右上那一枚齿轮在，且接得上设置页', (tester) async {
    final store = _MemoryStore();
    await pump(
      tester,
      FnthinkChannelListPage(service: store, health: ChannelHealthStore()),
    );
    final gear = find.byKey(const ValueKey('fnthink-channel-settings'));
    expect(gear, findsOneWidget);
    expect(
      tester.widget<IconButton>(gear).onPressed,
      isNotNull,
      reason: '画一枚点了没反应的齿轮，比不画更坏（这一族自己的判据）',
    );
    // 真跳转的那一页要读契约与 DI，由 `fnthink_settings_page_test.dart` 那批用例负责；
    // 这里只钉"这一格在、且接得上"，不去替那一页构造世界。
  });

  testWidgets('删除走长按菜单 + 二次确认：取消 ⇒ 那一条还在（点了没反应比删错好）', (tester) async {
    final store = _MemoryStore();
    await store.create(
      id: 'fc_2',
      name: '留着',
      target: 'https://example.com/hook',
      targetKind: FnthinkChannelTarget.webhook,
    );
    await pump(
      tester,
      FnthinkChannelListPage(service: store, health: ChannelHealthStore()),
    );

    await tester.longPress(
      find.byKey(const ValueKey('fnthink-channel-row-fc_2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(await store.list(), hasLength(1));
    expect(find.text('留着'), findsOneWidget);
  });

  testWidgets('长按菜单里确认 ⇒ 那一条真的没了，行上的开关不再替它说话', (tester) async {
    final store = _MemoryStore();
    await store.create(
      id: 'fc_3',
      name: '删掉',
      target: 'https://example.com/hook',
      targetKind: FnthinkChannelTarget.webhook,
    );
    await pump(
      tester,
      FnthinkChannelListPage(service: store, health: ChannelHealthStore()),
    );

    await tester.longPress(
      find.byKey(const ValueKey('fnthink-channel-row-fc_3')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(await store.list(), isEmpty);
    expect(find.byKey(const ValueKey('fnthink-channel-empty')), findsOneWidget);
  });

  testWidgets('行上那枚开关改的就是这一条（启停不必进详情）', (tester) async {
    final store = _MemoryStore();
    await store.create(
      id: 'fc_4',
      name: '先停',
      target: '8KMNPQRSTVWX999777',
      targetKind: FnthinkChannelTarget.device,
    );
    await pump(
      tester,
      FnthinkChannelListPage(service: store, health: ChannelHealthStore()),
    );

    final row = find.byKey(const ValueKey('fnthink-channel-row-fc_4'));
    final sw = find.descendant(of: row, matching: find.byType(CupertinoSwitch));
    expect(sw, findsOneWidget);
    expect(tester.widget<CupertinoSwitch>(sw).value, isTrue);
    // 点的是行尾那枚开关本身：tap 整行的中心落在标题区，那一下是「进详情」。
    await tester.tap(sw);
    await tester.pumpAndSettle();

    final after = (await store.list()).single;
    expect(after.enabled, isFalse, reason: '开关点了没落到那一条上，界面上它就只是个装饰');
    expect(after.name, '先停', reason: '只该动启停这一项，别把名字一起写掉');
  });

  testWidgets('设备那一支：没勾选任何设备时不可点，并说清去哪儿勾', (tester) async {
    final store = _MemoryStore(targets: const []);
    await pump(tester, FnthinkChannelSettingsPage(service: store));

    expect(find.text('还没有勾选过任何设备，先到「设备配对」里勾一台。'), findsOneWidget);
    final target = tester.widget<CupertinoButton>(
      find.byKey(const ValueKey('fnthink-channel-target')),
    );
    expect(
      target.onPressed,
      isNull,
      reason: '没勾选时让用户自由输地址码 = 把「这一台同不同意收」变成一个输入框',
    );
  });

  testWidgets('设备那一支：勾选过之后那一格可点', (tester) async {
    final store = _MemoryStore(targets: [_peer()]);
    await pump(tester, FnthinkChannelSettingsPage(service: store));

    final target = tester.widget<CupertinoButton>(
      find.byKey(const ValueKey('fnthink-channel-target')),
    );
    expect(target.onPressed, isNotNull);
  });

  testWidgets('窄屏（393dp＝这台机的逻辑宽）：空态那句话不顶到屏幕两边', (tester) async {
    // ⚠ 这一条是真机走查逼出来的（2026-10-08）：本文件其它用例都跑在 1080 逻辑宽上，
    //   那句话按整幅宽度换行**正好顶到两边**（手机上第一行从 x=0 起、末字压到边缘）。
    //   离开这台机之前，这个缺陷任何一条用例都看不见。
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: FnthinkChannelListPage(
          service: _MemoryStore(),
          health: ChannelHealthStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final line = lookupAppLocalizations(const Locale('zh')).fnthinkChannelEmpty;
    final rect = tester.getRect(find.text(line));
    expect(rect.left, greaterThan(8), reason: '那句话左边顶到屏幕 ⇒ 窄屏上会溢出去');
    expect(
      393 - rect.right,
      greaterThan(8),
      reason: '那句话右边顶到屏幕 ⇒ 同上（真机走查看到的就是这个）',
    );
  });

  testWidgets('窄屏（393dp）：这一页的卡头徽标与页脚两枚都不溢出', (tester) async {
    // 上一条是列表页的空态；这一条是**详情页**：它同一横排里有「种类 + 徽标（两段字）」，
    // 页脚又并排两枚按钮 —— 都是这一屏最宽的东西，而 393dp 是这台机的真实逻辑宽。
    tester.view.physicalSize = const Size(393, 851);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final store = _MemoryStore(targets: [_peer()]);
    final health = ChannelHealthStore();
    // 先记一发不通的，让那枚徽标真的带两段文字（带耗时的那种更容易挤爆）
    await health.record(
      kFnthinkChannelSlug,
      'fc_9',
      reachable: false,
      latencyMs: 4200,
    );
    final spy = _ProbeSpy();
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: FnthinkChannelSettingsPage(
          channel: _deviceChannel(),
          service: store,
          probe: FnthinkChannelProbeDeps(send: spy.send, health: health),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 溢出在测试里是一条 RenderFlex 异常，不是"看着有点挤"——它必须一条都没有。
    expect(tester.takeException(), isNull);
    for (final key in const ['fnthink-channel-probe', 'fnthink-channel-save']) {
      final finder = find.byKey(ValueKey(key));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      final rect = tester.getRect(finder);
      expect(
        [rect.left.floorToDouble(), (393 - rect.right).floorToDouble()],
        everyElement(greaterThanOrEqualTo(0.0)),
        reason: '$key 那枚按钮横着跑到屏幕外了',
      );
    }
  });

  // ── #271「测试这条通道」：徽标今天恒为「没测过」的那一发 ──────────────────────
  // 这一族**没有非侵入探针**（`presence` 只答本机醒不醒），所以徽标能记的只有
  // 「最近一次测试」—— 也就是说：没有这一枚，列表页那些徽标永远说不出话来。

  testWidgets('那一枚只看两件事（接了 probe ＋ 设备档）—— 新建那一条也画', (tester) async {
    final store = _MemoryStore();
    final health = ChannelHealthStore();
    final probe = FnthinkChannelProbeDeps(
      send: _ProbeSpy().send,
      health: health,
    );
    const probeKey = ValueKey('fnthink-channel-probe');

    await pump(
      tester,
      FnthinkChannelSettingsPage(
        key: const ValueKey('page-no-probe'),
        channel: _deviceChannel(),
        service: store,
      ),
    );
    expect(
      find.byKey(probeKey),
      findsNothing,
      reason: '没接 probe（测试与别处构造）就不画：点了没反应的按钮比没有这一枚更糟',
    );

    await pump(
      tester,
      FnthinkChannelSettingsPage(
        key: const ValueKey('page-new'),
        service: store,
        probe: probe,
      ),
    );
    expect(
      find.byKey(probeKey),
      findsOneWidget,
      reason:
          '维护者 2026-10-08 第 2 条点名的就是这个：新建那一页原本没有「仅探测」。'
          'id 在需要时先发号（与另三族 T04 同一做法），所以那一发的账有稳定归属',
    );

    await pump(
      tester,
      FnthinkChannelSettingsPage(
        key: const ValueKey('page-webhook'),
        channel: const FnthinkChannel(
          id: 'fc_w',
          name: '钩子',
          target: 'https://example.com/hook',
          targetKind: FnthinkChannelTarget.webhook,
          createdAt: 1780000000000,
          updatedAt: 1780000000000,
        ),
        service: store,
        probe: probe,
      ),
    );
    expect(
      find.byKey(probeKey),
      findsNothing,
      reason: 'webhook 档的发送实现在原生那侧 ⇒ 这一枚会是一条点了没反应的路',
    );

    await pump(
      tester,
      FnthinkChannelSettingsPage(
        key: const ValueKey('page-device'),
        channel: _deviceChannel(),
        service: store,
        probe: probe,
      ),
    );
    expect(find.byKey(probeKey), findsOneWidget);
  });

  testWidgets('测一下：发的是这一条通道的目标，账记在 (fnthink, 通道 id) 上', (tester) async {
    final store = _MemoryStore();
    final health = ChannelHealthStore();
    final spy = _ProbeSpy();
    await pump(
      tester,
      FnthinkChannelSettingsPage(
        channel: _deviceChannel(),
        service: store,
        probe: FnthinkChannelProbeDeps(send: spy.send, health: health),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('fnthink-channel-probe')));
    await tester.pumpAndSettle();

    expect(spy.sent, hasLength(1), reason: '「测试」这一下必须真发一条 —— 这一族没有非侵入探针');
    expect(
      spy.sent.single.peer,
      '8KMNPQRSTVWX999777',
      reason: '发的是**这一条**通道的目标，不是别的通道、也不是随便哪一台',
    );
    expect(spy.sent.single.title, isNotEmpty);

    final h = health.of(kFnthinkChannelSlug, 'fc_9');
    expect(h, isNotNull, reason: '不记账 ⇒ 列表页那个徽标永远「没测过」，而那正是 #271 要修的东西');
    expect(h!.reachable, isTrue);
    expect(
      find.byKey(const ValueKey('fnthink-channel-probe-note')),
      findsOneWidget,
    );
  });

  testWidgets('对面没接下（不是 accepted）⇒ 结论是「没接」，账记成不通', (tester) async {
    final store = _MemoryStore();
    final health = ChannelHealthStore();
    final spy = _ProbeSpy()..ok = false;
    await pump(
      tester,
      FnthinkChannelSettingsPage(
        channel: _deviceChannel(),
        service: store,
        probe: FnthinkChannelProbeDeps(send: spy.send, health: health),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('fnthink-channel-probe')));
    await tester.pumpAndSettle();

    expect(spy.sent, hasLength(1));
    expect(
      health.of(kFnthinkChannelSlug, 'fc_9')!.reachable,
      isFalse,
      reason: '没报错不等于通了：这一档必须落成"不通"，否则徽标会给一条没送到的通道发绿',
    );
    expect(
      find.byKey(const ValueKey('fnthink-channel-probe-note')),
      findsOneWidget,
    );
  });

  testWidgets('发的时候抛了 ⇒ 界面上留原话，账同样记成不通', (tester) async {
    final store = _MemoryStore();
    final health = ChannelHealthStore();
    final spy = _ProbeSpy()..boom = StateError('对面关机了');
    await pump(
      tester,
      FnthinkChannelSettingsPage(
        channel: _deviceChannel(),
        service: store,
        probe: FnthinkChannelProbeDeps(send: spy.send, health: health),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('fnthink-channel-probe')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('对面关机了'),
      findsOneWidget,
      reason: '把服务/网络层的原话折叠成一句「失败」，用户与我们都不知道被什么挡住',
    );
    final h = health.of(kFnthinkChannelSlug, 'fc_9');
    expect(h, isNotNull, reason: '抛了也要落一条不通 —— 徽标说的是"最近一次试过"，不是"最近一次成功"');
    expect(h!.reachable, isFalse);
  });

  testWidgets('列表页 → 测一条 → 回来徽标就带上了这一次（写键与读键是同一个）', (tester) async {
    final store = _MemoryStore();
    await store.create(
      id: 'fc_1',
      name: '给孩子',
      target: '8KMNPQRSTVWX999777',
      targetKind: FnthinkChannelTarget.device,
    );
    final health = ChannelHealthStore();
    final spy = _ProbeSpy();
    await pump(
      tester,
      FnthinkChannelListPage(
        service: store,
        health: health,
        probe: FnthinkChannelProbeDeps(send: spy.send, health: health),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('fnthink-channel-row-fc_1')));
    await tester.pumpAndSettle();
    expect(find.byType(FnthinkChannelSettingsPage), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('fnthink-channel-probe')));
    await tester.pumpAndSettle();
    // 这一页是 Material 路由：`pageBack()` 只认 Cupertino 背键／英文 tooltip，
    // 中文下必失败（`bootstrap_order_test` 里那条守卫写的就是这件事）⇒ 按 BackButton 点。
    await tester.tap(
      find.descendant(
        of: find.byType(FnthinkChannelSettingsPage),
        matching: find.byType(BackButton),
      ),
    );
    await tester.pumpAndSettle();

    final badge = tester.widget<ChannelHealthBadge>(
      find.descendant(
        of: find.byKey(const ValueKey('fnthink-channel-row-fc_1')),
        matching: find.byType(ChannelHealthBadge),
      ),
    );
    expect(
      badge.health,
      isNotNull,
      reason: '测完回来徽标还是「没测过」⇒ 写键与读键不是同一个（#271 的原形）',
    );
    expect(badge.health!.reachable, isTrue);
  });

  // ── 维护者 2026-10-08 点名的四条：红字 / 页脚两枚 / 角色中文 / 版式 ─────────────
  // 判据都打在**能观察的东西**上：红字挂在哪个控件上、一次点击落下几件事、
  // 那一格画的是译文还是 token。不断措辞（措辞会漂），也不断装饰性的尺寸。

  /// 屏幕上那句话实际用的颜色：`Text.style` 或外面那层 `DefaultTextStyle`。
  Color? paintedColor(WidgetTester tester, String text) {
    final finder = find.text(text);
    final element = finder.evaluate().single;
    return tester.widget<Text>(finder).style?.color ??
        DefaultTextStyle.of(element).style.color;
  }

  /// 把一条设备档通道填到可以保存（名称 + 从名单里挑目标）。
  Future<void> fillDeviceForm(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(const ValueKey('fnthink-channel-name')),
      '给孩子',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('fnthink-channel-target')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('ios-picker-8KMNPQRSTVWX999777')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('名称为空 ⇒ 红字挂在**名称字段**上，而且不发也不存', (tester) async {
    final store = _MemoryStore(targets: [_peer()]);
    final spy = _ProbeSpy();
    await pump(
      tester,
      FnthinkChannelSettingsPage(
        key: const ValueKey('page-empty-name'),
        service: store,
        probe: FnthinkChannelProbeDeps(
          send: spy.send,
          health: ChannelHealthStore(),
        ),
      ),
    );
    final line = lookupAppLocalizations(
      const Locale('zh'),
    ).fnthinkChannelNameEmpty;

    await tester.tap(find.byKey(const ValueKey('fnthink-channel-save')));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const ValueKey('fnthink-channel-name')),
    );
    expect(
      field.decoration!.errorText,
      line,
      reason: '那句话必须挂在字段上：卡片底下那行灰字与"这条为什么没存上"混在一起，等于没说',
    );
    expect(
      paintedColor(tester, line),
      AppColors.red,
      reason: '要的是红字（维护者第 1 条）；12px 灰字那一版就是"提醒不明显"的那个东西',
    );
    expect(spy.sent, isEmpty, reason: '名称没填就往外发一条 = 给一条还不存在的通道记上"最近测过"');
    expect(await store.list(), isEmpty);
  });

  testWidgets('填全之后点「探测并保存」⇒ 一次点击：建一条、真发一条、账挂在这条上', (tester) async {
    final store = _MemoryStore(targets: [_peer()]);
    final spy = _ProbeSpy();
    final health = ChannelHealthStore();
    await pump(
      tester,
      FnthinkChannelSettingsPage(
        service: store,
        probe: FnthinkChannelProbeDeps(send: spy.send, health: health),
      ),
    );
    await fillDeviceForm(tester);

    await tester.tap(find.byKey(const ValueKey('fnthink-channel-save')));
    await tester.pumpAndSettle();

    final rows = await store.list();
    expect(rows, hasLength(1));
    expect(rows.single.name, '给孩子');
    expect(
      spy.sent,
      hasLength(1),
      reason:
          '保存默认带探测（维护者第 2 条）：这一族没有非侵入探针，'
          '"存下来了、通不通"只能真的发一条才知道 —— 分两下点等于让用户猜',
    );
    expect(
      health.of(kFnthinkChannelSlug, rows.single.id)?.reachable,
      isTrue,
      reason: 'id 在写库前就发好了 ⇒ 那一发的账有稳定归属，不是挂到别处',
    );
    // 卡头那枚徽标当场就说上话（另三族详情页的同一件）。测完这一页还停在"没测过"的话，
    // 用户得退出这一页去列表页确认 —— 那一发像是根本没做。
    final badge = tester.widget<ChannelHealthBadge>(
      find.descendant(
        of: find.byType(FnthinkChannelSettingsPage),
        matching: find.byType(ChannelHealthBadge),
      ),
    );
    expect(badge.health?.reachable, isTrue);

    // 再点一次是**更新那一条**，不是又建一条（连按两下不该在库里留下两条同名通道）。
    await tester.tap(find.byKey(const ValueKey('fnthink-channel-save')));
    await tester.pumpAndSettle();
    expect(await store.list(), hasLength(1));
  });

  testWidgets('「仅探测」不落库：真发一条、给出结论，库里仍然一条都没有', (tester) async {
    final store = _MemoryStore(targets: [_peer()]);
    final spy = _ProbeSpy();
    await pump(
      tester,
      FnthinkChannelSettingsPage(
        service: store,
        probe: FnthinkChannelProbeDeps(
          send: spy.send,
          health: ChannelHealthStore(),
        ),
      ),
    );
    await fillDeviceForm(tester);

    await tester.tap(find.byKey(const ValueKey('fnthink-channel-probe')));
    await tester.pumpAndSettle();

    expect(spy.sent, hasLength(1));
    expect(
      await store.list(),
      isEmpty,
      reason: '「仅探测」这一枚存在的全部理由就是"别替我存下来"（另三族的「仅测试」同义）',
    );
    expect(
      find.byKey(const ValueKey('fnthink-channel-probe-note')),
      findsOneWidget,
    );
  });

  testWidgets('主备那一档画的是**译文**（起点「未设置」），存下去的仍是字面量', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('zh'));
    final store = _MemoryStore(targets: [_peer()]);
    await pump(
      tester,
      FnthinkChannelSettingsPage(
        service: store,
        probe: FnthinkChannelProbeDeps(
          send: _ProbeSpy().send,
          health: ChannelHealthStore(),
        ),
      ),
    );
    final cell = find.byKey(const ValueKey('fnthink-channel-role-value'));

    expect(
      tester.widget<Text>(cell).data,
      l10n.roleUnset,
      reason:
          '新建的起点是「未设置」而不是「主」——与另外三族同一口径（全停在「主」时'
          '同一条通知会被重复推送）',
    );
    for (final token in ['primary', 'backup', 'none', 'unset']) {
      expect(
        find.textContaining(token),
        findsNothing,
        reason: '$token 是落库的字面量，不是画给用户看的 label（维护者第 3 条）',
      );
    }

    await tester.tap(find.byKey(const ValueKey('fnthink-channel-role')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.rolePrimary), findsOneWidget);
    expect(
      find.text(l10n.roleBackup),
      findsOneWidget,
      reason: '弹层里那一档也得画译文 —— 维护者第 3 条说的就是这一格里画着英文 token',
    );
    expect(find.text(l10n.roleNone), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ios-picker-backup')));
    await tester.pumpAndSettle();
    expect(tester.widget<Text>(cell).data, l10n.roleBackup);

    await fillDeviceForm(tester);
    await tester.tap(find.byKey(const ValueKey('fnthink-channel-save')));
    await tester.pumpAndSettle();
    expect(
      (await store.list()).single.role,
      'backup',
      reason: '画的是译文、存的是 `ChannelConfigCodec` 的字面量 —— 换译名不许改掉落库值',
    );
  });

  testWidgets('切到 webhook 那一支 ⇒ 主操作只说「保存」，并说清这一支为什么测不了', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('zh'));
    final store = _MemoryStore(targets: [_peer()]);
    final spy = _ProbeSpy();
    await pump(
      tester,
      FnthinkChannelSettingsPage(
        service: store,
        probe: FnthinkChannelProbeDeps(
          send: spy.send,
          health: ChannelHealthStore(),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('fnthink-channel-probe')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('fnthink-channel-kind')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.fnthinkChannelTargetKindWebhook));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('fnthink-channel-probe')),
      findsNothing,
      reason: '那一支的发送实现在原生那侧，从 Dart 画一枚按钮就是摆一条点了没反应的路',
    );
    expect(find.text(l10n.fnthinkChannelSave), findsOneWidget);
    expect(find.text(l10n.fnthinkChannelProbeAndSave), findsNothing);
    expect(
      find.byKey(const ValueKey('fnthink-channel-probe-unavailable')),
      findsOneWidget,
      reason: '按钮少了一枚要当场说为什么 —— 否则用户以为这一页少了个功能',
    );

    await tester.enterText(
      find.byKey(const ValueKey('fnthink-channel-name')),
      '给孩子',
    );
    await tester.enterText(
      find.byKey(const ValueKey('fnthink-channel-target')),
      'https://example.com/hook',
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('fnthink-channel-save')));
    await tester.pumpAndSettle();

    expect(await store.list(), hasLength(1), reason: '保存本身照常 —— 只是不冒充探测');
    expect(spy.sent, isEmpty, reason: 'webhook 那一支从这一页发不出去，保存也不许假装探测一次');
  });
}
