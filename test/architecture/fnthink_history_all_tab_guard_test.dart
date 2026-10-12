import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T84「全部」档的形状守卫：三张账并排看，但**每样东西仍然只有一个作者**。
///
/// 这一档最容易长坏的地方不是"看不清"，而是**复制**：把收件行再抄一份、把计数再加一个、
/// 把读表再写一遍。三份都会绿，而错位的那一份只在下一次改口径时现形。
void main() {
  final root = projectRoot();
  final src = stripComments(
    File(
      '$root/lib/pages/history_page.dart',
    ).readAsStringSync().replaceAll('\r\n', '\n'),
  );

  String bodyOf(String signature) {
    final start = src.indexOf(signature);
    expect(start, greaterThan(-1), reason: '找不到 $signature —— 它被改名或删掉了？');
    return src.substring(start).split('\n  }').first;
  }

  int count(String needle) =>
      RegExp(RegExp.escape(needle)).allMatches(src).length;

  /// 另一种切法：`_inboxRow` 的参数表以 `}) {` 收尾，上面那个按 `\n  }` 切的口径在它身上
  /// 会**截早**（截到参数表那一行，函数体一行都拿不到）。这一族切到"下一个成员开头"。
  String bodyToNextMember(String signature) {
    final start = src.indexOf(signature);
    expect(start, greaterThan(-1), reason: '找不到 $signature —— 它被改名或删掉了？');
    final end = src.indexOf('\n  Widget ', start + signature.length);
    expect(end, greaterThan(start), reason: '$signature 之后找不到下一个成员 ⇒ 页面形状变了');
    return src.substring(start, end);
  }

  group('全部档没有长出第二份实现', () {
    test('收件/发出那一行的形状只有一个作者', () {
      // T148 片3：行 key 由通用件按 `keyNamespace` + `identity` 拼 ⇒ 页面里只许有一枚命名空间，
      // 而手写的行 key 应当为 0（还有就说明有人绕过件又拼了一份行）。
      expect(
        count("keyNamespace: 'fnthink-inbox'"),
        1,
        reason:
            '全部档若自己再抄一份行，`read` 那一列的读法就有了第二个作者，'
            '两处朝不同方向改时界面仍然"看起来正常"',
      );
      expect(
        count("'fnthink-inbox-row-"),
        0,
        reason:
            '行 key 的作者已经交给通用件：页面里再出现这一串 ⇒ 那一行的字号/行距/圆角/状态画法'
            '就是第二套（T148 那张差异清单的来路）',
      );
      expect(
        count("'fnthink-inbox-unread-"),
        1,
        reason: '未读点画不画只该有一处判据（判据②：转发与发出根本没有 read 这一列）',
      );
      // 三处复用：收件档那段 + 全部档的收件段 + 全部档的发出段
      expect(
        count('_inboxRow(') - 1, // 减去定义那一处
        3,
        reason: '`_inboxRow` 的复用点数变了 ⇒ 要么少接了一处（有一档不画了），要么又多抄了一份',
      );
    });

    test('收件行走的是通用件，不再由页面自己拼一行（T148 片3）', () {
      final row = bodyToNextMember('Widget _inboxRow(');
      expect(row, contains('HistoryRowTile('));
      // 行的字号/行距/圆角/状态画法只有件里那一份：页面里再出现这些字面量
      // ⇒ 同一类事实又长了第二套画法（T148 那张差异清单的来路）。
      for (final forbidden in ['ListTile(', 'fontSize: 15', 'fontSize: 11']) {
        expect(
          row,
          isNot(contains(forbidden)),
          reason: '收件行里出现 $forbidden ⇒ 页面又开始自己画行',
        );
      }
      // 三样行内容各归其位：徽标（未读点、「备用」）、状态原话（本机报出去的那一串）。
      expect(
        row,
        contains('badges: ['),
        reason: '未读点/备用标不走 badge 口 = 又在页面里另画一处',
      );
      expect(
        row,
        contains('statusMessage:'),
        reason: '回执那一串走散文拼接 ⇒ 状态画法长出第二套（差异③）',
      );
    });

    test('全部档不新增第四种计数（判据③）', () {
      final all = bodyOf('Widget _buildAllView(');
      // 只钉"把数画到屏上"那几枚：`records.length` 当 itemCount 用是必需的，不是计数 ——
      // 计数指的是界面上多出一个"共 N 条"那种口径（页面里只有 historyTitle / searchResultCount 两处作者）。
      for (final forbidden in [
        'historyTitle(',
        'searchResultCount(',
        'unreadCount',
      ]) {
        expect(
          all,
          isNot(contains(forbidden)),
          reason:
              '全部档里出现 $forbidden ⇒ 这一档开始自己算数了。三张表分页口径不同，'
              '"全部 = 三者之和"当下就不准，而那正是判据③要拦的第四种计数',
        );
      }
      final header = bodyOf('Widget _allSectionHeader(');
      expect(
        header,
        isNot(contains('.length')),
        reason: '段标题一旦开始算数，就是长出了第四种计数（判据③）',
      );
    });

    test('两本幻念账的读法仍走注入优先那对读口', () {
      final all = bodyOf('Future<void> _loadAll()');
      expect(
        all,
        contains('widget.inboxLoader ??'),
        reason: '页面不许绕开注入点直连表 —— 那是收件档早就钉住的那条线',
      );
      expect(all, contains('widget.sentLoader ??'));
      // T148 差异⑦：这两档不再自己写死条数，而是与转发档同一个「续到取尽」口径。
      expect(all, contains('drainAllPages'), reason: '全部档又不续页了 ⇒ 读回到一页的尾就收场');
      expect(
        count('drainAllPages'),
        4,
        reason:
            'flat 读法只有两本账 × 两个档位（收件/发出档各读一本，全部档一次读两本）'
            '—— 多一处就要问是不是又开了一条读径，少一处就是某一档退回了一页就收场',
      );
      expect(
        count('limit: 100'),
        0,
        reason: '写死的条数回来了：那一档超过它就直接看不见而界面不说少（历史不设上限，T133 已拍）',
      );
      expect(
        all,
        contains("if (_direction != 'all') return;"),
        reason: '读回来时已被切走档 ⇒ 交出去会把两本账画在别的档位上（与 `_loadInbox` 同一条竞态纪律）',
      );
    });

    test('档位切换与预置都认得全部档，且全部档不兑现 focusMessageId', () {
      final set = bodyOf('void _setDirection(');
      expect(set, contains("value == 'all'"));
      expect(
        set,
        contains('unawaited(_loadAll())'),
        reason: '切过去不读表 = 一格永远停在加载圈上',
      );
      expect(
        bodyOf('void _applyPendingFocus()'),
        isNot(contains('_allIn')),
        reason: '跳转只会落在收件档；在全部档兑现就是让"全部"去猜那一条属于哪本账',
      );
      final init = bodyOf('void initState()');
      expect(init, contains("if (_direction == 'all')"), reason: '预置到全部档时没人读表');
    });

    test('四档芯片各有抓手（按文本点会点错：转发那两个字第出现三次）', () {
      for (final kind in ['forwarded', 'received', 'sent', 'all']) {
        expect(
          src,
          contains("ValueKey('direction-chip-$kind')"),
          reason: '缺档位芯片的 key ⇒ 测试与闸门只能按文本点，而全部档里那枚文本会有三处命中',
        );
      }
    });
  });
}
