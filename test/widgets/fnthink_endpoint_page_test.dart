import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/pages/fnthink_endpoint_page.dart';
import 'package:notice_transmit/services/fnthink_contract_loader.dart';
import 'package:notice_transmit/services/fnthink_receive_coordinator.dart';
import 'package:notice_transmit/services/fnthink_receiver_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 接入端点那一页的「教程」形状（T97 片D）。
///
/// §1 2026-10-07 拍：那几条说明收进右上问号弹窗 —— 页面里不许成段堆小字。
/// 这里钉的是**搬家的两条边界**：
///  ① 搬走的是**说明**：页面上不再有那五条小字（键名一个都不在），而右上那枚问号在；
///  ② 长文**一字未删**：弹窗正文里还是原来那五段（拿它们各自独有的字句去认，不是拿标题认）。
/// ⚠ 网址与四枚复制**不上楼**：它们跟着手上那一把变，出现条件原样留在页面上
///   （T87 那句"挪进弹层会让人以为关掉弹层口令还在"针对的正是它们）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  FnthinkEndpointDeps deps({bool contractOk = true}) {
    final loader = FnthinkContractLoader(
      readAsset: (_) async => contractOk
          ? File('protocol/fnthink-v1.json').readAsStringSync()
          : '{ 这不是合法 JSON',
    );
    return FnthinkEndpointDeps(
      contracts: loader,
      // 这一页的用例只碰"教程那一格"的形状：协调者不被调用，但仍要一个实例
      //（建/读/关/换四条链的判据在 `fnthink_settings_page_test.dart` 那批里）。
      coordinator: FnthinkReceiveCoordinator(
        contracts: loader,
        signer: _StubSigner(),
        persist: (_) async => true,
      ),
    );
  }

  Future<void> pump(WidgetTester tester, FnthinkEndpointDeps d) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: FnthinkEndpointPage(deps: d),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('那五条说明从页面上搬走了，右上那枚问号在（契约读到之后）', (tester) async {
    await pump(tester, deps());

    expect(
      find.byKey(const ValueKey('fnthink-endpoint-help')),
      findsOneWidget,
      reason: '说明的新家是右上那枚问号；它不在，这几段话就等于被删了',
    );
    for (final key in const [
      'fnthink-endpoint-post-why',
      'fnthink-endpoint-get-warning',
      'fnthink-endpoint-push-url-why',
      'fnthink-endpoint-fields',
      'fnthink-endpoint-copy-hint',
    ]) {
      expect(
        find.byKey(ValueKey(key)),
        findsNothing,
        reason: '$key 还在页面上 ⇒ 成段小字又长回来了（§1 的两条去处：底部无序列表 / 右上问号）',
      );
    }
  });

  testWidgets('点开问号 ⇒ 原来那五段一字未删（键数不变）', (tester) async {
    await pump(tester, deps());

    await tester.tap(find.byKey(const ValueKey('fnthink-endpoint-help')));
    await tester.pumpAndSettle();

    // 每条取一句只有它才有的字 —— 拿标题去认会把"只搬了标题、正文丢了"读成通过。
    for (final fragment in const [
      '这一条可以整行复制',
      '进反代的访问日志',
      'webhook 输入框',
      '取第一个非空',
      '口令只活在这一页的内存里',
    ]) {
      expect(
        find.textContaining(fragment),
        findsOneWidget,
        reason: '弹窗正文里找不到「$fragment」⇒ 有一段说明在搬家路上被丢了',
      );
    }
  });

  testWidgets('契约读不到 ⇒ 整页只剩那一句，问号也不画', (tester) async {
    await pump(tester, deps(contractOk: false));

    expect(
      find.byKey(const ValueKey('fnthink-contract-error')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('fnthink-endpoint-help')),
      findsNothing,
      reason: '路径与字段别名只有契约一份作者 —— 读不到时弹窗里讲不了任何一条真话',
    );
  });
}

class _StubSigner implements FnthinkIdentitySigner {
  @override
  Future<String> call(List<int> canonicalBytes) async => 'AAAAc2ln';

  @override
  Future<bool> probe() async => true;

  @override
  Future<String?> publicKey() async => 'cHVibGljLWtleQ==';
}
