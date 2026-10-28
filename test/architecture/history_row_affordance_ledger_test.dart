import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T148 差异⑤：「可点与长按语义有的有、有的没有」—— 这本账把**每一类历史行**的三格
/// （点整行 / 长按整行 / 行内动作）逐类登记成现读读数，并为每一格写下它通向哪、为什么不给。
///
/// ## 为什么这一族只剩"登记"而不是一次搬运
/// T148 片1～片9 已把八处差异里的七处搬进同一个件（`HistoryRowTile`）。形状统一之后，
/// 三格的**画法**已经只有一个作者（件的 `onTap` / `onLongPress` / `lines` 三个口），
/// 剩下的不齐全在"这一类行到底给不给这三格"上 —— 那是产品判断，不是版式：
/// - 转发行：三格全给（详情、就地屏蔽菜单、单条补推）。
/// - 幻念收件／发出行：只有点行。**长按要补什么动作？本机今天只有详情弹层里的回复／重发，
///   把它们再摊到行上就是同一件事两个入口** ⇒ 登记成待拍，不自造动作。
/// - 远程执行行：点行与长按都不给（这一页没有详情层，全部读数就摊在行上），办事靠行内那枚「取消」。
///
/// ## 这本账的牙在哪
/// ① 账不许为空；② 每一格都要有说法（空串＝没人想过，也红）；
/// ③ `lib/` 里**真实存在**的行装配点必须与账上的条数一一对上（新增第四类行而不入账 ⇒ 红）；
/// ④⑤ 逐类核「点行 / 长按」两格在代码里的有无 == 账上的真值（漏传与私自补上都红）；
/// ⑥ 行内动作那一格按每一类各自的探针核（探针是那一格的装配点，不是文案）；
/// ⑦ 转发行那两格的**语义**（批量档点行=切换选中、长按禁用）钉在写法上 —— 这一格是这一族里
///   唯一"同一行随界面状态变语义"的，改回单态就没人知道自己把 F2 抹掉了。
/// ⑧ 收件行「动作在详情里」这件事本身要有落点：那两枚件仍在弹层那一段源码里。
///
/// ⚠ 读源码一律先剥注释（`stripComments`）：这一页的注释里就写着"长按菜单禁用"几个字，
/// 不剥的话「补上 onLongPress」和「只补一句注释」在守卫眼里同形（本仓已撞过 3–4 次那一族）。
void main() {
  final root = projectRoot();

  /// 每个文件的行体按**剥注释后**的整行取（锚点是整行字面，逐行比不会漂）。
  List<String> strippedLines(String rel) =>
      stripComments(librarySource(root, 'lib/$rel'))
          .replaceAll('\r\n', '\n')
          .split('\n');

  testWidgets('① 这本账不许为空', (tester) async {
    expect(
      kRowAffordanceLedger,
      isNotEmpty,
      reason: '账空了就等于差异⑤ 从没被核过：这一族的"齐不齐"从此没有读数',
    );
  });

  testWidgets('② 每一格都要有说法（不给也要写成一句"不给"）', (tester) async {
    for (final e in kRowAffordanceLedger) {
      expect(
        e.tapWhat.trim(),
        isNotEmpty,
        reason: '${e.kind}：点行那一格没写通向哪 —— 空串＝没人想过，与"故意不给"同形',
      );
      expect(e.longPressWhat.trim(), isNotEmpty, reason: '${e.kind}：长按那一格同上');
      expect(e.inlineWhat.trim(), isNotEmpty, reason: '${e.kind}：行内动作那一格同上');
      expect(
        e.gap.trim(),
        isNotEmpty,
        reason:
            '${e.kind}：三格不齐的地方必须写下为什么不齐'
            '（否则下一次"补齐"就没人知道代价）',
      );
    }
  });

  testWidgets('③ 代码里真实存在的行装配点，一类都不许漏到账外', (tester) async {
    expect(
      realHistoryRowCallSites(root),
      kRowAffordanceLedger.length,
      reason:
          '新增一类历史行而没登记它的三格 ⇒ 差异⑤ 就从这一格重新长出来；'
          '反方向（删了一类而账上还有）同样红：账要读得出今天，不是读得出去年',
    );
    for (final e in kRowAffordanceLedger) {
      final lines = strippedLines(e.file);
      expect(
        lines.where((l) => l.trim() == e.start.trim()).length,
        1,
        reason: '${e.kind}：起点锚在 ${e.file} 里读不到（行装配点被挪走或改名，账要一起改）',
      );
    }
  });

  testWidgets('④ 点行那一格：账上的有无 == 代码里的有无', (tester) async {
    for (final e in kRowAffordanceLedger) {
      final body = e.body(strippedLines(e.file));
      expect(
        body.contains('onTap:'),
        e.tapRow,
        reason: e.tapRow
            ? '${e.kind}：账上写着点行有事，代码里那一格却漏传了 —— '
                  '页面上这行看起来一模一样，点了什么都不发生'
            : '${e.kind}：账上写着点行不给，代码里却长出了一格 —— '
                  '这就是"同一屏两种行、一种点得动一种点不动"的回归路径',
      );
    }
  });

  testWidgets('⑤ 长按那一格：账上的有无 == 代码里的有无', (tester) async {
    for (final e in kRowAffordanceLedger) {
      final body = e.body(strippedLines(e.file));
      expect(
        body.contains('onLongPress:'),
        e.longPressRow,
        reason: e.longPressRow
            ? '${e.kind}：长按菜单那一格被漏传 ⇒ 就地处置的入口静默消失'
                  '（T148 片2 立这本账就是为了这一手）'
            : '${e.kind}：账上登记的是"长按不给"（那一拍还没拍），代码里却先补上了 —— '
                  '补动作要先回答"出什么"，别让一发明成第二个入口',
      );
    }
  });

  testWidgets('⑥ 行内动作那一格：按每一类自己的探针核', (tester) async {
    for (final e in kRowAffordanceLedger) {
      final body = e.body(strippedLines(e.file));
      final probe = e.inlineProbe;
      if (probe == null) {
        expect(
          body.contains('FnthinkInlineAction(') ||
              body.contains('CupertinoButton(') ||
              body.contains('onPressed:'),
          isFalse,
          reason:
              '${e.kind}：账上写着行上不带动作件，代码里却多长出一枚 —— '
              '它和详情弹层里那两枚是同一件事，要合就一起合，不许两处各留一份',
        );
        continue;
      }
      expect(
        body.contains(probe),
        isTrue,
        reason: '${e.kind}：行内动作那一格读不到了（探针＝那一格的装配点，不是它的文案）',
      );
    }
  });

  testWidgets('⑦ 转发行那两格随界面状态变语义（批量档点行=选中、长按禁用）', (tester) async {
    final forwarded = kRowAffordanceLedger.firstWhere(
      (e) => e.kind.startsWith('转发行'),
    );
    final body = forwarded.body(strippedLines(forwarded.file));
    expect(
      body,
      contains('onTap: _batchMode'),
      reason: '批量档点行必须换成"切换选中"：留着打开详情，用户勾选时点开的是另一层',
    );
    expect(body, contains('_toggleBatchSelect(record)'));
    expect(body, contains('_showRecordDetail(record)'));
    expect(
      body,
      contains('onLongPress: _batchMode ? null'),
      reason: '批量档长按要禁用：留着就是一边勾选一边弹屏蔽菜单，两件事在同一行上抢',
    );
  });

  testWidgets('⑧ 收件行的动作住在详情弹层里，不在行上', (tester) async {
    final src = stripComments(
      File('$root/lib/pages/history_page.dart').readAsStringSync(),
    );
    final sheet = src.substring(
      src.indexOf('Future<void> _showInboxDetail('),
      src.indexOf('Future<void> _composeFromInbox('),
    );
    expect(
      sheet.contains("ValueKey('fnthink-inbox-reply')"),
      isTrue,
      reason:
          '弹层里那枚「回复」读不到了 —— 收件行既没有长按、弹层里又少了这一格，'
          '那"这条消息能办事"就全凭运气',
    );
    expect(sheet, contains("ValueKey('fnthink-inbox-resend')"));
    expect(
      sheet.contains('peer != null'),
      isTrue,
      reason: '那两枚只给"对端还在本机名单里"的那几条：不在册的给入口就是一个必然 403 的按钮',
    );
  });
}

