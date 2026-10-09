import 'dart:async';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/fnthink_remote_execution_record.dart';
import 'package:notice_transmit/services/fnthink_l2_actions.dart';
import 'package:notice_transmit/services/fnthink_l3_settings.dart';
import 'package:notice_transmit/services/fnthink_remote_command_handler.dart';
import 'package:notice_transmit/services/fnthink_remote_execution.dart';
import 'package:notice_transmit/services/fnthink_remote_runner.dart';
import 'package:notice_transmit/services/remote_execution_notifier.dart';

/// 远程执行 片3c-5：**状态栏那一枚通知**与「到点前问原生那一句」。
///
/// 这一组钉的是**撤销入口其二那条独有的路径**：用户在状态栏按了「撤销」，
/// 而 Dart 那一侧压根不在（后台轮次随时被回收 —— 那正是这一格存在的理由）。
/// 于是三件事必须各有一个用例：
///  ① 窗口一开始就在状态栏发一条（撤销入口之二在那儿）；
///  ② 到点动手前**问原生一句**；问了说"撤过" ⇒ 不动手，终态 `cancelled`
///     且理由是 `cancelled-from-status-bar`（不是用户撤的假话，也不是"没成"）；
///  ③ 没撤过 ⇒ 照常动手；**任何一次**到终点都把那一枚收掉
///     （留着"10 秒后执行"就是在骗用户"还有机会"）。
class _NoopL2 implements FnthinkL2Executor {
  final List<String> calls = [];

  @override
  Future<FnthinkL2Result> setListener({required bool enabled}) async {
    calls.add('setListener($enabled)');
    return const FnthinkL2Result.ok();
  }

  @override
  Future<FnthinkL2Result> toggleChannel(RemoteChannelTarget target) async =>
      const FnthinkL2Result.ok();

  @override
  Future<FnthinkL2Result> pushDeviceState() async => const FnthinkL2Result.ok();

  @override
  Future<String?> reportNotifications(int count) async => null;
}

class _NoopL3 implements FnthinkL3Executor {
  @override
  Future<bool> grant(FnthinkL3Setting setting) async => true;

  @override
  Future<bool> toggle(FnthinkL3Setting setting) async => true;
}

/// 原生那一侧的替身：记下"哪几条被用户在通知栏按掉了"。
class _FakeNotifier implements RemoteExecutionNotifier {
  final List<String> shown = [];
  final List<String> cleared = [];
  final Set<String> cancelledOutOfBand = {};

  @override
  Future<bool> show({
    required String execId,
    required String item,
    required int seconds,
  }) async {
    shown.add(execId);
    return true;
  }

  @override
  Future<void> clear(String execId) async => cleared.add(execId);

  @override
  Future<bool> takeCancelled(String execId) async =>
      cancelledOutOfBand.remove(execId);

  @override
  Future<void> forget(String execId) async {}

  /// 白名单那一路：原生那边攒着的（拿一条少一条）。
  final List<String> localInbox = [];
  final List<String> localTaken = [];

