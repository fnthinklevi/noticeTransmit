import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/fnthink_settings_page.dart';
import 'package:notice_transmit/services/fnthink_contract_loader.dart';
import 'package:notice_transmit/services/fnthink_endpoint_probe.dart';
import 'package:notice_transmit/services/fnthink_identity_service.dart';
import 'package:notice_transmit/services/fnthink_receive_coordinator.dart';
import 'package:notice_transmit/services/fnthink_receiver_service.dart'
    show FnthinkIdentitySigner;
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/source_guards.dart';
import '../test_setup.dart';

/// T155：**服务器上的契约是旧的那一份**时，设置页那一句在场。
///
/// 这一族钉四件事，缺一件就有一类失效能静默回来：
///  ① 三档分得开 —— `mismatch` / `unreadable` 画，`match` 与 `null` **都不画**；
///  ② 「没读数」绝不画成「一致」（那是凭空报功，与本页健康度那一格的口径相反）；
///  ③ 那句话说的是**服务器**那份 —— 方向写反的话用户会去清本机缓存，而病根在服务器上；
///  ④ 读口是**纯函数**：三档原样带回，折成布尔的那一版会让「读不出来」与「一致」同形。
///
/// ⚠ harness 照 `fnthink_settings_page_test.dart` 抄，不自己造：
///   第一版自己造了一版（少注册一个 GetIt、`setMockInitialValues` 放错位置），
///   现场是 `_load()` 抛在中途 ⇒ `_host` 停在 `''`、屏上写着 `—`，
///   而契约与默认值都读得到 —— **看着像"契约坏了"，实际是 DI/时序**。
///   这个坑值得记：页面级用例的 harness 坏掉时，症状会伪装成产品缺陷。
///
/// 按 key 找，不按文案：那一格与本页其它状态行共用同一枚公共件。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final contract = FnthinkContract.readFile();

  Key contractRow() => const ValueKey('fnthink-contract-version-row');

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'flutter.${'fnthink.consent_version'}': 1,
    });
    GetIt.instance.registerSingleton<FnthinkIdentityService>(
      FnthinkIdentityService(),
    );
    stubNativeChannels();
  });

  tearDown(() {
    clearNativeChannelStubs();
    GetIt.instance.reset();
  });

  Future<void> pumpSettings(WidgetTester tester, {Object? verdict}) async {
    final loader = FnthinkContractLoader(
      readAsset: (_) async =>
          File('protocol/fnthink-v1.json').readAsStringSync(),
    );
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: FnthinkSettingsPage(
          deps: FnthinkSettingsDeps(
            contracts: loader,
            coordinator: FnthinkReceiveCoordinator(
              contracts: loader,
              signer: _StubSigner(),
              persist: (_) async => true,
            ),
            identity: FnthinkIdentityService(),
            healthOf: (_) => null,
            // 探测这一发做两件事：把契约声明的那些 host 答一遍，并把
            // `/health` 正文里那一格交给页面（T155 新增的那个口）。
            probeHosts: (hosts, {onHealthBody}) async {
              for (final h in hosts) {
                onHealthBody?.call(h, {
                  if (verdict != null)
                    contract.versionEchoHealthKey: '$verdict',
                });
              }
              return {
                for (final h in hosts) h: const Duration(milliseconds: 20),
              };
            },
            recordHealth:
                ({
                  required String host,
                  required bool reachable,
                  required int latencyMs,
                }) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 打开「切换服务」那一格（探测在那里跑）**然后关掉**。
  ///
  /// ⚠ 必须关掉才能断言：那一格挂在**主页面**的服务器卡片上，而探测跑在
  ///   `_pickHostRegion` 里（**弹层打开之前**就跑完了）。弹层还开着时，
  ///   下面量到的是"它在树上"，而用户看到的是弹层 —— 判据量错了对象。
  Future<void> probeThenClose(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('fnthink-host-switch')));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(20, 20)); // 点外面关掉
    await tester.pumpAndSettle();
    // ⚠ **再空一拍**：`_probeDeclaredHosts` 的 `setState` 在 `record` 那个循环**之后**，
    //   而 `record` 是 await 的 ⇒ 弹层关掉那一刻那一格可能还没进下一帧。
    //   少这一拍的话「正向不画 / 负向不画」两类用例会一起绿 ——
    //   而它们绿的原因与被测的判据无关。
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
  }

  AppLocalizations l10nOf(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(FnthinkSettingsPage)));

  testWidgets('mismatch ⇒ 那一格在场，说的是「服务器上的协议是旧的」', (tester) async {
    await pumpSettings(tester, verdict: 'mismatch');
    await probeThenClose(tester);

    expect(
      find.byKey(contractRow()),
      findsOneWidget,
      reason: '这一格不见了 ⇒ 最要紧的那一档被静默掉了',
    );
    expect(
      find.text(l10nOf(tester).fnthinkContractVersionMismatch),
      findsOneWidget,
    );
    expect(
      find.text(l10nOf(tester).fnthinkContractVersionUnreadable),
      findsNothing,
      reason: '说的是"不一致"，就不许同时挂上"读不出来"那句',
    );
  });

  testWidgets('unreadable ⇒ 画的是**另一句**（不与"不一致"折成同一句）', (tester) async {
    await pumpSettings(tester, verdict: 'unreadable');
    await probeThenClose(tester);

    expect(
      find.text(l10nOf(tester).fnthinkContractVersionUnreadable),
      findsOneWidget,
    );
    expect(
      find.text(l10nOf(tester).fnthinkContractVersionMismatch),
      findsNothing,
      reason: '两档折成同一句 ⇒ "读不出来"与"确实不一致"在界面上分不开',
    );
  });

  testWidgets('⚠ 一致时不画那一格（没有要说的事就不占一格）', (tester) async {
    await pumpSettings(tester, verdict: 'match');
    await probeThenClose(tester);

    expect(find.byKey(contractRow()), findsNothing);
  });

  testWidgets('⚠ 没读数（服务器没这一格）同样不画 —— 不许画成"一致"', (tester) async {
    await pumpSettings(tester, verdict: null);
    await probeThenClose(tester);

    expect(
      find.byKey(contractRow()),
      findsNothing,
      reason:
          'null 有两个来路（没收到过 / 服务器没部署关联键），而"没有读数"画成一句'
          '"一致"就是凭空报功 —— 本页健康度那一格不这么干',
    );
    expect(
      find.text(l10nOf(tester).fnthinkContractVersionMismatch),
      findsNothing,
    );
  });

  testWidgets('反向自证：harness 真的照得出档位差别（否则上面三条是假绿）', (tester) async {
    // 单独成条，不与第一条合并：它量的是「这个 harness 有效」，
    // 而不是「mismatch 那一档画了」。合成一条的话，将来 harness 整体哑掉
    // （DI 少注册、时序不对），mismatch 那条会跟着红 ——
    // 而报告上写的是「档位判错」，指错方向。
    await pumpSettings(tester, verdict: 'mismatch');
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('fnthink-host-value')))
          .data,
      isNot('—'),
      reason:
          '前置：页面 `_load()` 跑完了整条链（服务地址那一格有值）。'
          '它停在 `—` ⇒ `_load` 中途抛了 ⇒ 下面所有断言都在量一个半开的页面',
    );
    await probeThenClose(tester);
    expect(find.byKey(contractRow()), findsOneWidget);
  });

  test('读口：三档原样带回，不折成布尔（纯函数，不开网络）', () {
    final key = contract.versionEchoHealthKey;
    expect(key, isNotEmpty, reason: '前置：仓库那份契约声明了这一格');

    expect(readClientContractVerdict({key: 'match'}, key), 'match');
    expect(readClientContractVerdict({key: 'mismatch'}, key), 'mismatch');
    expect(readClientContractVerdict({key: 'unreadable'}, key), 'unreadable');

    // 缺这一格 = 没读数（null），与服务端 `/health` 回的 null 同形
    expect(readClientContractVerdict(const {}, key), isNull);

    // ⚠ 回成别的类型（形状变了）⇒ 如实报 unreadable，不猜成"一致"
    expect(readClientContractVerdict({key: 1}, key), 'unreadable');
    expect(readClientContractVerdict({key: true}, key), 'unreadable');

    // ⚠ 键名为空（契约缺 `versionEcho` 段）⇒ 不画那一格，而不是回一个"看起来
    //   像读数"的 null：空串会让 `body['']` 恒不存在，而那与"服务器没这一格"
    //   在页面上同形 —— 分开它们对用户没意义，可一旦有人把空串当成有效键名
    //   传进来，这条就是唯一挡住它的东西。
    expect(readClientContractVerdict({'': 'mismatch'}, ''), isNull);
  });

  // ⚠ 第一版给 [readClientContractVerdict] 的键名参数设了默认值（走
  //   `FnthinkContract.readFile()`），被 `fnthink_contract_loader_test.dart`
  //   「lib/ 里除了这个文件没人自己读契约」当场喊红。那条守卫是对的：
  //   `readFile` 按"向上找仓库根"定位，**设备沙箱里没有仓库根** ⇒ 真机上会抛。
  //   这条判的是**签名**（不是实现），因为正是那个默认值让 lib/ 里长出了那一声调用。
  test('⚠ 读口不许自己找契约：键名必填，lib/ 里零个 readFile 调用点', () {
    final src = File(
      'lib/services/fnthink_endpoint_probe.dart',
    ).readAsStringSync();
    // ⚠ 必须剥注释再判：这个函数的**说明里**就写着 `FnthinkContract.readFile()`（讲
    //   它为什么被删），不剥就会把说明读成调用 —— 与既有守卫同一条教训。
    expect(
      stripComments(src).contains('FnthinkContract.readFile'),
      isFalse,
      reason:
          '探针自己去磁盘找契约 ⇒ 真机上找不到仓库根而抛（守卫 '
          '`fnthink_contract_loader_test.dart` 量的是同一条纪律）。'
          '键名要由手上已经握着契约的调用方交进来',
    );
    // 正向自证：这把尺得认得出**确实存在**的那一声，否则上面那句是恒真。
    expect(
      stripComments(src).contains('readClientContractVerdict'),
      isTrue,
      reason: '尺退化成"这份文件里没有那串字"⇒ 负向断言量不到任何东西',
    );
    // 尺的第二维：剥注释这一步本身得有效 —— 喂一段**只在注释里**出现的目标串，
    //   剥完必须读不到。喂得进来说明这一维退化成恒真。
    expect(
      stripComments(
        '// FnthinkContract.readFile()\nvoid f() {}',
      ).contains('FnthinkContract.readFile'),
      isFalse,
      reason: '剥注释这一维没生效 ⇒ 上面那句量的是"连注释里都躲不掉"',
    );
  });
}

/// 假的签名注入点（与 `fnthink_settings_page_test.dart` 同一形状）。
/// 本页这一批用例不测签名，但协调者要一个真的 —— 传替身会让「页面起不来」
/// 与「那一格没画」在报告上同形。
class _StubSigner implements FnthinkIdentitySigner {
  @override
  Future<String> call(List<int> canonicalBytes) async => 'AAAAc2ln';

  @override
  Future<bool> probe() async => true;

  @override
  Future<String?> publicKey() async => 'cHVibGljLWtleQ==';
}
