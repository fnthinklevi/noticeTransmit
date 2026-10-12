import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T149（维护者 2026-10-12 第 4 条：「当前软件内依然存留大量的大段文字说明，详细检索所有页面」）。
///
/// 这一族是 T90 片5/片6 的续：当时定了「两种去处（底部无序列表 / 右上问号弹层）」，
/// 今天**收窄成一处 —— 长说明只进问号弹层**，页面上只留一行短说（状态原话是例外，不许搬）。
///
/// ## 这本账为什么现在必须是空的
/// 片1～片8 逐页搬完了：`remote_history`／`fnthink_receive`／`remote_credential_settings`／
/// `fnthink_shortcuts`／`fnthink_endpoint`／`fnthink_peers`／`fnthink_send`。
/// 账在的时候牙是「不许超过登记值」；账空之后同一句读作「任何一页都不许有」。
/// ⚠ 但空表让那条判据**对任何干净仓库都不响**，于是"没人加行"与"加行的人是对的"同形 ⇒
///   另加一条「这本账保持为空」，并把尺的口径抽成纯函数、用**自造源码**做正面对照（见下）。
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

  /// 每页**现在**还挂在页面上的长说明段数。片8 之后为空。
  /// 确实要新增一段解释性文字 ⇒ 走那一页的问号弹层；搬不动 ⇒ 开一条新任务写清为什么。
  /// ⚠ 不要往这张表里加一行：加一行就是替下一位把违规登记成许可。
  const ledger = <String, int>{};

  /// 尺的本体：给定源码与一张"键→文案"表，数出挂在页面说明块上的长段。
  /// 抽成纯函数是为了下面那条**尺自校** —— 仓库全干净之后，"每页都读到 0"与"尺根本读不到"
  /// 在断言里同形，只有能自己造一段页面源码喂给它，才分得开这两种 0。
  Set<String> longKeysIn(String source, Map<String, Object?> table) {
    final lines = stripComments(source).replaceAll('\r\n', '\n').split('\n');
    final keys = <String>{};
    // 窗口只有三行，且**自己会清零**：一枚问号行（`HelpNoteRow`）不是页面说明块，
    // 若说明块的标记一直粘着不放，量到的就是"搬进弹层的那句"，
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
        final v = table[m.group(1)];
        if (v is String && cjkLen(v) >= 40) keys.add(m.group(1)!);
      }
      remaining--;
    }
    return keys;
  }

  Map<String, int> countAll() {
    final out = <String, int>{};
    final dir = Directory('$root/lib/pages');
    for (final e
        in dir.listSync().whereType<File>().toList()
          ..sort((a, b) => a.path.compareTo(b.path))) {
      final name = e.path.split(Platform.pathSeparator).last;
      final keys = longKeysIn(e.readAsStringSync(), arb);
      if (keys.isNotEmpty) out[name] = keys.length;
    }
    return out;
  }

  // ── 尺自校：正面对照不再依赖"哪一页还脏着"（片8 之后没有这样的页了）───────────
  // 片1～片7 用的是"重灾区那一页读得出条数"，那条对照现在会随仓库变干净而失效
  // （它读的数与"尺坏了"同形）。换成自己造源码：同一句长文案，挂在页面上必须读 1、
  // 放进问号必须读 0 —— 两条同时成立才叫"尺认得这两种形状"。
  test('尺自校：同一句长说明，挂在页面上读得出 1、放进问号读成 0', () {
    final table = <String, Object?>{
      'probeLong': List<String>.filled(45, '字').join(),
      'probeShort': '这一句短',
    };
    expect(
      longKeysIn(
        "FnthinkNote(\n  keyName: 'probe',\n  text: l10n.probeLong,\n)\n",
        table,
      ),
      {'probeLong'},
      reason: '挂在页面说明块上的长段读不到 ⇒ 下面每一条"0"都是假的（尺瞎了）',
    );
    expect(
      longKeysIn(
        'HelpNoteRow(\n'
        "  noteKey: 'probe',\n"
        "  helpKey: 'probe-help',\n"
        '  text: l10n.probeShort,\n'
        '  helpTitle: l10n.probeShort,\n'
        '  helpBody: l10n.probeLong,\n'
        ')\n',
        table,
      ),
      isEmpty,
      reason:
          '问号弹层正是这一族指定的**去处**：尺要是把 helpBody 也当成挂在页面上的说明，'
          '它就在罚合规的那一步，于是每一片"搬完了"都要红着收场',
    );
    // ⚠ 上面那条竖排的问号**测不出"尺被改宽"**：窗口只有三行，而 `helpBody` 落在第五行，
    //   就算把 `HelpNoteRow(` 也列成说明块标记，那一格也在窗口外（片8 的反证 Q9 就是这么露出来的）。
    //   所以补这一条**收紧到同一行**的探针（它不是仓库里真实排版，只是为了让这一维可观察）：
    //   同一句长说明写在 helpBody 上、且就在标记那一行里 —— 尺一变宽就立刻读成 1。
    expect(
      longKeysIn(
        "HelpNoteRow(noteKey: 'p', text: l10n.probeShort, helpBody: l10n.probeLong)\n",
        table,
      ),
      isEmpty,
      reason: '换一种排版就把去处读成违规 ⇒ 尺的口径跟着排版走，那就是每片都要红着收场',
    );
  });

  test('尺不瞎：扫得到的页面数量不许掉', () {
    // 与"哪一页搬完了"完全无关的另一条对照：读不到文件时上面所有数都是"没看见"，
    // 而"没看见"与"干净"在断言里同形。
    final scanned = Directory('$root/lib/pages')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .length;
    expect(
      scanned,
      greaterThanOrEqualTo(30),
      reason: '扫不到页面文件 ⇒ 上面每一条读数都是"没看见"而不是"干净"',
    );
  });

  test('这本账保持为空：T149 已收口，任何一页都不许再挂长说明段', () {
    expect(
      ledger,
      isEmpty,
      reason:
          '台账又被加行了。空表是这一族收完的形状，加一行等于替下一位把违规登记成许可：'
          '要新增解释性文字就走那一页的问号弹层，真搬不动就开一条新任务写清为什么',
    );
    expect(countAll(), isEmpty, reason: '有页面又挂回成段说明了（去处只有一处：右上问号弹层）');
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
