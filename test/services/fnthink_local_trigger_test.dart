import 'dart:async';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:notice_transmit/models/fnthink_remote_execution_record.dart';
import 'package:notice_transmit/services/fnthink_l2_actions.dart';
import 'package:notice_transmit/services/fnthink_l3_settings.dart';
import 'package:notice_transmit/services/fnthink_remote_command_handler.dart';
import 'package:notice_transmit/services/fnthink_remote_execution.dart';
import 'package:notice_transmit/services/fnthink_remote_runner.dart';
import 'package:notice_transmit/services/fnthink_remote_settings.dart';
import 'package:notice_transmit/services/fnthink_remote_wiring.dart';
import 'package:notice_transmit/services/remote_credential_store.dart';
import 'package:notice_transmit/services/remote_execution_notifier.dart';
import 'package:notice_transmit/services/secure_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 白名单通知触发的那一路（契约 `capabilities.remoteExecution.sources.L1` 的第二条来源）。
///
/// 这一组钉的是**安全面**与**接线面**，而原生那一侧的交接（前缀/新鲜期/上限）
/// 由 `android/.../LocalRemoteCommandInboxTest.kt` 钉 —— 那一格 Dart 看不到。
///
/// 最要紧的四条：
///  ① **L2/L3 从这一路走不通**（契约 sources 里它们只有 `fnthink`）——
///     这是"无凭据入口"的三层收窄之一，少了它那条路就是任意 L2 动作的免费执行口；
///  ② 被拒的那一条**要留痕、不发回执**（回执无处可发：没有远端发送方）；
///  ③ `peerAddress` 必须**空** —— 历史页按它判「本机触发」，填了包名会显示成"来自 com.xxx"；
///  ④ drain **一次只取一条**，只调一次会留下后面几条既没执行也没丢弃。
class _MemStorage implements SecureStorageService {
  final Map<String, String> data = {};

  @override
  Future<void> write(String key, String value) async => data[key] = value;

  @override
  Future<String?> read(String key) async => data[key];

  @override
  Future<void> delete(String key) async => data.remove(key);

  @override
  Future<void> clearAll() async => data.clear();

  @override
  Future<void> saveWebhookUrls(List<String> urls) async {}

  @override
  Future<List<String>> loadWebhookUrls() async => const [];

  @override
  Future<void> saveWebhookChannels(String jsonStr) async {}

  @override
  Future<String?> loadWebhookChannels() async => null;
}

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

  @override
  Future<FnthinkL2Result> ringAlert() async => const FnthinkL2Result.ok();

  @override
  Future<({String? payload, String? reason})> searchSms(String keyword) async =>
      (payload: null, reason: 'sms-search-disabled');

  @override
  Future<({String? payload, String? reason})> searchCalls(
    String keyword,
  ) async => (payload: null, reason: 'calls-search-disabled');

  @override
  Future<({String? payload, String? reason})> getLocation() async =>
      (payload: null, reason: 'location-disabled');

  @override
  Future<({String? payload, String? reason})> snapPhoto() async =>
      (payload: null, reason: 'camera-snap-disabled');

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

/// 原生那一格的替身：拿一条少一条；`localInbox` 就是"原生那边攒着的"。
class _FakeNotifier implements RemoteExecutionNotifier {
  final List<String> localInbox = [];
  final List<String> localTaken = [];
  final List<String> shown = [];
  final Set<String> cancelledOutOfBand = {};

  @override
  Future<String?> takeLocalCommand() async {
    if (localInbox.isEmpty) return null;
    final body = localInbox.removeAt(0);
    localTaken.add(body);
    return body;
  }

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
  Future<void> clear(String execId) async {}

  @override
  Future<bool> takeCancelled(String execId) async =>
      cancelledOutOfBand.remove(execId);

  @override
  Future<void> forget(String execId) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final contract = FnthinkContract.readFile();
  final localSource = contract.remoteExecutionLocalTriggerSource;

