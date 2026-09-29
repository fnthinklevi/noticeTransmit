import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/fnthink_push_page.dart';
import 'package:notice_transmit/services/fnthink_contract_loader.dart';
import 'package:notice_transmit/services/fnthink_credential_store.dart';
import 'package:notice_transmit/services/fnthink_identity_service.dart';
import 'package:notice_transmit/services/fnthink_receive_coordinator.dart';
import 'package:notice_transmit/services/fnthink_receive_loop.dart';
import 'package:notice_transmit/services/fnthink_receiver_service.dart';
import 'package:notice_transmit/services/fnthink_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_setup.dart';

/// 幻念推送页（T44 的②③ + T42 的入口那半）—— 整条收货链路唯一的用户入口。
///
/// 这里钉的全是"界面说的话是不是真话"，每条都有一个"写歪了用户会怎么被骗"：
///  ① 只是**看一眼**这一页，不该生成任何凭证、不该动 KeyStore、不该把循环起来；
///  ② 起不来的时候不许把开关回弹 —— prefs 里已经是"开"的那一份，回弹说的是"你没点上"这句假话；
///     真相要两格分开：开关=用户要的，状态行=实际的，中间贴服务端/本机给的原话；
///  ③ "上一轮还在途"、"开关没开"、"这一轮取到 0 条"是三件不同的事，不许都显示成第三句；
///  ④ 换地址码必须**重启**循环：循环握的是启动那一刻定型的码，继续跑等于拿旧码签新的请求；
///  ⑤ 那笔账上界面时不许带标题与正文。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final contract = FnthinkContract.readFile();
  late Map<String, String?> disk;

  setUp(() {
    disk = {};
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(clearNativeChannelStubs);

  /// `flutter_secure_storage` 与 `getFnthinkIdentity` 共用一枚桩：`disk` 就是那台机的加密盘。
  void stubChannels({bool identityOk = true}) {
    stubNativeChannels(
      onCall: (call) async {
        switch (call.method) {
          case 'read':
            return disk[call.arguments['key'] as String];
          case 'write':
            disk[call.arguments['key'] as String] =
                call.arguments['value'] as String?;
            return null;
          case 'delete':
            disk.remove(call.arguments['key'] as String);
            return null;
          case 'getFnthinkIdentity':
            if (!identityOk) return null;
            return <String, Object?>{
              'publicKey': 'AAAApublicKeyBytesForTests',
              'plan': 'androidKeyStoreEd25519',
              'keystoreBacked': true,
            };
          default:
            return null;
        }
      },
    );
  }

  final validAddress = FnthinkAddressCode.generate(contract).value;
  final validPairing = FnthinkPairingCode.generate(contract).value;

  /// 一套装配：可控的签名能力 + 只记账不碰网络的循环 + 数得到"循环被建了几次"。
  _Harness harness({
    bool canSign = true,
    List<String> messages = const [],
    int pending = 0,
    Future<void> Function()? gate,
    bool contractOk = true,
  }) {
    final loader = FnthinkContractLoader(
      readAsset: (_) async {
        if (!contractOk) return '{ 这不是合法 JSON';
        return File('protocol/fnthink-v1.json').readAsStringSync();
      },
    );
    var builds = 0;
    final coordinator = FnthinkReceiveCoordinator(
      contracts: loader,
      signer: _StubSigner(canSign),
      persist: (_) async => true,
      loopFactory: (spec) {
        builds++;
        return FnthinkReceiveLoop(
          poll: () async {
            if (gate != null) await gate();
            return FnthinkReceiveOutcome(
              status: FnthinkPollStatus.ok,
              messages: [
                for (final id in messages)
                  FnthinkDelivered(
                    messageId: id,
                    type: 'notice',
                    item: '',
                    title: '机箱温度',
                    body: '温度 63 度（$id）',
                    sender: 'endpoint:ep_7',
                  ),
              ],
              pending: pending,
              nextDelay: const Duration(seconds: 20),
            );
          },
          ack: (id, result) async => const FnthinkAckResult(
            status: FnthinkPollStatus.ok,
            nextDelay: Duration(seconds: 20),
          ),
          persist: (_) async => true,
          schedule: (delay, callback) => Timer(Duration.zero, () {}),
        );
      },
    );
    return _Harness(
      page: FnthinkPushPage(
        deps: FnthinkPushDeps(
          contracts: loader,
          coordinator: coordinator,
          identity: FnthinkIdentityService(),
        ),
      ),
      coordinator: coordinator,
      builds: () => builds,
    );
  }

  Future<AppLocalizations> pump(WidgetTester tester, Widget page) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: page,
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byType(FnthinkPushPage)));
  }

  group('看一眼不该发生的事', () {
    testWidgets('还没生成地址码 ⇒ 明说"还没生成"，并且盘上一个键都没写', (tester) async {
      stubChannels();
      final h = harness();
      final l10n = await pump(tester, h.page);
      expect(
        find.text(l10n.fnthinkAddressCodeNone),
        findsOneWidget,
        reason: '空白会被读成"坏了"，而事实是还没到过需要它的那一刻',
      );
      expect(disk, isEmpty, reason: '只是看了一眼，不该落一枚凭证');
      expect(h.coordinator.isRunning, isFalse, reason: '看页面不等于把循环起来起来');
    });

    testWidgets('契约读不到 ⇒ 只剩那一条原因，开关那一格根本不存在', (tester) async {
      stubChannels();
      final h = harness(contractOk: false);
      await pump(tester, h.page);
      expect(
        find.byKey(const ValueKey('fnthink-contract-error')),
        findsOneWidget,
      );
      expect(
        find.byType(CupertinoSwitch),
        findsNothing,
        reason: '契约不在还让人翻开关，等于把一个值写进没人能解释的地方',
      );
    });

    testWidgets('存量地址码坏掉 ⇒ 原话贴出来，且绝不被自动换掉', (tester) async {
      stubChannels();
      disk[FnthinkCredentialStore.addressCodeKey] = 'TOO_SHORT!';
      final h = harness();
      await pump(tester, h.page);
      expect(
        find.byKey(const ValueKey('fnthink-credential-error')),
        findsOneWidget,
        reason: '自动换一枚的表现不是报错，而是别人白名单里那条指向一台不再存在的设备',
      );
      expect(
        disk[FnthinkCredentialStore.addressCodeKey],
        'TOO_SHORT!',
        reason: '自愈式换码正是这条判据最坏的实现方式',
      );
    });

    testWidgets('身份取不到 ⇒ 说成身份问题，不伪装成网络或未配置', (tester) async {
      stubChannels(identityOk: false);
      final h = harness();
      final l10n = await pump(tester, h.page);
      expect(find.text(l10n.fnthinkKeystoreUnknown), findsOneWidget);
    });
  });

  group('开关那一格与状态那一格', () {
    testWidgets('默认关 ⇒ 开关关着、"立即收取"是灰的', (tester) async {
      stubChannels();
      final h = harness();
      final l10n = await pump(tester, h.page);
      expect(
        tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
        isFalse,
      );
      expect(find.text(l10n.fnthinkStatusIdle), findsOneWidget);
      expect(
        tester
            .widget<ButtonStyleButton>(
              find.byKey(const ValueKey('fnthink-receive-now')),
            )
            .onPressed,
        isNull,
        reason: '关着时点它只会拿回 null，把按钮点亮是请用户来验证一条死路',
      );
    });

    testWidgets('翻开 ⇒ 写进 prefs、循环起来、状态行改口', (tester) async {
      stubChannels();
      final h = harness();
      final l10n = await pump(tester, h.page);
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      final prefs = await SharedPreferences.getInstance();
      // 注意读的是**不带前缀**的那个键：SharedPreferences 自己会加 `flutter.`，
      // 手抄前缀就变成找 `flutter.flutter.…`，那条断言会永远拿到 null（我第一版就是这么红的）。
      expect(prefs.getBool(FnthinkSettings.keyReceiveEnabled), isTrue);
      expect(h.builds(), 1);
      expect(h.coordinator.isRunning, isTrue);
      expect(find.text(l10n.fnthinkStatusRunning), findsOneWidget);
      expect(find.byKey(const ValueKey('fnthink-start-note')), findsNothing);
    });

    testWidgets('起不来 ⇒ 开关**留在开**、原话贴在下面（不回弹、不谎称在跑）', (tester) async {
      stubChannels();
      final h = harness(canSign: false);
      final l10n = await pump(tester, h.page);
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      expect(
        tester.widget<CupertinoSwitch>(find.byType(CupertinoSwitch)).value,
        isTrue,
        reason: 'prefs 已经是开的那一份；回弹说的是"你没点上"，而真实情况是"点上了但起不来"',
      );
      expect(find.text(l10n.fnthinkStatusIdle), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('fnthink-start-note')))
            .data,
        contains('signing-unavailable'),
        reason: '五种起不来各有各的用户动作，归并成"出错了"就没了可诊断性',
      );
      expect(h.builds(), 0, reason: '签名能力没探测过就不该建循环');
    });

    testWidgets('关掉 ⇒ 循环停、状态行改回来', (tester) async {
      stubChannels();
      final h = harness();
      final l10n = await pump(tester, h.page);
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      expect(h.coordinator.isRunning, isFalse);
      expect(find.text(l10n.fnthinkStatusIdle), findsOneWidget);
    });
  });

  group('立即收取那一发', () {
    testWidgets('有货 ⇒ 上界面的是那笔账，而账里没有标题与正文', (tester) async {
      stubChannels();
      final h = harness(messages: const ['m_1'], pending: 2);
      await pump(tester, h.page);
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('fnthink-receive-now')));
      await tester.pumpAndSettle();
      final text = tester
          .widget<Text>(find.byKey(const ValueKey('fnthink-last-round')))
          .data!;
      expect(text, contains('取 1'));
      expect(text, contains('待取 2'));
      expect(text, isNot(contains('机箱温度')));
      expect(text, isNot(contains('温度 63 度')));
    });

    testWidgets('上一轮还在途 ⇒ 说"还在途"，不许说成"取 0 条"', (tester) async {
      stubChannels();
      final gate = Completer<void>();
      final h = harness(gate: () => gate.future, messages: const ['m_1']);
      final l10n = await pump(tester, h.page);
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      // 起循环的那一轮此刻卡在 poll 上，这一发拿回的是"整轮跳过"那份账。
      await tester.tap(find.byKey(const ValueKey('fnthink-receive-now')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.fnthinkReceiveSkipped), findsOneWidget);
      expect(
        find.byKey(const ValueKey('fnthink-last-round')),
        findsNothing,
        reason: '把"跳过"显示成"取 0 条"，用户读到的是"服务器那边没有货"',
      );
      gate.complete();
      await tester.pumpAndSettle();
    });
  });

  group('三件套面板', () {
    testWidgets('挂出口令 ⇒ 口令显示出来，并顺手把地址码补上（口令没有落点的码等于没口令）', (tester) async {
      stubChannels();
      final h = harness();
      await pump(tester, h.page);
      await tester.tap(find.byKey(const ValueKey('fnthink-arm-pairing')));
      await tester.pumpAndSettle();
      expect(disk.containsKey(FnthinkCredentialStore.addressCodeKey), isTrue);
      expect(disk.containsKey(FnthinkCredentialStore.pairingCodeKey), isTrue);
      expect(
        find.text(disk[FnthinkCredentialStore.pairingCodeKey]!),
        findsOneWidget,
      );
    });

    testWidgets('口令挂了多久：时间戳缺失 ⇒ 显示"未知"，不许显示 0 秒', (tester) async {
      stubChannels();
      disk[FnthinkCredentialStore.pairingCodeKey] = validPairing;
      final h = harness();
      final l10n = await pump(tester, h.page);
      final text = tester
          .widget<Text>(find.byKey(const ValueKey('fnthink-pairing-age')))
          .data!;
      expect(text, l10n.fnthinkPairingHeld(l10n.unknown));
      expect(text, isNot(contains('0')));
    });

    testWidgets('重置地址码：取消 ⇒ 码一个字都不动', (tester) async {
      stubChannels();
      disk[FnthinkCredentialStore.addressCodeKey] = validAddress;
      final h = harness();
      final l10n = await pump(tester, h.page);
      await tester.tap(find.byKey(const ValueKey('fnthink-reset-code')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(disk[FnthinkCredentialStore.addressCodeKey], validAddress);
      expect(h.builds(), 0);
    });

    testWidgets('重置地址码：确认 ⇒ 换新码，并且正在跑的循环被重启（旧码不许继续签）', (tester) async {
      stubChannels();
      disk[FnthinkCredentialStore.addressCodeKey] = validAddress;
      final h = harness();
      final l10n = await pump(tester, h.page);
      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();
      expect(h.builds(), 1);
      await tester.tap(find.byKey(const ValueKey('fnthink-reset-code')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.confirm));
      await tester.pumpAndSettle();
      final fresh = disk[FnthinkCredentialStore.addressCodeKey];
      expect(fresh, isNot(validAddress));
      expect(find.text(fresh!), findsOneWidget);
      expect(h.builds(), 2, reason: '循环手里握的是启动那一刻定型的地址码，不重启就是拿旧码签新的请求');
    });
  });

  group('服务地址', () {
    testWidgets('多写了 scheme ⇒ 贴出校验原话，值一个字都不改', (tester) async {
      stubChannels();
      final h = harness();
      final l10n = await pump(tester, h.page);
      final before = contract.str(const ['transport', 'endpoints', 'default']);
      // 这一格在 ListView 的折叠线以下：不先滚进视口，tap 打在一个够不着的坐标上。
      final edit = find.widgetWithText(TextButton, l10n.edit);
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('fnthink-host-input')),
        'https://Push.Example.COM',
      );
      await tester.tap(find.widgetWithText(TextButton, l10n.save));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('fnthink-host-error')))
            .data,
        contains('scheme'),
      );
      expect(find.text(before!), findsOneWidget, reason: '校验没过就不该改值');
    });

    testWidgets('合法值按归一后的那一份显示（大小写不是两台服务）', (tester) async {
      stubChannels();
      final h = harness();
      final l10n = await pump(tester, h.page);
      // 这一格在 ListView 的折叠线以下：不先滚进视口，tap 打在一个够不着的坐标上。
      final edit = find.widgetWithText(TextButton, l10n.edit);
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('fnthink-host-input')),
        'PUSH.Example:8443',
      );
      await tester.tap(find.widgetWithText(TextButton, l10n.save));
      await tester.pumpAndSettle();
      expect(find.text('push.example:8443'), findsOneWidget);
      expect(find.byKey(const ValueKey('fnthink-host-error')), findsNothing);
      final resetDefault = find.byKey(const ValueKey('fnthink-host-default'));
      await tester.ensureVisible(resetDefault);
      await tester.pumpAndSettle();
      await tester.tap(resetDefault);
      await tester.pumpAndSettle();
      expect(
        find.text(contract.str(const ['transport', 'endpoints', 'default'])!),
        findsOneWidget,
      );
    });
  });
}

class _StubSigner implements FnthinkIdentitySigner {
  _StubSigner(this.canSign);

  final bool canSign;

  @override
  Future<String> call(List<int> canonicalBytes) async => 'AAAAc2ln';

  @override
  Future<bool> probe() async => canSign;
}

class _Harness {
  _Harness({
    required this.page,
    required this.coordinator,
    required this.builds,
  });

  final FnthinkPushPage page;
  final FnthinkReceiveCoordinator coordinator;
  final int Function() builds;
}
