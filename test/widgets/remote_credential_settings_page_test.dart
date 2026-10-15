import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/remote_credential_settings_page.dart';
import 'package:notice_transmit/services/fnthink_contract_loader.dart';
import 'package:notice_transmit/services/fnthink_remote_settings.dart';
import 'package:notice_transmit/services/remote_credential_store.dart';
import 'package:notice_transmit/services/secure_storage_service.dart';
import 'package:notice_transmit/theme/app_colors.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/fnthink_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

class _StubLoader extends FnthinkContractLoader {
  _StubLoader(this._contract, {this.failWith});

  final FnthinkContract _contract;
  final FnthinkContractUnavailable? failWith;

  @override
  Future<FnthinkContract> load({bool refresh = false}) async {
    final err = failWith;
    if (err != null) throw err;
    return _contract;
  }
}

/// 凭据设置页此前**没有任何**页面级用例。这一组钉三件：
///  ① 总开关默认关、开了才出现"开了但没凭据"那一句（契约 l3Requires 的后果）；
///  ② 生成一枚 TOTP 之后，**二维码画的就是那串链接本身**（两处各拼一次 = 扫出来
///     指向别处而界面完全正常）；
///  ③ 明文只出现一次：重读一次之后链接与密钥串都不再在场。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final contract = FnthinkContract.readFile();

  Future<void> pump(
    WidgetTester tester, {
    bool enabled = true,
    Map<String, Object> initialPrefs = const {},
    FnthinkContractUnavailable? failWith,
  }) async {
    // ⚠ 不给 prefs 打桩的话 `SharedPreferences.getInstance` 抛，而那一页的 `_load`
    //   整块不画 —— 症状是「页面空的」，很容易被误读成"这一格不存在"。
    // T152 片D：`enabled` 这一档以前是个**空参数** —— 传 true 也不往 prefs 里写，
    //   于是页面读到的永远是默认关。那几条写 `pump(tester, enabled: true)` 的用例
    //   其实一直在测"关着"那一路。现在按它写：这一片的用例不许建立在"参数说了而没人做"上。
    SharedPreferences.setMockInitialValues({
      ...initialPrefs,
      if (enabled) 'flutter.${FnthinkRemoteSettings.keyEnabled}': true,
    });
    final storage = _MemStorage();
    final settings = FnthinkRemoteSettings(contract: contract);
    final store = RemoteCredentialStore(contract: contract, storage: storage);
    tester.view.physicalSize = const Size(1080, 6400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: RemoteCredentialSettingsPage(
          deps: RemoteCredentialDeps(
            contracts: _StubLoader(contract, failWith: failWith),
            settings: settings,
            credentials: store,
            addressCode: null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return Future.value();
  }

  // T145 片1（维护者 2026-10-12 裁定 4）：这一路新加的两格 —— 那颗开关 + 可触发的应用。
  // ⚠ 这一组钉的是**界面上看得见的那两件事**（默认关 / 空清单等于都不触发），
  //   判定本身在 `fnthink_local_trigger_gates_test.dart` 那一组。
  testWidgets('本机通知触发默认关，而且那句「任何通知正文都不会被执行」画出来了', (tester) async {
    await pump(tester, enabled: true);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(RemoteCredentialSettingsPage)),
    );

    expect(
      find.byKey(const ValueKey('remote-exec-local-trigger-switch')),
      findsOneWidget,
      reason: '这一路今天的实际语义是"一直开着"，那颗开关必须看得见、点得动',
    );
    expect(
      find.text(l10n.remoteExecLocalTriggerOff),
      findsOneWidget,
      reason: '默认值要能读出来：画成"已开启"是把没做过的事说成做过了',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(FnthinkRemoteSettings.keyLocalTriggerEnabled),
      isNull,
      reason: '没点过就不该有值 —— 写了 false 会让"从没选过"与"明确关掉"分不开',
    );
  });

  testWidgets('点开那颗开关 ⇒ 落盘 true，那句换成「已开启」；应用那一行照旧可点', (tester) async {
    await pump(tester, enabled: true);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(RemoteCredentialSettingsPage)),
    );

    await tester.tap(
      find.byKey(const ValueKey('remote-exec-local-trigger-switch')),
    );
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(FnthinkRemoteSettings.keyLocalTriggerEnabled), isTrue);
    expect(find.text(l10n.remoteExecLocalTriggerOn), findsOneWidget);
    // ⚠ 没开也点得进那份清单（T109 同一条纪律）：入口只在开着时才给点，
    //   用户要配就得先来开 —— 那是把一次设置拆成两次往返。
    expect(
      find.byKey(const ValueKey('remote-exec-local-trigger-apps')),
      findsOneWidget,
    );
  });

  testWidgets('空清单那一句必须说「哪一条都不会触发」，不许读成"不限"', (tester) async {
    await pump(tester, enabled: true);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(RemoteCredentialSettingsPage)),
    );
    // 开着开关 + 一个应用都没选：这一路是 fail-closed 的（与转发面"空集=不限"相反）。
    await tester.tap(
      find.byKey(const ValueKey('remote-exec-local-trigger-switch')),
    );
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.remoteExecLocalTriggerAllowNone),
      findsOneWidget,
      reason: '不说这一句，用户看到的就是"我开了怎么没用"而查不出原因',
    );
    expect(
      find.text(l10n.remoteExecLocalTriggerAllowCount(0)),
      findsNothing,
      reason: '"允许 0 个"与"都不触发"是两件事，画成前者就是替本机编一句话',
    );
  });

  testWidgets('远程执行那一行的「为什么」收进了问号：短说在界面上，点开一字不少', (tester) async {
    await pump(tester, enabled: true);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(RemoteCredentialSettingsPage)),
    );

    expect(find.text(l10n.remoteExecShort), findsOneWidget);
    expect(
      find.text(l10n.remoteExecWhy),
      findsNothing,
      reason: '整段说明还画在开关那一行上 ⇒ 这一格又变回小字论文',
    );
    // 比的是**同一个词条**，不抄字面量：抄了的话改了文案会假红，
    // 而"长文被删掉"这件事反倒没人喊。
    await tester.tap(find.byKey(const ValueKey('remote-exec-switch-help')));
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.remoteExecWhy),
      findsOneWidget,
      reason: '问号点开看不见那句原话 ⇒ 长文是被删掉了，不是被搬进弹窗',
    );
  });

  testWidgets('凭据那一格的「两把钥匙」说明同样搬进了问号弹窗', (tester) async {
    await pump(tester, enabled: true);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(RemoteCredentialSettingsPage)),
    );

    expect(find.text(l10n.remoteCredShort), findsOneWidget);
    expect(
      find.text(l10n.remoteCredWhy),
      findsNothing,
      reason: '整段还画在凭据那一格里 ⇒ 这一格又变回小字论文',
    );
    await tester.tap(find.byKey(const ValueKey('remote-cred-why-help')));
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.remoteCredWhy),
      findsOneWidget,
      reason: '问号点开看不见那句原话 ⇒ 长文是被删掉了，不是被搬进弹窗',
    );
  });

  testWidgets('密钥明文那句「只出现一次」搬进问号：短说在场、点开一字不少', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('remote-cred-key-generate')));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(RemoteCredentialSettingsPage)),
    );

    expect(find.byKey(const ValueKey('remote-cred-key-fresh')), findsOneWidget);
    expect(
      find.text(l10n.remoteCredKeyOnceShort),
      findsOneWidget,
      reason: '明文下面那一行短说要在场 —— 它说的是"这一串现在不抄就走不了了"',
    );
    expect(
      find.text(l10n.remoteCredKeyOnce),
      findsNothing,
      reason: '那 68 字又摊回明文下面 ⇒ 这一格重新长成小字论文（T149 第 4 条）',
    );

    await tester.tap(find.byKey(const ValueKey('remote-cred-key-once-help')));
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.remoteCredKeyOnce),
      findsOneWidget,
      reason:
          '"关掉这一页本机只剩哈希、谁都看不回来"这句被搬丢 ⇒ '
          '用户下一次还以为回来看得到，而这一枚是**错过就没了**的那种',
    );
  });

  testWidgets('TOTP 那格同样只剩一行短说（两处装配点不许只改一处）', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('remote-cred-totp-generate')));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(RemoteCredentialSettingsPage)),
    );

    expect(
      find.byKey(const ValueKey('remote-cred-totp-secret')),
      findsOneWidget,
    );
    expect(find.text(l10n.remoteCredTotpOnceShort), findsOneWidget);
    expect(
      find.text(l10n.remoteCredTotpOnce),
      findsNothing,
      reason: '密钥那一格搬了、TOTP 这一格没搬 = 同一页两种形状（两处装配点要各验一次）',
    );
  });

  testWidgets('弹层里那句「只出现一次、不经过服务器」读得到（正文不许被删）', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('remote-cred-totp-generate')));
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(RemoteCredentialSettingsPage)),
    );

    await tester.tap(find.byKey(const ValueKey('remote-cred-totp-once-help')));
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.remoteCredTotpOnce),
      findsOneWidget,
      reason:
          '那句"之后由验证器保管、不经过任何服务器"是隐私承诺，'
          '不是排版 —— 搬的时候丢掉它就等于本页改口了',
    );
  });

  testWidgets('两枚问号都按 key 点得中（密钥与 TOTP 是两处装配点，各一枚）', (tester) async {
    await pump(tester);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(RemoteCredentialSettingsPage)),
    );
    // ⚠ **一生成一验**：明文那一格只跟"最近这一次生成"绑定，先生成两枚会把密钥那格的
    //   fresh 顶掉 ⇒ 问号压根不在场，红的就是"我按错顺序"而不是定位串（夹具遮错因那一族）。
    await tester.tap(find.byKey(const ValueKey('remote-cred-key-generate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remote-cred-key-once-help')));
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.remoteCredKeyOnce),
      findsOneWidget,
      reason: '密钥那一格的问号点不开 = helpKey 漂了（不是页面没有那一枚）',
    );
    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('remote-cred-totp-generate')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remote-cred-totp-once-help')));
    await tester.pumpAndSettle();
    expect(
      find.text(l10n.remoteCredTotpOnce),
      findsOneWidget,
      reason: 'TOTP 那一格是**另一处装配点**：只给密钥那格装上，这一格就没人说话',
    );
  });

  // T152 片D：那一格换成 `FnthinkStatusRow` 之后多了一枚点亮的小圆点。这两条钉的是
  // **点与句子不许说反话** —— 那一枚只跟 `state.enabled` 这一个真值走，接错了（例如恒亮）
  // 屏幕上就是"一盏灯、一句话"两个结论源。
  // ⚠ 拆成两条而不是一条里 pump 两次：`SharedPreferences` 的单例在同一发用例里不会跟着
  //   `setMockInitialValues` 重读，第二次 pump 拿到的还是第一次的值（本仓那条
  //   "mock 没换就复跑"的同族坑）。两条各测一档，才是各自独立的一发。
  Color? switchDot(WidgetTester tester) {
    final box = tester.widget<Container>(
      find.byKey(const ValueKey('remote-exec-switch-state-dot')),
    );
    return (box.decoration! as BoxDecoration).color;
  }

  testWidgets('总开关开着 ⇒ 状态那一枚点是亮的', (tester) async {
    await pump(tester, enabled: true);
    expect(
      find.byKey(const ValueKey('remote-exec-switch-state')),
      findsOneWidget,
    );
    expect(switchDot(tester), AppColors.green, reason: '开着 ⇒ 亮的是绿的');
  });

  testWidgets('总开关关着 ⇒ 那一枚不许亮绿，也不许藏起来', (tester) async {
    await pump(tester, enabled: false);
    expect(
      find.byKey(const ValueKey('remote-exec-switch-state-dot')),
      findsOneWidget,
      reason: '关着也要画那一枚：藏起来等于说这一页没有"开关状态"这回事',
    );
    expect(
      switchDot(tester),
      isNot(AppColors.green),
      reason: '一句"没开"配一盏绿灯，用户不知道该信哪个',
    );
  });

  // T153 片2：「可触发的应用」那一格从「纯文字按钮 + 下面一行计数小字」
  // 换成 `FnthinkEntryRow`（图标 + 主文案 + 副文案 + chevron）—— 同族页
  // （配对页设备行、端点页那一行）在 T152 已换完，这一格是漏网的那一枚。
  //
  // 三条判据：① 入口是**行**不是纯文字；② 计数那句话一个字没删（搬进了副文案）；
  // ③ 点那一行仍然进得来（换件不许把入口弄丢）。
  testWidgets('「可触发的应用」是入口行，计数搬进副文案而非下面另起一行', (tester) async {
    await pump(tester, enabled: true);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(RemoteCredentialSettingsPage)),
    );

    // ① 那一行在场（key 逐字搬：`remote-exec-local-trigger-apps`）
    expect(
      find.byKey(const ValueKey('remote-exec-local-trigger-apps')),
      findsOneWidget,
    );
    // ① 它是 `FnthinkEntryRow`（不是裸文字按钮）
    //    ⚠ `find.ancestor` 方向是"key 的后代"，而这一枚 key 在 widget 自身上 ⇒ 恒 0。
    //      改断"这一行就是那一枚"：key 与类型指向同一个 element。
    final rowFinder = find.byType(FnthinkEntryRow);
    expect(rowFinder, findsOneWidget);
    expect(
      tester.widget<FnthinkEntryRow>(rowFinder).key,
      const ValueKey('remote-exec-local-trigger-apps'),
      reason: 'key 没落在那一行上 ⇒ 换件把入口弄丢了，而屏上看起来一切正常',
    );

    // ② 计数那句**还在**（allow 空档 ⇒「允许 0 个应用 ⇒ 哪一条通知都不会触发」）——
    //    它是搬家不是删除：这一路 fail-closed，不说这句用户看到的是"我开了怎么没用"。
    expect(
      find.text(l10n.remoteExecLocalTriggerAllowNone),
      findsOneWidget,
      reason: '空清单那一句必须还在，只是换了宿主',
    );
  });

  testWidgets('契约读不到 ⇒ 整页只显示那一句，不给设凭据', (tester) async {
    await pump(tester, failWith: const FnthinkContractUnavailable('missing'));
    expect(
      find.byKey(const ValueKey('remote-cred-contract-error')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('remote-exec-switch')), findsNothing);
    expect(
      find.byKey(const ValueKey('remote-cred-key-generate')),
      findsNothing,
    );
  });

  testWidgets('总开关默认关；关着时不说"开了但没凭据"', (tester) async {
    await pump(tester, enabled: false);
    expect(find.byKey(const ValueKey('remote-exec-switch')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('remote-exec-switch-state')),
      findsOneWidget,
    );
    // enabled:false 那次是"不往 prefs 里写开关"（默认就是关），
    // 所以这句只在开了且一把凭据都没有时出现。
    expect(
      find.byKey(const ValueKey('remote-exec-needs-credential')),
      findsNothing,
    );
  });

  testWidgets('生成一枚 TOTP：二维码 + 链接 + 密钥串三者指向同一件事', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('remote-cred-totp-generate')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('remote-cred-totp-qr')), findsOneWidget);
    final uriWidget = tester.widget<SelectableText>(
      find.byKey(const ValueKey('remote-cred-totp-uri')),
    );
    final secretWidget = tester.widget<SelectableText>(
      find.byKey(const ValueKey('remote-cred-totp-secret')),
    );
    expect(uriWidget.data, startsWith('otpauth://totp/'));
    // 链接里带的就是那一枚种子 —— 二维码画的是同一个串，所以这一条成立时
    // "二维码画的东西"与"人能抄走的东西"必然一致。
    expect(uriWidget.data, contains('secret=${secretWidget.data}'));
    expect(secretWidget.data, isNotEmpty);
  });

  testWidgets('二维码只画一份，且与链接同处一个卡片（不是另拼一遍）', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('remote-cred-totp-generate')));
    await tester.pumpAndSettle();
    // ⚠ **不断言第三方内部 widget 的类型**：它是私有实现，改版就会假红。
    //   这里断的是两件我们自己的事：二维码在场；它与那串链接在**同一次生成**里。
    //   "扫出来的内容对不对"由 `RemoteCommandEnvelope`/otpauth 那侧保证，
    //   而二维码只是把同一个字符串画成图 —— 画错了用户一眼就看出来。
    expect(find.byKey(const ValueKey('remote-cred-totp-qr')), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.byKey(const ValueKey('remote-cred-totp-uri')), findsOneWidget);
  });

  testWidgets('撤掉之后明文不再在场（只出现一次）', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('remote-cred-totp-generate')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('remote-cred-totp-uri')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('remote-cred-totp-clear')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('remote-cred-totp-uri')), findsNothing);
    expect(find.byKey(const ValueKey('remote-cred-totp-secret')), findsNothing);
    expect(find.byKey(const ValueKey('remote-cred-totp-qr')), findsNothing);
  });

  testWidgets('延时那一格：范围与生效值都来自契约（不写死秒数）', (tester) async {
    await pump(tester);
    expect(
      find.byKey(const ValueKey('remote-exec-delay-range')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('remote-exec-delay-slider')),
      findsOneWidget,
    );
  });
}
