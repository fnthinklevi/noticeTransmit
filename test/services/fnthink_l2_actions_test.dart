import 'dart:io';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_l2_actions.dart';

/// T50：L2 动作执行器的**设备侧那一半**（纯枚举映射 + 派发）。
///
/// 这一组钉的是四件事：
///  ① 词表来自契约，代码里不重复写一遍（两端各持一份映射是刻意的，名单**只能**在契约里）；
///  ② 认不出的动作一律拒，**不静默跳过** —— 跳过等于让对端用编出来的动作名试探边界；
///  ③ 契约点名要参数的动作缺参数就是缺，**不回退到"第一条"**（那是静默的越权）；
///  ④ 失败与"不认得"是两种东西：前者回 `actionReceipt`，后者根本不该被执行。
/// 只记调用、不做事的执行器 —— 派发这一层要验的是"哪个动作落到哪个方法"。
///
/// ⚠ 放在**顶层**而不是 `main()` 里面：Dart 不许在函数体内声明类，
/// 而把它写在 `main()` 里第一版就是这么写的（`dart format` 当场报
/// 「class can't be used as an identifier」）。
class RecordingExecutor implements FnthinkL2Executor {
  final List<String> calls = [];
  bool failEverything = false;

  @override
  Future<FnthinkL2Result> setListener({required bool enabled}) async {
    calls.add('setListener($enabled)');
    return failEverything
        ? const FnthinkL2Result.failed('listener-unavailable')
        : const FnthinkL2Result.ok();
  }

  @override
  Future<FnthinkL2Result> toggleChannel(RemoteChannelTarget target) async {
    calls.add('toggleChannel(${target.family}:${target.id}:${target.enabled})');
    return failEverything
        ? const FnthinkL2Result.failed('no-such-channel')
        : const FnthinkL2Result.ok();
  }

  @override
  Future<FnthinkL2Result> pushDeviceState() async {
    calls.add('pushDeviceState()');
    return failEverything
        ? const FnthinkL2Result.failed('no-bridge')
        : const FnthinkL2Result.ok();
  }

  /// 回传那一条要回的那段正文（null = 这一步没做成）。
  String? reportPayload;

  @override
  Future<String?> reportNotifications(int count) async {
    calls.add('reportNotifications($count)');
    return failEverything ? null : reportPayload;
  }

  @override
  Future<FnthinkL2Result> ringAlert() async {
    calls.add('ringAlert()');
    return failEverything
        ? const FnthinkL2Result.failed('alert-ring-refused')
        : const FnthinkL2Result.ok();
  }

  /// 搜短信那一条要回的那段正文（null = 没成，理由看 reason）。
  ({String? payload, String? reason})? smsResult;

  @override
  Future<({String? payload, String? reason})> searchSms(String keyword) async {
    calls.add('searchSms($keyword)');
    if (failEverything) {
      return (payload: null, reason: 'sms-search-failed');
    }
    return smsResult ?? (payload: null, reason: 'sms-search-disabled');
  }

  /// 打开入口那一条要回的结果（null = 用默认：名字对不上）。
  ({bool ok, String? reason})? launchResult;

  @override
  Future<({bool ok, String? reason})> launchApp(String name) async {
    calls.add('launchApp($name)');
    if (failEverything) return (ok: false, reason: 'app-launch-failed');
    return launchResult ?? (ok: false, reason: 'app-launch-unknown-name');
  }

  /// 搜通话记录那一条要回的那段正文（null = 没成，理由看 reason）。
  ({String? payload, String? reason})? callsResult;

  @override
  Future<({String? payload, String? reason})> searchCalls(
    String keyword,
  ) async {
    calls.add('searchCalls($keyword)');
    if (failEverything) {
      return (payload: null, reason: 'calls-search-failed');
    }
    return callsResult ?? (payload: null, reason: 'calls-search-disabled');
  }

  /// 定位那一条要回的那段正文（null = 没成，理由看 reason）。
  ({String? payload, String? reason})? locationResult;

