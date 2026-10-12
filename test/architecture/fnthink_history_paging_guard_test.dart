import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T148 差异⑦ 的口径守卫：历史三个档「一次读多少行 / 读不读得尽」归成一枚数 + 一件续拉。
///
/// 这一片在页面上是**看不见**的：幻念两档的注入点（`inboxLoader`/`sentLoader`）是零参闭包，
/// 存在的理由就是让 widget 测试不必开 sqlite，而续拉恰好写在生产回退那一半里 ——
/// 页面级用例永远走的是替身那条路。所以这里的证据是源码形状，而"续拉对不对"的证据在
/// `test/services/history_paging_test.dart`（纯函数那侧）。
///
/// ⚠ 三条判据不许合成一条计数：枚数相等（长回写死的条数）、口径只有一个作者（改数要三档一起）、
/// 读口要有 offset（没有它，续拉在第一页之后拿回的是同一批）。各管一维，红哪条就知道坏在哪维。
void main() {
  final root = projectRoot();
  final libCode = libCodeByRel(root);

  String strip(String rel) {
    final src = libCode[rel.replaceFirst('lib/', '')];
    expect(src, isNotNull, reason: '$rel 不在扫描口径里 ⇒ 下面几条对任何仓库都恒真');
    return src!;
  }

  int countIn(String rel, String needle) =>
      RegExp(RegExp.escape(needle)).allMatches(strip(rel)).length;

  group('一枚数只有一个作者', () {
    test('kHistoryPageSize 的定义在 lib/ 里恰好一处', () {
      final defining =
          libCode.entries
              .where((e) => e.value.contains('const int kHistoryPageSize'))
              .map((e) => e.key)
              .toList()
            ..sort();
      expect(
        defining,
        ['services/history_paging.dart'],
        reason:
            '深度长出第二个作者 ⇒ 三档会朝不同方向漂（这一片要修的正是"转发 200／幻念 100／'
            '远程吃缺省"那一族），而漂了之后每条判据都还是绿的',
      );
    });

    test('转发档的那页也吃这枚数（不是自己留一份 200）', () {
      expect(
        countIn(
          'lib/pages/history_page.dart',
          'static const int _pageSize = kHistoryPageSize;',
        ),
        1,
        reason: '转发档退回自己写死一枚数 ⇒ 三档深度又各说各话',
      );
    });

    test('调用点不许把条数写成裸字面量', () {
      final bare = RegExp(
        r'list(?:Sent)?\(\s*limit:\s*\d',
      ).hasMatch(strip('pages/history_page.dart'));
      expect(
        bare,
        isFalse,
        reason:
            '页面里出现 `limit: <数字>` ⇒ 写死的条数回来了。那一档超过它就直接看不见，'
            '而界面不说少（历史不设上限，T133 已拍）',
      );
    });
  });

  group('三个档的生产读口都续到取尽', () {
    const drainSites = <String, int>{
      'pages/history_page.dart': 4,
      'di/service_locator.dart': 1,
    };

    test('续拉的调用点与台账相等，多一处少一处都红', () {
      for (final e in drainSites.entries) {
        expect(
          countIn('lib/${e.key}', 'drainAllPages('),
          e.value,
          reason:
              '${e.key} 的续拉点实际与台账不等：少一处就是某一档退回"读一页就收场"，'
              '多一处就是有人另开了一条读径（两本账 × 两档 = 4，DI 那一档 = 1）',
        );
      }
      expect(
        drainSites.values.fold<int>(0, (a, b) => a + b),
        greaterThan(0),
        reason: '台账为空 ⇒ 上面那条对任何仓库都恒真',
      );
    });

    test('台账里那几个文件都还在扫描口径里', () {
      for (final key in drainSites.keys) {
        expect(
          libCode.containsKey(key),
          isTrue,
          reason: '$key 漂了（改名/移走）⇒ 这本账整册空转，而没人会红',
        );
      }
    });

    test('DI 里远程执行那一档把 limit 与 offset 都传下去', () {
      final block = blockAfter(
        strip('di/service_locator.dart'),
        'loadRemoteExecutions:',
      );
      expect(block, contains('drainAllPages('));
      for (final needle in ['limit: limit', 'offset: offset']) {
        expect(
          block,
          contains(needle),
          reason: '$needle 没传 ⇒ 续拉每一批拿回的是同一批，界面会出现同一条重复',
        );
      }
    });
  });

  /// 取「这个成员从签名到下一个成员为止」那一段。
  ///
  /// ⚠ 不用 `blockAfter`：它的尺是「签名之后第一个 `{` 配对到它的 `}`」，而 Dart 的具名参数表
  /// 本身就是一对花括号 ⇒ 拿回来的只有参数表、函数体一行都没有（那条判据会对着一截签名恒真）。
  String memberSlice(String src, String signature, String nextSignature) {
    final start = src.indexOf(signature);
    expect(start, greaterThan(-1), reason: '找不到 $signature —— 它被改名或删掉了？');
    final end = src.indexOf(nextSignature, start + signature.length);
    expect(
      end,
      greaterThan(start),
      reason: '$signature 之后找不到 $nextSignature ⇒ 文件形状变了，这段尺会一直读到文件尾',
    );
    return src.substring(start, end);
  }

  group('读口本身要接得住翻页', () {
    test('远程执行历史的读口有 offset 并把它交给查询', () {
      final src = File(
        '$root/lib/database/database_helper.dart',
      ).readAsStringSync();
      final block = memberSlice(
        src,
        'loadRemoteExecutionRecords({',
        'Future<List<FnthinkRemoteExecutionRecord>>\n',
      );
      expect(
        block,
        contains('int offset = 0'),
        reason: '参数表没有 offset ⇒ 那一档没法续页，只能吃缺省那 200 条',
      );
      expect(
        block,
        contains('offset: offset'),
        reason: '收了参数却不交给查询 = 每一批都从头读，续拉会变成死循环',
      );
    });

    test('收件读口把 limit 与 offset 都交给表（不是只收下不用）', () {
      final block = memberSlice(
        strip('services/fnthink_inbox_service.dart'),
        'Future<List<FnthinkInboxMessage>> list({',
        'Future<List<FnthinkInboxMessage>> listSent({',
      );
      for (final needle in ['limit: limit', 'offset: offset']) {
        expect(block, contains(needle), reason: '$needle 不在 ⇒ 页面续到第几批都是同一批');
      }
    });
  });
}
