import 'dart:io';

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

  group('stripXmlComments', () {
    test('跨行注释整体剥离，标签本体保留', () {
      const src =
          '<a>1<!-- 说明'
          '\n'
          '第二行 -->2</a>';
      final out = stripXmlComments(src);
      expect(out, '<a>12</a>');
    });

    test('注释里的组件名不得污染断言（守卫存在的前提）', () {
      const src = '<activity android:name=".Real"/><!-- .Ghost -->';
      final out = stripXmlComments(src);
      expect(out.contains('.Ghost'), isFalse);
      expect(out.contains('.Real'), isTrue);
    });

    test('未闭合注释按截断处理，不静默保留原文', () {
      const src = '<a>1<!-- 未闭合';
      expect(stripXmlComments(src), '<a>1');
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

  group('librarySource – 把整个 library 拼起来', () {
    // 为什么需要它：R3 那类拆分把实现从 main_page.dart 搬进它的 part 文件，
    // 而"读一个文件 + 断言里面没有 X"的负向守卫**从拆分那天起就瞎了**
    // （把 X 写进 part 照样绿）。T65 盘点时发现，见 base.md 116。
    final root = projectRoot();

    test('确实读到 part 里的代码（探针：只存在于 part 的标记）', () {
      final entry = File('$root/lib/pages/main_page.dart').readAsStringSync();
      final whole = librarySource(root, 'lib/pages/main_page.dart');
      expect(
        whole.length,
        greaterThan(entry.length),
        reason: '拼完不比单文件长 ⇒ part 根本没被读进来',
      );
      expect(entry, isNot(contains('ChannelRoleGuide.decide(')));
      expect(
        whole,
        contains('ChannelRoleGuide.decide('),
        reason: 'librarySource 没覆盖 part ⇒ 负向断言会把缺陷读成正常',
      );
    });

    test('没有 part 的文件原样返回（不误伤）', () {
      const rel = 'lib/services/active_channels.dart';
      expect(librarySource(root, rel), File('$root/$rel').readAsStringSync());
    });

    test('声明了不存在的 part ⇒ 抛，而不是静默少读一个文件', () {
      final tmp = Directory.systemTemp.createTempSync('nt-library-source-');
      try {
        File(
          '${tmp.path}/entry.dart',
        ).writeAsStringSync("part 'missing.dart';\n");
        expect(() => librarySource(tmp.path, 'entry.dart'), throwsStateError);
      } finally {
        tmp.deleteSync(recursive: true);
      }
    });
  });
}
