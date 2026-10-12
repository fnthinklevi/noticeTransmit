import 'dart:async';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/fnthink_remote_execution_record.dart';
import 'package:notice_transmit/services/fnthink_l2_actions.dart';
import 'package:notice_transmit/services/fnthink_l3_settings.dart';
import 'package:notice_transmit/services/fnthink_remote_command_handler.dart';
import 'package:notice_transmit/services/fnthink_remote_execution.dart';
import 'package:notice_transmit/services/fnthink_remote_outcome_words.dart';
import 'package:notice_transmit/services/fnthink_remote_runner.dart';
import 'package:notice_transmit/services/remote_execution_notifier.dart';

/// 远程执行 片3c-3：**执行链编排**（落历史 → 回执 → 延时窗口 → 动手 → 终态回执）。
///
/// 这一组钉的是那条链上的**次序**与**两段回执各发一次**，外加三件不做就一定会出的事：
///  ① 窗口内撤销 ⇒ 不动手，且回执带 `cancelled`（不是 `failed`）；
///  ② **已经动手的那一条不许撤** —— 界面不能给一个按了没反应的按钮；
///  ③ 进程重启后那批 `pending` 必须被扫成 `interrupted`，否则界面永远显示"待执行"
///     而撤销那一下点下去毫无反应（撤销靠的就是那个已经随进程死掉的 Timer）。
///
/// 时钟与延时都注入：这里不睡真表。
class _RecordingL2 implements FnthinkL2Executor {
  final List<String> calls = [];
  bool ok = true;

  /// 挂住这一次的执行（用来观察"已动手、还没做完"那个中间态）。
  ///
  /// ⚠ 这一格此前**没有任何用例能观察到**：`run()` 在窗口 0 时是一条同步 await 链，
  /// 走到 `started = true` 之后紧接着就 `_finish` 把工作集摘掉了 ——
  /// 于是「已动手的那一条不许撤」在外部看来与「已做完的那一条不许撤」完全一样，
  /// 摘掉那一格也照样全绿（反证 S3 实测：fake green）。
  /// 观测它必须把执行器挂住，让那个中间态在 `await` 上停一会儿。
  Completer<void>? gate;

  Future<void> _pass() async {
    final g = gate;
    if (g != null) await g.future;
  }

  @override
  Future<FnthinkL2Result> setListener({required bool enabled}) async {
    calls.add('setListener($enabled)');
    await _pass();
    return ok
        ? const FnthinkL2Result.ok()
        : const FnthinkL2Result.failed('nope');
  }

  @override
  Future<FnthinkL2Result> toggleChannel(RemoteChannelTarget target) async {
    calls.add('toggleChannel(${target.family}:${target.id}:${target.enabled})');
    await _pass();
    return ok
        ? const FnthinkL2Result.ok()
        : const FnthinkL2Result.failed('nope');
  }

  @override
  Future<FnthinkL2Result> pushDeviceState() async {
    calls.add('pushDeviceState()');
    await _pass();
    return ok
        ? const FnthinkL2Result.ok()
        : const FnthinkL2Result.failed('nope');
  }

  /// 回传那一条要回的那段正文（null = 这一步没做成）。
  String? reportPayload;

  @override
  Future<String?> reportNotifications(int count) async {
    calls.add('reportNotifications($count)');
    await _pass();
    return ok ? reportPayload : null;
  }

  @override
  Future<FnthinkL2Result> ringAlert() async {
    calls.add('ringAlert()');
    await _pass();
    return ok
        ? const FnthinkL2Result.ok()
        : const FnthinkL2Result.failed('alert-ring-refused');
  }

  /// 搜短信那一条要回的那段正文（null = 没成，理由看 reason）。
  ({String? payload, String? reason})? smsResult;

  @override
  Future<({String? payload, String? reason})> searchSms(String keyword) async {
    calls.add('searchSms($keyword)');
    await _pass();
    if (!ok) return (payload: null, reason: 'sms-search-failed');
    return smsResult ?? (payload: null, reason: 'sms-search-failed');
  }

