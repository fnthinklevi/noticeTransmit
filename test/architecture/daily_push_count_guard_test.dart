import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T131：「当日已推送 X 条」这一句话只有一个作者（跨语言那一半的账）。
///
/// 报上来的现象是「暂停转发推送时，通知栏依然显示当日已推送 X 条，且还在递增」。
/// 根因不是某一处写错，而是**同一条句子上住着三个口径**：服务里的内存计数（每次扇出 +1，
/// 不看暂停闸）、桌面小部件的计数（每次写历史 +1，连被规则拦下的都算）、以及 Flutter
/// 启动/恢复时把 DB「今日记录数」灌回原生基数那一发（同一天还取较大值）。
/// 三份里任何一份单独改对都没用 —— 另外两份会在下一次重启/恢复时把错补回来。
///
/// 所以这一族守卫钉的是"只剩一份"，而不是"某一行现在是对的"：
/// 旧作者的**名字**全库零命中、累加点**枚数**为一、两个读数（栏里 / 桌面上）读同一个口子。
void main() {
  final root = projectRoot();

  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  /// 原生侧全部 Kotlin 源码（剥注释后的拼接）。
  String kotlinAll() {
    final dir = Directory(
      '$root/android/app/src/main/kotlin/com/fnthink/notice',
    );
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.kt'))
        .toList();
    expect(files, isNotEmpty, reason: '原生源码目录读空了 ⇒ 下面的"零命中"全是假绿');
    return files.map((f) => stripComments(f.readAsStringSync())).join('\n');
  }

  String libAll() {
    final dir = Directory('$root/lib');
    final files = dir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty, reason: 'lib/ 读空了 ⇒ 零命中同样是假绿');
    return files.map((f) => stripComments(f.readAsStringSync())).join('\n');
  }

  group('T131：当日已推送只有一个作者', () {
    test('三个旧作者的名字两侧都零命中（不许有人把它接回来）', () {
      final native = kotlinAll();
      final dartSide = libAll();
      for (final dead in [
        'pushCount',
        'WidgetDailyCounter',
        'syncDailyPushCount',
        'syncDailyCountToNative',
      ]) {
        expect(
          native.contains(dead),
          isFalse,
          reason: '`$dead` 还在原生里 ⇒ 第二份"当日"口径没拆干净（T131）',
        );
        expect(
          dartSide.contains(dead),
          isFalse,
          reason: '`$dead` 还在 lib/ 里 ⇒ Flutter 又有了替原生作数的那一发（T131）',
        );
      }
    });

    test('累加点全库一枚，且它读的暂停闸与发送器是同一个作者', () {
      final native = kotlinAll();
      expect(
        'DailyPushCounter.record('.allMatches(native).length,
        1,
        reason: '多一枚 ⇒ 又回到"五个调用点各写一遍"；少一枚 ⇒ 那个数字没人涨了',
      );
      // 判据必须读 PushToggleManager.isPushActive() —— 那正是 NetworkClient / 幻念 / 邮件
      // 三处发送闸用的同一个作者。另判一次就会出现"闸拦住了、计数照涨"。
      expect(
        native.contains('DailyPushCounter.countsAsPush('),
        isTrue,
        reason: '扇出前没走那条判据 ⇒ 暂停态下数字还会涨',
      );
      final gate = native.indexOf('DailyPushCounter.countsAsPush(');
      expect(
        native
            .substring(gate, gate + 260)
            .contains('PushToggleManager.isPushActive()'),
        isTrue,
        reason: '判据没接在暂停闸那一个作者上 ⇒ 两处口径会分叉',
      );
    });

    test('栏里那两句与桌面上那句，三个读数全走同一个口子', () {
      final native = kotlinAll();
      // 三处 = 常驻通知的两态（监听中／已暂停，同一句话的两种时态）+ 桌面小部件那句。
      // 长出第四处 ⇒ 又有一个显示面在别处取数；少一处 ⇒ 有一个显示面没人作了。
      expect(
        'DailyPushCounter.todayCount('.allMatches(native).length,
        3,
        reason: '三个读数（栏里两态 + 小部件）必须都读这一个作者',
      );
      expect(
        read(
          'android/app/src/main/kotlin/com/fnthink/notice/I18n.kt',
        ).contains('当日已推送'),
        isTrue,
        reason: '那句话还在（改的是数，不是把句子藏起来）',
      );
    });

    test('另一个口径（今日记录数）没被牵连：首页统计仍走 DB', () {
      // 「今日记录数」与「当日已推送」是两件事，这一条钉的是前者没被顺手改成后者。
      expect(
        read(
          'lib/services/notification_service.dart',
        ).contains('getTodayCount'),
        isTrue,
        reason: '今日记录数没了 ⇒ 统计页那个数就没人作了',
      );
      expect(
        read('lib/pages/stats_page.dart').contains('getTodayCount'),
        isTrue,
        reason: '统计页不再读今日记录数 ⇒ 它显示的到底是什么要说清',
      );
    });
  });
}
