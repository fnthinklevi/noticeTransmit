import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T148 片13：历史页那 13 枚筛选芯片的形状只有一个作者（公共件 `FnthinkChoiceChip`）。
///
/// ## 为什么留一枚"只做转发的装配点"而不是逐处展开
/// 这一页有 13 枚，展开会把同一件事写在 13 个位置 —— 而"这一族的字号/圆角/描边只有一个作者"
/// 正是 T100 立起来的那条判据。所以 `_filterChip` 留着，但**函数体只许是一次转发**：
/// 壳（`GestureDetector`／`Container`／`BoxDecoration`）一回到那枚方法里，13 枚就同时变回私有形状，
/// 而屏幕上没人看得出来（公共件与自搭壳的差别只有底色那几像素）。
///
/// ## ⚠ 两把尺的口径（都是"形状"而不是"写法"）
/// - keyName 抓的是**整段调用**里的 `keyName: '<串>'`。命名实参在 Dart 里必须排在位置实参之后 ⇒
///   13 处里 4 处的 keyName 在第四行、9 处在第一行；把尺写成"紧跟在 `_filterChip(` 之后"会漏掉那 4 处，
///   而那 4 处恰好是闸门与页面级用例定位用的方向档。
/// - 读源码一律剥注释（`stripComments`）：注释里写的 `GestureDetector` 不是代码里的。
void main() {
  final root = projectRoot();

  test('① 那枚装配点的函数体只许是一次转发（自搭壳一律红）', () {
    final body = chipBody(
      stripComments(librarySource(root, 'lib/pages/history_page.dart')),
    );
    for (final shell in [
      'GestureDetector',
      'Container',
      'BoxDecoration',
      'Border.all',
    ]) {
      expect(
        body.contains(shell),
        isFalse,
        reason:
            '函数体里出现 $shell ⇒ 这一页 13 枚芯片同时变回私有形状，'
            '而公共件与它只差底色那几像素（屏幕上没人看得见这次退化）',
      );
    }
    expect(body.contains('FnthinkChoiceChip('), isTrue);
  });

  test('② 13 枚调用点各有唯一抓手，一枚不多一枚不少', () {
    final keys = chipKeys(
      stripComments(librarySource(root, 'lib/pages/history_page.dart')),
    );
    expect(
      keys,
      hasLength(13),
      reason:
          '筛选芯片应当是 13 枚（时间段 6 + 送达状态 3 + 方向 4）；'
          '少一枚通常是那枚的 keyName 被摘掉了 ⇒ 测试与闸门只能按文本点，'
          '而这一页「转发」两个字会出现三次',
    );
  });

  test('③ 这 13 枚的 keyName 互不重复（共用一枚等于按 key 点中第一个）', () {
    final keys = chipKeys(
      stripComments(librarySource(root, 'lib/pages/history_page.dart')),
    );
    expect(
      keys.toSet(),
      hasLength(13),
      reason: '两枚共用一个 keyName ⇒ 按 key 点会点中第一个，"筛不出东西"被读成数据问题',
    );
  });

  test('④ 方向那四枚的 key 字符串不许漂（闸门与两张页面级用例按它定位）', () {
    final keys = chipKeys(
      stripComments(librarySource(root, 'lib/pages/history_page.dart')),
    );
    for (final kind in ['forwarded', 'received', 'sent', 'all']) {
      expect(
        keys,
        contains('direction-chip-$kind'),
        reason:
            '方向档的抓手改了名 ⇒ 闸门 5.14 那一格与 all_tab 那组点不到东西，'
            '而屏幕上看起来一切正常',
      );
    }
  });

  test('⑤ 尺认得合成样本（防 ①②③④ 退化成"恒不匹配＝恒绿"）', () {
    const shell = '''
Widget _filterChip(String label, bool selected, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      decoration: BoxDecoration(border: Border.all()),
      child: Text(label),
    ),
  );
}

Widget nextMember() => const SizedBox();
''';
    expect(chipBody(shell).contains('GestureDetector'), isTrue);
    expect(chipBody(shell).contains('FnthinkChoiceChip'), isFalse);

    // keyName 在第一位与在第四位都得抓到（真页面上两种都有）。
    const mixed = '''
_filterChip(
  keyName: 'time-all',
  label,
  selected,
  () => doThing(),
),
_filterChip(
  label,
  _direction == 'sent',
  () => _setDirection('sent'),
  keyName: 'direction-chip-sent',
),
_filterChip(label, selected, () {}, keyName: 'inline-key'),
Widget nextMember() => const SizedBox();
''';
    expect(chipKeys(mixed), ['direction-chip-sent', 'inline-key', 'time-all']);
    // 摘掉 keyName 的那一枚不该被算进来（否则"13 枚"会数给一个没有抓手的页面）。
    expect(
      chipKeys(
        '_filterChip(label, selected, () {}),\nWidget x() => const SizedBox();',
      ),
      isEmpty,
    );
  });
}

/// 那枚装配点的函数体：参数表按**括号配平**收尾（不假设它写成 `}) {` 还是单行 `) {`），
/// 再取函数体那对花括号**之内**的文字 —— 这样"下一个成员"不会被卷进来。
String chipBody(String strippedSource) {
  final at = strippedSource.indexOf('Widget _filterChip');
  expect(at, greaterThan(-1), reason: '这一页不再有 `_filterChip` 那枚装配点');
  final close = _matching(
    strippedSource,
    strippedSource.indexOf('(', at),
    '(',
    ')',
  );
  final brace = strippedSource.indexOf('{', close);
  expect(brace, greaterThan(-1), reason: '找不到那枚装配点的函数体开头');
  final end = _matching(strippedSource, brace, '{', '}');
  return strippedSource.substring(brace + 1, end);
}

/// 从 [open] 那一个括号开始，返回配对的那个闭合括号的下标。
int _matching(String src, int open, String left, String right) {
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == left) {
      depth++;
    } else if (src[i] == right) {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// 每一处 `_filterChip(` 调用**整段**里的 keyName（按括号配平取整段，不假设它在第几行）。
List<String> chipKeys(String strippedSource) {
  final found = <String>[];
  var from = 0;
  while (true) {
    final at = strippedSource.indexOf('_filterChip(', from);
    if (at < 0) break;
    var depth = 0;
    var end = -1;
    for (var i = at + '_filterChip'.length; i < strippedSource.length; i++) {
      final ch = strippedSource[i];
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        depth--;
        if (depth == 0) {
          end = i;
          break;
        }
      }
    }
    if (end < 0) break;
    final call = strippedSource.substring(at, end + 1);
    final m = RegExp(r"keyName:\s*'([a-z0-9-]+)'").firstMatch(call);
    if (m != null) found.add(m.group(1)!);
    from = end + 1;
  }
  return found..sort();
}
