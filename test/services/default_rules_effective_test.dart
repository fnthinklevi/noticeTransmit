import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/notification_rule.dart';
import 'package:notice_transmit/services/filter_service.dart';

/// 预制（默认）规则**生效链路**契约测试。
///
/// 背景：`NotificationRule.defaultRules()` 只是「内存里有一套默认规则」。
/// 真正的「默认规则是否生效」取决于三段链路每一段都通：
///
///   1. **落盘**：`FilterService._ensureDefaultRulesActive` 是否把默认规则写进
///      `notification_rules`（否则每次启动都是"内存有、磁盘无"）；
///   2. **下发原生**：`saveNotificationRules` 是否调用 `setNotificationRules`
///      （否则原生 RuleEngine 拿到空规则表，聚合/拦截全部失效）；
///   3. **可决策**：默认规则序列化后的 JSON 喂给引擎，能否真的产出预期决策
///      （聚合规则产出 merge、营销规则产出 silent、夜间规则产出 silent、验证码产出 push）。
///
/// 本文件锁住第 3 段（行为断言）+ 第 1/2 段（静态源码断言），
/// 原生侧同一链路由 RuleEngineTest + MergeFailureContractTest 覆盖。
void main() {
  const mergeBurst = 'merge_burst';
  const marketingBlock = 'marketing_block';
  const nightDnd = 'night_dnd';
  const smsCode = 'sms_code';

  /// 把默认规则序列化成原生 RuleEngine 实际收到的 JSON（与 setNotificationRules 一致）
  String defaultRulesJson() => jsonEncode(
    NotificationRule.defaultRules().map((r) => r.toMap()).toList(),
  );

  group('默认规则生效链（3）可决策：默认规则喂给引擎产出预期动作', () {
    late Map<String, List<NotificationRule>> byId;

    setUp(() {
      byId = {
        for (final r in NotificationRule.defaultRules()) r.id: [r],
      };
    });

    NotificationRule rule(String id) => byId[id]!.first;

    test('merge_burst 命中任意应用 → 聚合决策（ActionType.merge）', () {
      final r = rule(mergeBurst);
      // 引擎应命中（packageName='*' 通配任意应用）
      expect(
        FilterService().evaluateRule(r, {
          'packageName': 'com.any.app',
          'title': '普通通知',
          'content': '正文',
        }),
        true,
        reason: 'merge_burst 条件为 packageName="*"，必须命中任意应用',
      );
      // 动作必须是 merge，且窗口参数必须随规则一起带下去（丢了就退回原生默认 60s）
      expect(r.actions.first.type, ActionType.merge);
      expect(r.actions.first.params['windowSeconds'], 60);
    });

    test('merge_burst 对空包名也命中（进程重建等边界）', () {
      expect(
        FilterService().evaluateRule(rule(mergeBurst), {
          'packageName': '',
          'title': 'x',
          'content': 'y',
        }),
        true,
      );
    });

    test('sms_code 命中"验证码" → push 且优先级最高', () {
      final r = rule(smsCode);
      expect(
        FilterService().evaluateRule(r, {
          'packageName': 'com.tencent.mm',
          'title': '验证码',
          'content': '您的验证码是 1234',
        }),
        true,
      );
      expect(r.actions.first.type, ActionType.push);
      // 优先级必须高于聚合，否则验证码会被聚合吞进窗口
      expect(r.priority, greaterThan(rule(mergeBurst).priority));
    });

    test('marketing_block 命中"优惠" → silent（不推送不记录）', () {
      final r = rule(marketingBlock);
      expect(
        FilterService().evaluateRule(r, {
          'packageName': 'com.shop.app',
          'title': '限时优惠',
          'content': '全场促销抢购',
        }),
        true,
      );
      expect(r.actions.first.type, ActionType.silent);
    });

    test('night_dnd 优先级最高（200），确保跨零点时段规则先于其他规则匹配', () {
      final r = rule(nightDnd);
      for (final other in NotificationRule.defaultRules()) {
        if (other.id == nightDnd) continue;
        expect(
          r.priority,
          greaterThan(other.priority),
          reason: 'night_dnd 必须优先级最高，否则夜间免打扰会被聚合/推送规则抢先命中',
        );
      }
    });

    test('默认规则之间优先级无重复（决定匹配顺序的确定性）', () {
      // ⚠ 只断言「无重复」而**不断言声明顺序降序**：优先级相同时"高者先匹配"的结果
      //   会依赖 JSON 数组顺序，属不确定行为。声明顺序本身无约束（`decide` 会排序）。
      final priorities = NotificationRule.defaultRules()
          .map((r) => r.priority)
          .toList();
      expect(
        priorities.toSet().length,
        priorities.length,
        reason: '优先级重复会让"高者先匹配"的结果依赖 JSON 顺序，不确定',
      );
    });
  });

  group('默认规则序列化 → 原生 RuleEngine 可解析', () {
    test('全量默认规则 JSON 中每条都 enabled 且有非空 id/actions', () {
      final json = defaultRulesJson();
      final parsed = jsonDecode(json) as List;
      expect(parsed, hasLength(4));

      for (final raw in parsed) {
        final m = raw as Map<String, dynamic>;
        expect((m['id'] as String).isNotEmpty, true, reason: 'id 不能为空');
        expect(m['enabled'], true, reason: '${m['id']} 预制规则必须默认开启');
        expect(m['priority'], isA<int>(), reason: '${m['id']} 必须有优先级');
        expect((m['actions'] as List), isNotEmpty, reason: '${m['id']} 必须有动作');
        expect(
          (m['conditions'] as List),
          isNotEmpty,
          reason: '${m['id']} 必须有条件',
        );
      }
    });

    test('merge 动作的 params.windowSeconds 必须能穿过序列化（不能丢字段）', () {
      // 回归：Condition/RuleAction 曾因泛型推断把 params 丢成 Map<dynamic,dynamic>，
      // 用户编辑规则后再落盘，windowSeconds 被静默清空 → 原生退回默认窗口。
      final json = defaultRulesJson();
      final parsed = jsonDecode(json) as List;
      final merge = parsed.firstWhere((r) => r['id'] == mergeBurst) as Map;
      final action = (merge['actions'] as List).first as Map;
      expect(action['type'], 'merge');
      expect(action['params'], isNotNull);
      expect(
        (action['params'] as Map)['windowSeconds'],
        60,
        reason: 'windowSeconds 必须原样穿过序列化，否则聚合窗口静默变成默认值',
      );
    });

    test('merge 规则条件序列化为 package_name/*（与原生 evaluateCondition 契约一致）', () {
      final parsed = jsonDecode(defaultRulesJson()) as List;
      final merge = parsed.firstWhere((r) => r['id'] == mergeBurst) as Map;
      final cond = (merge['conditions'] as List).first as Map;
      // 原生只认 'package_name' 这个字面量，写成 'packageName' 会静默不匹配
      expect(cond['type'], 'package_name');
      expect(cond['value'], '*');
    });
  });

  group('默认规则生效链（1）落盘 +（2）下发原生：静态契约', () {
    late String filterService;
    late String notificationService;

    setUpAll(() {
      filterService = File(
        'lib/services/filter_service.dart',
      ).readAsStringSync();
      notificationService = File(
        'lib/services/notification_service.dart',
      ).readAsStringSync();
    });

    test('saveNotificationRules 必须同时落盘并下发原生（缺一即默认规则不生效）', () {
      final i = filterService.indexOf('Future<void> saveNotificationRules(');
      expect(i >= 0, true, reason: '应存在 saveNotificationRules');
      // ⚠ 窗口必须够大：`prefs.setString(` 与 `invokeMethod(` 都写成**跨行**形式
      //   （字符串键与值分列两行），窗口过小会把两者一起切掉，得出假失败。
      final body = filterService.substring(
        i,
        (i + 2200).clamp(0, filterService.length),
      );
      expect(
        // 跨行写法，故用正则容忍换行与缩进
        RegExp(r"setString\(\s*'notification_rules'").hasMatch(body),
        true,
        reason: '必须落盘到 notification_rules',
      );
      expect(
        body.contains("invokeMethod('setNotificationRules'"),
        true,
        reason: '必须下发原生；只落盘不下发 → 原生 RuleEngine 拿空表，预制规则形同不存在',
      );
    });

    test('_ensureDefaultRulesActive 首次启动走全量落盘分支', () {
      final i = filterService.indexOf('_ensureDefaultRulesActive');
      expect(i >= 0, true);
      final body = filterService.substring(
        i,
        (i + 1600).clamp(0, filterService.length),
      );
      expect(body.contains("getString('notification_rules')"), true);
      expect(
        body.contains('saveNotificationRules(NotificationRule.defaultRules())'),
        true,
        reason: '首次启动（无键）必须全量落盘并下发默认规则',
      );
      expect(
        body.contains('missingDefaults'),
        true,
        reason: '老用户升级必须走补齐分支，仅补缺失 id',
      );
    });

    test('启动路径必须真的调用 _ensureDefaultRulesActive（否则补丁是死代码）', () {
      // ⚠ 计数必须匹配「定义 + 调用」两种形态：定义是
      //   `Future<void> _ensureDefaultRulesActive(SharedPreferences prefs) async {`（参数带类型），
      //   调用是 `await _ensureDefaultRulesActive(prefs);`。
      //   只匹配 `(prefs)` 会漏掉定义处 → 恒得 1 → 假失败。
      final calls = RegExp(
        r'_ensureDefaultRulesActive\(',
      ).allMatches(filterService).length;
      expect(
        calls,
        greaterThanOrEqualTo(2),
        reason: '_ensureDefaultRulesActive 只有定义没有调用 = 死代码，默认规则永不生效',
      );
    });

    test('原生侧 setNotificationRules 必须落到 flutter.notification_rules 并广播配置变更', () {
      final handler = File(
        'android/app/src/main/kotlin/com/fnthink/notice/channels/ConfigChannelHandler.kt',
      ).readAsStringSync();
      expect(handler.contains('"setNotificationRules"'), true);
      final activity = File(
        'android/app/src/main/kotlin/com/fnthink/notice/MainActivity.kt',
      ).readAsStringSync();
      expect(
        activity.contains('flutter.notification_rules'),
        true,
        reason: '原生必须把规则写到 RuleEngine 读取的那个 key',
      );
      expect(
        activity.contains('notifyServiceConfigChanged'),
        true,
        reason: '写规则后必须广播让 Service 刷新 ConfigSnapshot，否则规则要等重启才生效',
      );
    });

    test('原生 RuleEngine 读取的 key 必须与 Flutter 写入的 key 完全一致', () {
      final cm = File(
        'android/app/src/main/kotlin/com/fnthink/notice/ConfigManager.kt',
      ).readAsStringSync();
      // ⚠ 原生不是直接写字符串字面量，而是走 KEY_NOTIFICATION_RULES 常量：
      //   `fun getNotificationRules() { return prefs.getString(KEY_NOTIFICATION_RULES, "") }`
      //   因此必须**两段断言**——① 函数体用常量取值；② 常量值 == Flutter 侧键 + "flutter." 前缀。
      expect(
        RegExp(
          r'fun getNotificationRules\(\)[\s\S]{0,200}?KEY_NOTIFICATION_RULES',
        ).hasMatch(cm),
        true,
        reason: 'getNotificationRules 必须经常量取值',
      );
      expect(
        cm.contains('KEY_NOTIFICATION_RULES = "flutter.notification_rules"'),
        true,
        reason:
            '常量值必须 = Flutter 侧 notification_rules + shared_preferences 的 "flutter." 前缀；'
            '不一致会导致"写进去了但读不到"，默认规则静默失效',
      );
    });

    test('notification_service 不得在启动时用空表覆盖规则（回归防护）', () {
      expect(
        RegExp(
          r"setString\(\s*'notification_rules'\s*,\s*'\[\]'\s*\)",
        ).hasMatch(notificationService),
        false,
        reason: '启动时写空数组会把用户规则表清空',
      );
    });
  });
}
