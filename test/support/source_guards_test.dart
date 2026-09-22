import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// 剥注释工具的行为守卫。
///
/// 本项目的静态源码守卫（读源文件 + 字符串断言）全部依赖 stripComments。
/// 若它退化成「按行内首个 // 截断」，含 `https://` 的字符串会被从中间切断，
/// 被守卫的键集合**静默少项**——守卫照样变绿，保护却没了。
/// 这里把该退化直接钉成失败。
void main() {
  group('stripComments – 引号感知', () {
    test('含 // 的字符串字面量不被截断，行注释仍被剥离', () {
      const src = "const url = 'https://oapi.example.com/robot/send'; // 真正的注释";
      final out = stripComments(src);
      expect(out, contains('https://oapi.example.com/robot/send'));
      expect(out, isNot(contains('真正的注释')));
    });

    test('转义引号不提前闭合字符串', () {
      const src = r"""const a = "x\"//y"; // cut""";
      final out = stripComments(src);
      expect(out, contains(r'x\"//y'));
      expect(out, isNot(contains('cut')));
    });

    test('键集合不因截断而静默少项', () {
      const src = '''
const keys = {
  'webhook': 'https://example.com/a//b',
  'sms': '',
}; // 尾注释
''';
      final out = stripComments(src);
      final keys = RegExp(
        r"'(\w+)':",
      ).allMatches(out).map((m) => m.group(1)).toSet();
      expect(keys, {'webhook', 'sms'});
      // 值同样必须完整：截断版会把 'https://…' 从中间切断，留下未闭合的字符串
      expect(out, contains("'https://example.com/a//b'"));
      expect(out, isNot(contains('尾注释')));
    });

    test('块注释整体剥离', () {
      const src = 'a /* 块\n注释 */ b\n// 行注释\nc';
      final out = stripComments(src);
      expect(out, contains('a '));
      expect(out, contains('b'));
      expect(out, isNot(contains('块')));
      expect(out, isNot(contains('行注释')));
    });
  });

  group('blockAfter – 按大括号配对取块', () {
    test('命中签名自身起点，不误取前一个同名片段', () {
      const src = 'fun a() { x }\nfun b() { if (c) { y }\n  z }\nfun c() {}';
      expect(blockAfter(src, 'fun b()'), 'fun b() { if (c) { y }\n  z }');
    });

    test('未命中时明确抛错而非静默返回空', () {
      expect(() => blockAfter('fun a() {}', 'fun missing('), throwsStateError);
    });
  });
}
