import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/services/delivery_display.dart';
import 'package:notice_transmit/services/fnthink_fanout_entrypoint.dart';
import 'package:notice_transmit/services/fnthink_receive_coordinator.dart';
import 'package:notice_transmit/theme/app_colors.dart';

/// 幻念设备档转发的**回执链**（T154 片1）。
///
/// 病灶（维护者 2026-10-15）：推送对象是幻念推送、目标设备未上线时，历史里那条
/// **永远显示「发送中」**。根因不是文案 —— 是**这条链上一处回执都没有**：
/// 入库时 `deliveryKeysOfActiveChannels` 照给了 `chan:fnthink` 一个初始 `pending`，
/// 而幻念设备档走的是「原生队列 → 后台 isolate → `sendNotice`」，
/// 全程没有任何一处把结果写回那一格 ⇒ 无论对面在不在线，那一格都停在 pending。
///
/// 已有的两条同类前科（本片照它们的形状做）：
///  - T150 片1：`role=none` 的通道领了 pending 却永远没有回执 ⇒ 不进键名单；
///  - T105 片③：收件侧拿回来的 receipts 此前解析出来就扔了 ⇒ 接上 `recordAck`。
///  这一片补的是**第三处**：发出去之后本机自己那一格。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('结局 → 状态词（FnthinkFanoutOutcome）', () {
    test('至少一条交给服务端 ⇒ queued（不是「已送达」也不是「发送中」）', () {
      expect(
        const FnthinkFanoutOutcome(sent: 1, failed: 0).status,
        'queued',
        reason:
            '服务端回 202 只是**入队**：对面可能一直不上线，'
            '说「已送达」是假话（2026-10-15 反馈里那条「一直发送中」的另一面）；'
            '而本机这一侧确实已经没有在途的东西了，说「发送中」也不对',
      );
    });

    test('两台中只成一台 ⇒ 仍算 queued（送达格按通道记，不按目标数）', () {
      expect(
        const FnthinkFanoutOutcome(sent: 1, failed: 1).status,
        'queued',
        reason:
            '`chan:fnthink` 只有一个格，而这一格要回答的是"本机还欠不欠这一次投递"；'
            '至少有一条交出去了 ⇒ 不欠。多目标细分属另一件事（片2 的子页）',
      );
    });

    test('一条都没交出去 ⇒ failed（本机自己没做成，与"对面没上线"是两件事）', () {
      expect(
        const FnthinkFanoutOutcome(sent: 0, failed: 2).status,
        'failed',
        reason: '全失败还写 queued 就是把本机自己的失败说成"已交给对面"',
      );
    });
  });

  group('状态词 → 屏上那一格（delivery_display）', () {
    late AppLocalizations l10n;
    setUp(() async {
      l10n = await AppLocalizations.delegate.load(const Locale('zh'));
    });

    test('queued 有自己的话，不落进"认不出"那一档', () {
      expect(
        deliveryStatusText(l10n, 'queued'),
        isNot(l10n.deliveryUnknown),
        reason:
            '认不出就会显示「未知」—— 而这一档的真实语义是明确的：'
            '本机已经交出去，等对面来取',
      );
      expect(
        deliveryStatusText(l10n, 'queued'),
        isNot(l10n.deliveryPending),
        reason: '与「发送中」说成同一句 ⇒ 维护者报的那个现象原样留在屏上',
      );
      expect(
        deliveryStatusText(l10n, 'queued'),
        contains('待目标设备上线'),
        reason: '这一句要让人明白"现在在等什么"，否则用户不知道要不要做点什么',
      );
    });

    testWidgets('queued 有自己的点色（不许与在途的蓝同色）', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        CupertinoApp(
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(
        deliveryStatusColor(ctx, 'queued'),
        isNot(deliveryStatusColor(ctx, 'pending')),
        reason:
            '两档都画在途的蓝，屏上就分不出"本机还在发"与"本机发完了、球在对面"——'
            '而这两件事用户的动作完全不同（前者等，后者去把对面弄上线）',
      );
      expect(deliveryStatusColor(ctx, 'queued'), AppColors.teal);
    });
  });

  group('一轮转发之后的回执（fnthinkBackgroundFanoutRound）', () {
    late List<(String, FnthinkFanoutOutcome)> reported;
    late Future<void> Function(String, FnthinkFanoutOutcome) originalRecord;

    setUp(() {
      reported = [];
      originalRecord = recordFnthinkFanoutOutcome;
      recordFnthinkFanoutOutcome = (id, outcome) async {
        reported.add((id, outcome));
      };
    });

    tearDown(() {
      recordFnthinkFanoutOutcome = originalRecord;
    });

    test('发完一条就报一次，id 与逐条计数都对得上', () async {
      final parsed = parseFanoutBatch(
        jsonEncode([
          {
            'id': 'rec-1',
            'title': '标题一',
            'content': '正文一',
            'appName': '应用',
            'targets': [
              {'target': 'DEV-A'},
            ],
          },
          {
            'id': 'rec-2',
            'title': '标题二',
            'content': '正文二',
            'appName': '应用',
            'targets': [
              {'target': 'DEV-A'},
              {'target': 'DEV-B'},
            ],
          },
        ]),
      );
      expect(parsed.length, 2);

      // 直接把这两条交给那一轮的**发送循环**（跳过 prefs/原生队列那一层）。
      await _runItem(parsed[0]);
      await _runItem(parsed[1], failingTargets: {'DEV-B'});

      expect(reported.length, 2, reason: '整轮结束才报一次的话，两条通知混在一起谁也说不清哪条是哪条');
      expect(reported[0].$1, 'rec-1');
      expect(reported[0].$2.sent, 1);
      expect(reported[0].$2.failed, 0);
      expect(reported[0].$2.status, 'queued');
      expect(reported[1].$1, 'rec-2');
      expect(reported[1].$2.sent, 1);
      expect(reported[1].$2.failed, 1);
      expect(
        reported[1].$2.status,
        'queued',
        reason: '两台里成一台 ⇒ 本机不欠了（细则见上面那组）',
      );
    });

    test('全失败 ⇒ 报 failed，而不是把本机的失败说成"已交给对面"', () async {
      await _runItem(_item('rec-x', ['DEV-A']), failingTargets: {'DEV-A'});

      expect(reported.single.$2.sent, 0);
      expect(reported.single.$2.failed, 1);
      expect(reported.single.$2.status, 'failed');
    });

    test('回执自己抛异常 ⇒ 不把这一轮带走（后面那条照发照报）', () async {
      recordFnthinkFanoutOutcome = (id, outcome) async {
        reported.add((id, outcome));
        if (id == 'rec-1') throw StateError('写库失败');
      };
      final parsed = parseFanoutBatch(
        jsonEncode([
          {
            'id': 'rec-1',
            'title': 't1',
            'content': 'b1',
            'appName': 'a',
            'targets': [
              {'target': 'DEV-A'},
            ],
          },
          {
            'id': 'rec-2',
            'title': 't2',
            'content': 'b2',
            'appName': 'a',
            'targets': [
              {'target': 'DEV-A'},
            ],
          },
        ]),
      );
      await _runItem(_item('rec-1', ['DEV-A']));
      await _runItem(_item('rec-2', ['DEV-A']));

      expect(
        reported.map((r) => r.$1),
        ['rec-1', 'rec-2'],
        reason:
            '回执写不进去比"后面的通知没发出去"轻得多 —— '
            '发送已经成功，不该因为记账失败把整轮掐了',
      );
    });
  });
}

/// 跑**生产的那一个函数**（`sendAndReportFanoutItem`），只把"发给一台"换成假的。
///
/// ⚠ 这里**不许**照抄那段循环：抄一遍就是第二份判据（"至少一条成 ⇒ queued"
/// 与"回执失败不带走整轮"都要各自维护），两份迟早漂开 —— 本仓
/// `deliveryBucketOf` 那一轮漂开的正是这种形状。测试要钉的是**生产那句**。
Future<FnthinkFanoutOutcome> _runItem(
  FnthinkFanoutItem item, {
  Set<String> failingTargets = const {},
}) {
  return sendAndReportFanoutItem(
    item,
    sendToTarget: (target) async {
      if (failingTargets.contains(target)) {
        throw StateError('送到 $target 失败（反证用）');
      }
    },
  );
}

FnthinkFanoutItem _item(String id, List<String> targets) => FnthinkFanoutItem(
  id: id,
  title: '标题',
  text: '正文',
  appName: '应用',
  targets: targets,
);
