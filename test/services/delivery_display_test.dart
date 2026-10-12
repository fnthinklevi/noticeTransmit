import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/services/delivery_display.dart';
import 'package:notice_transmit/theme/app_colors.dart';

/// T150 片1（维护者 2026-10-12 第 6 条：「推送已暂停时为什么一直显示发送中」）。
///
/// 这一格原先是页面里的一个 `switch`，而它的 `default:` 返回「发送中」。两个后果：
/// 1. 任何**对不上号**的状态串（词表外的新值、写坏的旧值）都被界面说成"这条正在发"；
/// 2. 「发送中」于是成了兜底读数 ⇒ 没人会来回执的那些键（`role=none`）也永远亮着这一句。
/// 现在词表只有一个作者：认不出的说「状态未知」，而「发送中」只剩一个来路 ——
/// 入库瞬间写下的 `pending`，且**只有还会被人来回执的键**才拿得到它。
void main() {
  final zh = lookupAppLocalizations(const Locale('zh'));
  final en = lookupAppLocalizations(const Locale('en'));

  group('送达状态那一格只有一个作者', () {
    test('五个认得的状态各有一句，且互不相同', () {
      final said = <String, String>{
        for (final s in const [
          'success',
          'failed',
          'intercepted',
          'paused',
          'pending',
        ])
          s: deliveryStatusText(zh, s),
      };
      expect(said.values.toSet(), hasLength(5), reason: '两档共用一句话 = 这一档白分');
      expect(said['success'], zh.deliverySuccess);
      expect(said['failed'], zh.deliveryFailed);
      expect(said['intercepted'], zh.deliveryIntercepted);
      expect(said['pending'], zh.deliveryPending);
      // 暂停那一档要说的是**这条的下场**，不是"用户动了开关"（T138 ③）
      expect(said['paused'], zh.deliveryPausedNotSent);
      expect(said['paused'], contains('未发送'));
    });

    test('认不出的与空串都说「状态未知」，不许兜底成「发送中」', () {
      for (final weird in const ['sending', 'PENDING', '', 'queued', 'null']) {
        expect(
          deliveryStatusText(zh, weird),
          zh.deliveryUnknown,
          reason:
              '「$weird」不是这张表上的词 —— 兜底成「发送中」就是界面替本机造了一条在途任务'
              '（这正是维护者这次看到的：暂停期间那一格一直"发送中"）',
        );
        expect(deliveryStatusText(en, weird), en.deliveryUnknown);
      }
      expect(
        zh.deliveryUnknown,
        isNot(zh.deliveryPending),
        reason: '两句话若同义，这一档就白分了',
      );
    });

    test('「发送中」只跟着 pending 一个词，不跟着 default', () {
      // 这条盯的是形状：将来有人把 `default:` 又改回 deliveryPending，上面那条会红，
      // 而这一条说明**为什么**不许 —— 词表外的值不该有一个"看起来在途"的读数。
      for (final s in const ['success', 'failed', 'intercepted', 'paused']) {
        expect(deliveryStatusText(zh, s), isNot(zh.deliveryPending));
      }
      expect(deliveryStatusText(zh, 'pending'), zh.deliveryPending);
    });
  });

  group('颜色与文字同一次判定', () {
    testWidgets('未知不许画在途的蓝', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        CupertinoApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(
        deliveryStatusColor(ctx, 'sending'),
        isNot(deliveryStatusColor(ctx, 'pending')),
        reason: '一句「状态未知」配一枚在途的蓝点 = 两句谎互相壮胆',
      );
      expect(deliveryStatusColor(ctx, 'pending'), AppColors.blue);
      expect(deliveryStatusColor(ctx, 'success'), AppColors.green);
      expect(deliveryStatusColor(ctx, 'failed'), AppColors.red);
      expect(deliveryStatusColor(ctx, 'intercepted'), AppColors.orange);
      expect(deliveryStatusColor(ctx, 'paused'), AppColors.orange);
      for (final concluded in const [
        AppColors.blue,
        AppColors.green,
        AppColors.red,
        AppColors.orange,
      ]) {
        expect(
          deliveryStatusColor(ctx, ''),
          isNot(concluded),
          reason: '认不出的读数不许借用任何一种"有结论"的颜色',
        );
      }
    });
  });
}
