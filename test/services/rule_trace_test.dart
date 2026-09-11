import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notice_transmit/models/notification_rule.dart';
import 'package:notice_transmit/services/filter_service.dart';
import 'package:notice_transmit/services/rule_trace.dart';

/// F1 规则测试器追踪引擎的语义锁定测试。
///
/// 追踪引擎镜像原生 `FilterEngine.filter` + `RuleEngine.decide/decideAction`；
/// 本测试锁定「链路各阶段的分支与优先级」不被无意破坏（与双端 golden 51 条互补：
/// golden 锁条件语义，本测试锁链路编排）。
void main() {
  setUp(() {
    // save* 方法会写 SharedPreferences（mock 即可）；原生通道调用在 save* 内
    // 已 try/catch 包裹，缺失 mock 时静默降级，不影响内存态。
    SharedPreferences.setMockInitialValues({});
  });

  /// 构造带配置的 FilterService
  Future<FilterService> buildFilter({
    String mode = 'allow',
    List<String> packages = const [],
    List<String> blacklist = const [],
    List<String> whitelist = const [],
    List<Map<String, dynamic>> rules = const [],
  }) async {
    final filter = FilterService();
    await filter.saveAppFilter(mode, packages);
    await filter.saveBlacklistKeywords(blacklist);
    await filter.saveWhitelistKeywords(whitelist);
    if (rules.isNotEmpty) {
      await filter.saveNotificationRules(
        rules.map(NotificationRule.fromMap).toList(),
      );
    }
    return filter;
  }

  Map<String, dynamic> rule({
    String id = 'r1',
    String name = '规则',
    bool enabled = true,
    int priority = 10,
    String conditionType = 'package_name',
    String conditionValue = '*',
    List<Map<String, dynamic>> actions = const [
      {'type': 'push', 'params': <String, dynamic>{}},
    ],
    List<String> excludedPackages = const [],
  }) => {
    'id': id,
    'name': name,
    'enabled': enabled,
    'priority': priority,
    'conditions': [
      {'type': conditionType, 'value': conditionValue, 'logic': 'and'},
    ],
    'actions': actions,
    'excludedPackages': excludedPackages,
  };

  RuleTraceResult run(
    FilterService filter, {
    String packageName = 'com.demo.app',
    String title = '标题',
    String content = '内容',
    int priority = 1,
    String sourceType = 'notification',
  }) => RuleTracer.trace(
    filter,
    packageName: packageName,
    title: title,
    content: content,
    notifyPriority: priority,
    sourceType: sourceType,
  );

  group('① 过滤阶段（镜像 FilterEngine.filter）', () {
    test('黑名单关键词优先于白名单关键词（同时命中仍拦截）', () async {
      final filter = await buildFilter(blacklist: ['广告'], whitelist: ['广告']);
      final r = run(filter, content: '这是一条广告');
      expect(r.allowed, isFalse);
      expect(r.filterSource, TraceFilterSource.blacklist);
      expect(r.filterKeyword, '广告');
    });

    test('白名单关键词命中 → 放行且无视应用过滤（allow 模式未选中该应用）', () async {
      final filter = await buildFilter(
        mode: 'allow',
        packages: ['com.other.app'],
        whitelist: ['验证码'],
      );
      final r = run(filter, content: '验证码 123456');
      expect(r.allowed, isTrue);
      expect(r.filterSource, TraceFilterSource.whitelist);
    });

    test('allow 模式：列表非空且未包含该应用 → 应用过滤拦截', () async {
      final filter = await buildFilter(
        mode: 'allow',
        packages: ['com.other.app'],
      );
      final r = run(filter, packageName: 'com.demo.app');
      expect(r.allowed, isFalse);
      expect(r.filterSource, TraceFilterSource.appFilter);
    });

    test('allow 模式：列表为空 → 放行（全部应用）', () async {
      final filter = await buildFilter(mode: 'allow', packages: []);
      final r = run(filter);
      expect(r.allowed, isTrue);
      expect(r.filterSource, TraceFilterSource.defaultPass);
    });

    test('block 模式：列表包含该应用 → 拦截；不在列表 → 放行', () async {
      final blocked = await buildFilter(
        mode: 'block',
        packages: ['com.demo.app'],
      );
      expect(run(blocked).allowed, isFalse);
      expect(run(blocked).filterSource, TraceFilterSource.appFilter);

      final passed = await buildFilter(mode: 'block', packages: ['com.x']);
      expect(run(passed).allowed, isTrue);
    });

    test('sms 来源不走应用过滤（与原生一致）', () async {
      final filter = await buildFilter(
        mode: 'allow',
        packages: ['com.other.app'],
      );
      final r = run(filter, sourceType: 'sms');
      expect(r.allowed, isTrue);
      expect(r.filterSource, TraceFilterSource.defaultPass);
    });

    test('re: 前缀正则关键词（黑名单匹配 6 位连续数字）', () async {
      // 注意：匹配目标是「标题 内容 副文本」合并串（与原生一致），
      // 因此正则不做 ^$ 锚定（锚定在合并串上永不命中）
      final filter = await buildFilter(blacklist: [r're:\d{6}']);
      expect(run(filter, content: '123456').allowed, isFalse);
      expect(run(filter, content: '12ab56').allowed, isTrue);
    });

    test('过滤拦截时不做规则评估（ruleEntries 为空）', () async {
      final filter = await buildFilter(
        mode: 'allow',
        packages: ['com.other.app'],
        rules: [rule()],
      );
      final r = run(filter);
      expect(r.allowed, isFalse);
      expect(r.ruleEntries, isEmpty);
      expect(r.hitRule, isNull);
    });
  });

  group('② 规则阶段（镜像 RuleEngine.decide）', () {
    test('按优先级降序命中第一条即停止', () async {
      final filter = await buildFilter(
        rules: [
          rule(id: 'low', name: '低优先', priority: 10),
          rule(id: 'high', name: '高优先', priority: 200),
          rule(id: 'never', name: '不该评估', priority: 1),
        ],
      );
      final r = run(filter);
      expect(r.hitRule?.id, 'high');
      // 降序后：high(hit 停止)，后续规则不再评估
      expect(r.ruleEntries.map((e) => e.rule.id).toList(), ['high']);
    });

    test('禁用规则被跳过（标记 disabled）且不参与命中', () async {
      final filter = await buildFilter(
        rules: [
          rule(id: 'off', enabled: false, priority: 500),
          rule(id: 'on', priority: 10),
        ],
      );
      final r = run(filter);
      expect(r.ruleEntries.first.mark, TraceRuleMark.disabled);
      expect(r.hitRule?.id, 'on');
    });

    test('excludedPackages 命中的规则被跳过（标记 excluded）', () async {
      final filter = await buildFilter(
        rules: [
          rule(id: 'excl', priority: 500, excludedPackages: ['com.demo.app']),
          rule(id: 'ok', priority: 10),
        ],
      );
      final r = run(filter);
      expect(r.ruleEntries.first.mark, TraceRuleMark.excluded);
      expect(r.hitRule?.id, 'ok');
    });

    test('未命中规则 → 默认立即推送', () async {
      final filter = await buildFilter(
        rules: [
          rule(
            id: 'nomatch',
            conditionType: 'content_contains',
            conditionValue: '不存在的词',
          ),
        ],
      );
      final r = run(filter);
      expect(r.hitRule, isNull);
      expect(r.ruleEntries.single.mark, TraceRuleMark.missed);
      expect(r.action, TraceActionKind.push);
    });

    test('条件真实参与评估（title_contains 命中）', () async {
      final filter = await buildFilter(
        rules: [
          rule(id: 't', conditionType: 'title_contains', conditionValue: '银行'),
        ],
      );
      expect(run(filter, title: '招商银行').hitRule?.id, 't');
      expect(run(filter, title: '其他').hitRule, isNull);
    });
  });

  group('③ 动作阶段（镜像 RuleEngine.decideAction）', () {
    test('silent 短路：同规则含 merge 也判静默', () async {
      final filter = await buildFilter(
        rules: [
          rule(
            actions: [
              {
                'type': 'merge',
                'params': {'windowSeconds': 30},
              },
              {'type': 'silent', 'params': <String, dynamic>{}},
            ],
          ),
        ],
      );
      expect(run(filter).action, TraceActionKind.silent);
    });

    test('delay 优先于 merge（与原生裁诀一致）', () async {
      final filter = await buildFilter(
        rules: [
          rule(
            actions: [
              {
                'type': 'merge',
                'params': {'windowSeconds': 30},
              },
              {
                'type': 'delay',
                'params': {'delaySeconds': 120},
              },
            ],
          ),
        ],
      );
      final r = run(filter);
      expect(r.action, TraceActionKind.delay);
      expect(r.delayFireAtMs, isNotNull);
    });

    test('merge 默认窗口 60 秒；windowSeconds=3 被钳制到 5 秒', () async {
      final def = await buildFilter(
        rules: [
          rule(
            actions: [
              {'type': 'merge', 'params': <String, dynamic>{}},
            ],
          ),
        ],
      );
      expect(run(def).mergeWindowSeconds, 60);

      final clamped = await buildFilter(
        rules: [
          rule(
            actions: [
              {
                'type': 'merge',
                'params': {'windowSeconds': 3},
              },
            ],
          ),
        ],
      );
      expect(run(clamped).mergeWindowSeconds, 5);
    });

    test('F3：maxItems 与 groupByTitle 被解析并透出（镜像原生 params）', () async {
      final filter = await buildFilter(
        rules: [
          rule(
            actions: [
              {
                'type': 'merge',
                'params': {
                  'windowSeconds': 30,
                  'maxItems': 5,
                  'groupByTitle': true,
                },
              },
            ],
          ),
        ],
      );
      final r = run(filter);
      expect(r.action, TraceActionKind.merge);
      expect(r.mergeWindowSeconds, 30);
      expect(r.mergeMaxItems, 5);
      expect(r.mergeGroupByTitle, isTrue);
    });

    test('F3：maxItems=0/负数 视为关闭，groupByTitle 缺失 视为按应用聚合', () async {
      final filter = await buildFilter(
        rules: [
          rule(
            actions: [
              {
                'type': 'merge',
                'params': {'maxItems': 0},
              },
            ],
          ),
        ],
      );
      final r = run(filter);
      expect(r.mergeMaxItems, 0);
      expect(r.mergeGroupByTitle, isFalse);
      expect(r.mergeWindowSeconds, 60); // 未配置窗口 → 默认 60 秒
    });

    test('record → 仅记录；push → 直推', () async {
      final record = await buildFilter(
        rules: [
          rule(
            actions: [
              {'type': 'record', 'params': <String, dynamic>{}},
            ],
          ),
        ],
      );
      expect(run(record).action, TraceActionKind.record);

      final push = await buildFilter(rules: [rule()]);
      expect(run(push).action, TraceActionKind.push);
    });
  });
}
