import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T186 片1 的形状守卫：「本机认不出的条件类型」这一档，**判据只许有一条路**。
///
/// 这一族编译器看不见的三种塌法：
///  ① 求值层给 unknown 补一段"那就按标题比吧"⇒ 与原生 `RuleEngine` 的 `else -> false` 分叉，
///     影子求值与真机各自转发不同的东西（最难查的那种不一致）；
///  ② 选择器改回 `ConditionType.values` ⇒ 界面上多出一档"不认得的条件类型"可以点，
///     用户配出一条本机永远不匹配的规则；
///  ③ 写回时又抄一份 `type.value` ⇒ 那条条件被改写成规范串（或空串），用户的存量规则变了形状。
void main() {
  String stripComments(String src) =>
      src.split('\n').map((l) => l.split('//').first).join('\n');

  int countIn(String src, String needle) => src.split(needle).length - 1;

  final filterSrc = stripComments(
    File('lib/services/filter_service.dart').readAsStringSync(),
  );
  final modelSrc = stripComments(
    File('lib/models/notification_rule.dart').readAsStringSync(),
  );
  final pickerSrc = stripComments(
    File('lib/pages/rule_edit_widgets.dart').readAsStringSync(),
  );
  final zhArb = File('lib/l10n/arb/app_zh.arb').readAsStringSync();
  final enArb = File('lib/l10n/arb/app_en.arb').readAsStringSync();

  test('① 求值层对 unknown 只有「判不匹配」一句，不许比标题、内容或包名', () {
    const label = 'case ConditionType.unknown:';
    final arm = filterSrc.indexOf(label);
    expect(arm, greaterThan(-1), reason: 'unknown 这一臂没了 ⇒ 本条在测空气');
    final body = filterSrc.substring(
      arm + label.length,
      filterSrc.indexOf('break;', arm),
    );
    expect(
      body.trim(),
      'conditionMatch = false;',
      reason:
          '这一臂除了"不匹配"不许有第二句判据：任何"拿 value 去比点什么"的形状，'
          '都是把"不认识"说成"我懂"，而原生侧对同一串判 false ⇒ 两端分叉。',
    );
  });

  test('② 两枚条件弹层共用一个装配点，且那份可选项里不是整份枚举', () {
    expect(
      countIn(pickerSrc, 'options: _conditionTypeOptions(l10n)'),
      2,
      reason: '新增/编辑两枚弹层各一处；少一处就是某一枚自己拼了一份选项',
    );
    expect(
      countIn(pickerSrc, 'selectableConditionTypes'),
      1,
      reason: '可选项名单只在装配点里读一次；多一处就是第二个抄本',
    );
    expect(
      countIn(pickerSrc, 'ConditionType.values'),
      0,
      reason: '选择器里出现整份枚举 ⇒ unknown 变成一档可以点的条件',
    );
  });

  test('③ 认不出的串只由 fromValue 的 default 一处产出，且不猜成任何认得的类型', () {
    final entry = modelSrc.indexOf(
      'static ConditionType fromValue(String value)',
    );
    expect(entry, greaterThan(-1), reason: 'fromValue 入口没了 ⇒ 本条在测空气');
    final def = modelSrc.indexOf('default:', entry);
    expect(def, greaterThan(-1));
    final ret = modelSrc.indexOf('return', def);
    expect(
      modelSrc.substring(ret, ret + 40),
      contains('ConditionType.unknown'),
      reason: 'default 分支改猜某个认得的类型 ⇒ 降级会改变匹配结果（原生侧对同一串判 false）',
    );
  });

  test('④ Condition 写回只用 wireType 一处，不再抄 type.value', () {
    // 限定到 Condition 那一块：同一个文件里 RuleAction 也有 `type` 字段，
    // 整文件 contains 会把那处合法写法当成违规（本仓撞过同族的反向形状）。
    final start = modelSrc.indexOf('class Condition {');
    final end = modelSrc.indexOf('enum ActionType', start);
    expect(start, greaterThan(-1));
    expect(end, greaterThan(start), reason: '块端点没取到 ⇒ 这条断言量的可能是半截类');
    final block = modelSrc.substring(start, end);
    expect(
      block.contains('factory Condition.fromMap'),
      isTrue,
      reason: '块里连 fromMap 都没有 ⇒ 提取跑偏，下面的计数不算数',
    );
    expect(countIn(block, "'type': wireType"), 1);
    expect(
      block.contains("'type': type.value"),
      isFalse,
      reason: '又一处落笔形状：认不出的类型会被写成规范串或空串 ⇒ 替用户改了他的规则',
    );
  });

  test('⑤ 这一档的两句话中英都有（否则切到英文就断言不了）', () {
    for (final arb in [zhArb, enArb]) {
      expect(countIn(arb, '"condUnknown"'), 1);
      expect(countIn(arb, '"hintUnknown"'), 1);
    }
  });
}