  @override
  Future<({String? payload, String? reason})> searchCalls(
    String keyword,
  ) async {
    calls.add('searchCalls($keyword)');
    await _pass();
    if (!ok) return (payload: null, reason: 'calls-search-failed');
    return (payload: null, reason: 'calls-search-disabled');
  }

  @override
  Future<({String? payload, String? reason})> searchContacts(
    String keyword,
  ) async {
    calls.add('searchContacts($keyword)');
    await _pass();
    if (!ok) return (payload: null, reason: 'contacts-search-failed');
    return (payload: null, reason: 'contacts-search-disabled');
  }

  @override
  Future<({String? payload, String? reason})> getLocation() async {
    calls.add('getLocation()');
    await _pass();
    if (!ok) return (payload: null, reason: 'location-failed');
    return (payload: null, reason: 'location-disabled');
  }

  @override
  Future<({String? payload, String? reason})> snapPhoto() async {
    calls.add('snapPhoto()');
    await _pass();
    if (!ok) return (payload: null, reason: 'camera-snap-failed');
    return (payload: null, reason: 'camera-snap-disabled');
  }

  @override
  Future<({bool ok, String? reason})> launchApp(String name) async {
    calls.add('launchApp($name)');
    await _pass();
    return ok
        ? (ok: true, reason: null)
        : (ok: false, reason: 'app-launch-unknown-name');
  }
}

class _RecordingL3 implements FnthinkL3Executor {
  final List<String> calls = [];
  bool granted = true;
  bool toggled = true;

  @override
  Future<bool> grant(FnthinkL3Setting setting) async {
    calls.add('grant(${setting.key})');
    return granted;
  }

