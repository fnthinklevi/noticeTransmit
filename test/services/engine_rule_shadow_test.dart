import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/engine_rule_codec.dart';
import 'package:notice_transmit/services/engine_rule_diff.dart';
import 'package:notice_transmit/services/engine_rule_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/engine_rule_store_fake.dart';
import '../test_setup.dart';

/// T21：并存期的影子求值（比对不发送）。
///
/// 判据分三层，缺任一层都会留下静默腐烂的口子：
/// 1. **纯函数**：两份规则集在什么情况下算不一致（顺序敏感 —— 库里第 i 条就是引擎
///    的第 i 优先级，换了序就是换了判定顺序，即使集合相同）；
/// 2. **记录环**：不一致必须留下证据，且**正常路径不许制造噪声**（否则 20 条环很快
///    被刷满，真出问题时什么都看不见）；
/// 3. **链路不变**：影子层是探针 —— 它自己抛异常时规则的读写必须照常返回，
///    且它记不记都不许改变 load/save 的结论与写入顺序（那才是"只记账不发送"的字面含义）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const at = 1700000000000;
  const family = EngineRuleCodec.familyBattery;

  Map<String, dynamic> rule({
    String id = 'r1',
    String type = 'level_below',
    int value = 20,
    bool enabled = true,
    String title = '',
    String content = '',
  }) => {
    'id': id,
    'type': type,
    'value': value,
    'enabled': enabled,
    'title': title,
    'content': content,
  };

  String mirrorOf(List<Map<String, dynamic>> rules) =>
      EngineRuleCodec.toLegacyJson(rules);

  List<EngineRuleDiff> cmp({
    required List<Map<String, dynamic>> db,
    String? raw,
    List<Map<String, dynamic>>? mirror,
  }) => compareEngineRuleSets(
    family: family,
    db: db,
    mirrorRaw: raw,
    mirror: mirror,
    at: at,
  );

  group('影子比对（纯函数）', () {
    test('两份一致：空差异（正向锚点，别把"没报"当"报不出来"）', () {
      final rules = [rule(id: 'a'), rule(id: 'b', value: 30)];
      final diffs = cmp(
        db: rules,
        raw: mirrorOf(rules),
        mirror: EngineRuleCodec.parseLegacyJson(mirrorOf(rules), family),
      );
      expect(diffs, isEmpty);
      // 同一份输入再比一次仍为空：引擎是确定性函数 ⇒ 输入等价即结论等价。
      expect(
        cmp(
          db: rules,
          raw: mirrorOf(rules),
          mirror: EngineRuleCodec.parseLegacyJson(mirrorOf(rules), family),
        ),
        isEmpty,
      );
    });

    test('两边都没有规则：不算差异', () {
      expect(cmp(db: [], raw: '[]', mirror: const []), isEmpty);
    });

    test('镜像从没写过而库里有规则：mirrorAbsent（原生等于全部规则不认）', () {
      final diffs = cmp(db: [rule()], raw: null);
      expect(diffs.map((d) => d.kind), ['mirrorAbsent']);
      expect(diffs.single.detail, contains('1'));
    });

    test('库是空的而镜像里有规则：extraInMirror（补导入没跑成那种）', () {
      final diffs = cmp(
        db: const [],
        raw: mirrorOf([rule(id: 'ghost')]),
        mirror: [rule(id: 'ghost')],
      );
      expect(diffs.map((d) => d.kind), ['extraInMirror']);
      expect(diffs.single.index, 0);
      expect(diffs.single.detail, contains('ghost'));
    });

    test('镜像存在但读不出规则：mirrorUnparsable（与"没写过"分开）', () {
      final diffs = cmp(db: [rule()], raw: '{"不是数组"');
      expect(diffs.map((d) => d.kind), ['mirrorUnparsable']);
    });

    test('阈值/启停/标题不一致各自点名，且带上两边的值', () {
      final diffs = cmp(
        db: [rule(value: 20, enabled: true, title: '低于20')],
        raw: mirrorOf([rule(value: 80, enabled: false, title: '')]),
        mirror: [rule(value: 80, enabled: false, title: '')],
      );
      expect(diffs.map((d) => d.kind).toSet(), {'value', 'enabled', 'title'});
      expect(
        diffs.firstWhere((d) => d.kind == 'value').detail,
        allOf(contains('20'), contains('80')),
      );
    });

    test('顺序敏感：集合相同但换了序也算差异', () {
      // 引擎一轮只出一条，谁在前谁先被推 ⇒ 顺序不是外观问题。
      final a = [rule(id: 'x'), rule(id: 'y')];
      final b = [rule(id: 'y'), rule(id: 'x')];
      final diffs = cmp(db: a, raw: mirrorOf(b), mirror: b);
      expect(diffs, isNotEmpty);
      expect(diffs.map((d) => d.kind), contains('id'));
      expect(diffs.every((d) => d.index != null), isTrue);
    });

    test('库少一条：missingInMirror 带下标', () {
      final b = [rule(id: 'x'), rule(id: 'y')];
      final diffs = cmp(
        db: [rule(id: 'x')],
        raw: mirrorOf(b),
        mirror: b,
      );
      expect(diffs.map((d) => d.kind), ['extraInMirror']);
      expect(diffs.single.index, 1);
      final back = cmp(
        db: b,
        raw: mirrorOf([rule(id: 'x')]),
        mirror: [rule(id: 'x')],
      );
      expect(back.map((d) => d.kind), ['missingInMirror']);
    });
  });

  group('差异环', () {
    late EngineRuleDiffLog log;
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      log = EngineRuleDiffLog();
    });

    test('没有差异时一个字节都不写（正常路径不许制造噪声）', () async {
      await log.record(const []);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(EngineRuleDiffLog.prefsKey), isNull);
      expect(await log.read(), isEmpty);
    });

    test('有界：只留最近 20 条', () async {
      for (var i = 0; i < 25; i++) {
        await log.record([
          EngineRuleDiff(
            family: family,
            kind: 'value',
            index: i,
            detail: 'd$i',
            at: at + i,
          ),
        ]);
      }
      final kept = await log.read();
      expect(kept, hasLength(EngineRuleDiffLog.maxEntries));
      expect(kept.last.detail, 'd24', reason: '丢的必须是最旧的，否则刚发生的问题被旧记录挤掉了');
    });

    test('环本身坏了：按空处理但不抛', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        EngineRuleDiffLog.prefsKey,
        '[{"family":"battery"}',
      );
      expect(await log.read(), isEmpty);
      // 坏了也还能写：下一次记账覆盖掉坏内容
      await log.record([EngineRuleDiff(family: family, kind: 'x', at: at)]);
      expect(await log.read(), hasLength(1));
    });

    test('toJson/fromJson 往返（含"整集级别"的 null 下标）', () async {
      final one = EngineRuleDiff(
        family: family,
        kind: 'mirrorAbsent',
        detail: '库里有 5 条而原生镜像不存在',
        at: at,
      );
      await log.record([one]);
      final back = await log.read();
      expect(back.single.kind, 'mirrorAbsent');
      expect(back.single.index, isNull);
      expect(back.single.at, at);
      expect(back.single.toString(), contains('mirrorAbsent'));
    });
  });

  group('仓储挂钩：只记账，不改行为', () {
    late MemoryRuleStore store;
    late List<MethodCall> calls0;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      calls0 = [];
      stubNativeChannels(
        onCall: (call) async {
          calls0.add(call);
          return null;
        },
      );
      store = MemoryRuleStore();
    });

    tearDown(clearNativeChannelStubs);

    EngineRuleRepository repo({EngineRuleDiffLog? diffLog}) =>
        EngineRuleRepository(
          family: family,
          prefsKey: 'battery_rules',
          store: store,
          diffLog: diffLog,
        );

    test('镜像落后于库：仍返回库的内容、记一条差异、镜像按 DB 修回（T20 语义不变）', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'battery_rules',
        mirrorOf([rule(id: 'r1', value: 99)]),
      );
      store.rows[family] = [rule(id: 'r1', value: 20)];

      final got = await repo().load();

      expect(got.single['value'], 20, reason: '影子层不许改变读到的规则');
      expect(
        jsonDecode(
          (await SharedPreferences.getInstance()).getString('battery_rules')!,
        ).first['value'],
        20,
        reason: '以 DB 为准修镜像是 T20 定的，T21 不能顺手改掉',
      );
      final diffs = await EngineRuleDiffLog().read();
      expect(diffs.map((d) => d.kind), ['value']);
      expect(diffs.single.family, family);
    });

    test('正常读写不留任何差异记录（环被正常噪声刷满 = 真出事时看不见）', () async {
      final r = repo();
      await r.save([rule(id: 'a'), rule(id: 'b', value: 30)]);
      await r.load();
      await r.save([rule(id: 'a')]);
      await r.load();
      expect(await EngineRuleDiffLog().read(), isEmpty);
    });

    test('库里为空而旧键有规则：先记下 extraInMirror，再补导入', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('battery_rules', mirrorOf([rule(id: 'legacy')]));

      final got = await repo().load();

      expect(got.map((r) => r['id']), ['legacy']);
      expect(
        store.rows[family],
        hasLength(1),
        reason: '补导入本身是 T20 的行为，T21 只负责把这件事记下来',
      );
      expect(
        (await EngineRuleDiffLog().read()).map((d) => d.kind),
        contains('extraInMirror'),
      );
    });

    test('影子层自己抛异常：规则照常返回，异常不外泄', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'battery_rules',
        mirrorOf([rule(id: 'r1', value: 99)]),
      );
      store.rows[family] = [rule(id: 'r1', value: 20)];

      final got = await repo(diffLog: _ExplodingLog()).load();

      expect(got.single['value'], 20);
      expect(calls0.map((c) => c.method), contains('refreshEngineRules'));
    });
  });
}

class _ExplodingLog extends EngineRuleDiffLog {
  @override
  Future<int> record(List<EngineRuleDiff> diffs) =>
      throw StateError('模拟：影子层自己坏了');
}
