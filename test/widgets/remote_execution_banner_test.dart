import 'dart:async';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_l2_actions.dart';
import 'package:notice_transmit/services/fnthink_l3_settings.dart';
import 'package:notice_transmit/services/fnthink_remote_command_handler.dart';
import 'package:notice_transmit/services/fnthink_remote_runner.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/remote_execution_banner.dart';

/// 远程执行 片3c-4：**界面顶端横幅**（契约 `delay.cancelChannels` 的 `inAppBanner`）。
///
/// 这一组钉的是"用户真的看得见、也真的按得动"：
///  ① 没在窗口里 ⇒ **一个字都不画**（常驻一条横幅等于占着半个屏幕）；
///  ② 画出来了的那一句带 item 与**还剩几秒**（倒计时停住会让用户以为撤不掉了）；
///  ③ 按「撤销」⇒ 真的撤掉，横幅随即消失 —— 而那一格必须经 `runner.cancel`
///     而不是自己把那一行藏起来；
///  ④ 撤不掉时（已动手）不假装成功：那一句要说清撤不回来，
///     而界面**仍然把按钮收起来**（再点一次只会得到同一句话）。
class _NoopL2 implements FnthinkL2Executor {
  @override
  Future<FnthinkL2Result> setListener({required bool enabled}) async =>
      const FnthinkL2Result.ok();

  @override
  Future<FnthinkL2Result> toggleChannel(RemoteChannelTarget target) async =>
      const FnthinkL2Result.ok();

  @override
  Future<FnthinkL2Result> pushDeviceState() async => const FnthinkL2Result.ok();

  @override
  Future<String?> reportNotifications(int count) async => null;

  @override
  Future<FnthinkL2Result> ringAlert() async => const FnthinkL2Result.ok();

  @override
  Future<({String? payload, String? reason})> searchSms(String keyword) async =>
      (payload: null, reason: 'sms-search-disabled');

  @override
  Future<({bool ok, String? reason})> launchApp(String name) async =>
      (ok: false, reason: 'app-launch-unknown-name');
}

class _NoopL3 implements FnthinkL3Executor {
  @override
  Future<bool> grant(FnthinkL3Setting setting) async => true;

  @override
  Future<bool> toggle(FnthinkL3Setting setting) async => true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final contract = FnthinkContract.readFile();

  late List<void Function()> fired;
  var clock = DateTime.utc(2026, 10, 4, 12);
  late RemoteCommandRunner runner;

  setUp(() {
    fired = [];
    clock = DateTime.utc(2026, 10, 4, 12);
    runner = RemoteCommandRunner(
      contract: contract,
      windowSeconds: () async => 10,
      l2: _NoopL2(),
      l3: _NoopL3(),
      saveRecord: (_) async {},
      sendReceipt: (peer, receipt) async => true,
      sendReport: (peer, action, payload) async => true,
      now: () => clock,
      // 手动点火（横幅这一组关心的是"看得见、撤得动"，不是计时本身）
      // ⚗ 手动点火，且返回的那枚句柄**当场取消**：
      //   一枚活着的 Timer 在用例结束时会被框架拦下（"A Timer is still pending"），
      //   而 `addTearDown` 跑在那声拦截**之后** —— 也就是说想让用例绿，
      //   只能让这枚 Timer 在用例体内就结束。
      //   被测物拿到的仍然是一个 Timer 句柄（形状没变），只是它已经是取消态。
      schedule: (d, f) {
        fired.add(f);
        return Timer(const Duration(microseconds: 1), () {})..cancel();
      },
    );
    // ⚠ runner 自己也要 dispose：它替每一条指令排了一枚 Timer（就是上面那个替身
    //   `schedule` 的返回值），不撤就留下一枚 pending timer —— 框架会在每一条用例
    //   末尾当场拦下，而那声拦截拦的正是「执行链忘了撤窗口」这一类真实缺陷。
    addTearDown(runner.dispose);
  });

  RemoteCommandAccepted accepted() => const RemoteCommandAccepted(
    command: RemoteCommand(level: 'L2', item: 'listener:start'),
    sender: '8K3FJ6QPTM9WZ4VHNS',
    source: 'fnthink',
    credential: '',
    grantedKeys: <String>{},
  );

  Future<void> pumpBanner(
    WidgetTester tester, {
    void Function(bool)? onCancelled,
  }) async {
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: RemoteExecutionBanner(
          runner: runner,
          clock: () => clock,
          onCancelled: onCancelled,
        ),
      ),
    );
    await tester.pump();
  }

  group('界面顶端横幅', () {
    testWidgets('没有在窗口里的指令 ⇒ 一个字都不画', (tester) async {
      await pumpBanner(tester);
      expect(find.textContaining('远程指令'), findsNothing);
      expect(find.text('撤销'), findsNothing);
    });

    testWidgets('收了一条之后画出来，那一句带 item 与还剩几秒', (tester) async {
      await pumpBanner(tester);
      await runner.run(accepted());
      // 横幅靠 Listenable 即时重画（新指令 `notifyListeners()`），而倒计时那一拍
      // 由 Ticker 驱动 —— 走一秒保证它已经画过一次。
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('listener:start'), findsOneWidget);
      expect(find.textContaining('10'), findsOneWidget);
      expect(find.text('撤销'), findsOneWidget);
    });

    testWidgets('倒计时现算：时钟走了，横幅上那个数跟着走', (tester) async {
      await pumpBanner(tester);
      await runner.run(accepted());
      // 横幅靠 Listenable 即时重画（新指令 `notifyListeners()`），而倒计时那一拍
      // 由 Ticker 驱动 —— 走一秒保证它已经画过一次。
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('10'), findsOneWidget);

      clock = clock.add(const Duration(seconds: 4));
      await tester.pump();
      expect(find.textContaining('6'), findsOneWidget);
      expect(
        find.textContaining('10'),
        findsNothing,
        reason: '倒计时停住会让用户以为窗口过了却还留着「撤销」',
      );
    });

    testWidgets('按「撤销」⇒ 真的撤掉，横幅随即消失', (tester) async {
      bool? reported;
      await pumpBanner(tester, onCancelled: (ok) => reported = ok);
      await runner.run(accepted());
      // 横幅靠 Listenable 即时重画（新指令 `notifyListeners()`），而倒计时那一拍
      // 由 Ticker 驱动 —— 走一秒保证它已经画过一次。
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('撤销'), findsOneWidget);

      await tester.tap(find.text('撤销'));
      await tester.pump();

      expect(reported, isTrue);
      expect(find.text('撤销'), findsNothing);
      expect(find.textContaining('远程指令'), findsNothing);
      expect(runner.unsettledCount, 0);
      expect(
        find.textContaining('已撤销'),
        findsOneWidget,
        reason: '横幅直接消失的话，用户分不清「我撤成功了」与「它自己跑完了」',
      );
    });

    testWidgets('撤不掉时不假装成功，按钮收起来', (tester) async {
      bool? reported;
      await pumpBanner(tester, onCancelled: (ok) => reported = ok);
      await runner.run(accepted());
      // 到点并手动点火：执行已经在跑 ⇒ `cancel` 按设计回 false。
      fired.single();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      expect(
        find.text('撤销'),
        findsNothing,
        reason: '已动手的那一条撤不回来，不该还给一个按了没反应的按钮',
      );
      expect(reported, isNull);
    });
  });
}
