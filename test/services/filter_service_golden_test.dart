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
  // ⚠ fixture 读取包在 try 里：写在 `main()` 顶层时，文件改名或 `cases` 键漂移会抛在测试体之外
  //   ⇒ 整个文件加载失败，CI 里表现为"这个文件没有用例"而不是红（本仓库撞过三次，见 base.md（75））。
  Object? fixtureError;
  List<Map<String, dynamic>> cases = const [];
  try {
    final fixture =
        jsonDecode(
              File('test/fixtures/rule_engine_golden.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();
  } catch (e) {
    fixtureError = e;
  }

  test('黄金 fixture 可读且用例数未漂移', () {
    if (fixtureError != null) throw fixtureError;
    // 用例数=0 时下面的 for 一枚用例都不会生成，"全绿"其实等于没跑 —— 这条是那个空洞的正面锚点。
    expect(
      cases,
      hasLength(51),
      reason:
          '用例数变化本身不是风险，但未经确认的变化要让人停下来：'
          '增删用例必须同时改 test/fixtures/ 与 android/app/src/test/resources/ 两份副本'
          '（一致性由 RuleEngineTest 逐字节比对钉住），再改这个期望值。',
    );
  });

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
