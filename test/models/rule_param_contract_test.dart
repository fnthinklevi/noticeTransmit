import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/notification_rule.dart';

import '../support/source_guards.dart';

/// T23-B：规则里的"文件值"两侧必须取到同一个数。
///
/// 出问题的形状：设备侧读的是 JSON（`JSONObject.optInt/optBoolean`，任何 `Number` 截断取整、
/// 数字串也认），而 Dart 侧原先用 `v is int` 判 —— 于是 `windowSeconds: 30.0`（别的工具导出的
/// 备份、手改的 JSON）在**设备上生效**、在**界面上等于没配**。最坏的一条不是显示错：
/// 规则编辑页 `initState` 按 `is int` 取不到值 ⇒ 输入框是空的 ⇒ 用户打开看一眼并保存，
/// 原本生效的延迟/聚合配置被静默抹掉。
///
/// 本文件钉三件事：① 取值口径（一处函数，形状表逐条锁）；② 消费侧**必须**走它（形状守卫）；
/// ③ 原生新加一个数值/布尔键时，Dart 侧没有对应镜像就读不到 ⇒ 跨语言键守卫判红。
void main() {
  final root = projectRoot();
  String read(String rel) =>
      File('$root/$rel').readAsStringSync().replaceAll('\r\n', '\n');

  group('取值口径：与设备侧 optInt/optBoolean 同一条', () {
    test('整数：Number 截断取整、数字串也认、垃圾值按"没配"（null）', () {
      expect(ruleParamInt(5), 5);
      // 截断而不是四舍五入：`Number.intValue()` 就是截断，round 会让 100.7 两侧不同。
      expect(ruleParamInt(5.0), 5, reason: 'Double 形状必须认（旧写法 is int 直接丢）');
      expect(ruleParamInt(5.999), 5, reason: '截断，不是 6');
      expect(ruleParamInt(-3.5), -3, reason: '向零截断');
      expect(ruleParamInt('5'), 5);
      expect(ruleParamInt(' 5.7 '), 5, reason: '空白与实数字符串都要能落回整数');
      expect(ruleParamInt(0), 0, reason: '0 是有效值，不能和"没配"混为一谈');
      expect(ruleParamInt('abc'), isNull);
      expect(ruleParamInt(''), isNull);
      expect(ruleParamInt(null), isNull);
      expect(ruleParamInt(true), isNull, reason: '布尔不当数用');
    });

    test('布尔：只认 Boolean 与 "true"/"false"，数字不当真', () {
      expect(ruleParamBool(true), isTrue);
      expect(ruleParamBool(false), isFalse);
      expect(ruleParamBool('true'), isTrue);
      expect(ruleParamBool(' FALSE '), isFalse, reason: '与 org.json 的大小写无关一致');
      expect(ruleParamBool(1), isFalse, reason: '1 不是布尔（两侧都不 coerce 数字）');
      expect(ruleParamBool(null, fallback: true), isTrue, reason: '缺省归调用方');
      expect(ruleParamBool('maybe', fallback: true), isTrue);
    });

    test('规则级 priority 走同一条口径（截断，不 round）', () {
      final fromInt = NotificationRule.fromMap({'priority': 100.7});
      final fromString = NotificationRule.fromMap({'priority': '150'});
      expect(fromInt.priority, 100, reason: '原生 optInt 是截断，round 会读出 101');
      expect(fromString.priority, 150);
      expect(NotificationRule.fromMap({}).priority, 0);
      // 反证锚点：形状守卫不能只对着"本来就是 int"的值测（那等于没测）。
      expect(fromInt.priority, isNot(101));
    });
  });

  group('消费侧必须走这一处（形状守卫）', () {
    const consumers = [
      'lib/pages/rule_edit_widgets.dart',
      'lib/pages/rule_edit_page.dart',
      'lib/services/rule_trace.dart',
    ];
    const paramKeys = ['delaySeconds', 'windowSeconds', 'maxItems'];

    test('三个消费点里 params 的数值取读一律经 ruleParamInt/ruleParamBool', () {
      for (final rel in consumers) {
        final src = stripComments(read(rel));
        // 反向锚点：文件在、且有 params 读取，否则下面的判据是空转。
        expect(
          RegExp(r"params\['").hasMatch(src),
          isTrue,
          reason: '$rel 里已经没有 params 读取了 ⇒ 本守卫需要重新指向',
        );
        for (final key in paramKeys) {
          // 数"读取处"（排除 `params['k'] = v` 这种赋值左侧），再数"包在统一口径里"的处数。
          // ⚠ 不能用"同一行内有没有 is int"来判：旧写法是
          //   `final w = params['w']; if (w is int …)` 跨两行，行内匹配抓不到（反证测过）。
          final reads = RegExp(
            "params\\['$key'\\](?!\\s*=[^=])",
          ).allMatches(src).length;
          final wrapped = RegExp(
            "ruleParam(Int|Bool)\\([^)]*params\\['$key'\\]",
          ).allMatches(src).length;
          expect(
            wrapped,
            equals(reads),
            reason:
                '$rel 读 $key 有 $reads 处、只有 $wrapped 处走 ruleParamInt/ruleParamBool ⇒ '
                '剩下那处在 Double/数字串上会与设备读数不同',
          );
        }
      }
    });

    test('groupByTitle 不许再用 `== true` 直接比（字符串形状两侧读法要一致）', () {
      for (final rel in consumers) {
        final src = stripComments(read(rel));
        expect(
          RegExp(r"params\['groupByTitle'\]\s*==\s*true").hasMatch(src),
          isFalse,
          reason: '$rel 用 `== true` 判分组开关 ⇒ "true" 这类文件值在界面上是关',
        );
      }
    });
  });

  group('跨语言：原生新读一个键，Dart 侧必须跟着读得到', () {
    /// 原生 `RuleEngine` 用 optInt/optBoolean 读的键（去掉注释后扫）。
    /// 这一份清单是"设备会按这些键改变推送行为"的事实，Dart 侧取不到就等于两侧不同。
    List<String> nativeCoercedKeys() {
      final kt = stripComments(
        read('android/app/src/main/kotlin/com/fnthink/notice/RuleEngine.kt'),
      );
      return RegExp(
        r'opt(?:Int|Boolean|Long|Double)\(\s*"([A-Za-z][A-Za-z0-9_]*)"',
      ).allMatches(kt).map((m) => m.group(1)!).toSet().toList()..sort();
    }

    test('原生确实只读这几个键（清单变了要显式复核，不许静默扩容）', () {
      expect(nativeCoercedKeys(), [
        'delaySeconds',
        'enabled',
        'groupByTitle',
        'maxItems',
        'priority',
        'windowSeconds',
      ], reason: 'RuleEngine 强转读的键集合变了 ⇒ 下面的镜像覆盖判据要重新看');
    });

    test('除已登记的例外，每个键在 Dart 侧都经统一口径读', () {
      // 例外是**刻意的**：rule 级 enabled 的 `0` 若按 optBoolean 退回默认值，等于
      // 把用户关掉的规则读成开着 —— 失败方向不可接受，宁可留着按值判。
      const carveOuts = {
        'enabled': "map['enabled'] != false && map['enabled'] != 0",
      };
      final dartSources = [
        'lib/pages/rule_edit_widgets.dart',
        'lib/pages/rule_edit_page.dart',
        'lib/services/rule_trace.dart',
        'lib/models/notification_rule.dart',
      ].map((rel) => stripComments(read(rel))).join('\n');
      for (final key in nativeCoercedKeys()) {
        if (carveOuts.containsKey(key)) {
          expect(
            dartSources,
            contains(carveOuts[key]!),
            reason: '例外 $key 的形状被改了 ⇒ 例外本身要重新登记，不能悄悄换实现',
          );
          continue;
        }
        expect(
          RegExp("ruleParam(Int|Bool)\\([^)]*'$key'").hasMatch(dartSources) ||
              RegExp('ruleParam(Int|Bool)\\(.*"$key"').hasMatch(dartSources),
          isTrue,
          reason:
              '原生按 opt* 读 $key 改变推送行为，而 Dart 侧没有同一口径的取法 ⇒ '
              '界面上看不到、也改不动那条规则实际生效的值',
        );
      }
    });
  });

  group('守卫自己', () {
    test('反证：把 Double/数字串改回 is int 判法，形状守卫必须判假', () {
      const oldShape = r'''
void f(Map<String, dynamic> params) {
  final w = params['windowSeconds'];
  if (w is int && w > 0) { print(w); }
}
''';
      // 计数判据要能抓住这个**跨两行**的旧形状：读取 1 处、包装 0 处 ⇒ 不等 ⇒ 红。
      final reads = RegExp(
        r"params\['windowSeconds'\](?!\s*=[^=])",
      ).allMatches(oldShape).length;
      final wrapped = RegExp(
        r"ruleParam(Int|Bool)\([^)]*params\['windowSeconds'\]",
      ).allMatches(oldShape).length;
      expect(oldShape.contains('params'), isTrue);
      expect([reads, wrapped], [1, 0], reason: '旧形状没被数成"有读取、无包装" ⇒ 判据抓不到它');
      expect(wrapped == reads, isFalse);
      // 赋值左侧不该被算成读取（否则新写的保存路径会假红）。
      expect(
        RegExp(
          r"params\['windowSeconds'\](?!\s*=[^=])",
        ).hasMatch("  params['windowSeconds'] = 30;\n"),
        isFalse,
      );
      const oldGroup = "  final g = params['groupByTitle'] == true;\n";
      expect(
        RegExp(r"params\['groupByTitle'\]\s*==\s*true").hasMatch(oldGroup),
        isTrue,
      );
      // 口径函数自己：round 与 trunc 的区别必须在表里显式锁住（否则改回 round 无人发现）。
      expect(ruleParamInt(100.7), 100);
      expect((100.7).round(), 101);
    });
  });
}
