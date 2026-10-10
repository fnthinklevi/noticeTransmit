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
    final block = blockAfter(src, 'text: l10n.fnthinkPeerLine(');
    expect(
      block,
      contains('peer.whoLabel'),
      reason: '「是谁」那一段必须由模型那一个作者给（地址码在前、别名在括号里）',
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
