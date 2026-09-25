import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/services/engine_rule_codec.dart';
import 'package:notice_transmit/services/engine_rule_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_setup.dart';

/// T20：规则读写的咽喉行为（[EngineRuleRepository]）。
///
/// 这里钉的是**存储分工**的六条判据，每条都对应一种会静默改变告警行为的错法：
/// 1. DB 为准，prefs 旧键是原生镜像；两者不一致时以 DB 修镜像（不是反向）；
/// 2. "从没配过"与"删空了"必须分得开 —— 否则出厂默认规则每开机复活一遍；
/// 3. DB 打不开时只读回退，绝不写（写了就可能把还没迁进库的规则洗成空的）；
/// 4. 原生重载信号必须每次写之后都发（不发 = 改了阈值但服务按旧值判，下次启动才生效）；
/// 5. 通知原生失败不许把用户的保存一起吞掉；
/// 6. 两族互不干扰（键名、表内 family 都要隔）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    SharedPreferences.setMockInitialValues({});
    stubNativeChannels(
      onCall: (call) async {
        calls.add(call);
        return null;
      },
    );
  });

  tearDown(clearNativeChannelStubs);

  EngineRuleRepository battery({EngineRuleStore? store}) =>
      EngineRuleRepository(
        family: EngineRuleCodec.familyBattery,
        prefsKey: 'battery_rules',
        store: store ?? _FakeStore(),
      );

  Map<String, dynamic> rule(String id, {int value = 20, bool enabled = true}) =>
      {
        'id': id,
        'type': 'level_below',
        'value': value,
        'enabled': enabled,
        'title': '',
        'content': '',
      };

  Future<List<Map<String, dynamic>>> mirrored(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    return raw == null ? [] : List<Map<String, dynamic>>.from(jsonDecode(raw));
  }

  group('播种与"删空"的分别', () {
    test('从没配过规则：播默认值，并同时落库、落镜像、通知原生', () async {
      final store = _FakeStore();
      final repo = battery(store: store);

      final got = await repo.load(seed: () => [rule('low20')]);

      expect(got.map((r) => r['id']), ['low20']);
      expect(
        store.rows[EngineRuleCodec.familyBattery],
        hasLength(1),
        reason: '只播内存不入库 = 下次开机又播一遍，用户改的东西永远存不住',
      );
      expect(await mirrored('battery_rules'), hasLength(1));
      expect(calls.map((c) => c.method), contains('refreshEngineRules'));
    });

    test('用户把规则删空（镜像是 []）：不许再播默认值', () async {
      SharedPreferences.setMockInitialValues({
        'battery_rules': jsonEncode(<Map<String, dynamic>>[]),
      });
      final store = _FakeStore();
      final repo = battery(store: store);

      final got = await repo.load(seed: () => [rule('low20')]);

      expect(got, isEmpty, reason: '"库里没行"不等于"没配过"：刚删掉的默认规则复活是无声的改动');
      expect(store.rows[EngineRuleCodec.familyBattery], isNull);
    });

    test('库里没行而旧键有规则：补导入一次（迁移没跑成的那条路）', () async {
      SharedPreferences.setMockInitialValues({
        'battery_rules': jsonEncode([rule('low30', value: 30)]),
      });
      final store = _FakeStore();
      final repo = battery(store: store);

      final got = await repo.load();

      expect(got.map((r) => r['value']), [30]);
      expect(
        store.rows[EngineRuleCodec.familyBattery],
        hasLength(1),
        reason: '只读不回补 = 下次镜像写失败时规则真的没了',
      );
    });
  });

  group('DB 与镜像谁为准', () {
    test('DB 有行时以 DB 为准，并把过期的镜像修回 DB 的内容', () async {
      SharedPreferences.setMockInitialValues({
        // 镜像比库里"新"（其实是上次镜像写成功、库写失败留下的）—— 必须以 DB 为准
        'battery_rules': jsonEncode([rule('ghost', value: 99)]),
      });
      final store = _FakeStore()
        ..rows[EngineRuleCodec.familyBattery] = [rule('low20', value: 20)];
      final repo = battery(store: store);

      final got = await repo.load();

      expect(got.map((r) => r['id']), ['low20']);
      expect(
        (await mirrored('battery_rules')).map((r) => r['id']),
        ['low20'],
        reason: '镜像不修回，原生就还按用户已经删掉的那条规则推',
      );
    });

    test('DB 读失败：只读回退到旧键，且不写库、不写镜像', () async {
      SharedPreferences.setMockInitialValues({
        'battery_rules': jsonEncode([rule('low20', value: 20)]),
      });
      final store = _FakeStore()..failReads = true;
      final repo = battery(store: store);

      final got = await repo.load(seed: () => [rule('brand-new')]);

      expect(got.map((r) => r['id']), ['low20'], reason: '库打不开时旧键是用户规则唯一的活路');
      expect(store.saved, isEmpty, reason: '回退分支不许写库');
      expect(
        (await mirrored('battery_rules')).map((r) => r['id']),
        ['low20'],
        reason: '回退分支更不许写镜像 —— 那会把"还没迁进库"的规则洗掉',
      );
    });

    test('保存时库写不进去：镜像仍然写、异常抛给调用方（内存编辑不丢）', () async {
      final store = _FakeStore()..failWrites = true;
      final repo = battery(store: store);

      Object? thrown;
      try {
        await repo.save([rule('low20', value: 20)]);
      } catch (e) {
        thrown = e;
      }
      expect(thrown, isNotNull, reason: '入库失败必须让上层知道，不许静默"保存成功"');
      expect(
        await mirrored('battery_rules'),
        hasLength(1),
        reason: 'DB 已经不可信，prefs 是这条编辑唯一的去处',
      );
      expect(calls.map((c) => c.method), contains('refreshEngineRules'));
    });
  });

  group('写入内容与顺序', () {
    test('落库与落镜像的都是**归一后**的规则（Double 截成 int、缺字段补齐）', () async {
      final store = _FakeStore();
      final repo = battery(store: store);

      await repo.save([
        <String, dynamic>{'id': 'r1', 'value': 33.7, 'type': 'level_below'},
      ]);

      final saved = store.rows[EngineRuleCodec.familyBattery]!.single;
      expect(saved['value'], 33, reason: '滑块/备份给 Double，`as int` 会当场抛');
      expect(
        saved['enabled'],
        true,
        reason: '缺 enabled 算启用（原生 optBoolean 同口径）',
      );
      expect(saved['title'], '');
      expect(saved['content'], '');

      final mirror = (await mirrored('battery_rules')).single;
      expect(
        mirror.keys.toSet(),
        EngineRuleCodec.uiKeys.toSet(),
        reason: '镜像少一个键，原生就按自己的默认值补 —— 两处默认值正是 T20 要结束的',
      );
    });

    test('保存顺序：先库、再镜像、最后才通知原生重载', () async {
      SharedPreferences.setMockInitialValues({'battery_rules': '[标记]'});
      final prefs = await SharedPreferences.getInstance();
      String? mirrorWhenStoreCalled;
      int nativeCallsWhenStoreCalled = -1;

      final store = _FakeStore(
        onEvent: (event) {
          if (event != 'save') return;
          // 写库的那一刻：镜像还是旧值、原生还没被通知。顺序反了（先通知后写库）
          // 就是"服务 reload 读到的还是上一版规则"—— 用户改完阈值它按旧值判。
          mirrorWhenStoreCalled = prefs.getString('battery_rules');
          nativeCallsWhenStoreCalled = calls.length;
        },
      );
      await battery(store: store).save([rule('low20')]);

      expect(mirrorWhenStoreCalled, '[标记]', reason: '库还没写就先刷了镜像');
      expect(nativeCallsWhenStoreCalled, 0, reason: '库还没写就通知了原生');
      expect((await mirrored('battery_rules')).map((r) => r['id']), ['low20']);
      expect(calls.map((c) => c.method), contains('refreshEngineRules'));
    });

    test('通知原生失败不影响保存（规则已落库落镜像）', () async {
      clearNativeChannelStubs();
      final store = _FakeStore();
      final repo = battery(store: store);

      await repo.save([rule('low20')]);

      expect(store.rows[EngineRuleCodec.familyBattery], hasLength(1));
      expect(await mirrored('battery_rules'), hasLength(1));
    });

    test('两族互不干扰：存电量不动温度那把键', () async {
      SharedPreferences.setMockInitialValues({
        'temperature_rules': jsonEncode([
          {
            'id': 't1',
            'type': 'device_temp_above',
            'value': 45,
            'enabled': true,
          },
        ]),
      });
      final store = _FakeStore();
      await battery(store: store).save([rule('low20')]);

      expect(
        (await mirrored('temperature_rules')).map((r) => r['id']),
        ['t1'],
        reason: 'prefsKey 少写族前缀 = 两族互相覆盖（原生读到空数组，温度告警再也不来）',
      );
      expect(store.rows.keys, [
        EngineRuleCodec.familyBattery,
      ], reason: 'saveEngineRules 若把族当参数写错，温度那一族会被整族删掉');
    });
  });
}

/// 内存版存储：只管"按族存"，不模拟 SQL —— SQL 层的行为在
/// `test/database/engine_rules_schema_test.dart` 里用真库验。
class _FakeStore implements EngineRuleStore {
  _FakeStore({this.onEvent});

  final Map<String, List<Map<String, dynamic>>> rows = {};
  final List<List<Map<String, dynamic>>> saved = [];
  bool failReads = false;
  bool failWrites = false;
  final void Function(String event)? onEvent;

  @override
  Future<List<Map<String, dynamic>>> getEngineRules(String family) async {
    if (failReads) throw Exception('模拟：库打不开');
    onEvent?.call('read');
    return rows[family]?.map(Map<String, dynamic>.from).toList() ?? [];
  }

  @override
  Future<void> saveEngineRules(
    String family,
    List<Map<String, dynamic>> rules,
  ) async {
    if (failWrites) throw Exception('模拟：写入失败');
    onEvent?.call('save');
    saved.add(rules);
    rows[family] = rules.map(Map<String, dynamic>.from).toList();
  }
}