/// 一类历史行 = 账上一行。`file` 用相对 `lib/` 的路径，`start` / `end` 是行装配点体内的整行字面。
///
/// ⚠ 往账上加一行之前，先把那一类的三格各自读一遍并写下说法；改动了代码就要同时改这本账
/// —— 这本账的用途是"今天齐不齐"，不是"去年拍过什么"。
class RowAffordance {
  const RowAffordance({
    required this.kind,
    required this.file,
    required this.start,
    required this.end,
    required this.tapRow,
    required this.tapWhat,
    required this.longPressRow,
    required this.longPressWhat,
    required this.inlineProbe,
    required this.inlineWhat,
    required this.gap,
  });

  final String kind;
  final String file;
  final String start;
  final String end;

  final bool tapRow;
  final String tapWhat;
  final bool longPressRow;
  final String longPressWhat;

  /// 行内动作那一格的探针：行体里出现它才算"给了"；null 表示这一类的行上不带动作件。
  final String? inlineProbe;
  final String inlineWhat;
  final String gap;

  /// 「这一行的体内」= 起点锚到终点锚之间（不含终点那一行 = 下一个成员的头）。
  String body(List<String> lines) {
    final s = lines.indexOf(start);
    if (s < 0) {
      fail('$kind：起点锚在 $file 里读不到：$start');
    }
    final e = lines.indexOf(end, s + 1);
    if (e < 0) {
      fail('$kind：终点锚在起点之后读不到（改名或挪走要同时改这本账）：$end');
    }
    return lines.sublist(s, e).join('\n');
  }
}