  @override
  Future<({String? payload, String? reason})> getLocation() async {
    calls.add('getLocation()');
    if (failEverything) {
      return (payload: null, reason: 'location-failed');
    }
    return locationResult ?? (payload: null, reason: 'location-disabled');
  }
}

void main() {
  final contract = FnthinkContract.readFile();

  group('契约词表（唯一出处）', () {
    test('读得到词表，且设备侧映射把它们全认了（不多不少）', () {
      expect(contract.l2Actions, isNotEmpty);
      expect(
        l2ActionsCoveredByDevice(contract),
        isTrue,
        reason: '契约加了动作而设备侧没接 ⇒ 对端能发一个这台机器做不了的动作',
      );
    });

    test('点名要参数的动作与契约那张回传表对得上（不多不少）', () {
      expect(contract.l2ActionsRequiringArgument, [
        'channel:toggle',
        'notifications:report',
        'sms:search',
        'app:launch',
        'calls:search',
      ]);
      for (final a in contract.l2Reports.keys) {
        // ⚠ none（T124 片C-2 的 location:get）是**无参数**的回传：它不列
        // requiresArgumentFrom（列了自相矛盾），契约校验已把这一对关系双向钉住。
        if (contract.l2ReportKind(a) == 'none') continue;
        expect(
          contract.l2ActionsRequiringArgument,
          contains(a),
          reason: '回传的参数就是必须的参数，缺了它这一发没有东西可回',
        );
      }
    });

    test('执行失败回的那一个词在顶层 receipts 词表里', () {
      expect(contract.l2ActionReceipt, 'failed_action');
    });
  });

  group('parseL2Item：四种拒的理由各不相同', () {
    test('认得出的四种各解析成动作与参数', () {
      expect(
        parseL2Item(contract, 'listener:start'),
        const FnthinkL2Ok(FnthinkL2Action('listener:start', '')),
      );
      expect(
        parseL2Item(contract, 'channel:toggle/chan:wechat'),
        const FnthinkL2Ok(FnthinkL2Action('channel:toggle', 'chan:wechat')),
      );
    });

    test('item 为空或 null ⇒ missing-item（不猜一个动作出来）', () {
      for (final given in [null, '']) {
        expect(
          parseL2Item(contract, given),
          const FnthinkL2Rejected('missing-item'),
        );
      }
    });

    test('词表外的动作 ⇒ unknown-action:<名>，不静默跳过', () {
      expect(
        parseL2Item(contract, 'listener:reboot'),
        const FnthinkL2Rejected('unknown-action:listener:reboot'),
      );
      // ⚠ 这一条是本组最要紧的：跳过它 = 对端可以拿编出来的动作名试边界
      expect(parseL2Item(contract, 'nonsense'), isA<FnthinkL2Rejected>());
    });

    test('点名要参数而没给 ⇒ missing-argument，且**不取第一条**', () {
      final r = parseL2Item(contract, 'channel:toggle');
      expect(r, const FnthinkL2Rejected('missing-argument:channel:toggle'));
      // 回退到"第一条通道"就是一条静默的越权：签名者从没说要动哪一条
      expect(r.toString(), isNot(contains('chan:')));
    });

    test('参数里带斜杠原样保留（通道 id 里出现斜杠时不被截断）', () {
      expect(
        parseL2Item(contract, 'channel:toggle/a/b/c'),
        const FnthinkL2Ok(FnthinkL2Action('channel:toggle', 'a/b/c')),
      );
    });

    test('回调能改写 unknown-action 的措辞（留痕要带得走）', () {
      final r = parseL2Item(
        contract,
        'listener:reboot',
        onUnknown: (n) => 'rejected:$n',
      );
      expect(r, const FnthinkL2Rejected('rejected:listener:reboot'));
    });
  });

  group('派发：动作名 → 执行器方法', () {
    test('四个动作各落到该落的方法上，参数原样传下去', () async {
      final exec = RecordingExecutor();
      for (final item in [
        'listener:start',
        'listener:stop',
        'channel:toggle/webhook:acme:off',
        'device_state:push',
      ]) {
        final parsed = parseL2Item(contract, item);
        expect(parsed, isA<FnthinkL2Ok>());
        await dispatchL2Action(contract, exec, (parsed as FnthinkL2Ok).action);
      }
      expect(exec.calls, [
        'setListener(true)',
        'setListener(false)',
        'toggleChannel(webhook:acme:false)',
        'pushDeviceState()',
      ]);
    });

    test('执行器不会做的动作 ⇒ unmapped-action（与"做失败了"分开）', () async {
      // 手工构造一个词表外但已解析的动作：模拟"解析与派发读法不一致"这一种缺陷
      final r = await dispatchL2Action(
        contract,
        RecordingExecutor(),
        const FnthinkL2Action('made:up', ''),
      );
      expect(r.ok, isFalse);
      expect(r.reason, 'unmapped-action:made:up');
    });
  });

  group('回执：失败与成功对外各是哪一个词', () {
    test('成功 ⇒ delivered，失败 ⇒ 契约那一个词', () async {
      final exec = RecordingExecutor();
      final okRun = await exec.setListener(enabled: true);
      expect(okRun.receipt(contract), 'delivered');

      exec.failEverything = true;
      final badRun = await exec.toggleChannel(
        const RemoteChannelTarget(family: 'app', id: 'x', enabled: true),
      );
      expect(badRun.ok, isFalse);
      expect(badRun.receipt(contract), contract.l2ActionReceipt);
      expect(badRun.receipt(contract), 'failed_action');
    });

    test('本地细节只进 reason，不进对外那个词', () {
      const r = FnthinkL2Result.failed('no-such-channel:chan:wechat');
      expect(r.receipt(contract), isNot(contains('chan:')));
      expect(r.receipt(contract), 'failed_action');
    });
  });

  group('真实契约而不是夹具', () {
    test('这些用例读的是仓库那份契约（它自洽，否则本文件在测空气）', () {
      expect(contract.validate(), isEmpty);
      expect(File(fnthinkContractFile()).existsSync(), isTrue);
    });
  });

  group('回传那一条（T124 片B）：参数是「要几条」，产出从这一层带出来', () {
    test('契约声明了它与它的上下界，且它必带参数', () {
      expect(contract.l2Actions, contains('notifications:report'));
      expect(
        contract.l2ActionsRequiringArgument,
        contains('notifications:report'),
      );
      expect(contract.l2ReportMinItems('notifications:report'), 1);
      expect(contract.l2ReportMaxItems('notifications:report'), 20);
      expect(contract.l2ReportTitle('notifications:report'), 'notif-report');
    });

    test('区间内 ⇒ 执行器被调一次，产出挂在结果上（payload）', () async {
      final exec = RecordingExecutor()..reportPayload = 'REPORT';
      final r = await dispatchL2Action(
        contract,
        exec,
        const FnthinkL2Action('notifications:report', '10'),
      );
      expect(exec.calls, ['reportNotifications(10)']);
      expect(r.ok, isTrue);
      expect(r.payload, 'REPORT');
    });

    test('越界或不是数 ⇒ failed，且**执行器一次都不被调**', () async {
      for (final bad in ['0', '21', 'abc', '', ' 5.5']) {
        final exec = RecordingExecutor()..reportPayload = 'REPORT';
        final r = await dispatchL2Action(
          contract,
          exec,
          FnthinkL2Action('notifications:report', bad),
        );
        expect(r.ok, isFalse, reason: '参数「$bad」不该过');
        expect(r.reason, startsWith('bad-report-count:'));
        expect(exec.calls, isEmpty, reason: '拦在动手之前 —— 越界的请求不该占掉延时窗口');
      }
    });

    test('产出为空（读库失败那一支）⇒ failed，不装成"一条都没有"', () async {
      final exec = RecordingExecutor()..reportPayload = null;
      final r = await dispatchL2Action(
        contract,
        exec,
        const FnthinkL2Action('notifications:report', '5'),
      );
      expect(r.ok, isFalse);
      expect(r.reason, 'report-failed');
      expect(r.payload, isNull);
    });

    test('收件前的形状判据与派发同源（rejectL2Argument）', () {
      const ok = FnthinkL2Action('notifications:report', '3');
      expect(rejectL2Argument(contract, ok), isNull);
      expect(
        rejectL2Argument(
          contract,
          const FnthinkL2Action('notifications:report', '99'),
        ),
        startsWith('bad-report-count:'),
      );
      // channel:toggle 那一条仍走它自己的判据（两族参数各判各的）。
      expect(
        rejectL2Argument(
          contract,
          const FnthinkL2Action('channel:toggle', 'app:x:on'),
        ),
        isNull,
      );
      expect(
        rejectL2Argument(
          contract,
          const FnthinkL2Action('channel:toggle', 'x'),
        ),
        startsWith('bad-channel-argument:'),
      );
      // 没有参数形状要求的动作：两个判据都不拦（认不认得由 parseL2Item 管）。
      expect(
        rejectL2Argument(contract, const FnthinkL2Action('listener:start', '')),
        isNull,
      );
    });

    test('契约没声明上下界 ⇒ 一律不认（fail-closed，不是默认放行）', () {
      expect(reportCountInRange(contract, 'listener:start', 1), isFalse);
    });
  });

  group('响铃那一条（T124 片B 的 alert:ring）：无参数、瞬时动作', () {
    test('契约里有它、**不**必带参数、也不在回传表里', () {
      expect(contract.l2Actions, contains('alert:ring'));
      expect(
        contract.l2ActionsRequiringArgument,
        isNot(contains('alert:ring')),
      );
      expect(contract.l2Reports.containsKey('alert:ring'), isFalse);
      expect(
        rejectL2Argument(contract, const FnthinkL2Action('alert:ring', '')),
        isNull,
      );
    });

    test('派发到执行器的 ringAlert（不是别的方法）', () async {
      final exec = RecordingExecutor();
      final r = await dispatchL2Action(
        contract,
        exec,
        const FnthinkL2Action('alert:ring', ''),
      );
      expect(exec.calls, ['ringAlert()']);
      expect(r.ok, isTrue);
    });

    test('执行器说"没显示" ⇒ failed（对面不许收到 done）', () async {
      final exec = RecordingExecutor()..failEverything = true;
      final r = await dispatchL2Action(
        contract,
        exec,
        const FnthinkL2Action('alert:ring', ''),
      );
      expect(r.ok, isFalse);
      expect(r.reason, 'alert-ring-refused');
      expect(r.receipt(contract), 'failed_action');
    });
  });

  group('搜短信那一条（T124 片B 的 sms:search）：关键词形态的回传', () {
    test('契约：在词表里、必带参数、kind 是 keyword、上下界与点名的标题都在', () {
      expect(contract.l2Actions, contains('sms:search'));
      expect(contract.l2ActionsRequiringArgument, contains('sms:search'));
      expect(contract.l2ReportKind('sms:search'), 'keyword');
      expect(contract.l2ReportMinChars('sms:search'), 1);
      expect(contract.l2ReportMaxChars('sms:search'), 32);
      expect(contract.l2ReportTitle('sms:search'), 'sms-search');
    });

    test('命中 ⇒ 执行器被调一次，产出挂在结果上', () async {
      final exec = RecordingExecutor()
        ..smsResult = (payload: '07-12 09:31 10086 验证码 123456', reason: null);
      final r = await dispatchL2Action(
        contract,
        exec,
        const FnthinkL2Action('sms:search', '验证码'),
      );
      expect(exec.calls, ['searchSms(验证码)']);
      expect(r.ok, isTrue);
      expect(r.payload, contains('123456'));
    });

    test('执行器回一句理由（开关关着 / 没权限 / 读不出来）⇒ failed 原样带上', () async {
      for (final reason in [
        'sms-search-disabled',
        'sms-search-refused',
        'sms-search-failed',
      ]) {
        final exec = RecordingExecutor()
          ..smsResult = (payload: null, reason: reason);
        final r = await dispatchL2Action(
          contract,
          exec,
          const FnthinkL2Action('sms:search', '验证码'),
        );
        expect(r.ok, isFalse);
        expect(r.reason, reason);
      }
    });

    test('关键词越界/空/带控制字符 ⇒ failed，且**执行器一次都不被调**', () async {
      for (final bad in ['', '   ', 'x' * 33, 'x\ny']) {
        final exec = RecordingExecutor()
          ..smsResult = (payload: 'HIT', reason: null);
        final r = await dispatchL2Action(
          contract,
          exec,
          FnthinkL2Action('sms:search', bad),
        );
        expect(r.ok, isFalse, reason: '关键词「$bad」不该过');
        expect(r.reason, startsWith('bad-keyword:'));
        expect(exec.calls, isEmpty, reason: '拦在动手之前');
      }
    });

    test('收件前的形状判据与派发同源（rejectL2Argument 也按 keyword 判）', () {
      expect(
        rejectL2Argument(contract, const FnthinkL2Action('sms:search', '验证码')),
        isNull,
      );
      expect(
        rejectL2Argument(contract, FnthinkL2Action('sms:search', 'x' * 33)),
        startsWith('bad-keyword:'),
      );
      // count 那一条不受影响（两种形态各判各的）。
      expect(
        reportArgumentProblem(contract, 'notifications:report', '10'),
        isNull,
      );
      expect(
        reportArgumentProblem(contract, 'notifications:report', '21'),
        startsWith('bad-report-count:'),
      );
    });
  });

  group('打开入口那一条（T124 片B 的 app:launch）：按名字对、不回传', () {
    test('契约：在词表里、必带参数、kind 是 keyword、**没有**回传标题', () {
      expect(contract.l2Actions, contains('app:launch'));
      expect(contract.l2ActionsRequiringArgument, contains('app:launch'));
      expect(contract.l2ReportKind('app:launch'), 'keyword');
      expect(contract.l2ReportMinChars('app:launch'), 1);
      expect(contract.l2ReportMaxChars('app:launch'), 32);
      expect(
        contract.l2ReportTitle('app:launch'),
        isNull,
        reason: '它不产出任何东西 —— 没有标题才是它的形状，不是漏配',
      );
    });

    test('派发到执行器的 launchApp（名字原样交过去）', () async {
      final exec = RecordingExecutor()..launchResult = (ok: true, reason: null);
      final r = await dispatchL2Action(
        contract,
        exec,
        const FnthinkL2Action('app:launch', '开门'),
      );
      expect(exec.calls, ['launchApp(开门)']);
      expect(r.ok, isTrue);
      expect(r.payload, isNull, reason: '它不产出东西 ⇒ 不该借道回传那一路');
    });

    test('执行器说名字对不上 ⇒ failed 原样带上理由', () async {
      final exec = RecordingExecutor()
        ..launchResult = (ok: false, reason: 'app-launch-unknown-name');
      final r = await dispatchL2Action(
        contract,
        exec,
        const FnthinkL2Action('app:launch', '不存在的名字'),
      );
      expect(r.ok, isFalse);
      expect(r.reason, 'app-launch-unknown-name');
      expect(r.receipt(contract), 'failed_action');
    });

    test('名字越界/空/带控制字符 ⇒ failed，且执行器一次都不被调', () async {
      for (final bad in ['', '   ', 'x' * 33, 'a\nb']) {
        final exec = RecordingExecutor()
          ..launchResult = (ok: true, reason: null);
        final r = await dispatchL2Action(
          contract,
          exec,
          FnthinkL2Action('app:launch', bad),
        );
        expect(r.ok, isFalse, reason: '名字「$bad」不该过');
        expect(r.reason, startsWith('bad-keyword:'));
        expect(exec.calls, isEmpty, reason: '拦在动手之前');
      }
    });
  });

  group('搜通话记录那一条（T124 片C 的 calls:search）：与 sms:search 同形', () {
    test('契约：在词表里、必带参数、kind 是 keyword、上下界与点名的标题都在', () {
      expect(contract.l2Actions, contains('calls:search'));
      expect(contract.l2ActionsRequiringArgument, contains('calls:search'));
      expect(contract.l2ReportKind('calls:search'), 'keyword');
      expect(contract.l2ReportMinChars('calls:search'), 1);
      expect(contract.l2ReportMaxChars('calls:search'), 32);
      expect(contract.l2ReportTitle('calls:search'), 'call-log-search');
    });

    test('命中 ⇒ 执行器被调一次，产出挂在结果上', () async {
      final exec = RecordingExecutor()
        ..callsResult = (payload: '07-12 09:31 ↙ 10086 (12s)', reason: null);
      final r = await dispatchL2Action(
        contract,
        exec,
        const FnthinkL2Action('calls:search', '10086'),
      );
      expect(exec.calls, ['searchCalls(10086)']);
      expect(r.ok, isTrue);
      expect(r.payload, contains('10086'));
    });

    test('执行器回一句理由（开关关着 / 没权限 / 读不出来）⇒ failed 原样带上', () async {
      for (final reason in [
        'calls-search-disabled',
        'calls-search-refused',
        'calls-search-failed',
      ]) {
        final exec = RecordingExecutor()
          ..callsResult = (payload: null, reason: reason);
        final r = await dispatchL2Action(
          contract,
          exec,
          const FnthinkL2Action('calls:search', '10086'),
        );
        expect(r.ok, isFalse);
        expect(r.reason, reason);
      }
    });

    test('关键词越界/空/带控制字符 ⇒ failed，且执行器一次都不被调', () async {
      for (final bad in ['', '   ', 'x' * 33, 'x\ny']) {
        final exec = RecordingExecutor()
          ..callsResult = (payload: 'HIT', reason: null);
        final r = await dispatchL2Action(
          contract,
          exec,
          FnthinkL2Action('calls:search', bad),
        );
        expect(r.ok, isFalse, reason: '关键词「$bad」不该过');
        expect(r.reason, startsWith('bad-keyword:'));
        expect(exec.calls, isEmpty, reason: '拦在动手之前');
      }
    });
  });

  group('定位那一条（T124 片C-2 的 location:get）：无参数、第三种形态 none', () {
    test('契约：在词表里、**不**必带参数、kind 是 none、回传标题在', () {
      expect(contract.l2Actions, contains('location:get'));
      expect(
        contract.l2ActionsRequiringArgument,
        isNot(contains('location:get')),
        reason: '无参数的动作列进 requiresArgumentFrom 是自相矛盾（一处说必填、一处说没有）',
      );
      expect(contract.l2ReportKind('location:get'), 'none');
      expect(contract.l2ReportTitle('location:get'), 'location-report');
      expect(
        rejectL2Argument(contract, const FnthinkL2Action('location:get', '')),
        isNull,
      );
    });

    test('命中 ⇒ 执行器被调一次，产出挂在结果上', () async {
      final exec = RecordingExecutor()
        ..locationResult = (
          payload: '31.230416,121.473701 ±25m gps',
          reason: null,
        );
      final r = await dispatchL2Action(
        contract,
        exec,
        const FnthinkL2Action('location:get', ''),
      );
      expect(exec.calls, ['getLocation()']);
      expect(r.ok, isTrue);
      expect(r.payload, contains('31.230416'));
    });

    test('带了参数 ⇒ failed 且**执行器一次都不被调**（unexpected-argument）', () async {
      final exec = RecordingExecutor()
        ..locationResult = (payload: 'HIT', reason: null);
      final r = await dispatchL2Action(
        contract,
        exec,
        const FnthinkL2Action('location:get', 'where'),
      );
      expect(r.ok, isFalse);
      expect(r.reason, 'unexpected-argument:location:get');
      expect(exec.calls, isEmpty, reason: '拦在动手之前');
    });

    test('执行器回一句理由（开关关着 / 没权限 / 没有最近定位 / 读不出来）⇒ 原样带上', () async {
      for (final reason in [
        'location-disabled',
        'location-refused',
        'location-unavailable',
        'location-failed',
      ]) {
        final exec = RecordingExecutor()
          ..locationResult = (payload: null, reason: reason);
        final r = await dispatchL2Action(
          contract,
          exec,
          const FnthinkL2Action('location:get', ''),
        );
        expect(r.ok, isFalse);
        expect(r.reason, reason);
      }
    });
  });
}
