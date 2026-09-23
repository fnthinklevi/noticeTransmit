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
