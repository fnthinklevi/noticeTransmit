import 'package:notice_transmit/services/device_info_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/pages/battery_page.dart';
import 'package:notice_transmit/pages/notification_engine_page.dart';
import 'package:notice_transmit/pages/temperature_page.dart';
import 'package:notice_transmit/pages/device_state_page.dart';
import 'dart:io';

import 'package:notice_transmit/models/fnthink_peer.dart';
import 'package:notice_transmit/pages/fnthink_peers_page.dart';
import 'package:notice_transmit/services/fnthink_contract_loader.dart';
import 'package:notice_transmit/services/fnthink_receive_coordinator.dart';
import 'package:notice_transmit/services/fnthink_receiver_service.dart';
import 'package:notice_transmit/services/battery_service.dart';
import 'package:notice_transmit/services/temperature_service.dart';
import 'package:notice_transmit/services/device_state_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/services/fnthink_remote_gate.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/widgets/fnthink_card.dart';

import '../support/engine_rule_store_fake.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_setup.dart';

/// T15：「通知引擎」tab 骨架页 + 电量页改为订阅服务。
///
/// 两件事一起做是因为互相卡着：骨架页要 push 电量页，而电量页原先是"父页装配回调 +
/// 传快照"的形状 —— 它作为被 push 的子页时，父页 rebuild 根本到不了它（T16 在温度页上
/// 踩过的坑）。所以电量页先改成订阅 [BatteryService]，骨架页才不必复制第三份接线。
///
/// 共同判据与 temperature_page_test 一致：**只改服务、不重建父树，界面必须自己跟上**。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BatteryService battery;
  late TemperatureService temperature;
  late DeviceStateService deviceState;
  late MemoryRuleStore store;

  setUp(() async {
    await GetIt.instance.reset();
    SharedPreferences.setMockInitialValues({});
    stubNativeChannels();
    // T20：规则住 engine_rules 表。这两个服务共用一份内存存储（与真实表一样按族分隔）
    // —— 不注伪就会走"库打不开→只读回退"的降级分支，看着绿其实测的是兜底路径。
    store = MemoryRuleStore();
    battery = BatteryService(store: store);
    temperature = TemperatureService(store: store);
    // T24：骨架页现在订阅三个服务，少注册一个就是 GetIt 找不到实例（整文件红）。
    deviceState = DeviceStateService(store: store);
    GetIt.instance
      ..registerSingleton<BatteryService>(battery)
      ..registerSingleton<TemperatureService>(temperature)
      ..registerSingleton<DeviceStateService>(deviceState)
      // 温度页/设备状态页的顶部读数走 T17 快照：push 进这两页时页面构造函数要取它，
      // 少注册一个就是整文件红（与上面那条注释同一个坑）。
      ..registerSingleton<DeviceInfoService>(DeviceInfoService());
    await battery.loadSettings();
    await temperature.loadSettings();
    await deviceState.loadSettings();
  });

  tearDown(() async {
    battery.dispose();
    temperature.dispose();
    deviceState.dispose();
    await GetIt.instance.reset();
    clearNativeChannelStubs();
  });

  Future<void> pumpHome(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppRoot(locale: const Locale('zh'), dark: false, home: home),
    );
    await tester.pumpAndSettle();
  }

  Map<String, dynamic> batteryRule({String id = 'b1', bool enabled = true}) => {
    'id': id,
    'type': 'level_below',
    'value': 20,
    'enabled': enabled,
    'title': '闸门电量规则',
    'content': '',
  };

  group('骨架页：两类设备侧告警的入口', () {
    testWidgets('两行都在，副标题反映服务里的状态（温度无规则 → 提示去添加）', (tester) async {
      await pumpHome(tester, const NotificationEnginePage());

      expect(find.text('电量告警'), findsOneWidget);
      expect(find.text('温度告警'), findsOneWidget);
      // T24：亮度/网络第三行必须在同一张卡里（二分口径：都是"设备自己到了某个状态"）
      expect(find.text('设备状态告警'), findsOneWidget);
      // 温度与设备状态两族初始都没有规则：各自提示"点击添加规则"，而不是硬凑一个"0 条规则"
      expect(find.text('点击添加规则'), findsNWidgets(2));
      expect(find.textContaining('0 条规则'), findsNothing);
    });

    testWidgets('点入口真的 push 到对应设置页', (tester) async {
      await pumpHome(tester, const NotificationEnginePage());

      await tester.tap(find.text('电量告警'));
      await tester.pumpAndSettle();
      expect(find.byType(BatteryPage), findsOneWidget);

      Navigator.of(tester.element(find.byType(BatteryPage))).pop();
      await tester.pumpAndSettle();

      await tester.tap(find.text('温度告警'));
      await tester.pumpAndSettle();
      expect(find.byType(TemperaturePage), findsOneWidget);

      Navigator.of(tester.element(find.byType(TemperaturePage))).pop();
      await tester.pumpAndSettle();

      // T24 的第三个入口：不点这一条，"入口画出来了但推不到页"这种形状测不出来
      await tester.tap(find.text('设备状态告警'));
      await tester.pumpAndSettle();
      expect(find.byType(DeviceStatePage), findsOneWidget);
    });

    testWidgets('开关关掉 → 入口副标题出现「已暂停」（不重建父树）', (tester) async {
      await pumpHome(tester, const NotificationEnginePage());
      expect(find.textContaining('已暂停'), findsNothing);

      await battery.saveNotifyEnabled(false);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('已暂停'),
        findsOneWidget,
        reason: '暂停了却看不出来 = 用户以为还会响；这一格存在的理由就是可见',
      );
    });
  });

  group('电量页：订阅服务（T16 先例）', () {
    testWidgets('服务侧新增规则 → 界面立刻出现', (tester) async {
      await battery.restoreSettings(rules: []);
      await pumpHome(tester, const BatteryPage());
      expect(find.text('闸门电量规则'), findsNothing);

      await battery.addRule(batteryRule());
      await tester.pumpAndSettle();

      expect(
        find.text('闸门电量规则'),
        findsOneWidget,
        reason: '不重建父树就看不到 = 页面读的还是进页那一刻的快照',
      );
    });

    testWidgets('点规则开关 → 停在新位置（不弹回）', (tester) async {
      await battery.restoreSettings(rules: [batteryRule(enabled: false)]);
      await pumpHome(tester, const BatteryPage());

      // 页面上第一个开关是"总开关"，规则行的开关在它后面 ⇒ 取最后一个
      final sw = find.byType(CupertinoSwitch).last;
      expect(tester.widget<CupertinoSwitch>(sw).value, isFalse);

      await tester.tap(sw);
      await tester.pumpAndSettle();

      expect(
        tester.widget<CupertinoSwitch>(sw).value,
        isTrue,
        reason: '弹回 = 写操作没广播，或页面还在读旧列表',
      );
      expect(battery.rules.single['enabled'], isTrue);
    });
  });

  group('T94：这一页多了一块「幻念推送」（往哪儿发）', () {
    testWidgets('那一块在，且只有「已配对的设备」一行（其余三格随片2/片3 落，不摆占位行）', (tester) async {
      await pumpHome(tester, const NotificationEnginePage());

      expect(find.text('幻念推送'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('engine-fnthink-peers')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('engine-fnthink-peers')),
        findsOneWidget,
        reason:
            '「点了没反应的行比没有这行更糟」是这一页上面三格只放真能用的入口的理由，'
            '同一页里摆三行占位会把那条理由自己拆了',
      );
    });

    testWidgets('点它真的 push 到设备绑定页（不是画出来点不动）', (tester) async {
      await pumpHome(tester, NotificationEnginePage(peersDeps: _peersDeps()));

      await tester.tap(find.byKey(const ValueKey('engine-fnthink-peers')));
      await tester.pumpAndSettle();

      expect(
        find.byType(FnthinkPeersPage),
        findsOneWidget,
        reason: '这一格的主题是"我和谁有关系"，而绑定那一页正是它的去处',
      );
    });

    // T97 片C：第四行「远程控制」—— 它与会上面三行不同：**会灰，且灰的原因写在副标题里**。
    testWidgets('远程控制那一行：缺哪一条就说哪一条，并当场点不动', (tester) async {
      await pumpHome(
        tester,
        NotificationEnginePage(
          remoteGateOf: () async => FnthinkRemoteGate.receiveOff,
        ),
      );

      final row = find.byKey(const ValueKey('engine-fnthink-remote'));
      expect(row, findsOneWidget);
      expect(
        find.text('先开「接收」—— 这一页的前提是这台愿意收别人的东西'),
        findsOneWidget,
        reason: '灰了不说原因，用户只会以为这一页坏了',
      );
      expect(
        tester.widget<FnthinkEntryRow>(row).onTap,
        isNull,
        reason: '前置不满足还能点进去，等于把"能不能用"这件事留到下一屏才说',
      );
    });

    testWidgets('前置齐了 ⇒ 那一行可点、副标题回到中性那句', (tester) async {
      await pumpHome(
        tester,
        NotificationEnginePage(
          remoteGateOf: () async => FnthinkRemoteGate.ready,
        ),
      );

      expect(
        tester
            .widget<FnthinkEntryRow>(
              find.byKey(const ValueKey('engine-fnthink-remote')),
            )
            .onTap,
        isNotNull,
      );
      // 断在**词条**上，不抄那把字面量（措辞改一次这里就假红）。
      final l10n = AppLocalizations.of(
        tester.element(find.byType(NotificationEnginePage)),
      );
      expect(find.text(l10n.remoteExecShort), findsOneWidget);
    });

    testWidgets('读不到前置（没装配）⇒ 不禁用、也不说"缺东西"', (tester) async {
      await pumpHome(tester, const NotificationEnginePage());

      expect(
        tester
            .widget<FnthinkEntryRow>(
              find.byKey(const ValueKey('engine-fnthink-remote')),
            )
            .onTap,
        isNotNull,
        reason: '「还不知道」不是「不能用」——禁用会把没读到契约说成用户的问题',
      );
    });
  });

  group('T23：设备态告警也接受约束（默认关）', () {
    testWidgets('页面上只有一枚，且默认是关的', (tester) async {
      await pumpHome(tester, const NotificationEnginePage());

      expect(find.text('设备态告警也接受约束'), findsOneWidget);
      // 一次作用于两族的开关只放一枚：两处各一枚迟早一个开一个关，
      // 而"设备态告警受不受约束"不可能同时有两个答案。
      expect(find.byType(CupertinoSwitch), findsOneWidget);
      expect(
        tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
        isFalse,
        reason: '默认开 = 升级之后本来必推的电量告警可能被关键词拦掉',
      );
    });

    testWidgets('点一下：服务、prefs、开关三处同步，且不弹回', (tester) async {
      await pumpHome(tester, const NotificationEnginePage());
      final sw = find.byType(CupertinoSwitch);

      await tester.tap(sw);
      await tester.pumpAndSettle();

      expect(battery.deviceAlertsRespectConstraints, isTrue);
      expect(tester.widget<CupertinoSwitch>(sw).value, isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('device_alert_constraint_enabled'), isTrue);
    });
  });
}

/// 绑定页的依赖替身（T94）。
///
/// 只需要能把页面推进去、并且读出一个空名单 —— 这里连坐轮都不走；
/// 给一个真跑轮子的替身就变成了「测端点的是哪一行入口」的问题。
FnthinkPeersDeps _peersDeps() => FnthinkPeersDeps(
  contracts: FnthinkContractLoader(
    readAsset: (_) async => File('protocol/fnthink-v1.json').readAsStringSync(),
  ),
  coordinator: FnthinkReceiveCoordinator(
    contracts: FnthinkContractLoader(
      readAsset: (_) async =>
          File('protocol/fnthink-v1.json').readAsStringSync(),
    ),
    signer: _NoSigner(),
    persist: (_) async => true,
    serviceFactory: (_) => throw StateError('本用例不走收货'),
  ),
  loadPeers: () async => const <FnthinkPeer>[],
);

/// 签名器替身：这一页只看名单，不发任何需要签名的请求。
class _NoSigner implements FnthinkIdentitySigner {
  @override
  Future<String> call(List<int> canonicalBytes) async => 'AAAAc2ln';

  @override
  Future<bool> probe() async => false;

  @override
  Future<String?> publicKey() async => null;
}
