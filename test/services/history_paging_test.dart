import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/history_paging.dart';

/// T148 差异⑦：三个档的「一次读多少行 / 读不读得尽」归成一枚数 + 一件续拉。
///
/// 这一件是纯函数，所以这里就是它的**主证据**：页面级用例碰不到那一段 ——
/// 幻念两档的注入点（`inboxLoader`/`sentLoader`）是零参闭包，存在的理由就是让
/// widget 测试不必开 sqlite，而续拉恰好写在生产回退那一半里。
/// 那条边界由 `test/architecture/fnthink_history_paging_guard_test.dart` 钉住。
void main() {
  group('续拉本身', () {
    test('不满一页就收场：读口只被问一次', () async {
      final seen = <(int, int)>[];
      final out = await drainAllPages<String>((limit, offset) async {
        seen.add((limit, offset));
        return const ['a', 'b'];
      }, pageSize: 5);
      expect(out, hasLength(2));
      expect(seen, [(5, 0)], reason: '不满一页就是尾 —— 多问一次是白问');
    });

    test('满页就一直续到尾，游标是已累计的行数、顺序就是读口给的顺序', () async {
      final seen = <(int, int)>[];
      final batches = [
        ['1', '2', '3'],
        ['4', '5', '6'],
        ['7'],
      ];
      final out = await drainAllPages<String>((limit, offset) async {
        seen.add((limit, offset));
        return batches[offset ~/ limit];
      }, pageSize: 3);
      expect(out, [
        '1',
        '2',
        '3',
        '4',
        '5',
        '6',
        '7',
      ], reason: '续拉不许重排 —— 排序口径在读口那一处（页面自己排就是第二份）');
      expect(seen, [
        (3, 0),
        (3, 3),
        (3, 6),
      ], reason: '游标按已拿到的行数走，第二次的 offset 就是第一批的行数');
    });

    test('第一页就是空 ⇒ 空表，且不许变成无限循环', () async {
      var calls = 0;
      final out = await drainAllPages<String>((limit, offset) async {
        calls++;
        return const [];
      }, pageSize: 2);
      expect(out, isEmpty);
      expect(calls, 1, reason: '空表不满一页就是尾 —— 再问一次就永远问不完');
    });

    test('续拉没有页数闸：读到尾为止（历史不设上限，T133 已拍）', () async {
      var calls = 0;
      final out = await drainAllPages<String>((limit, offset) async {
        calls++;
        // 十批满页再给一批短的：只按"不满一页"收场，不按"读了几页"收场。
        return calls <= 10 ? List<String>.filled(limit, 'x') : const ['尾'];
      }, pageSize: 4);
      expect(calls, 11);
      expect(out, hasLength(41));
    });

    test('缺省那一页就是三档共用的那枚数', () async {
      final seen = <(int, int)>[];
      await drainAllPages<String>((limit, offset) async {
        seen.add((limit, offset));
        return const ['x'];
      });
      expect(
        seen.single.$1,
        kHistoryPageSize,
        reason: '读口收到的 limit 必须来自那枚共用的数，不是调用点手写的',
      );
      expect(kHistoryPageSize, 200, reason: '这枚数是转发档早就在用的那个深度；改它要三档一起想');
    });

    test('非空类型也走同一件（续拉不是只为收件写的）', () async {
      final out = await drainAllPages<int>((limit, offset) async {
        return offset == 0 ? List<int>.filled(limit, 7) : const [1];
      }, pageSize: 2);
      expect(out, [7, 7, 1]);
    });
  });
}