const List<RowAffordance> kRowAffordanceLedger = [
  RowAffordance(
    kind: '转发行（推送历史的本地转发记录）',
    file: 'pages/history_page.dart',
    start: '    final item = HistoryRowTile(',
    end: '    if (!_batchMode) return item;',
    tapRow: true,
    tapWhat: '非批量档打开该条详情（详细信息＋送达记录在同一层）；批量档点行=切换选中',
    longPressRow: true,
    longPressWhat: '出就地动作菜单（屏蔽该应用／屏蔽该内容）；批量档禁用',
    inlineProbe: '_buildPushNowButton(record, l10n)',
    inlineWhat:
        '行内出口每行都给（T133 片9 走 (b)）；说的话按 `repushIntentOf` 分两种 —— '
        '还有没发出去的那几条「现在推送」（只补那几族），已经发出去的「再发一次」（收件端会多收一条）',
    gap: '三格齐 —— 这一类是差异⑤ 的基座；下面两类照不照它对齐，账上各写各的。',
  ),
  RowAffordance(
    kind: '幻念收件／发出行',
    file: 'pages/history_page.dart',
    // T147② 起 `return HistoryRowTile(` 在组行里也有一处 ⇒ 起点改取这一行（唯一）。
    start: '    final peer = m.sender.isEmpty ? l10n.unknown : _senderText(m.sender);',
    end: '  Widget _buildInboxView(AppLocalizations l10n) {',
    tapRow: true,
    tapWhat:
        '打开收件详情（全文可读 + 对端在册时给回复／重发）；收件档点开即标已读；'
        '选项态下点行只切勾选（T208）',
    longPressRow: true,
    longPressWhat:
        '收件行长按进入多选（T208）—— 出的是「取消 · 已选 N · 确认已读」那一套，'
        '不是第二个详情入口；发出行不长这一格（那本账没有"未读"这回事）',
    inlineProbe: null,
    inlineWhat: '不给：行上没有动作件（未读点与「备用」是徽标，不是动作）',
    gap: 'T208 起三格齐 —— 长按那一格补上的正是当初登记的那条"产品判断"（长按出什么＝批量标已读）。',
  ),
  RowAffordance(
    kind: '规则扇出组行（T147②）',
    file: 'pages/history_page.dart',
    start: '    final group = view.group;',
    end: '  Widget _groupMemberRow(',
    tapRow: true,
    tapWhat: 'T179 起点行打开只读成员子页（标题／时间／各通道状态），成员可再点进详情；组本身不可重推',
    longPressRow: false,
    longPressWhat: '不给：组行不对应某一条可处置的通知，长按菜单没有主语',
    inlineProbe: null,
    inlineWhat: '不给：行上没有动作件（「组」是徽标，不是动作）；逐条重推按 T147 ④ 不做',
    gap: '点行给的是「看这批里有哪些」；长按与行内动作仍不给（组不是一条可处置的记录）。',
  ),
  RowAffordance(
    kind: '组子页成员行（T179）',
    file: 'pages/history_page.dart',
    start: "      key: ValueKey('history-group-member-\${record.id}'),",
    end: '  Widget _buildRecordItem(',
    tapRow: true,
    tapWhat: '关掉组子页并打开那一条的详情（详情自己也是弹层，叠着开会让「返回」语义走样）',
    longPressRow: false,
    longPressWhat: '不给：成员行在组子页里只承担"挑一条去看"，就地处置仍回到详情那一层',
    inlineProbe: null,
    inlineWhat: '不给：行上没有动作件；这一页只回答"这一组里有哪些记录"',
    gap: '点行与长按不同齐是设计：给"进去看"不等于给"就地处置"。',
  ),
  RowAffordance(
    kind: '远程执行行',
    file: 'pages/remote_history_page.dart',
    start: '    return HistoryRowTile(',
    end: '  Color _stateColor(String state) => switch (state) {',
    tapRow: false,
    tapWhat: '不给：这一页没有详情层，时间／来源／状态／结果／理由全摊在这一行上',
    longPressRow: false,
    longPressWhat: '不给：这一类行没有"就地处置"可给（撤销是对那一次执行的，不是对这条记录的）',
    inlineProbe: 'FnthinkInlineAction(',
    inlineWhat:
        '行内「取消」一枚，只给 in + unsettled 那几条（发起端 out 不给）；'
        '片11 起这枚走公共件 `FnthinkInlineAction`（探针跟着换 —— 探针记的是"行上有动作件"这件事，'
        '不是某一枚壳的写法），键名 `remote-history-cancel-<execId>` 逐字没动',
    gap:
        '点行与长按两格为空是**设计**（没有可打开的东西＝不发明动作）；'
        '它靠行内动作那一格保证"要办事时办事有着落"。',
  ),
];

/// `lib/` 里真实的行装配点：`HistoryRowTile(` 的出现次数，排除件本体
/// （件里那一处是构造函数声明，不是装配点）。
int realHistoryRowCallSites(String root) {
  var n = 0;
  for (final entry in libCodeByRel(root).entries) {
    if (entry.key == 'widgets/history_row_tile.dart') {
      // 件本体只许有构造函数那一处；多出来说明件里自己起了行（这本账的主语就变了）。
      expect(
        RegExp(r'HistoryRowTile\(').allMatches(entry.value).length,
        1,
        reason: '件本体里 `HistoryRowTile(` 只该是构造函数声明',
      );
      continue;
    }
    n += RegExp(r'HistoryRowTile\(').allMatches(entry.value).length;
  }
  return n;
}
