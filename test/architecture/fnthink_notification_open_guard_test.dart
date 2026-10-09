import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// 点通知 → 跳到「历史页 + 展开这一条」那一条链的**跨语言**接线守卫（T83）。
///
/// T125 补：**反向的 null 语义那一对**（冷启动 null 不跳／热恢复 null 也要开列表）也钉在这一份里 ——
/// 那一对少任何一条都是缺陷（拿一个方向的对换另一个方向的错）。原生侧"推的时机"由 JVM 守卫
/// `FnthinkNotificationOpenGuardTest` 钉形状。
///
/// 钉的全是"改一边、另一边不会报错"的那些地方：通道方法名与 Intent 键名都是字符串，
/// 编译器与运行时都不喊。名字一律从 Kotlin 侧**派生** —— 本仓库的教训是守卫自己重打一份
/// 字面量 = 第二份可以朝同一个方向写错，而那时两侧编译与全部测试仍然绿。
void main() {
  final root = projectRoot();
  String read(String rel) =>
      File('$root/$rel').readAsStringSync().replaceAll('\r\n', '\n');

  const activity =
      'android/app/src/main/kotlin/com/fnthink/notice/MainActivity.kt';
  const displayKt =
      'android/app/src/main/kotlin/com/fnthink/notice/FnthinkInboxDisplay.kt';
  const handler =
      'android/app/src/main/kotlin/com/fnthink/notice/channels/FnthinkChannelHandler.kt';
  const display = 'lib/services/fnthink_inbox_display.dart';
  const mainPage = 'lib/pages/main_page.dart';
  const actions = 'lib/pages/main_page_actions.dart';
  const historyPage = 'lib/pages/history_page.dart';

  /// Dart 侧调用/处理的那一端：`"name" ->` 的分支形态（与 channel_method_parity 同一口径）。
  String pullMethodFromKotlin() {
    final src = stripComments(read(handler));
    return RegExp(r'"([A-Za-z_]*OpenTarget)"\s*->').firstMatch(src)?.group(1) ??
        fail('原生侧已经没有"取走要跳的那一条"那枚方法分支了 ⇒ 这条守卫要跟着改口径');
  }

  String wakeMethodFromKotlin() {
    final src = stripComments(read(activity));
    return RegExp(
          r'''invokeMethod\("([A-Za-z_]*NotificationOpened)"''',
        ).firstMatch(src)?.group(1) ??
        fail(
          '原生侧不再推那一发讯号 ⇒ App 活着时点通知没有人跳，'
          '而那正是 T83 的原始缺陷（三种进入形状里的热恢复那一半）',
        );
  }

  group('跨语言的那三个名字', () {
    test('拉的那枚方法名两侧同一个（Dart 调用点从原生派生）', () {
      final name = pullMethodFromKotlin();
      expect(
        stripComments(read(display)),
        contains("'$name'"),
        reason:
            '原生改了名而 Dart 还调旧的 ⇒ invokeMethod 抛 MissingPluginException，'
            '被兜底成 null，表现是"点了通知只打开软件"（与这片要修的缺陷同形）',
      );
    });

    test('推的那枚方法名两侧同一个（Dart 侧的 handler 认它）', () {
      final name = wakeMethodFromKotlin();
      expect(
        stripComments(read(mainPage)),
        contains("'$name'"),
        reason: '原生推了而没人接 = 静默丢；Dart 装了 handler 而原生那头发的是别的名字 = 同样没人跳',
      );
    });

    test('extra 的键名只有一个作者：Dart 侧不许重打一遍', () {
      final literal = RegExp(
        r'EXTRA_MESSAGE_ID\s*=\s*"([^"]+)"',
      ).firstMatch(read(displayKt));
      expect(literal, isNotNull, reason: '键名的作者换了地方 ⇒ 派生的源头没了，这条守卫要跟着改口径');
      final value = literal!.group(1)!;
      for (final rel in [display, mainPage, actions, historyPage]) {
        expect(
          read(rel),
          isNot(contains(value)),
          reason: '$rel 里出现了原生那个 extra 的键名字面量：两份字面量可以朝同一个方向写错',
        );
      }
    });
  });

  group('Dart 侧那一半的形状', () {
    test('冷启动那一路由 Dart 主动拉，且排在第一帧之后', () {
      final src = stripComments(read(mainPage));
      expect(
        src,
        contains('addPostFrameCallback'),
        reason: '在 handler 装好之前拉等于没拉；这一发要排在第一帧之后',
      );
      expect(
        src,
        contains('_consumeNotificationOpenTargetOnLaunch()'),
        reason: '冷启动那一枚没人取 ⇒ 进程被杀之后从通知进来还是"只打开软件"',
      );
    });

    test('两条落点都是历史页的收件档，并把那一条带下去', () {
      final src = stripComments(read(actions));
      for (final entry in [
        '_consumeNotificationOpenTargetOnLaunch',
        '_openFnthinkMessageFromNotification',
      ]) {
        final start = src.indexOf('Future<void> $entry');
        expect(start, isNonNegative, reason: '少了一路：$entry');
        final body = src.substring(start, start + 600).split('\n  }').first;
        expect(
          body,
          contains("direction: 'received'"),
          reason: '通知只会由收件那一档产生：落到转发档就是"点了一条却看见别的账本"',
        );
        expect(
          body,
          contains('focusMessageId:'),
          reason: '没把那一条带下去 ⇒ 页面只被告知"停在收件档"，展开哪一行没人负责',
        );
      }
    });

    test('兑现点只挂在「这一次进入」那一发读表上（防"详情关不掉"）', () {
      final src = stripComments(read(historyPage));
      // 定义那一处写作 `_applyPendingFocus() {`，调用点写作 `_applyPendingFocus()`：
      // 只有后者算数。两处调用点（initState 与标已读后的重读）＝ 用户按了返回它又起来。
      final callSites = RegExp(
        r'_applyPendingFocus\(\)(?!\s*\{)',
      ).allMatches(src).length;
      expect(
        callSites,
        1,
        reason:
            '兑现点多于一个 ⇒ 展开之后的那一次重读会把详情再弹一遍，'
            '那一条详情就关不掉了',
      );
      final loadBody = src.substring(
        src.indexOf('Future<void> _loadInbox() async {'),
      );
      expect(
        loadBody.split('\n  }').first,
        isNot(contains('_applyPendingFocus')),
        reason: '要挂在"这一次进入"的那一发读表上，而不是任何一次读表上',
      );
    });

    test('两个方向的 null 语义同时成立：冷启动 null 不跳；热恢复 null 也要开列表', () {
      // T125：这一对是**反向**的 —— 钉死一条、丢掉另一条都是缺陷（少一条 = 拿一个方向的
      // 对换另一个方向的错）。原生侧"推的时机"由 JVM 守卫钉形状；这一条钉 Dart 侧
      // 收到／没收到讯号之后各自的判法。
      final src = stripComments(read(actions));
      final cold = blockAfter(
        src,
        'Future<void> _consumeNotificationOpenTargetOnLaunch()',
      );
      final warm = blockAfter(
        src,
        'Future<void> _openFnthinkMessageFromNotification()',
      );
      expect(
        cold,
        contains('if (messageId == null || !mounted) return;'),
        reason: '冷启动这一发每次打开 App 都跑，"没有待跳的那条"是常态 —— 不早退就是"每次启动都被送到历史页"',
      );
      expect(
        warm,
        isNot(contains('messageId == null')),
        reason: 'T125：不许改成"Dart 侧 null 就不跳" —— 那会把 T83 判据③（点了通知却什么都不发生）原样放回来',
      );
      expect(
        warm,
        contains('if (!mounted) return;'),
        reason: '热恢复这一发只有"页面没了"才早退；id 拿不到也要把列表打开',
      );
      expect(
        warm,
        contains(
          "_openHistoryPage(direction: 'received', focusMessageId: messageId);",
        ),
        reason: '拿不到 id 就把 null 传下去（focusMessageId 可空）—— 展开哪一行没人负责这件事由历史页兜',
      );
    });
  });
}
