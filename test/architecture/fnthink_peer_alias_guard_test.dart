import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T128 片1：名单那一行的「是谁」只有一个作者，改名那一发只有一个咽喉。
///
/// 这一族的两种错法都很具体：
///  ① 页面自己拼 `"$地址码 ($别名)"` —— 于是"地址码永远留在行里"这条纪律只在某一处成立，
///     第二处（收件行的发送方、幻念通道页的目标选择器）迟早会写成"只显别名"，
///     而那时用户核对的已经不是那 18 位；
///  ② 页面绕过服务直接写库 —— 别名的长度口径（超长截断）就在没人走的那一侧失效，
///     屏幕上出现一整行挤到换行的名字，而"撤掉这一行"那枚按钮被挤出屏幕。
void main() {
  final root = projectRoot();
  const page = 'lib/pages/fnthink_peers_page.dart';

  String readPage() => stripComments(File('$root/$page').readAsStringSync());

  test('行里那一段走 whoLabel，不在页面里拼', () {
    final src = readPage();
    // T152 片B：那一行不再是 `FnthinkNote(text: l10n.fnthinkPeerLine(…))` 一整句，而是
    // `FnthinkPeerRow(title: 是谁, subtitle: 方向那句话)` 两格。**判据的内容没变** ——
    // 「是谁」那一段必须由模型那一个作者给，页面不许自己拼「地址码 (别名)」。
    // ⚠ 尺从 `blockAfter` 换成**行窗口**：换件之后 `FnthinkPeerRow(` 后面第一个左花括号落在
    //   `'fnthink-peer-${peer.peerAddress}'` 的插值里，按花括号配对取块只会截出一小段 ——
    //   那种截法让下面两条断言对着半截签名恒真（本仓量过的假绿形状⑨）。
    final block = _windowAfter(src, 'FnthinkPeerRow(', 12);
    expect(block, isNotEmpty, reason: '名单行不再走公共件 ⇒ 下面那两条断言就管不着了（先确认还在本题里）');
    expect(
      block,
      contains('title: peer.whoLabel,'),
      reason: '「是谁」那一段必须由模型那一个作者给（地址码在前、别名在括号里）',
    );
    expect(
      block,
      contains('l10n.fnthinkPeerLine('),
      reason:
          '「它 → 你 · 授到 L2 · 时刻」那一格还在本题里（T98 片① 判的是这一族有两个方向）；'
          '把它换回页面自己拼的字符串，这条就断了',
    );
    expect(
      block.contains('peer.alias'),
      isFalse,
      reason: '页面自己把别名拼进那一行 ⇒ 第二处必然拼得不一样（T128）',
    );
  });

  test('改名只走服务那一个咽喉，页面不碰库', () {
    final src = readPage();
    expect(src, contains('rename('), reason: '那一发没接上服务 ⇒ 别名的长度口径没人执行');
    expect(
      src.contains('setFnthinkPeerAlias'),
      isFalse,
      reason: '页面直接写库 = 绕过 normalizeAlias，那一行会被挤到换行（T128）',
    );
  });

  test('三件事三句，各在自己的词条上', () {
    final src = readPage();
    for (final key in [
      'fnthinkPeerRename,',
      'fnthinkPeerRenameSaved(',
      'fnthinkPeerRenameCleared',
      'fnthinkPeerRenameGone',
    ]) {
      expect(
        src.contains(key),
        isTrue,
        reason: '`$key` 没被引用 ⇒ 「改了／抹了／那一行已经不在」被并成了一句',
      );
    }
    // 取消那一发不许落库：它回 null，页面必须在落到服务之前就退出。
    expect(
      src,
      contains('if (typed == null || !mounted) return;'),
      reason: '把"取消"当成"抹掉名字"写下去，用户关掉弹层就丢了一个名字',
    );
  });
}

/// 从含 [needle] 的那一行起，往下取 [depth] 行（含该行）。
///
/// 找不到就回**空串** —— 空串让调用点那条 `isNotEmpty` 红，而不是"窗口为空所以什么都包含"。
String _windowAfter(String source, String needle, int depth) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].contains(needle)) {
      final end = (i + depth < lines.length) ? i + depth : lines.length;
      return lines.sublist(i, end).join('\n');
    }
  }
  return '';
}
