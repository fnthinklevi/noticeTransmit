import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T140 层2 的三件事：读数两侧同源、cancel 不许抹掉那段历史、判据只有一个作者。
///
/// 为什么钉源码而不是行为：这一族的失败要等一次"进程被 ROM 杀掉 / 被限流撤过"才现形，
/// 而那在测试里复现不出来。所以钉的是**链条每环都还在、且两端说的是同一枚键名**。
void main() {
  final root = projectRoot();
  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  final kotlinAlarm = read(
    'android/app/src/main/kotlin/com/fnthink/notice/FnthinkPresenceAlarm.kt',
  );
  final kotlinHandler = read(
    'android/app/src/main/kotlin/com/fnthink/notice/channels/FnthinkChannelHandler.kt',
  );
  final dartScheduler = read('lib/services/fnthink_presence_scheduler.dart');
  final dartPage = read('lib/pages/fnthink_receive_page.dart');

  test('交付给 Dart 的那三枚读数，键名两侧同源（派生，不重抄）', () {
    final sent = RegExp(
      r'"([A-Za-z]+)"\s+to\s+alarm\.([A-Za-z]+)\(\)',
    ).allMatches(kotlinHandler).map((m) => m.group(1)!).toSet();
    expect(
      sent,
      containsAll(<String>['nextRoundAt', 'cadenceSeconds', 'everArmedAt']),
      reason: '少交一枚，界面就少一种说法 —— 而"链死了"正是缺的那一种',
    );
    for (final key in sent) {
      expect(
        dartScheduler,
        contains("['$key']"),
        reason: '原生回 $key 而 Dart 不读 ⇒ 这一枚是装饰性的声明，静默消失',
      );
    }
  });

  test('cancel 只清"下一颗在哪儿"，不许清掉"曾经排上过"那一枚', () {
    final cancel = kotlinAlarm.substring(kotlinAlarm.indexOf('fun cancel()'));
    final body = cancel.substring(0, cancel.indexOf('\n    }'));
    expect(
      body.contains('KEY_NEXT_AT, 0L') && body.contains('KEY_CADENCE, 0L'),
      isTrue,
      reason: '这两个必须清：留着界面会拿一个已过期的时间点说"下一次在几点"',
    );
    expect(
      body.contains('KEY_EVER_ARMED_AT'),
      isFalse,
      reason:
          '清了它，"被撤过"与"从没排过"就再也分不开 ⇒ 真凶那一次（cancel 之后 13.5 小时无闹钟）'
          '会被界面报成"刚开起来"，链死可见这件事当场落空',
    );
  });

  test('排上才记"曾经"：两处 NEXT_AT 的写点都必须走同一个 markArmed', () {
    expect(
      RegExp('markArmed\\(').allMatches(kotlinAlarm).length,
      greaterThanOrEqualTo(3),
      reason: '一处定义 + 精确/非精确两个排程出口各一次；自己裸写 NEXT_AT 的那一条路会漏掉这枚戳',
    );
    expect(
      RegExp('putLong\\(KEY_NEXT_AT, fireAt').allMatches(kotlinAlarm).length,
      1,
      reason:
          '排上时的写点必须只剩 markArmed 里那一处（cancel 那一处写的是 0L，不算：'
          '它清的是"下一颗在哪儿"，不是"曾经排上过"）',
    );
  });

  test('四档判据只有一个作者：页面不自己比零、也不自己判 armed', () {
    expect(
      dartPage,
      contains('judgePresenceLiveness('),
      reason: '页面绕开那一位作者，就是长出第二份"什么叫死了"',
    );
    expect(
      RegExp(r'nextRoundAt\s*[=!]=\s*0|status\.armed').hasMatch(dartPage),
      isFalse,
      reason: '页面自己比零 / 自己读 armed ⇒ 第二份"什么叫死了"长出来了',
    );
    expect(
      RegExp('judgePresenceLiveness\\(').allMatches(dartPage).length,
      1,
      reason: '调两次就是在两处各自解释一遍档位 —— 判据要只有一个落点',
    );
  });
}
