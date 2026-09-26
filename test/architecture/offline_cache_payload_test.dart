import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// #94-A 的跨端契约：`drainOfflineCache` 的载荷形状。
///
/// 为什么单独钉：这条链的两端在两个语言里各写一遍键名，**改一边而另一边没跟上时不会有任何
/// 编译错误** —— Dart 读不到 `records` 就当"没有离线通知"，用户的历史静默少一批。
/// 键名从 Kotlin 侧**派生**（本仓库的教训：守卫自己重打一份字面量 = 第二份可以朝同一方向写错）。
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
    expect(recordsKey, isNotNull, reason: '原生不再用 records 交记录 ⇒ 这条契约要跟着改');
    expect(droppedKey, isNotNull, reason: '原生不再交丢弃数 ⇒ #94-A 的可见性落空了');

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
  });

  test('交付时记录与溢出计数一起清（只清一个就会重复提示或永久漏提示）', () {
    final src = stripComments(read(cache));
    final drain = src.substring(src.indexOf('fun drainAll('));
    final body = drain.substring(0, drain.indexOf('\n    }'));
    expect(
      body.contains('.remove(KEY_RECORDS)') &&
          body.contains('.remove(KEY_DROPPED)'),
      isTrue,
      reason: '只清记录 ⇒ 计数留着，下次冷启动同一批"丢了 N 条"再报一遍',
    );
  });

  test('确认送达只动记录，不许顺手清掉未报的溢出计数', () {
    final src = stripComments(read(cache));
    final fn = src.substring(src.indexOf('fun remove('));
    final body = fn.substring(0, fn.indexOf('\n    }'));
    expect(
      RegExp(r'writeArray\([^)]*getInt\(KEY_DROPPED').hasMatch(body),
      isTrue,
      reason: 'remove 里把计数写回 0 ⇒ 用户可能永远看不到"期间丢了 N 条"',
    );
  });

  test('记录与计数必须同一次 commit 落盘（分两次写就有半状态）', () {
    final src = stripComments(read(cache));
    final fn = src.substring(src.indexOf('private fun writeArray('));
    final body = fn.substring(0, fn.indexOf('\n    }'));
    expect(body, contains('.putString(KEY_RECORDS'));
    expect(body, contains('.putInt(KEY_DROPPED'));
    expect(body, contains('.commit()'));
    expect(body.contains('.apply()'), isFalse, reason: '异步落盘会丢计数（进程被杀时）');
  });
}