  @override
  Future<String?> takeLocalCommand() async {
    if (localInbox.isEmpty) return null;
    final body = localInbox.removeAt(0);
    localTaken.add(body);
    return body;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final contract = FnthinkContract.readFile();

  late _NoopL2 l2;
  late _FakeNotifier notifier;
  late List<FnthinkRemoteExecutionRecord> saved;
  late List<void Function()> fired;

  setUp(() {
    l2 = _NoopL2();
    notifier = _FakeNotifier();
    saved = [];
    fired = [];
  });

  RemoteCommandRunner runner() => RemoteCommandRunner(
    contract: contract,
    windowSeconds: () async => 10,
    l2: l2,
    l3: _NoopL3(),
    saveRecord: (r) async => saved.add(r),
    sendReceipt: (peer, receipt) async => true,
    sendReport: (peer, action, payload) async => true,
    now: () => DateTime.utc(2026, 10, 4, 12),
    schedule: (d, f) {
      fired.add(f);
      return Timer(const Duration(microseconds: 1), () {})..cancel();
    },
    statusBar: notifier,
  );

  RemoteCommandAccepted accepted() => const RemoteCommandAccepted(
    command: RemoteCommand(level: 'L2', item: 'listener:start'),
    sender: '8K3FJ6QPTM9WZ4VHNS',
    source: 'fnthink',
    credential: '',
    grantedKeys: <String>{},
  );

  group('状态栏撤销入口（片3c-5）', () {
    test('窗口一开始就在状态栏发一条', () async {
      final r = runner();
      addTearDown(r.dispose);
      final id = await r.run(accepted());
      expect(notifier.shown, [id]);
    });

    test('窗口 0（立刻执行）不发那条 —— 那一秒里用户看不到它', () async {
      // ⚠ 0 秒窗口没有"先看到再撤销"的余地 —— 发一条只亮 0 秒的通知，
      //   是通知栏的一次噪音（而且它会被立刻 clear，等于闪一下）。
      final r = RemoteCommandRunner(
        contract: contract,
        windowSeconds: () async => 0,
        l2: l2,
        l3: _NoopL3(),
        saveRecord: (x) async => saved.add(x),
        sendReceipt: (peer, receipt) async => true,
        sendReport: (peer, action, payload) async => true,
        now: () => DateTime.utc(2026, 10, 4, 12),
        schedule: (d, f) =>
            Timer(const Duration(microseconds: 1), () {})..cancel(),
        statusBar: notifier,
      );
      addTearDown(r.dispose);
      await r.run(accepted());
      expect(notifier.shown, isEmpty);
    });

    test('到点前问原生一句；它说撤过 ⇒ 不动手，终态 cancelled', () async {
      final r = runner();
      addTearDown(r.dispose);
      final id = await r.run(accepted());
      notifier.cancelledOutOfBand.add(id);

      fired.single();
      await Future<void>.delayed(Duration.zero);

      expect(l2.calls, isEmpty, reason: '用户在状态栏按了撤销，就必须不执行 —— 这一句问不到就等于按了没用');
      expect(saved.last.state, RemoteExecutionStates.cancelled);
      expect(saved.last.reason, 'cancelled-from-status-bar');
    });

    test('没被撤过 ⇒ 照常动手', () async {
      final r = runner();
      addTearDown(r.dispose);
      await r.run(accepted());
      fired.single();
      await Future<void>.delayed(Duration.zero);
      expect(l2.calls, ['setListener(true)']);
      expect(saved.last.state, RemoteExecutionStates.done);
    });

    test('到终点都收掉那一枚（留着"10 秒后执行"是在骗用户还有机会）', () async {
      final r = runner();
      addTearDown(r.dispose);
      final id = await r.run(accepted());
      fired.single();
      await Future<void>.delayed(Duration.zero);
      expect(notifier.cleared, contains(id));
    });

    test('窗口内从界面撤掉 ⇒ 那一枚也收掉', () async {
      final r = runner();
      addTearDown(r.dispose);
      final id = await r.run(accepted());
      expect(await r.cancel(id), isTrue);
      expect(notifier.cleared, contains(id));
    });

    test('第二段回执带上终态 cancelled（对面要知道它被撤了）', () async {
      final r = runner();
      addTearDown(r.dispose);
      final receipts = <RemoteReceipt>[];
      final withSpy = RemoteCommandRunner(
        contract: contract,
        windowSeconds: () async => 10,
        l2: l2,
        l3: _NoopL3(),
        saveRecord: (x) async => saved.add(x),
        sendReceipt: (peer, receipt) async {
          receipts.add(receipt);
          return true;
        },
        sendReport: (peer, action, payload) async => true,
        now: () => DateTime.utc(2026, 10, 4, 12),
        schedule: (d, f) {
          fired.add(f);
          return Timer(const Duration(microseconds: 1), () {})..cancel();
        },
        statusBar: notifier,
      );
      addTearDown(withSpy.dispose);
      final id = await withSpy.run(accepted());
      notifier.cancelledOutOfBand.add(id);
      fired.single();
      await Future<void>.delayed(Duration.zero);

      expect(receipts.length, 2);
      expect(receipts.last.state, RemoteExecutionStates.cancelled);
      expect(
        receipts.last.result,
        contract.remoteExecutionReceipts['finished'],
      );
    });
  });
}
