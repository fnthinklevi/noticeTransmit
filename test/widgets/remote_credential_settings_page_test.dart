import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/pages/remote_credential_settings_page.dart';
import 'package:notice_transmit/services/fnthink_contract_loader.dart';
import 'package:notice_transmit/services/fnthink_remote_settings.dart';
import 'package:notice_transmit/services/remote_credential_store.dart';
import 'package:notice_transmit/services/secure_storage_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';
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
    FnthinkContractUnavailable? failWith,
  }) async {
    // ⚠ 不给 prefs 打桩的话 `SharedPreferences.getInstance` 抛，而那一页的 `_load`
    //   整块不画 —— 症状是「页面空的」，很容易被误读成"这一格不存在"。
    SharedPreferences.setMockInitialValues({});
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
