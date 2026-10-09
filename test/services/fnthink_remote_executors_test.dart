import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_l2_actions.dart';
import 'package:notice_transmit/services/fnthink_remote_executors.dart';

/// 远程执行 片3c-2：**设备侧执行器**。
///
/// T50/T51 把 `FnthinkL2Executor` / `FnthinkL3Executor` 两个抽象类与 `dispatch*` 派发
/// 都写好了，但**到那为止没有任何实现** —— 也就是说那两个派发函数一个调用方都没有，
/// "认得这个词"与"真的动手"之间那一段是空的。这一组钉动手那一半的分支：
///  ① 系统拒绝 ⇒ `failed` 且理由说得出是哪一步；
///  ② 抛异常也记成 `failed`/`false`（不让一轮收货停在一条坏指令上）；
///  ③ **"这一台没有这一项" ⇒ false，不是成功** —— 当成成功的话界面上会立刻显示"已开启"；
///  ④ `channel:toggle` 落的是**目标值**（幂等），不是"翻"。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final contract = FnthinkContract.readFile();

  group('L2 执行器', () {
    late List<bool> listenerCalls;
    late List<RemoteChannelTarget> channelCalls;
    var listenerOk = true;
    var listenerThrows = false;
    var channelOk = true;
    var pushOk = true;
    var pushThrows = false;
    late List<int> reportCalls;
    var reportPayload = 'REPORT';
    var reportThrows = false;
    var ringCalls = 0;
    var ringOk = true;
    var ringThrows = false;
    late List<String> smsCalls;
    ({String? payload, String? reason}) smsResult = (
      payload: 'HIT',
      reason: null,
    );
    var smsThrows = false;
    late List<String> launchCalls;
    ({bool ok, String? reason}) launchResult = (ok: true, reason: null);
    var launchThrows = false;

    setUp(() {
      listenerCalls = [];
      channelCalls = [];
      listenerOk = true;
      listenerThrows = false;
      channelOk = true;
      pushOk = true;
      pushThrows = false;
      reportCalls = [];
      reportPayload = 'REPORT';
      reportThrows = false;
      ringCalls = 0;
      ringOk = true;
      ringThrows = false;
      smsCalls = [];
      smsResult = (payload: 'HIT', reason: null);
      smsThrows = false;
      launchCalls = [];
      launchResult = (ok: true, reason: null);
      launchThrows = false;
    });

    DeviceL2Executor build() => DeviceL2Executor(
      setListenerEnabled: ({required bool enabled}) async {
        listenerCalls.add(enabled);
        if (listenerThrows) throw StateError('boom');
        return listenerOk;
      },
      setChannelEnabled: (target) async {
        channelCalls.add(target);
        return channelOk;
      },
      reportNotificationsNow: (count) async {
        reportCalls.add(count);
        if (reportThrows) throw StateError('boom');
        return reportPayload;
      },
      pushDeviceStateNow: () async {
        if (pushThrows) throw StateError('boom');
        return pushOk;
      },
      ringAlertNow: () async {
        ringCalls++;
        if (ringThrows) throw StateError('boom');
        return ringOk;
      },
      searchSmsNow: (keyword) async {
        smsCalls.add(keyword);
        if (smsThrows) throw StateError('boom');
        return smsResult;
      },
      launchAppNow: (name) async {
        launchCalls.add(name);
        if (launchThrows) throw StateError('boom');
        return launchResult;
      },
    );

    test('启停按 enabled 落到两个不同的动作上', () async {
      final exec = build();
      expect((await exec.setListener(enabled: true)).ok, isTrue);
      expect((await exec.setListener(enabled: false)).ok, isTrue);
      expect(listenerCalls, [true, false]);
    });

    test('系统拒绝 ⇒ failed 且理由说清是哪一步', () async {
      listenerOk = false;
      final exec = build();
      expect((await exec.setListener(enabled: true)).reason, 'listener:start');
      expect((await exec.setListener(enabled: false)).reason, 'listener:stop');
    });

    test('抛异常也记成 failed（不让一条坏指令停住整轮收货）', () async {
      listenerThrows = true;
      final r = await build().setListener(enabled: true);
      expect(r.ok, isFalse);
      expect(r.reason, startsWith('threw:listener'));
    });

    test('channel:toggle 把目标值原样落下去，不是"翻"', () async {
      const target = RemoteChannelTarget(
        family: 'webhook',
        id: 'acme',
        enabled: false,
      );
      expect((await build().toggleChannel(target)).ok, isTrue);
      expect(channelCalls.single.enabled, isFalse);
      expect(channelCalls.single.family, 'webhook');
      expect(channelCalls.single.id, 'acme');
    });

    test('族里没有那一条通道 ⇒ failed 且理由带得上族与 id', () async {
      channelOk = false;
      final r = await build().toggleChannel(
        const RemoteChannelTarget(family: 'email', id: 'x', enabled: true),
      );
      expect(r.ok, isFalse);
      expect(r.reason, 'no-such-channel:email/x');
    });

    test('写通道抛异常 ⇒ failed（不是 ok）', () async {
      final exec = DeviceL2Executor(
        setListenerEnabled: ({required bool enabled}) async => true,
        setChannelEnabled: (target) async => throw StateError('boom'),
        reportNotificationsNow: (count) async => null,
        ringAlertNow: () async => true,
        searchSmsNow: (keyword) async =>
            (payload: null, reason: 'sms-search-failed'),
        launchAppNow: (name) async =>
            (ok: false, reason: 'app-launch-unknown-name'),
        pushDeviceStateNow: () async => true,
      );
      expect(
        (await exec.toggleChannel(
          const RemoteChannelTarget(family: 'app', id: 'y', enabled: true),
        )).reason,
        startsWith('threw:channel:app/y'),
      );
    });

    test('alert:ring：响出去 ⇒ ok；没显示（权限被关）与被拒都记失败', () async {
      expect((await build().ringAlert()).ok, isTrue);
      expect(ringCalls, 1);
      ringOk = false;
      final refused = await build().ringAlert();
      expect(
        refused.ok,
        isFalse,
        reason: '没显示却记成 ok ⇒ 对面以为这台的用户被提醒过了，而用户什么都没看到',
      );
      expect(refused.reason, 'alert-ring-refused');
      ringThrows = true;
      expect((await build().ringAlert()).reason, 'threw:alert:ring');
    });

    test('device_state:push：发出去 ⇒ ok，被拒与抛异常 ⇒ failed', () async {
      expect((await build().pushDeviceState()).ok, isTrue);
      pushOk = false;
      expect(
        (await build().pushDeviceState()).reason,
        'device-state-push-refused',
      );
      pushThrows = true;
      expect((await build().pushDeviceState()).reason, startsWith('threw:'));
    });

    test('app:launch：名字交过去、结果原样透传；抛异常收成 threw', () async {
      final ok = await build().launchApp('开门');
      expect(launchCalls, ['开门']);
      expect(ok.ok, isTrue);
      launchResult = (ok: false, reason: 'app-launch-unknown-name');
      expect((await build().launchApp('x')).reason, 'app-launch-unknown-name');
      launchThrows = true;
      expect((await build().launchApp('x')).reason, 'threw:app:launch');
    });

    test('sms:search：产出与理由原样透传；抛异常收成 threw', () async {
      final hit = await build().searchSms('验证码');
      expect(smsCalls, ['验证码']);
      expect(hit.payload, 'HIT');
      expect(hit.reason, isNull);
      smsResult = (payload: null, reason: 'sms-search-disabled');
      expect((await build().searchSms('x')).reason, 'sms-search-disabled');
      smsThrows = true;
      expect((await build().searchSms('x')).reason, 'threw:sms:search');
    });
  });

  group('L3 执行器：grant（把人送到那一页，不是"已经改好了"）', () {
    late List<String> granted;
    late DeviceL3Executor exec;

    setUp(() {
      granted = [];
      exec = DeviceL3Executor(
        grantNotificationListener: () async => granted.add('notification'),
        grantExactAlarm: () async => granted.add('exact_alarm'),
        grantBatteryOptimization: () async =>
            granted.add('battery_optimization'),
        grantVendorAutoStart: () async => granted.add('autostart'),
        serviceRunning: () async => false,
        setListenerEnabled: ({required bool enabled}) async => enabled,
        collectInboxEnabled: () async => false,
        setCollectInboxEnabled: (enabled) async => enabled,
      );
    });

    test('契约那四项每一项都落到自己那个入口', () async {
      for (final key in [
        'notification',
        'exact_alarm',
        'battery_optimization',
        'autostart',
      ]) {
        final setting = contract.l3Settings[key];
        expect(setting, isNotNull, reason: '契约里没有 $key');
        expect(setting!.isToggle, isFalse, reason: '$key 在契约里是 grant 项');
        expect(await exec.grant(setting), isTrue);
        expect(granted.last, key);
      }
      expect(granted.length, 4);
    });

    test('厂商那一项没接 ⇒ false（不是"已开启"）', () async {
      final bare = DeviceL3Executor(
        grantNotificationListener: () async {},
        grantExactAlarm: () async {},
        grantBatteryOptimization: () async {},
        grantVendorAutoStart: null,
        serviceRunning: () async => false,
        setListenerEnabled: ({required bool enabled}) async => enabled,
        collectInboxEnabled: () async => false,
        setCollectInboxEnabled: (enabled) async => enabled,
      );
      expect(
        await bare.grant(contract.l3Settings['autostart']!),
        isFalse,
        reason: '没接入口 = 这一台压根没有那一项的入口，不许当成功',
      );
    });

    test('送设置页抛异常 ⇒ false（不是成功，也不许把整轮收货停住）', () async {
      final throwing = DeviceL3Executor(
        grantNotificationListener: () async => throw StateError('boom'),
        grantExactAlarm: () async {},
        grantBatteryOptimization: () async {},
        grantVendorAutoStart: () async {},
        serviceRunning: () async => false,
        setListenerEnabled: ({required bool enabled}) async => enabled,
        collectInboxEnabled: () async => false,
        setCollectInboxEnabled: (enabled) async => enabled,
      );
      expect(
        await throwing.grant(contract.l3Settings['notification']!),
        isFalse,
      );
    });

    test('不在词表里的项既不 grant 也不 toggle（两格都 false）', () async {
      // ⚠ 这一条守的是"switch 的 default 不是兜底成功"。
      //   而判据要能观察到它，就需要一个词表外的键 —— 契约的
      //   `parseL3Item` 会在更早一格拒掉它，所以这里直接喂执行器。
      const outside = FnthinkL3Setting(key: 'nope', mode: 'grant', native: '');
      expect(await exec.grant(outside), isFalse);
      expect(await exec.toggle(outside), isFalse);
    });
  });

  group('L3 执行器：toggle（协议级非幂等，见类注释的裁决项）', () {
    late bool running;
    late bool inbox;
    late List<bool> listenerWrites;
    late List<bool> inboxWrites;

    setUp(() {
      running = false;
      inbox = false;
      listenerWrites = [];
      inboxWrites = [];
    });

    DeviceL3Executor build() => DeviceL3Executor(
      grantNotificationListener: () async {},
      grantExactAlarm: () async {},
      grantBatteryOptimization: () async {},
      grantVendorAutoStart: () async {},
      serviceRunning: () async => running,
      setListenerEnabled: ({required bool enabled}) async {
        listenerWrites.add(enabled);
        running = enabled;
        return true;
      },
      collectInboxEnabled: () async => inbox,
      setCollectInboxEnabled: (enabled) async {
        inboxWrites.add(enabled);
        inbox = enabled;
        return true;
      },
    );

    test('monitoring：当前关 ⇒ 写开；当前开 ⇒ 写关', () async {
      running = false;
      expect(await build().toggle(contract.l3Settings['monitoring']!), isTrue);
      expect(listenerWrites, [true]);

      listenerWrites.clear();
      running = true;
      expect(await build().toggle(contract.l3Settings['monitoring']!), isTrue);
      expect(listenerWrites, [false]);
    });

    test('collect_inbox：当前关 ⇒ 写开；当前开 ⇒ 写关', () async {
      inbox = false;
      expect(
        await build().toggle(contract.l3Settings['collect_inbox']!),
        isTrue,
      );
      expect(inboxWrites, [true]);

      inboxWrites.clear();
      inbox = true;
      expect(
        await build().toggle(contract.l3Settings['collect_inbox']!),
        isTrue,
      );
      expect(inboxWrites, [false]);
    });

    test('写的那一格抛异常 ⇒ false', () async {
      final throwing = DeviceL3Executor(
        grantNotificationListener: () async {},
        grantExactAlarm: () async {},
        grantBatteryOptimization: () async {},
        grantVendorAutoStart: () async {},
        serviceRunning: () async => false,
        setListenerEnabled: ({required bool enabled}) async =>
            throw StateError('boom'),
        collectInboxEnabled: () async => false,
        setCollectInboxEnabled: (enabled) async => true,
      );
      expect(
        await throwing.toggle(contract.l3Settings['monitoring']!),
        isFalse,
      );
    });
  });
}
