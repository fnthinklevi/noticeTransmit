import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notice_transmit/models/notification_rule.dart';
import 'package:notice_transmit/services/filter_service.dart';
import 'package:notice_transmit/services/platform_channel.dart';
import 'package:notice_transmit/services/rule_trace.dart';

/// F1 规则测试器追踪引擎的语义锁定测试。
///
/// 追踪引擎镜像原生 `FilterEngine.filter` + `RuleEngine.decide/decideAction`；
/// 本测试锁定「链路各阶段的分支与优先级」不被无意破坏（与双端 golden 51 条互补：
/// golden 锁条件语义，本测试锁链路编排）。
void main() {
  late List<MethodCall> channelCalls;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    // 必须注册通道 mock：此前本文件不注册，save* 里的 invokeMethod 抛
    // 「Binding has not yet been initialized」被生产代码的 try/catch 吞掉，
    // 于是 20 个用例只验了内存态，删掉下发调用或改错参数名都照样全绿。
    channelCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AppChannels.notification, (call) async {
          channelCalls.add(call);
          return true;
        });
  });

  group('save* 真正落盘 + 下发原生（防静默降级）', () {
    test('黑名单：prefs 与 setBlacklistKeywords 都收到同一份列表', () async {
      final filter = FilterService();
      await filter.saveBlacklistKeywords(<String>['广告', 'promo']);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('blacklist_keywords'), '["广告","promo"]');

      final call = channelCalls.firstWhere(
        (c) => c.method == 'setBlacklistKeywords',
      );
      expect((call.arguments as Map)['keywords'], <String>['广告', 'promo']);
    });

    test('应用筛选：prefs 与 setAppFilter 参数一致（mode/packages 两键齐备）', () async {
      final filter = FilterService();
      await filter.saveAppFilter('block', <String>['com.x']);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('app_filter_mode'), 'block');
      final call = channelCalls.firstWhere((c) => c.method == 'setAppFilter');
      final args = call.arguments as Map;
      expect(args['mode'], 'block');
      expect(args['packages'], <String>['com.x']);
    });

    test('白名单关键词下发 setWhitelistKeywords', () async {
      final filter = FilterService();
      await filter.saveWhitelistKeywords(<String>['重要']);
      final call = channelCalls.firstWhere(
        (c) => c.method == 'setWhitelistKeywords',
      );
      expect((call.arguments as Map)['keywords'], <String>['重要']);
    });

    test('通知规则下发 setNotificationRules，且规则 JSON 含 conditions/actions', () async {
      final filter = FilterService();
      await filter.saveNotificationRules([
        NotificationRule.fromMap({
          'id': 'r-persist',
          'name': 'n',
          'description': '',
          'enabled': true,
          'priority': 10,
          'conditions': <Map<String, dynamic>>[
            {'type': 'title_contains', 'value': '验证码', 'logic': 'and'},
          ],
          'actions': <Map<String, dynamic>>[
            {'type': 'push'},
          ],
        }),
      ]);

      final call = channelCalls.firstWhere(
        (c) => c.method == 'setNotificationRules',
      );
      final rules = (call.arguments as Map)['rules'] as List;
      expect(rules, hasLength(1));
      final r = rules.single as Map;
      expect(r['id'], 'r-persist');
      expect(r['conditions'], isNotEmpty);
      expect(r['actions'], isNotEmpty);
    });
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

    test('文件值形状（Double / 数字串 / "true"）与 int/bool 读出同一个结论', () async {
      // 备份或别的工具导出的规则里，params 常常是 `30.0`、`"30"`、`"true"`。
      // 设备侧 optInt/optBoolean 认这些形状，影子链路若不认就会给出与真机不同的追踪结论
      // （旧写法 `is int` 正是如此：窗口退回默认 60、分组退回 false）。
      Future<(int, int, bool)> traceOf(Map<String, dynamic> params) async {
        final filter = await buildFilter(
          rules: [
            rule(
              actions: [
                {'type': 'merge', 'params': params},
              ],
            ),
          ],
        );
        final t = run(filter);
        return (
          t.mergeWindowSeconds ?? -1,
          t.mergeMaxItems,
          t.mergeGroupByTitle,
        );
      }

      final asInt = await traceOf({
        'windowSeconds': 30,
        'maxItems': 5,
        'groupByTitle': true,
      });
      expect(asInt, (30, 5, true));
      expect(
        await traceOf({
          'windowSeconds': 30.0,
          'maxItems': 5.0,
          'groupByTitle': 'true',
        }),
        asInt,
        reason: '同一份规则，影子链路读成另一个数 = 测试器的结论是假的',
      );
      expect(
        await traceOf({
          'windowSeconds': '30',
          'maxItems': '5',
          'groupByTitle': 'TRUE',
        }),
        asInt,
        reason: '数字串也要落回同一个值',
      );
      // 垃圾值仍然按"没配"处理（不许顺手当真）。
      expect(await traceOf({'windowSeconds': 'abc', 'groupByTitle': 1}), (
        60,
        0,
        false,
      ));
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