  late _MemStorage storage;
  late _NoopL2 l2;
  late _FakeNotifier notifier;
  late List<FnthinkRemoteExecutionRecord> saved;
  late List<(String, RemoteReceipt)> receipts;
  late List<void Function()> fired;

  setUp(() {
    storage = _MemStorage();
    l2 = _NoopL2();
    notifier = _FakeNotifier();
    saved = [];
    receipts = [];
    fired = [];
  });

  Future<RemoteCommandWiring> wiring({bool enabled = true}) async {
    SharedPreferences.setMockInitialValues(
      enabled ? {FnthinkRemoteSettings.keyEnabled: true} : <String, Object>{},
    );
    final settings = FnthinkRemoteSettings(contract: contract);
    final store = RemoteCredentialStore(
      contract: contract,
      storage: storage,
      clockMs: () => 1700000000000,
    );
    final runner = RemoteCommandRunner(
      contract: contract,
      windowSeconds: () async => 0,
      l2: l2,
      l3: _NoopL3(),
      saveRecord: (r) async => saved.add(r),
      sendReceipt: (peer, receipt) async {
        receipts.add((peer, receipt));
        return true;
      },
      sendReport: (peer, action, payload) async => true,
      now: () => DateTime.utc(2026, 10, 5, 12),
      // ⚠ 窗口 0 ⇒ 立刻执行且不发状态栏通知（那一格另有用例），
      //   这样本组只看"判没判放行 + 执行器被调没调"。
      schedule: (d, f) {
        fired.add(f);
        return Timer(const Duration(microseconds: 1), () {})..cancel();
      },
      statusBar: notifier,
    );
    addTearDown(runner.dispose);
    return RemoteCommandWiring(
      contract: contract,
      recognizer: RemoteCommandRecognizer(
        contract: contract,
        settings: settings,
        credentials: store,
      ),
      runner: runner,
      notifier: notifier,
      saveRecord: (r) async => saved.add(r),
    );
  }

  String wire({
    String level = 'L1',
    String item = 'listener:start',
    String argument = '',
    String? key,
  }) => RemoteCommandEnvelope.encode(
    level: level,
    item: item,
    argument: argument,
    key: key,
  );

  group('这一路只走得到 L1', () {
    test('L1 白名单指令 ⇒ 真的执行', () async {
      final w = await wiring();
      await w.onLocalContent(wire());
      for (final fire in fired) {
        fire();
      }
      expect(l2.calls, ['setListener(true)']);
    });

    test('载荷写 L2 ⇒ 拒，理由是来源渠道不允许', () async {
      // ⚠ 这一条是"无凭据入口"的核心收窄：sources.L2 只有 fnthink。
      //   没有它，一条白名单通知就能免凭据执行任意 L2 动作。
      final w = await wiring();
      await w.onLocalContent(wire(level: 'L2'));
      for (final fire in fired) {
        fire();
      }
      expect(l2.calls, isEmpty, reason: 'L2 从白名单那一路不许执行');
      expect(saved.single.reason, 'source-not-allowed:L2');
    });

    test('载荷写 L3 ⇒ 拒（且带凭据也不行）', () async {
      final w = await wiring();
      await w.onLocalContent(
        wire(level: 'L3', item: 'monitoring', key: 'a-very-long-key'),
      );
      for (final fire in fired) {
        fire();
      }
      expect(l2.calls, isEmpty);
      expect(saved.single.reason, 'source-not-allowed:L3');
    });

    test('L1 里认不出的 item ⇒ 拒，不许"认不出就跳过"', () async {
      final w = await wiring();
      await w.onLocalContent(wire(item: 'self:destruct'));
      for (final fire in fired) {
        fire();
      }
      expect(l2.calls, isEmpty);
      expect(saved.single.reason, startsWith('item:'));
    });
  });

