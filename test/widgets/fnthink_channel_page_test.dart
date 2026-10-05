import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/fnthink_channel.dart';
import 'package:notice_transmit/models/fnthink_peer.dart';
import 'package:notice_transmit/pages/fnthink_channel_list_page.dart';
import 'package:notice_transmit/pages/fnthink_channel_settings_page.dart';
import 'package:notice_transmit/services/fnthink_channel_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';


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

  Future<void> pump(WidgetTester tester, Widget page) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppRoot(locale: const Locale('zh'), dark: false, home: page),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('一条都没有 ⇒ 说「还没有通道」，且新建按钮在', (tester) async {
    final store = _MemoryStore();
    await pump(tester, FnthinkChannelListPage(service: store));
    expect(find.byKey(const ValueKey('fnthink-channel-empty')), findsOneWidget);
    expect(find.byKey(const ValueKey('fnthink-channel-add')), findsOneWidget);
  });

  testWidgets('库读不出来 ⇒ 说读不到，**不**说「还没有通道」', (tester) async {
    final store = _MemoryStore(failList: true);
    await pump(tester, FnthinkChannelListPage(service: store));
    expect(find.byKey(const ValueKey('fnthink-channel-error')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('fnthink-channel-empty')),
      findsNothing,
      reason: '读不到时画「还没有通道」，界面就在替库说它没说过的话',
    );
  });

  testWidgets('有一条 ⇒ 列表上是它的名字与目标，且那一下能进详情', (tester) async {
    final store = _MemoryStore();
    await store.create(
      id: 'fc_1',
      name: '给孩子',
      target: '8KMNPQRSTVWX999777',
      targetKind: FnthinkChannelTarget.device,
    );
    await pump(tester, FnthinkChannelListPage(service: store));

    expect(find.text('给孩子'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('fnthink-channel-fc_1-target')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('fnthink-channel-fc_1-open')));
    await tester.pumpAndSettle();
    expect(find.byType(FnthinkChannelSettingsPage), findsOneWidget);
  });

  testWidgets('删除要二次确认：取消 ⇒ 那一条还在（点了没反应比删错好）', (tester) async {
    final store = _MemoryStore();
    await store.create(
      id: 'fc_2',
      name: '留着',
      target: 'https://example.com/hook',
      targetKind: FnthinkChannelTarget.webhook,
    );
    await pump(tester, FnthinkChannelListPage(service: store));

    await tester.tap(find.byKey(const ValueKey('fnthink-channel-fc_2-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(await store.list(), hasLength(1));
    expect(find.text('留着'), findsOneWidget);
  });

  testWidgets('删除确认 ⇒ 确认之后那一条真的没了', (tester) async {
    final store = _MemoryStore();
    await store.create(
      id: 'fc_3',
      name: '删掉',
      target: 'https://example.com/hook',
      targetKind: FnthinkChannelTarget.webhook,
    );
    await pump(tester, FnthinkChannelListPage(service: store));

    await tester.tap(find.byKey(const ValueKey('fnthink-channel-fc_3-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    expect(await store.list(), isEmpty);
    expect(find.byKey(const ValueKey('fnthink-channel-empty')), findsOneWidget);
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
