import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/fnthink_channel.dart';
import 'package:notice_transmit/models/fnthink_peer.dart';
import 'package:notice_transmit/pages/fnthink_channel_list_page.dart';
import 'package:notice_transmit/pages/fnthink_consent_gate.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:notice_transmit/services/fnthink_channel_service.dart';
import 'package:notice_transmit/services/fnthink_settings.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/source_guards.dart';

/// T118：「内容真会经服务器走」的那四类动作共用的那道同意门。
///
/// 这一组只钉两件事，缺一件这道门就是摆设：
///  ① **行为**：未同意时点那些入口 ⇒ 弹门、**一个字节都不写**（取消、去同意页都算"什么都没发生"）；
///  ② **形状**：那八条入口各自过门（按函数断），而非浸入探针那两条链**不过门**
///     —— 它们一个字段都不读、一条都不投，拦它等于把"同意之前先看看通不通"这条自检路弄死。
///
/// ⚠ widget 测试跑在假时钟里：真 IO 的 future 不会完成（不报错、也不挂断用例，表现是
/// "点了没反应"）⇒ 这一组用 `debugFnthinkConsentSettingsOverride` 塞一份**同步**读出来的契约。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 这一组测的就是门 ⇒ 默认**没同意**（prefs 里没有那枚键）。
    SharedPreferences.setMockInitialValues(<String, Object>{});
    debugFnthinkConsentSettingsOverride = FnthinkSettings(
      contract: FnthinkContract.readFile(),
    );
    addTearDown(() => debugFnthinkConsentSettingsOverride = null);
  });

  const channelId = 'fc_consent_1';
  const now = 1780000000000;
  const channel = FnthinkChannel(
    id: channelId,
    name: 'NAS',
    target: 'https://push.example.com/api/fnthink/p/ep_x',
    targetKind: FnthinkChannelTarget.webhook,
    enabled: false,
    role: 'primary',
    createdAt: now,
    updatedAt: now,
  );

  Future<AppLocalizations> pumpList(
    WidgetTester tester,
    _MemoryStore store,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: FnthinkChannelListPage(
          service: store,
          health: ChannelHealthStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(
      tester.element(find.byType(FnthinkChannelListPage)),
    );
  }

  testWidgets('未同意时打开一条通道的开关 ⇒ 弹门，库里一条都没写', (tester) async {
    final store = _MemoryStore(<FnthinkChannel>[channel]);
    final l10n = await pumpList(tester, store);

    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();

    expect(
      find.text(l10n.fnthinkConsentGateGo),
      findsOneWidget,
      reason: '点"开"砸在没同意上 ⇒ 要说清为什么、并给出去处（不许只是没反应）',
    );
    expect(store.saves, 0, reason: '门没过就先写了库 ⇒ 那道门是装饰');
    // 弹层里不许出现既成事实的措辞：这一下**什么都还没发生**。
    for (final forbidden in <String>['已保存', '已启用', '已发送']) {
      expect(find.textContaining(forbidden), findsNothing);
    }
  });

  testWidgets('在门上点取消 ⇒ 一样一个字节都不写（开关弹回去）', (tester) async {
    final store = _MemoryStore(<FnthinkChannel>[channel]);
    final l10n = await pumpList(tester, store);

    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();

    expect(store.saves, 0);
    final sw = tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch));
    expect(sw.value, isFalse, reason: '取消之后开关还画成开着的 ⇒ 界面替用户记了一次没发生的写入');
  });

  testWidgets('门给的出路是「去那一页同意」，而点它之前这一发仍然什么都没写', (tester) async {
    // ⚠ 这一条**不点**那枚去处：它推的是真的 `FnthinkReceivePage`，而那一页从 locator 取五个依赖，
    //   裸 widget 测试里建不起来（点下去会抛 "not registered inside GetIt"）。"去处指向同意页"
    //   这一半由下面的形状守卫钉（门的源码里必须出现 FnthinkReceivePage），这里只钉
    //   "给出路"与"还没写"两件事。
    final store = _MemoryStore(<FnthinkChannel>[channel]);
    final l10n = await pumpList(tester, store);

    await tester.tap(find.byType(CupertinoSwitch));
    await tester.pumpAndSettle();

    expect(find.text(l10n.fnthinkConsentGateGo), findsOneWidget);
    expect(find.text(l10n.cancel), findsOneWidget);
    expect(store.saves, 0, reason: '开门这一刻还什么都没发生');
  });

  group('形状守卫：八条入口各自过门，探针那两条不过门', () {
    final root = projectRoot();
    String read(String rel) =>
        stripComments(File('$root/$rel').readAsStringSync());

    void gated(String rel, String signature, String why) {
      final block = blockAfter(read(rel), signature);
      expect(
        block,
        contains('requireFnthinkRelayConsent('),
        reason: '$rel 的 `$signature` 没有过同意门 ⇒ $why',
      );
    }

    test('端点：建 / 换 / 撤 三发都在函数最前面过门', () {
      gated(
        'lib/pages/fnthink_endpoint_page.dart',
        'Future<void> _createEndpoint() async {',
        '建的那把口令存在的意义就是让内容经服务器走',
      );
      gated(
        'lib/pages/fnthink_endpoint_page.dart',
        'Future<void> _rotateEndpoint(',
        '换口令是让一把正在用的口令开始倒计时',
      );
      gated(
        'lib/pages/fnthink_endpoint_page.dart',
        'Future<void> _revokeEndpoint(',
        '撤的那一下也要落在那台中转机上',
      );
    });

    test('配对：发起与批准过门，**拒绝不过门**', () {
      // ⚠ 这一枚**不能用 `blockAfter`**：它有命名参数，而那个 helper 取的是签名之后第一个 `{`
      //   —— 命名参数表先撞上，取回来的只有参数表（源码里那条注释记着同一个坑）。
      //   改成"签名 → 填表弹层"这一段的区域断言，顺带把"门在弹层**之前**"也钉住。
      final peers = read('lib/pages/fnthink_peers_page.dart');
      final sig = peers.indexOf('Future<void> _pairWithPeer');
      final dialog = peers.indexOf(
        'final input = await showFnthinkPairDialog(',
        sig,
      );
      expect(sig, greaterThan(-1), reason: '尺没空转：发起那一枚签名读得到');
      expect(dialog, greaterThan(sig), reason: '尺没空转：填表弹层那一行读得到');
      expect(
        peers.substring(sig, dialog),
        contains('requireFnthinkRelayConsent('),
        reason: '发起配对没过门、或门排在了填表弹层之后 ⇒ 用户先把地址码与一次性口令敲完再被告知"先同意"',
      );
      final answer = blockAfter(
        read('lib/pages/fnthink_peers_page.dart'),
        'Future<void> _answer(FnthinkPairRequest request, bool approve) async {',
      );
      expect(
        answer,
        contains('requireFnthinkRelayConsent('),
        reason: '批准配对没过门 ⇒ 同意之前就能把一台设备记进那台机器的关系列',
      );
      expect(
        answer,
        contains('if (approve)'),
        reason:
            '门必须在"同意"那一支里：拒绝是**把关系挡在门外**，拦它等于让还没同意的人连拒绝都做不到'
            '（那条请求会一直挂在待处理里）',
      );
    });

    test('通道：创建/启用（存一条开着的）与那发会带正文的测试过门', () {
      gated(
        'lib/pages/fnthink_channel_settings_page.dart',
        'Future<void> _save() async {',
        '存一条"开着"的通道＝从此会把内容送到那台中转机上',
      );
      gated(
        'lib/pages/fnthink_channel_settings_page.dart',
        'Future<void> _probe() async {',
        '「仅探测」真的把标题与正文发出去',
      );
      gated(
        'lib/pages/fnthink_channel_list_page.dart',
        'Future<void> _setEnabled(',
        '打开一条通道＝这一族功能开始往外发',
      );
    });

    test('发一条：两档都过门（它们走同一条出站）', () {
      gated(
        'lib/pages/fnthink_send_page.dart',
        'Future<void> _sendNotice() async {',
        '那一发走的就是那台中转机',
      );
      gated(
        'lib/pages/fnthink_send_page.dart',
        'Future<void> _sendCommand() async {',
        '指令档与通知档同一条出站，且还带着凭据',
      );
    });

    test('非浸入探针那两条链**不过门**：同意之前先看看通不通这条路要留着', () {
      for (final rel in const [
        'lib/services/fnthink_channel_probe.dart',
        'lib/services/fnthink_endpoint_dryrun.dart',
      ]) {
        expect(
          read(rel),
          isNot(contains('requireFnthinkRelayConsent')),
          reason: '$rel 是探针链（一个字段都不读、一条都不投）⇒ 拦它等于把自检路弄死',
        );
      }
    });

    test('门的定义只有一处，且它自己**绝不**替用户点同意', () {
      final gate = read('lib/pages/fnthink_consent_gate.dart');
      expect(
        gate,
        contains('Future<bool> requireFnthinkRelayConsent('),
        reason: '门那一位作者不在 ⇒ 下面的判据全空转',
      );
      expect(
        gate,
        isNot(contains('grantRelayConsent')),
        reason: '门里出现 grantRelayConsent ⇒ 它在替用户点同意（T56 那条一次性显式同意的红线）',
      );
      expect(
        gate,
        contains('FnthinkReceivePage'),
        reason: '门要给出去处 ⇒ 它得指向同意那一页（那一页的同意键由 T56 的守卫钉着）',
      );
      final libFiles = Directory('$root/lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      final authors = <String>[];
      for (final f in libFiles) {
        if (stripComments(
          f.readAsStringSync(),
        ).contains('Future<bool> requireFnthinkRelayConsent(')) {
          authors.add(f.path.replaceAll('\\', '/').split('/lib/').last);
        }
      }
      expect(authors, <String>['pages/fnthink_consent_gate.dart']);
    });
  });
}

