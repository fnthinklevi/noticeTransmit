import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T149 片1（维护者 2026-10-12 第 4 条：「当前软件内依然存留大量的大段文字说明，详细检索所有页面」）。
///
/// 这一族是 T90 片5/片6 的续：当时定了「两种去处（底部无序列表 / 右上问号弹层）」，
/// 今天**收窄成一处 —— 长说明只进问号弹层**，页面上只留一行短说（状态原话是例外，不许搬）。
///
/// ## 为什么这里是一台账加一把棘轮
/// 逐页搬要好几片才搬完。没有台账，下一片就不知道"上一片搬了几段、还有几段"，
/// 而没有棘轮，**已经搬干净的那一页随时能长回来**（本仓治过很多轮的那类：改好一次的形状没人钉住）。
/// 所以这张表登记的是"每页现在还有几段"，判据是**不许超过登记值** —— 搬少是进展，变多是回退。
///
/// ## 尺的口径（为什么不是字数）
/// 判据取「挂在页面说明块上的长词条数」：字数会逼人把长句拆成多个短句（那就是假绿），
/// 而"几段"正好是要治的东西 —— 同屏连续两句以上解释性文字。
/// 只算**挂在页面上**的那些（`FnthinkNote(` / `_Note(` / `FnthinkBulletNote(`）：
/// 确认框与输入框的正文本来就是弹窗，那是 T90 认的去处，不许被这一族当成违规清掉。
void main() {
  final root = projectRoot();
  final arb =
      jsonDecode(File('$root/lib/l10n/arb/app_zh.arb').readAsStringSync())
          as Map<String, dynamic>;

  int cjkLen(String s) => s.runes.where((c) => c > 0x7f).length;

  /// 每页**现在**还挂在页面上的长说明段数（2026-10-12 实测）。搬完一页就把那一行改小或删掉 ——
  /// `remote_history_page.dart`（片1）、`fnthink_receive_page.dart`（片2）与
  /// `remote_credential_settings_page.dart`（片3）已在这条上被搬空，
  /// 所以它们不在表里，读到的必须是 0。
  const ledger = <String, int>{
    'fnthink_peers_page.dart': 6,
    'fnthink_send_page.dart': 6,
    'fnthink_endpoint_page.dart': 3,
    'fnthink_shortcuts_page.dart': 3,
  };

  Map<String, int> countAll() {
    final out = <String, int>{};
    final dir = Directory('$root/lib/pages');
    for (final e
        in dir.listSync().whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path))) {
      final name = e.path.split(Platform.pathSeparator).last;
      final lines = stripComments(
        e.readAsStringSync().replaceAll('\r\n', '\n'),
      ).split('\n');
      final keys = <String>{};
      // 窗口只有三行，且**自己会清零**：一枚问号行（`HelpNoteRow`）里那格 `helpBody`
      // 正是这一族要人去放的去处，若说明块的标记一直粘着不放，量到的就是"搬进弹层的那句"，
      // 棘轮反过来罚了合规的那一步 —— 尺不能这么长。
      var remaining = 0;
      for (var i = 0; i < lines.length; i++) {
        final ln = lines[i];
        if (ln.contains('FnthinkNote(') ||
            ln.contains('_Note(') ||
            ln.contains('FnthinkBulletNote(')) {
          remaining = 3;
        } else if (ln.contains('showExplainer(') ||
            ln.contains('helperText:') ||
            ln.contains('message:') ||
            ln.contains('askConfirm(') ||
            ln.contains('showInfo(')) {
          remaining = -3;
        }
        if (remaining <= 0) {
          if (remaining < 0) remaining++;
          continue;
        }
        for (final m in RegExp(r'l10n\.(?:get\.)?([A-Za-z0-9_]+)').allMatches(
          lines.sublist(i, (i + 3).clamp(0, lines.length)).join(' '),
        )) {
          final v = arb[m.group(1)];
          if (v is String && cjkLen(v) >= 40) keys.add(m.group(1)!);
        }
        remaining--;
      }
      if (keys.isNotEmpty) out[name] = keys.length;
    }
    return out;
  }

  test('尺不瞎：重灾区读得出条数、刚搬干净的那几页读出 0', () {
    // 正面对照：这条断言不依赖台账，台账写错也照样红 —— 没有它，"每页都读到 0"
    // 与"尺根本读不到"两种情况长得一模一样。
    final got = countAll();
    expect(
      got['fnthink_send_page.dart'] ?? 0,
      greaterThan(5),
      reason: '发送页是最重的一页，读不出来就是尺坏了而不是页面干净了',
    );
    expect(
      got['remote_history_page.dart'] ?? 0,
      0,
      reason: '片1 刚把它搬到问号弹层里，读到的还是"挂在页面上"就是尺不认得新形状',
    );
    expect(
      got['fnthink_receive_page.dart'] ?? 0,
      0,
      reason:
          '片2 搬的是渠道披露那一段（127 字，本表里最长的一条）——'
          '同一形状连搬两页都读得出来，这条对照才不是只对着一页写死的',
    );
    expect(
      got['remote_credential_settings_page.dart'] ?? 0,
      0,
      reason:
          '片3 一次搬两格（密钥明文那句 68 字 + TOTP 那句 80 字）——'
          '同一页里**两处**装配点都换了形状，只换一处这条就会红',
    );
  });

  test('台账：每页挂在页面上的长说明段数不许超过登记值', () {
    final got = countAll();
    final worse = <String, String>{};
    for (final e in got.entries) {
      final allowed = ledger[e.key] ?? 0;
      if (e.value > allowed) worse[e.key] = '$allowed -> ${e.value}';
    }
    expect(
      worse,
      isEmpty,
      reason:
          '这些页又长出成段说明了（T149 的去处只有一处：右上问号弹层）。'
          '确实要新增一段解释性文字，就搬进那一页的问号里；'
          '搬不动就把台账改掉并在 roadmap 的 T149 行写下为什么：$worse',
    );
  });

  test('台账里不许留着已经搬空的页（登记值要和实测一致地往下走）', () {
    final got = countAll();
    final stale = <String>[
      for (final e in ledger.entries)
        if ((got[e.key] ?? 0) < e.value)
          '${e.key}: 登记 ${e.value} 实测 ${got[e.key] ?? 0}',
    ];
    expect(
      stale,
      isEmpty,
      reason:
          '搬完一页要把那一行改成 0 或删掉 —— 留着旧数，下一次长回去时没人知道'
          '（台账骗人这一条在本仓摔过很多次）：$stale',
    );
  });
}
