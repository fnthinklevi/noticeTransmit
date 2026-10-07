import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/fnthink_channel.dart';
import 'package:notice_transmit/models/fnthink_peer.dart';
import 'package:notice_transmit/pages/fnthink_channel_list_page.dart';
import 'package:notice_transmit/pages/fnthink_channel_settings_page.dart';
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
}
