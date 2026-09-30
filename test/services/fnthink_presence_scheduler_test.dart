import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/services/fnthink_contract_loader.dart';
import 'package:notice_transmit/services/fnthink_presence_scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_setup.dart';

/// 幻念推送"被杀之后还有人去问一次货"的 Dart 侧（T33 第二片 / §4-9 片1b）。
///
/// 这一层没有算法，全部价值在**四件事的顺序与"谁也不许自己算一份"**上：
///  ① 间隔只有一个作者（契约）。这里喂的是**改过数值的契约副本**，不是真契约 ——
///     断言若拿实现读的同一份真值去比，那就是假绿（本仓假绿台账 X5/Z4/SA1/RC1 同族）；
///  ② 撤（keepAwake=false）不许被契约读数挡住：关了就停，哪怕契约那一刻不可用；
///  ③ 闹钟与后台入口的 handle 同生同死：handle 没落盘就不排（排了也起不了引擎，
///     白耗一次唤醒，而界面上看不出任何区别）；
///  ④ 后台那一轮**不论成败都要交回 `roundDone`**：不交，原生那一侧只能等到超时，
///     在 WorkManager 的账上记成"任务卡住"而不是"这一轮失败了"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final realContractText = File(fnthinkContractFile()).readAsStringSync();
  final realDefault = FnthinkContract.parse(
    realContractText,
  ).pollIntervalSeconds;

  /// 一份**改过数值**的契约副本：与真契约只差 `presence.pollIntervalSeconds.default`。
  /// 取 [min,max] 内的另一个数，为的是"改完之后这张表仍然自洽"——否则红的是校验，
  /// 而不是"有没有人自己写死一个间隔"，那条用例就答错了题。
  String mutatedContract(int seconds) {
    final json = jsonDecode(realContractText) as Map<String, Object?>;
    final presence = json['presence']! as Map<String, Object?>;
    final poll = presence['pollIntervalSeconds']! as Map<String, Object?>;
    poll['default'] = seconds;
    return jsonEncode(json);
  }

  late List<MethodCall> calls;

  FnthinkContractLoader loaderFrom(String text, {int Function()? onRead}) =>
      FnthinkContractLoader(
        readAsset: (key) async {
          onRead?.call();
          return text;
        },
      );

  void mockAppChannel({Object? reply}) {
    stubNativeChannels(
      onCall: (call) async {
        calls.add(call);
        return reply;
      },
    );
  }

  setUp(() {
    calls = <MethodCall>[];
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() => clearNativeChannelStubs());

  group('排与撤（节奏只有一个作者）', () {
    test('间隔来自契约：契约副本改成 27，交下去的就得是 27', () async {
      expect(mutatedContract(27) == realContractText, isFalse);
      mockAppChannel();
      final scheduler = FnthinkPresenceScheduler(
        contracts: loaderFrom(mutatedContract(27)),
      );

      await scheduler.notice(keepAwake: true);

      final schedule = calls.firstWhere(
        (c) => c.method == 'scheduleFnthinkPresence',
      );
      expect(
        (schedule.arguments as Map)['seconds'],
        27,
        reason:
            '交下去的秒数必须等于契约副本里那一档；这里如果读到 20（真契约那份），'
            '说明"实现自己带了一份节奏"，而改契约那一刀不会有任何东西报错',
      );
      expect((schedule.arguments as Map)['seconds'], isNot(realDefault));
    });

    test('契约不可用 ⇒ 不排，也不许补一个默认值（原话抛给调用方）', () async {
      mockAppChannel();
      final scheduler = FnthinkPresenceScheduler(
        contracts: FnthinkContractLoader(
          readAsset: (_) async => throw StateError('asset missing'),
        ),
      );

      await expectLater(
        scheduler.notice(keepAwake: true),
        throwsA(isA<FnthinkContractUnavailable>()),
      );
      expect(
        calls.map((c) => c.method),
        isNot(contains('scheduleFnthinkPresence')),
        reason: '排一颗间隔来路不明的闹钟 = 实现里藏了一份节奏。契约读不到就不排',
      );
    });

    test('撤不读契约：契约坏了也必须停（关了就停，别让"读不到"变成"还在醒"）', () async {
      mockAppChannel();
      var reads = 0;
      final scheduler = FnthinkPresenceScheduler(
        contracts: loaderFrom(realContractText, onRead: () => reads++),
      );

      await scheduler.notice(keepAwake: false);

      expect(calls.map((c) => c.method), contains('cancelFnthinkPresence'));
      expect(
        calls.map((c) => c.method),
        isNot(contains('scheduleFnthinkPresence')),
      );
      expect(reads, 0, reason: '撤那一发不该等契约：用户已经把开关关了，"读不到间隔"绝不能变成"闹钟留着"');
    });

    test('状态是从原生读回来的，不是 Dart 自己记的那份', () async {
      mockAppChannel(
        reply: {'nextRoundAt': 1800000020000, 'cadenceSeconds': 27},
      );
      final scheduler = FnthinkPresenceScheduler(
        contracts: loaderFrom(realContractText),
      );

      final status = await scheduler.status();

      expect(calls.single.method, 'fnthinkPresenceStatus');
      expect(status.nextRoundAt, 1800000020000);
      expect(status.cadenceSeconds, 27);
      expect(status.armed, isTrue);
    });

    test('原生回 null（从没排过）⇒ 两个 0、armed=false，不抛', () async {
      mockAppChannel();
      final scheduler = FnthinkPresenceScheduler(
        contracts: loaderFrom(realContractText),
      );

      final status = await scheduler.status();

      expect(status.armed, isFalse);
      expect(status.nextRoundAt, 0);
      expect(status.cadenceSeconds, 0);
    });

    test('闹钟与入口 handle 同生同死：handle 没落盘就不排', () async {
      mockAppChannel();
      final scheduler = FnthinkPresenceScheduler(
        contracts: loaderFrom(mutatedContract(27)),
      );

      await scheduler.notice(keepAwake: true);

      final handle = PluginUtilities.getCallbackHandle(
        fnthinkPresenceEntrypoint,
      );
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getInt(kFnthinkPresenceHandleKey);
      final scheduled = calls
          .map((c) => c.method)
          .contains('scheduleFnthinkPresence');
      if (handle == null) {
        // 这颗 VM 里算不出 handle（不是错误，是这台环境没有 isolate 快照）。
        // 要钉的是"这时候绝不排" —— 排了也进不了那个函数，只会白耗一次唤醒。
        expect(stored, isNull);
        expect(scheduled, isFalse);
      } else {
        expect(stored, handle.toRawHandle());
        expect(scheduled, isTrue);
      }
    });
  });

  group('后台入口（那一轮的成与败都要说得出话）', () {
    late List<String> presenceSeen;

    setUp(() {
      presenceSeen = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(kFnthinkPresenceChannel),
            (call) async {
              presenceSeen.add(call.method);
              return true;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel(kFnthinkPresenceChannel),
            null,
          );
    });

    test('那一轮失败也要交回 roundDone（不交只能等到超时）', () async {
      final original = runFnthinkPresenceRound;
      addTearDown(() => runFnthinkPresenceRound = original);
      final steps = <String>[];
      runFnthinkPresenceRound = () async {
        steps.add('round');
        throw StateError('模拟：那一轮起不来');
      };

      await fnthinkPresenceEntrypoint();

      expect(steps, ['round']);
      expect(
        presenceSeen,
        ['roundDone'],
        reason:
            '失败路径上 roundDone 必须照样送到：worker 那侧看到的是"这一轮失败了"，'
            '不是"任务卡住 90 秒"',
      );
    });

    test('那一轮成功 ⇒ 同样只交一次 roundDone（不重复、不漏）', () async {
      final original = runFnthinkPresenceRound;
      addTearDown(() => runFnthinkPresenceRound = original);
      runFnthinkPresenceRound = () async {};

      await fnthinkPresenceEntrypoint();

      expect(presenceSeen, ['roundDone']);
    });

    test('DI 漏接时那份占位必须红（不许静默"跑了但什么都没做"）', () async {
      // 这一条证的是占位实现本身：装配点漏接时全场其他用例仍绿（守卫见
      // test/architecture/fnthink_presence_guard_test.dart），而这里保证"漏接"是可红的。
      await expectLater(runFnthinkPresenceRound(), throwsStateError);
    });
  });
}
