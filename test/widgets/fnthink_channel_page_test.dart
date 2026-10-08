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

    expect(find.text('还没有勾选过任何设备，先到「已配对的设备」里勾一台。'), findsOneWidget);
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

  // ── #271「测试这条通道」：徽标今天恒为「没测过」的那一发 ──────────────────────
  // 这一族**没有非侵入探针**（`presence` 只答本机醒不醒），所以徽标能记的只有
  // 「最近一次测试」—— 也就是说：没有这一枚，列表页那些徽标永远说不出话来。

  testWidgets('那一枚只在三个条件同时成立时才画（接了 probe ＋ 已有通道 ＋ 设备档）', (tester) async {
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
      findsNothing,
      reason: '还没存过的新通道没有 id 可记账 —— 测出来的那一条会挂到一条不存在的通道上',
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
}
