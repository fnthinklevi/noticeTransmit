import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/channel_health_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 健康度单点的行为（第 6 步）。
///
/// 这三件事以前分散在三处（webhook 页自己判 6h、应用通道页只读不判、
/// email 另用一个无时间戳的 Map），所以谁都没被测过。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('读写与时效', () {
    test('record 落 prefs（键含 family）并可被读回', () async {
      final store = ChannelHealthStore();
      await store.load();
      await store.record(
        'webhook',
        'wh_1',
        reachable: true,
        latencyMs: 42,
        httpCode: 200,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('channel_health_webhook:wh_1'),
        isNotNull,
        reason: '键里没 family 时三族 id 序列会互相串台（webhook 徽标挂到应用通道上）',
      );
      final health = store.of('webhook', 'wh_1');
      expect(health, isNotNull);
      expect(health!.reachable, isTrue);
      expect(health.latencyMs, 42);
      expect(health.httpCode, 200);
      expect(ChannelHealthStore.needsProbe(health), isFalse);
    });

    test('空 id 不写不读（新增未保存的行没有 id）', () async {
      final store = ChannelHealthStore();
      await store.load();
      await store.record('webhook', '', reachable: true, latencyMs: 1);
      expect(store.of('webhook', ''), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((k) => k.startsWith('channel_health_')),
        isEmpty,
      );
    });

    test('超过 6 小时算过期；没有记录一律要探', () {
      ChannelHealth at(int msAgo) => ChannelHealth(
        reachable: true,
        latencyMs: 5,
        probedAt: DateTime.now().millisecondsSinceEpoch - msAgo,
      );
      expect(ChannelHealthStore.needsProbe(null), isTrue);
      expect(ChannelHealthStore.needsProbe(at(60 * 1000)), isFalse);
      expect(
        ChannelHealthStore.needsProbe(
          at(ChannelHealthStore.staleness.inMilliseconds + 1000),
        ),
        isTrue,
      );
    });

    test('remove：通道删掉后徽标不会复活成上一条的状态', () async {
      final store = ChannelHealthStore();
      await store.load();
      await store.record('app', 'app_1', reachable: true, latencyMs: 3);
      expect(store.of('app', 'app_1'), isNotNull);
      await store.remove('app', 'app_1');
      expect(store.of('app', 'app_1'), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('channel_health_app:app_1'), isNull);
    });

    test('remove 也要清掉旧格式的键（[of] 会读穿它）', () async {
      // 只清新键的话，删掉的通道在界面上仍然带着上一次的徽标 —— 实测于 webhook
      // 删除用例（第 6 步之前的老设备留的就是这种键）。
      SharedPreferences.setMockInitialValues({
        'channel_health_app_1': jsonEncode({
          'reachable': false,
          'latencyMs': 0,
          'probedAt': 1767223200000,
        }),
      });
      final store = ChannelHealthStore();
      await store.load();
      expect(store.of('app', 'app_1'), isNotNull, reason: '前提：旧格式键读得穿');
      await store.remove('app', 'app_1');
      expect(store.of('app', 'app_1'), isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('channel_health_app_1'), isNull);
    });
  });

  // ── 连续成功次数（T135：自动切回那条判据的证据来源）─────────────────────
  // 这一族计数**只在写记录那一次**算得出：那里同时握着旧值与新值。
  // 如果让原生自己数"我见到几次成功"，通知来得勤的设备切得快、来得少的永远切不回 ——
  // 那正是下面第一条用例要拦住的方向，所以这几条钉的是"数的是什么"，不是"屏幕上说什么"。
  group('连续成功探测次数（切回的证据）', () {
    test('连着成功往上加，一次失败归零，再成功从 1 起', () async {
      final store = ChannelHealthStore();
      await store.load();

      Future<int> probe(bool ok) async {
        await store.record('webhook', 'wh_1', reachable: ok, latencyMs: 10);
        return store.of('webhook', 'wh_1')!.okSuccesses;
      }

      expect(await probe(true), 1);
      expect(await probe(true), 2);
      expect(await probe(true), 3);
      expect(await probe(false), 0, reason: '一次失败就把连着成功清零：判据要的"连着"不能跨过失败累计');
      expect(await probe(true), 1, reason: '归零后重新开始，不接着上次那个数');
    });

    test('计数随记录落盘：进程重启（新实例 + load）之后接着数', () async {
      final first = ChannelHealthStore();
      await first.load();
      await first.record('webhook', 'wh_1', reachable: true, latencyMs: 10);
      await first.record('webhook', 'wh_1', reachable: true, latencyMs: 10);

      final prefs = await SharedPreferences.getInstance();
      final stored =
          jsonDecode(prefs.getString('channel_health_webhook:wh_1')!)
              as Map<String, dynamic>;
      expect(
        stored['okSuccesses'],
        2,
        reason: '没落盘的话，每次冷启动都从 1 重数 ⇒ 攒够阈值这件事在这台设备上永远做不到',
      );

      final second = ChannelHealthStore();
      await second.load();
      await second.record('webhook', 'wh_1', reachable: true, latencyMs: 10);
      expect(second.of('webhook', 'wh_1')!.okSuccesses, 3);
    });

    test('旧记录没这个字段 ⇒ 读成 0，第一次成功记 1（不猜历史上成功过几次）', () async {
      SharedPreferences.setMockInitialValues({
        'channel_health_webhook:wh_1': jsonEncode({
          'reachable': true,
          'latencyMs': 9,
          'probedAt': DateTime.now().millisecondsSinceEpoch,
        }),
      });
      final store = ChannelHealthStore();
      await store.load();
      expect(
        store.of('webhook', 'wh_1')!.okSuccesses,
        0,
        reason: '说不出连着几次就是没证据；替老数据补一个 1 会让判据读到一份并不存在的证据',
      );

      await store.record('webhook', 'wh_1', reachable: true, latencyMs: 9);
      expect(store.of('webhook', 'wh_1')!.okSuccesses, 1);
    });

    test('两条同 id 的通道各自数各自（键含 family 这一条在计数上也成立）', () async {
      final store = ChannelHealthStore();
      await store.load();
      await store.record('webhook', 'shared-id', reachable: true, latencyMs: 1);
      await store.record('webhook', 'shared-id', reachable: true, latencyMs: 1);
      await store.record('app', 'shared-id', reachable: true, latencyMs: 1);

      expect(store.of('webhook', 'shared-id')!.okSuccesses, 2);
      expect(
        store.of('app', 'shared-id')!.okSuccesses,
        1,
        reason: '串了台就把 webhook 的成功次数算到应用通道头上 ⇒ 那条从未通过的通道被判断"可以切回"',
      );
    });

    test('删掉通道时那份计数跟着走（id 复用不带走上一段历史）', () async {
      final store = ChannelHealthStore();
      await store.load();
      await store.record('webhook', 'wh_1', reachable: true, latencyMs: 1);
      await store.record('webhook', 'wh_1', reachable: true, latencyMs: 1);
      await store.remove('webhook', 'wh_1');

      await store.record('webhook', 'wh_1', reachable: true, latencyMs: 1);
      expect(
        store.of('webhook', 'wh_1')!.okSuccesses,
        1,
        reason: '清掉记录却留着计数 ⇒ 下一条同名通道一上来就带着"已连着成功两次"',
      );
    });
  });

  group('旧数据读穿（不换键、不丢徽标）', () {
    test('第 6 步之前的键（不带 family）仍读得到，按调用方的族解释', () async {
      SharedPreferences.setMockInitialValues({
        'channel_health_app-h2': jsonEncode({
          'reachable': false,
          'latencyMs': 0,
          'httpCode': 0,
          'probedAt': 1767223200000,
        }),
      });
      final store = ChannelHealthStore();
      await store.load();
      final health = store.of('app', 'app-h2');
      expect(health, isNotNull, reason: '旧徽标不该因为换了键格式就凭空消失');
      expect(health!.reachable, isFalse);
      expect(store.of('webhook', 'app-h2'), isNotNull);
      // 写侧只写新格式：旧键留着读穿即可，不批量改写用户 prefs（下次探测自然覆盖）
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('channel_health_app:app-h2'), isNull);
      expect(prefs.getString('channel_health_app-h2'), isNotNull);
    });

    test('email 旧 Map 搬进单点：没有时间戳 ⇒ 判过期，下次进页自然重探', () async {
      SharedPreferences.setMockInitialValues({
        'email_test_results': jsonEncode({'em_1': true, 'em_2': false}),
      });
      final store = ChannelHealthStore();
      await store.load();
      expect(store.of('email', 'em_1')?.reachable, isTrue);
      expect(store.of('email', 'em_2')?.reachable, isFalse);
      expect(ChannelHealthStore.needsProbe(store.of('email', 'em_1')), isTrue);
    });

    test('坏 JSON 条目只丢自己，不连带整份缓存', () async {
      SharedPreferences.setMockInitialValues({
        'channel_health_webhook:bad': '{oops',
        'channel_health_webhook:ok': jsonEncode({
          'reachable': true,
          'latencyMs': 7,
          'probedAt': 1767223200000,
        }),
      });
      final store = ChannelHealthStore();
      await store.load();
      expect(store.of('webhook', 'bad'), isNull);
      expect(store.of('webhook', 'ok')?.latencyMs, 7);
    });
  });

  test('load 幂等：重复调用不重复读 prefs', () async {
    final store = ChannelHealthStore();
    await store.load();
    await store.record('webhook', 'w', reachable: true, latencyMs: 1);
    await store.load();
    expect(store.of('webhook', 'w'), isNotNull);
  });
}
