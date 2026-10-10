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

  test('设备配对页那两处结论都弹：答复那一发与发起那一发', () {
    final calls = RegExp('showFnthinkOutcome\\(').allMatches(page).length;
    expect(
      calls,
      2,
      reason: '答复（_answer）与发起（_pairWithPeer）各一处，少一处就是"点了没反应"那个缺陷的复活',
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
}