/// 只记"写没写"的最小库（这一组关心的是门，不是通道本身）。
class _MemoryStore implements FnthinkChannelStore {
  _MemoryStore(List<FnthinkChannel> rows) : _rows = List.of(rows);

  final List<FnthinkChannel> _rows;
  int saves = 0;

  @override
  Future<void> setForward(String peerAddress, bool forwards) async {}

  @override
  Future<List<FnthinkChannel>> list() async => List.of(_rows);

  @override
  Future<FnthinkChannel> create({
    required String id,
    required String name,
    required String target,
    required FnthinkChannelTarget targetKind,
    String role = 'primary',
  }) async {
    final row = FnthinkChannel(
      id: id,
      name: name,
      target: target,
      targetKind: targetKind,
      enabled: true,
      role: role,
      createdAt: now,
      updatedAt: now,
    );
    _rows.add(row);
    return row;
  }

  @override
  Future<FnthinkChannel> save(FnthinkChannel channel) async {
    saves++;
    final i = _rows.indexWhere((r) => r.id == channel.id);
    if (i >= 0) _rows[i] = channel;
    return channel;
  }

  @override
  Future<List<FnthinkPeer>> listForwardTargets() async => const <FnthinkPeer>[];

  @override
  Future<void> delete(String id) async {
    _rows.removeWhere((r) => r.id == id);
  }

  static const int now = 1780000000000;
}