  @override
  Future<bool> toggle(FnthinkL3Setting setting) async {
    calls.add('toggle(${setting.key})');
    return toggled;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final contract = FnthinkContract.readFile();

  late _RecordingL2 l2;
  late _RecordingL3 l3;
  late List<FnthinkRemoteExecutionRecord> saved;
  late List<RemoteReceipt> receipts;
  late Timer Function(Duration, void Function()) schedule;
  var windowSeconds = 10;
  var receiptOk = true;
  final reports = <String>[];
  var reportOk = true;
  var clock = DateTime.utc(2026, 10, 4, 9);

  setUp(() {
    l2 = _RecordingL2()..gate = null;
    l3 = _RecordingL3();
    saved = [];
    receipts = [];
    windowSeconds = 10;
    receiptOk = true;
    reports.clear();
    reportOk = true;
    clock = DateTime.utc(2026, 10, 4, 9);
    // 手动点火：用例自己决定"到点没有"。
    schedule = (d, f) => Timer(const Duration(days: 1), () {});
  });

  RemoteCommandRunner runner({RemoteExecutionNotifier? statusBar}) =>
      RemoteCommandRunner(
        contract: contract,
        windowSeconds: () async => windowSeconds,
        l2: l2,
        l3: l3,
        saveRecord: (r) async => saved.add(r),
        sendReceipt: (peer, receipt) async {
          receipts.add(receipt);
          return receiptOk;
        },
        sendReport: (peer, action, payload) async {
          reports.add('$peer|$action|$payload');
          return reportOk;
        },
        now: () => clock,
        schedule: schedule,
        statusBar: statusBar,
        newId: (seed) => 'x${seed.length.toRadixString(16)}',
      );

  RemoteCommandAccepted accepted({
    String level = 'L2',
    String item = 'listener:start',
    String source = 'fnthink',
    Set<String> grantedKeys = const <String>{},
  }) => RemoteCommandAccepted(
    command: RemoteCommand(level: level, item: item),
    sender: '8K3FJ6QPTM9WZ4VHNS',
    source: source,
    credential: '',
    grantedKeys: grantedKeys,
  );

  group('次序：落一行 → 回第一段 → 到点 → 动手 → 回第二段', () {
    test('窗口 0 ⇒ 立刻动手，且回执两段各一次', () async {
      windowSeconds = 0;
      final r = runner();
      await r.run(accepted());
      expect(l2.calls, ['setListener(true)']);
      expect(receipts.length, 2);
      expect(receipts[0].state, isNull, reason: '第一段还没动手，没有终态');
      expect(receipts[1].state, RemoteExecutionStates.done);
      expect(saved.map((s) => s.state), [
        RemoteExecutionStates.pending,
        RemoteExecutionStates.done,
      ], reason: '同一行先 pending 后 done，exec_id 相同（靠覆盖写回）');
      expect(saved[0].execId, saved[1].execId);
      expect(r.unsettledCount, 0);
    });

    test('第一段回执**收到就发**，不等窗口走完', () async {
      final firedProbe = <void Function()>[];
      schedule = (d, f) {
        firedProbe.add(f);
        return Timer(const Duration(days: 1), () {});
      };
      final r = runner();
      await r.run(accepted());
      expect(receipts.length, 1, reason: '它在窗口走完之前就该到（10 秒的窗口谁也不该真等）');
      expect(receipts.single.state, isNull);
    });

    test('窗口 > 0 ⇒ 先只落 pending 与第一段回执，不动手', () async {
      final fired = <void Function()>[];
      schedule = (d, f) {
        fired.add(f);
        return Timer(const Duration(days: 1), () {});
      };
      final r = runner();
      final id = await r.run(accepted());
      expect(l2.calls, isEmpty, reason: '还在窗口里');
      expect(saved.single.state, RemoteExecutionStates.pending);
      expect(receipts.length, 1, reason: '第一段回执收到就发，不等窗口');
      expect(r.waitingCount, 1);
      expect(r.isUnsettled(id), isTrue);

      fired.single();
    });

    test('到点后第二次点火不再动手（Timer 只该走一次）', () async {
      final fired = <void Function()>[];
      schedule = (d, f) {
        fired.add(f);
        return Timer(const Duration(days: 1), () {});
      };
      final r = runner();
      await r.run(accepted());
      fired.single();
      fired.single();
      await Future<void>.delayed(Duration.zero);
      expect(l2.calls.length, 1);
      expect(receipts.length, 2);
    });
  });

  group('两段回执', () {
    test('词与状态都取自契约，不写死', () async {
      windowSeconds = 0;
      await runner().run(accepted());
      expect(receipts[0].result, contract.remoteExecutionReceipts['started']);
      expect(receipts[1].result, contract.remoteExecutionReceipts['finished']);
    });

    test('回执带得上 level/item，对面才能对回自己发的那一条', () async {
      windowSeconds = 0;
      await runner().run(accepted(item: 'channel:toggle/webhook:acme:off'));
      expect(receipts.first.level, 'L2');
      // ⚠ item 是**带斜杠参数的整串**（历史那一行也存整串）：
      //   拆开成两处之后，对面按 item 匹配就会永远对不上。
      expect(receipts.first.item, 'channel:toggle/webhook:acme:off');
    });

    test('送不出去不改执行状态（本机做完了就是做完了）', () async {
      windowSeconds = 0;
      receiptOk = false;
      await runner().run(accepted());
      expect(saved.last.state, RemoteExecutionStates.done);
      expect(receipts.length, 2, reason: '两段都该试一次，失败不吞掉后续那一段');
    });

    test('本机白名单触发那一路：落历史但**不发回执**', () async {
      windowSeconds = 0;
      await runner().run(
        accepted(source: contract.remoteExecutionLocalTriggerSource),
      );
      expect(l2.calls.length, 1, reason: '该动手还是要动手');
      expect(receipts, isEmpty, reason: '那一路上没有远端发送方可回');
      expect(saved.last.state, RemoteExecutionStates.done);
    });
  });

  group('撤销（状态栏与横幅共用的那一个咽喉）', () {
    test('窗口内撤销 ⇒ 不动手，终态是 cancelled 且理由说清是用户撤的', () async {
      final fired = <void Function()>[];
      schedule = (d, f) {
        fired.add(f);
        return Timer(const Duration(days: 1), () {});
      };
      final r = runner();
      final id = await r.run(accepted());
      expect(await r.cancel(id), isTrue);
      expect(l2.calls, isEmpty, reason: '撤了就不许动手');
      expect(saved.last.state, RemoteExecutionStates.cancelled);
      expect(saved.last.reason, 'cancelled-by-user');
      expect(receipts.last.state, RemoteExecutionStates.cancelled);
      expect(
        receipts.last.result,
        contract.remoteExecutionReceipts['finished'],
      );

      fired.single();
      await Future<void>.delayed(Duration.zero);
      expect(l2.calls, isEmpty, reason: '撤了之后那个到点也不许再动手');
      expect(r.waitingCount, 0);
      expect(r.unsettledCount, 0);
    });

    test('不认得的 exec_id ⇒ false（界面据此把那一格收起来）', () async {
      expect(await runner().cancel('nope'), isFalse);
    });

    test('已经做完的那一条 ⇒ false（做完就是终态，撤不回来）', () async {
      windowSeconds = 0;
      final r = runner();
      final id = await r.run(accepted());
      expect(await r.cancel(id), isFalse);
    });

    test('⚠ 已动手、还没做完的那一条 ⇒ 同样 false（把执行器挂住看这一格）', () async {
      // ⚠ 这一条是 `flight.started` 那一格**唯一**能观察到的地方：
      //   不挂住执行器的话，`run()` 是一条同步 await 链，走过 started 就到终态了，
      //   外部拿不到那个中间态 ⇒ 摘掉那一格也照样全绿（反证 S3 实测）。
      windowSeconds = 10;
      final firedProbe = <void Function()>[];
      schedule = (d, f) {
        firedProbe.add(f);
        return Timer(const Duration(days: 1), () {});
      };
      final gate = Completer<void>();
      l2.gate = gate;
      final r = runner();
      final id = await r.run(accepted());
      // 先在窗口里撤得掉（对照组）：那时还没动手。
      expect(r.isUnsettled(id), isTrue);

      // 到点：pending → executing，执行器挂住
      final void Function() fireNow = firedProbe.single;
      fireNow();
      await Future<void>.delayed(Duration.zero);
      expect(l2.calls.length, 1, reason: '到点了，该动手');
      expect(
        saved.last.state,
        RemoteExecutionStates.pending,
        reason: '还没回终态（执行器挂着）',
      );

      expect(await r.cancel(id), isFalse, reason: '已经动手的不许当成没发生：动作可能做完了一半');
      gate.complete();
      await Future<void>.delayed(Duration.zero);
      expect(
        saved.last.state,
        RemoteExecutionStates.done,
        reason: '撤不掉的那一条照常走到终态，不许停在 executing',
      );
    });
  });

  group('分档派发', () {
    test('L3 ⇒ 走设置表；延时窗口走完就是那一次确认', () async {
      windowSeconds = 0;
      await runner().run(accepted(level: 'L3', item: 'exact_alarm'));
      expect(l3.calls, ['grant(exact_alarm)']);
      expect(saved.last.state, RemoteExecutionStates.done);
    });

    test('L3 缺前置授权的那一项 ⇒ failed，理由逐字带上', () async {
      windowSeconds = 0;
      await runner().run(accepted(level: 'L3', item: 'collect_inbox'));
      expect(l3.calls, isEmpty);
      expect(saved.last.state, RemoteExecutionStates.failed);
      expect(saved.last.reason, startsWith('missing-grant:'));
    });

    test('⚠ 判定层把名单里那份授权传下来了 ⇒ 同一项到点真的动手', () async {
      // 这一条钉的是 `accepted.grantedKeys` **有人读**。它一度是个死字段：
      // 判定层已经放行（本机那一行勾了这项），而这一格拿空集再判一次 ⇒
      // 表现是"窗口走完、回执说 missing-grant 失败"，而名单明明写着勾过 ——
      // 两处的日志各自都说自己没错，最难查的那种。
      windowSeconds = 0;
      await runner().run(
        accepted(
          level: 'L3',
          item: 'collect_inbox',
          grantedKeys: const {'collect_inbox'},
        ),
      );
      expect(l3.calls, ['toggle(collect_inbox)']);
      expect(saved.last.state, RemoteExecutionStates.done);
      expect(saved.last.reason, isEmpty);
    });

    test('L1 的 item 落在 L3 那张表上 ⇒ 照样走设置表（并集表）', () async {
      windowSeconds = 0;
      await runner().run(accepted(level: 'L1', item: 'exact_alarm'));
      expect(l3.calls, ['grant(exact_alarm)']);
    });

    test('执行器说做不成 ⇒ failed，理由是它给的机器词', () async {
      windowSeconds = 0;
      l2.ok = false;
      await runner().run(accepted());
      expect(saved.last.state, RemoteExecutionStates.failed);
      expect(saved.last.reason, 'nope');
      expect(receipts.last.state, RemoteExecutionStates.failed);
    });
  });

  group('进程重启之后那批 pending', () {
    FnthinkRemoteExecutionRecord pendingRow(String id, String state) =>
        FnthinkRemoteExecutionRecord(
          execId: id,
          direction: kFnthinkRemoteDirectionIn,
          peerAddress: '8K3FJ6QPTM9WZ4VHNS',
          level: 'L2',
          item: 'listener:start',
          argument: '',
          state: state,
          source: 'fnthink',
          createdAt: 1,
        );

    test('扫一遍 ⇒ 全部记成 failed + interrupted（不偷偷补做）', () async {
      final swept = await runner().sweepInterrupted([
        pendingRow('a', RemoteExecutionStates.pending),
        pendingRow('b', RemoteExecutionStates.executing),
      ]);
      expect(swept, 2);
      expect(saved.map((s) => s.reason), ['interrupted', 'interrupted']);
      expect(
        saved.every((s) => s.state == RemoteExecutionStates.failed),
        isTrue,
      );
      expect(l2.calls, isEmpty, reason: '重启后自动补做 = 用户以为撤掉了其实又做了一遍');
    });

    test('已经在终态的行不碰（不许把 done 改写成 failed）', () async {
      final swept = await runner().sweepInterrupted([
        pendingRow('c', RemoteExecutionStates.done),
        pendingRow('d', RemoteExecutionStates.cancelled),
      ]);
      expect(swept, 0);
      expect(saved, isEmpty);
    });

    test('本进程正在跑的那些不扫（它们在工作集里，Timer 还活着）', () async {
      final fired = <void Function()>[];
      schedule = (d, f) {
        fired.add(f);
        return Timer(const Duration(days: 1), () {});
      };
      final r = runner();
      final id = await r.run(accepted());
      final swept = await r.sweepInterrupted([
        pendingRow(id, RemoteExecutionStates.pending),
      ]);
      expect(swept, 0);
      fired.single();
      await Future<void>.delayed(Duration.zero);
      expect(saved.last.state, RemoteExecutionStates.done);
    });
  });

  group('dispose', () {
    test('撤掉所有还在等窗口的（不给 orphan Timer 留活口）', () async {
      final fired = <void Function()>[];
      schedule = (d, f) {
        fired.add(f);
        return Timer(const Duration(days: 1), () {});
      };
      final r = runner();
      await r.run(accepted());
      expect(r.waitingCount, 1);
      r.dispose();
      expect(r.waitingCount, 0);
      expect(r.unsettledCount, 0);
    });
  });

  group('回传（T124 片B）：产出送去发起的那一台，送不到就算没做成', () {
    test('有产出 ⇒ 回传发给发起方，动作名是**不带参数的那一个**，终态 done', () async {
      windowSeconds = 0;
      l2.reportPayload = '07-12 09:31 微信 张三：晚上一起吃饭';
      final r = runner();
      await r.run(accepted(item: 'notifications:report/10'));
      expect(l2.calls, ['reportNotifications(10)']);
      expect(reports, [
        '8K3FJ6QPTM9WZ4VHNS|notifications:report|07-12 09:31 微信 张三：晚上一起吃饭',
      ], reason: '动作名若带上 /10，契约那张 reports 表就查不到标题（收件端认不出这是回传）');
      expect(saved.last.state, RemoteExecutionStates.done);
    });

    test('回传送不到 ⇒ 终态是 failed + report-not-sent（不是"做成了但对面没收到"）', () async {
      windowSeconds = 0;
      l2.reportPayload = 'X';
      reportOk = false;
      final r = runner();
      await r.run(accepted(item: 'notifications:report/10'));
      expect(saved.last.state, RemoteExecutionStates.failed);
      expect(saved.last.reason, 'report-not-sent');
      expect(receipts.last.state, RemoteExecutionStates.failed);
    });

    test('产不出正文（读库失败那一支）⇒ failed，且一次回传都不发', () async {
      windowSeconds = 0;
      l2.reportPayload = null;
      final r = runner();
      await r.run(accepted(item: 'notifications:report/10'));
      expect(reports, isEmpty);
      expect(saved.last.state, RemoteExecutionStates.failed);
      expect(saved.last.reason, 'report-failed');
    });

    test('没有产出的动作（listener:start）不许触发回传那一路', () async {
      windowSeconds = 0;
      final r = runner();
      await r.run(accepted());
      expect(reports, isEmpty, reason: 'payload 为空的 ok 结果不该借道回传');
    });

    test('sms:search 也走同一条回传（产出从 payload 出去）', () async {
      windowSeconds = 0;
      l2.smsResult = (payload: '07-12 09:31 10086 验证码 123456', reason: null);
      final r = runner();
      await r.run(accepted(item: 'sms:search/验证码'));
      expect(l2.calls, ['searchSms(验证码)']);
      expect(
        reports.single,
        '8K3FJ6QPTM9WZ4VHNS|sms:search|07-12 09:31 10086 验证码 123456',
      );
    });

    test('sms:search 没成（开关关着）⇒ failed 原样带上理由，且一次回传都不发', () async {
      windowSeconds = 0;
      l2.smsResult = (payload: null, reason: 'sms-search-disabled');
      final r = runner();
      await r.run(accepted(item: 'sms:search/验证码'));
      expect(reports, isEmpty);
      expect(saved.last.state, RemoteExecutionStates.failed);
      expect(saved.last.reason, 'sms-search-disabled');
    });
  });

  // ── T144 片2 格①（维护者 2026-10-12 第 2 条：失败**和成功都要有原因**）────────
  // 这一列以前**没有作者**：成功时 `result` 抄的是 `reason`（而成功时那是 null）⇒ 状态
  // 「执行完毕」配两格空白；失败时同一个机器词又被抄进两格，界面上两句一模一样。
  // 现在两列各管一件事：`result` = 本机做成了哪一步（只由那张封闭词表给），
  // `reason` = 为什么没成／为什么被拦。
  group('做成的那一条也要有读数（T144 片2 格①）', () {
    test('没有产出的动作做成 ⇒ result 写 performed，reason 仍留空', () async {
      windowSeconds = 0;
      await runner().run(accepted());
      expect(saved.last.state, RemoteExecutionStates.done);
      expect(
        saved.last.result,
        kFnthinkRemoteOutcomePerformed,
        reason: '成功时两格全空 = 界面只说"完毕了"，不说做成了什么',
      );
      expect(saved.last.reason, isEmpty);
    });

    test('有产出且真送出去了 ⇒ 写的是 reported，不是泛泛的"做完了"', () async {
      windowSeconds = 0;
      l2.reportPayload = '07-12 09:31 微信 张三：晚上一起吃饭';
      await runner().run(accepted(item: 'notifications:report/10'));
      expect(
        saved.last.result,
        kFnthinkRemoteOutcomeReported,
        reason: '这一族动作的全部产出就是那段回传：它到了对面手里，才是这一格该说的事',
      );
    });

    test('回传送不到 ⇒ 没有读数（不许留一个 reported 说产出已到手）', () async {
      windowSeconds = 0;
      l2.reportPayload = 'X';
      reportOk = false;
      await runner().run(accepted(item: 'notifications:report/10'));
      expect(
        saved.last.result,
        isEmpty,
        reason: 'failed 那一行还写着"已送回对面"，就是界面替本机编一句话',
      );
    });

    test('L3 那一档做成 ⇒ 写的是 set（改到位这件事本身）', () async {
      windowSeconds = 0;
      await runner().run(accepted(level: 'L3', item: 'exact_alarm'));
      expect(saved.last.state, RemoteExecutionStates.done);
      expect(saved.last.result, kFnthinkRemoteOutcomeSet);
    });

    test('没做成 ⇒ 理由只在 reason 一处，同一个码不许再抄进 result', () async {
      windowSeconds = 0;
      l2.ok = false;
      await runner().run(accepted());
      expect(saved.last.state, RemoteExecutionStates.failed);
      expect(saved.last.reason, 'nope');
      expect(
        saved.last.result,
        isEmpty,
        reason:
            '两格写同一串 ⇒ 界面上两句一模一样，而"结果"与"为什么没成"本来是两件事；'
            '要显示的是词表里那三个成功词，失败没有"结果"这一说',
      );
    });
  });

  // ── T147 ②（维护者 2026-10-12 第 1 条）───────────────────────────────────
  // `_execute` 跑在 **Timer 回调**里，没有人 await 它。它抛出时异常只是一个未处理的异步错误，
  // 而终态那一次写**根本不会发生** ⇒ 那一行永远停在「待执行」，历史页一直说"这条还没开始"，
  // 而这台设备其实已经试过一遍了。兜底那一条必须落 `failed` + 写明理由：
  // "没做成"与"不知道做没做成"是两句话，这里能确定的只有"我试过，它炸了"。
  group('窗口到点那一发抛出（T147 ②）', () {
    test('仍然落一条 failed，那一行不许永远停在待执行', () async {
      void Function()? fire;
      schedule = (d, f) {
        fire = f;
        return Timer(const Duration(days: 1), () {});
      };
      final r = runner(statusBar: const _ThrowingNotifier());

      await r.run(accepted());
      expect(fire, isNotNull, reason: '窗口没排上 ⇒ 这一条根本没进入"到点"那一步');
      expect(saved.last.state, RemoteExecutionStates.pending);

      fire!();
      await Future<void>.delayed(Duration.zero);
      expect(
        saved.last.state,
        RemoteExecutionStates.failed,
        reason: '抛出后不落终态 = 那一行永远写着「待执行」',
      );
    });

    test('兜底那条写的理由是这次抛出本身，不是规则句子', () async {
      void Function()? fire;
      schedule = (d, f) {
        fire = f;
        return Timer(const Duration(days: 1), () {});
      };
      final r = runner(statusBar: const _ThrowingNotifier());
      await r.run(accepted());
      fire!();
      await Future<void>.delayed(Duration.zero);
      // ⚠ 这条与上一条**分开钉**，是因为 `_finish` 那条路会把理由写成 `illegal-move`
      //   （内核拒 `pending → failed` 那一格）—— 那是关于规则的句子，不是关于这一次的句子。
      //   合成一条用例的话，"落没落终态"与"理由诚不诚实"两种坏会红在同一个标题上，分不出是哪一件。
      expect(
        saved.last.reason,
        startsWith('threw:'),
        reason: '只说 failed 不说为什么，用户与后来查的人都不知道是炸了还是被拒',
      );
      expect(saved.last.reason, contains('boom'));
    });

    test('没抛出的那条路不受兜底壳影响（不许把成功也写成 failed）', () async {
      void Function()? fire;
      schedule = (d, f) {
        fire = f;
        return Timer(const Duration(days: 1), () {});
      };
      final r = runner();
      await r.run(accepted());
      fire!();
      await Future<void>.delayed(Duration.zero);
      expect(saved.last.state, RemoteExecutionStates.done);
    });
  });
}

/// 到点第一问（"用户在状态栏撤过没有"）就抛的 notifier。
/// 选这一格是因为它在 `_execute` **最早**的位置：从这里抛出，终态那次写一定没发生。
class _ThrowingNotifier extends RemoteExecutionNotifier {
  const _ThrowingNotifier();

  @override
  Future<bool> takeCancelled(String execId) async => throw StateError('boom');
}
