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
  Future<FnthinkL2Result> toggleChannel(String channelId) async {
    calls.add('toggleChannel($channelId)');
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
}

void main() {
  final contract = FnthinkContract.readFile();

  group('契约词表（唯一出处）', () {
    test('读得到四个动作，且设备侧映射把它们全认了', () {
      expect(contract.l2Actions, isNotEmpty);
      expect(
        l2ActionsCoveredByDevice(contract),
        isTrue,
        reason: '契约加了动作而设备侧没接 ⇒ 对端能发一个这台机器做不了的动作',
      );
    });

    test('点名要参数的动作只有一个，且它确实在词表里', () {
      expect(contract.l2ActionsRequiringArgument, ['channel:toggle']);
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
        'channel:toggle/chan:email',
        'device_state:push',
      ]) {
        final parsed = parseL2Item(contract, item);
        expect(parsed, isA<FnthinkL2Ok>());
        await dispatchL2Action(contract, exec, (parsed as FnthinkL2Ok).action);
      }
      expect(exec.calls, [
        'setListener(true)',
        'setListener(false)',
        'toggleChannel(chan:email)',
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
      final badRun = await exec.toggleChannel('chan:x');
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
}
