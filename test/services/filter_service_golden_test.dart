import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/notification_rule.dart';
import 'package:notice_transmit/services/filter_service.dart';

/// 双端规则引擎黄金用例（Flutter 侧）。
///
/// fixture 与 android/app/src/test/resources/rule_engine_golden.json 为同步副本，
/// 由 RuleEngineTest 在原生侧消费同一批用例，保证同一 rule+输入 双端匹配结果一致。
/// 修改用例必须同步两份 fixture。
void main() {
  final fixture =
      jsonDecode(
            File('test/fixtures/rule_engine_golden.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();

  group('规则引擎黄金用例（与原生 RuleEngine 对齐）', () {
    for (final c in cases) {
      test(c['name'] as String, () {
        final rule = NotificationRule.fromMap(
          Map<String, dynamic>.from(c['rule'] as Map),
        );
        final notification = Map<String, dynamic>.from(
          c['notification'] as Map,
        );
        final result = FilterService().evaluateRule(rule, notification);
        expect(result, c['expected'], reason: 'case: ${c['name']}');
      });
    }
  });

  group('normalizeForMatch（与原生 FilterEngine.normalize 对齐）', () {
    test('全角字母数字转半角', () {
      expect(FilterService.normalizeForMatch('ＡＢＣ１２３'), 'abc123');
    });
    test('全角空格转半角空格', () {
      expect(FilterService.normalizeForMatch('ＡＢＣ　ＤＥＦ'), 'abc def');
    });
    test('全角标点转半角标点', () {
      expect(FilterService.normalizeForMatch('Ｈｅｌｌｏ！'), 'hello!');
    });
    test('连续空白折叠为单空格', () {
      expect(FilterService.normalizeForMatch('  a \t b　　c  '), 'a b c');
    });
    test('空串原样返回', () {
      expect(FilterService.normalizeForMatch(''), '');
    });
  });
}
