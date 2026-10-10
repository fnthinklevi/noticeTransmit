/// T126 片1：配对链的结论要"当场看得见"。
///
/// 钉三件事：① 两档标题各走对的一档（做成了／没做成），正文是那一页现有那句**原话**；
/// ② 设备配对页那两处发结论的地方**都**要弹（少一处就是"点了没反应"那个缺陷的复活）；
/// ③ 弹层外壳只有 `IosDialogActions.showInfo` 一个作者（自己搭 CupertinoAlertDialog 会绕开
///    T90 那本"不许再出现 Material 弹层"的账）。
library;

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_pairing_ack.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/fnthink_outcome.dart';

/// 现读源码（本仓的源码守卫一律自持读口，不引共享 helper —— 那些文件常被折行）。
String _read(String rel) => File(
  '${Directory.current.path}/$rel',
).readAsStringSync().replaceAll('\r\n', '\n');

/// 剥掉整行注释。守卫必须剥注释：注释里出现过的那个词不算用过（本仓砸过四次）。
String _code(String src) =>
    src.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// 一个能把 context 交出来调 helper 的占位首页（不引 DI，这一发不需要任何服务）。
class _Trigger extends StatelessWidget {
  const _Trigger({required this.ok, required this.detail});

  final bool ok;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CupertinoButton(
        key: const ValueKey('trigger'),
        onPressed: () => showFnthinkOutcome(context, ok: ok, detail: detail),
        child: const Text('触发'),
      ),
    );
  }
}

Future<void> _pump(
  WidgetTester tester, {
  required bool ok,
  required String detail,
}) async {
  await tester.pumpWidget(
    AppRoot(
      locale: const Locale('zh'),
      dark: false,
      home: _Trigger(ok: ok, detail: detail),
    ),
  );
  await tester.tap(find.byKey(const ValueKey('trigger')));
  await tester.pumpAndSettle();
}

void main() {
  final page = _code(_read('lib/pages/fnthink_peers_page.dart'));

  testWidgets('做成了 ⇒ 标题走「这一步做完了」，正文是那一页的原话', (tester) async {
    await _pump(tester, ok: true, detail: '已同意 ep_a1b2c3 的配对请求（L1）');
    expect(find.byType(CupertinoAlertDialog), findsOneWidget);
    expect(find.text('这一步做完了'), findsOneWidget);
    expect(find.text('已同意 ep_a1b2c3 的配对请求（L1）'), findsOneWidget);
  });

  testWidgets('没做成 ⇒ 标题走「这一步没做成」，正文仍用原话不另拼', (tester) async {
    await _pump(tester, ok: false, detail: '那枚口令已过期');
    expect(find.text('这一步没做成'), findsOneWidget);
    expect(find.text('那枚口令已过期'), findsOneWidget);
    expect(find.text('这一步做完了'), findsNothing);
  });

  test('设备配对页那三处结论都弹：答复、发起、以及手动问一次进度', () {
    final calls = RegExp('showFnthinkOutcome\\(').allMatches(page).length;
    expect(
      calls,
      3,
      reason:
          '答复（_answer）、发起（_pairWithPeer）、刷新（_refreshPairing）各一处，'
          '少一处就是"点了没反应"那个缺陷的复活',
    );
    // 正文必须来自现有唯一作者，不许在页面里另拼一句。
    expect(page, contains('detail: _pairAnswerText(l10n, entry)'));
    expect(page, contains('detail: fnthinkPairSubmitText('));
  });

  test('弹层外壳只有一个作者：helper 自己搭 CupertinoAlertDialog 就红', () {
    final src = _code(_read('lib/widgets/fnthink_outcome.dart'));
    expect(src, contains('IosDialogActions.showInfo('));
    expect(src, isNot(contains('CupertinoAlertDialog(')));
  });

  // ── T126 片2：挂口令那一发的三态，措辞与 key 都只许有一个作者 ──────────────
  test('三态的 key 与句子同源：acked 反了或漏一档就红', () {
    expect(fnthinkPairingAckKey(true), 'acked');
    expect(fnthinkPairingAckKey(false), 'local-only');
    expect(fnthinkPairingAckKey(null), 'unknown');
    expect(
      {
        fnthinkPairingAckKey(true),
        fnthinkPairingAckKey(false),
        fnthinkPairingAckKey(null),
      }.length,
      3,
      reason: '"没问过"与"问过而没成"合并成一档，就会让第三种人做多余的那一步',
    );
  });

  test('页面不再自己写那三句：三个词条只出现在单一作者文件里', () {
    final page = _code(_read('lib/pages/fnthink_settings_page.dart'));
    for (final word in [
      'fnthinkPairingAcked',
      'fnthinkPairingLocalOnly',
      'fnthinkPairingAckUnknown',
    ]) {
      expect(
        page,
        isNot(contains(word)),
        reason: '$word 被页面直接引用 ⇒ 弹层与小字各说一句的漂移回来了',
      );
    }
    expect(page, contains('fnthinkPairingAckText('));
    expect(page, contains('fnthinkPairingAckKey('));
  });

  // ── T129 片2：手动问一次配对进度 ────────────────────────────────────────
  test('那一页只有一个发 poll 的口子，且它的结论走同一个弹层', () {
    final src = _code(_read('lib/pages/fnthink_peers_page.dart'));
    final body = src.substring(src.indexOf('Future<void> _refreshPairing()'));
    final calls = RegExp(
      r'_coordinator\.receiveOnce\(\)',
    ).allMatches(src).length;
    expect(calls, 1, reason: '页面自己再发一轮 poll = 第二个"这一轮有没有货"的读者（T33 那一族踩过的形）');
    expect(
      body.substring(
        0,
        body.indexOf('\n  Future<void>') > 0
            ? body.indexOf('\n  Future<void>')
            : body.length,
      ),
      contains('showFnthinkOutcome('),
      reason: '刷新那一发的结论必须走同一个装配点，不许另弹一套',
    );
    // 三件事三句，全用现有词条（没开收取 / 被跳过 / 跑完而对面没答）。
    expect(body, contains('fnthinkReceiveDisabled'));
    expect(body, contains('fnthinkReceiveSkipped'));
    expect(body, contains('fnthinkPairRefreshQuiet'));
    expect(src, contains("ValueKey('fnthink-pair-refresh')"));
  });
}