  group('被拒的那一档：留痕、不回执', () {
    test('留一行，来源是本机触发且 peerAddress 为空', () async {
      final w = await wiring();
      await w.onLocalContent(wire(level: 'L2'));
      final row = saved.single;
      expect(row.source, localSource);
      // ⚠ 历史页按 peerAddress.isEmpty 判「本机应用的通知触发的」，
      //   这里填了值就会显示成"来自 <某地址>"。
      expect(row.peerAddress, isEmpty);
      expect(row.state, RemoteExecutionStates.failed);
    });

    test('不发回执（这一路上没有任何人可以回）', () async {
      final w = await wiring();
      await w.onLocalContent(wire(level: 'L2'));
      expect(receipts, isEmpty, reason: '契约 localTriggerReceipt = none');
    });

    test('幻念推送那一路仍然发回执 —— 判据按来源，不是"永远不发"', () async {
      // ⚠ 对照发：把判据改成"本机触发永远不发回执"，上一条照样绿，
      //   而对面会一直等一条永远不来的回执。这一条盯的是那半张脸。
      // L2 无凭据且 sources.fnthink 允许 ⇒ 放行并执行 ⇒ 两段回执（started + finished）。
      final w = await wiring();
      final msg = FnthinkInboxMessage(
        messageId: 'm_00000001',
        sender: '8K3FJ6QPTM9WZ4VHNS',
        type: 'notice',
        item: '',
        title: '',
        body: wire(level: 'L2'),
        receivedAt: 1700000000000,
      );
      await w.onCommand(msg);
      expect(receipts.map((e) => e.$2.result), ['executing', 'execution_done']);
    });
  });

  group('前两档什么都不做', () {
    test('正文不是指令 ⇒ 不执行、不留痕', () async {
      final w = await wiring();
      await w.onLocalContent('今天天气不错');
      for (final fire in fired) {
        fire();
      }
      expect(l2.calls, isEmpty);
      expect(saved, isEmpty, reason: '通知本身已经显示过了，不该再记一行噪声');
    });

    test('开关关着 ⇒ 不执行、不留痕', () async {
      final w = await wiring(enabled: false);
      await w.onLocalContent(wire());
      for (final fire in fired) {
        fire();
      }
      expect(l2.calls, isEmpty);
      expect(saved, isEmpty);
    });
  });

  group('drain', () {
    test('一次循环把攒着的全取空', () async {
      // ⚠ 原生那一侧一次只给一条；只取一次会把后面几条既没执行也没丢弃。
      final w = await wiring();
      notifier.localInbox.addAll([wire(), wire(item: 'listener:stop'), wire()]);
      expect(await w.drainLocalCommands(), 3);
      for (final fire in fired) {
        fire();
      }
      expect(l2.calls, [
        'setListener(true)',
        'setListener(false)',
        'setListener(true)',
      ]);
      expect(notifier.localInbox, isEmpty);
    });

    test('空的那一堆 ⇒ 一次就停，不空转', () async {
      final w = await wiring();
      expect(await w.drainLocalCommands(), 0);
      expect(notifier.localTaken, isEmpty);
    });

    test('上限生效：取满 maxDrains 就停，剩下的**留在原生那边**', () async {
      final w = await wiring();
      notifier.localInbox.addAll([wire(), wire(item: 'listener:stop'), wire()]);
      expect(await w.drainLocalCommands(maxDrains: 2), 2);
      expect(
        notifier.localInbox,
        hasLength(1),
        reason: '没取的必须还在那儿 —— 丢弃等于静默吞掉一条用户配的自动化指令',
      );
    });

    test('空串（坏值）⇒ 立刻停，不空转', () async {
      // ⚠ 原生 `take()` 永不返空串（`offer` 已判过前缀非空），所以空串只可能是
      //   通道返回了脏值。若循环只认 null，空串会让它**永远转下去**。
      final w = await wiring();
      notifier.localInbox.addAll(['', wire()]);
      expect(await w.drainLocalCommands(), 0);
      expect(notifier.localTaken, ['']);
      expect(notifier.localInbox, [wire()], reason: '后面那条还没轮到，不许被顺手吞掉');
    });
  });
}
