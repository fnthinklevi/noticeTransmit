import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// #94-A 的跨端契约：`drainOfflineCache` 的载荷形状 + 那条队列的落盘形状。
///
/// 为什么单独钉：这条链的两端在两个语言里各写一遍键名，**改一边而另一边没跟上时不会有任何
/// 编译错误** —— Dart 读不到 `records` 就当"没有离线通知"，用户的历史静默少一批。
/// 键名从 Kotlin 侧**派生**（本仓库的教训：守卫自己重打一份字面量 = 第二份可以朝同一方向写错）。
///
/// ⚠ T133 量级②换了载体（SharedPreferences 里那根 JSON 数组 → 追加式行文件），下面三条按新形状
/// 重指：原来钉的是「记录与计数同一次 commit」「remove 只回写不清零」，钉的都是"两处写会漂"这一族；
/// 新形状里同一族风险换了名字 —— 交付要写回余下的那批、remove 不该碰计数、重写必须走临时件。
void main() {
  final root = projectRoot();
  String read(String rel) =>
      File('$root/$rel').readAsStringSync().replaceAll('\r\n', '\n');

  const handler =
      'android/app/src/main/kotlin/com/fnthink/notice/channels/StatsChannelHandler.kt';
  const cache =
      'android/app/src/main/kotlin/com/fnthink/notice/HistoryCache.kt';
  const service = 'lib/services/notification_service.dart';

  test('原生交付的键名与 Dart 读取的键名是同一对（派生，不重抄）', () {
    final kt = stripComments(read(handler));
    final branch = kt.substring(kt.indexOf('"drainOfflineCache"'));
    final recordsKey = RegExp(
      r'"([A-Za-z_]+)"\s+to\s+drained\.records',
    ).firstMatch(branch)?.group(1);
    final droppedKey = RegExp(
      r'"([A-Za-z_]+)"\s+to\s+drained\.dropped',
    ).firstMatch(branch)?.group(1);
    // T133 量级②新增的第三枚：原生一次只交一批，"还有没有"由这一键说。
    // 它比前两枚更容易静默 —— 缺了它 Dart 只会当"没有下一批"，历史只进来头一批。
    final truncatedKey = RegExp(
      r'"([A-Za-z_]+)"\s+to\s+drained\.truncated',
    ).firstMatch(branch)?.group(1);
    expect(recordsKey, isNotNull, reason: '原生不再用 records 交记录 ⇒ 这条契约要跟着改');
    expect(droppedKey, isNotNull, reason: '原生不再交丢弃数 ⇒ #94-A 的可见性落空了');
    expect(
      truncatedKey,
      isNotNull,
      reason: '原生不再报"还有没有" ⇒ Dart 一句都不会续拉，分批交付退化成只取头一批',
    );

    final dart = stripComments(read(service));
    expect(
      dart,
      contains("['$recordsKey']"),
      reason: '原生回 $recordsKey，Dart 读的却是别的名字 ⇒ 离线通知会静默不合并',
    );
    expect(
      dart,
      contains("['$droppedKey']"),
      reason: '原生回 $droppedKey，Dart 不读 ⇒ 丢弃条数到了 Dart 这边又变成无声',
    );
    expect(
      dart,
      contains("['$truncatedKey']"),
      reason: '原生回 $truncatedKey，Dart 不读 ⇒ 交接不再"排到没了为止"',
    );
  });

  test('交付时把没交走的那批写回队列，并连同溢出计数一起清', () {
    final src = stripComments(read(cache));
    final drain = src.substring(src.indexOf('fun drainAll('));
    final body = drain.substring(0, drain.indexOf('\n    }'));
    expect(
      body.contains('writeLines(context, remaining)') &&
          body.contains('.remove(KEY_DROPPED)'),
      isTrue,
      reason:
          '分批之后"清干净"是两件事：余下的必须写回队列文件，计数必须一起清。'
          '只做一个 ⇒ 要么下次冷启动同一批"丢了 N 条"再报一遍，要么没交付的那批凭空蒸发',
    );
    expect(
      body.contains('.delete()'),
      isFalse,
      reason: '整份删文件 = 把这一批之外的记录一起删了 —— 那比旧的 500 条上限更狠',
    );
  });

  test('确认送达只动记录，不许顺手清掉未报的溢出计数', () {
    final src = stripComments(read(cache));
    final fn = src.substring(src.indexOf('fun remove('));
    final body = fn.substring(0, fn.indexOf('\n    }'));
    expect(body, contains('tombstoneLine('));
    expect(
      body.contains('KEY_DROPPED'),
      isFalse,
      reason: 'remove 里碰计数 ⇒ 用户可能永远看不到"期间丢了 N 条"（计数只该由交付那一发清）',
    );
  });

  test('队列重写走临时件＋rename（半截文件会让整条离线兜底失效）', () {
    final src = stripComments(read(cache));
    final fn = src.substring(src.indexOf('private fun writeLines('));
    final body = fn.substring(0, fn.indexOf('\n    }'));
    expect(
      body.contains('.tmp') && body.contains('renameTo('),
      isTrue,
      reason:
          '直接往队列文件里写：进程写一半被杀，留下的不是"上一份完整队列"而是半截文件，'
          '而读它的那一句会把整条兜底判成空',
    );
  });
}
