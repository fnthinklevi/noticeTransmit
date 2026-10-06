import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/privacy_gate_body.dart';

/// 首启同意门的正文（`PrivacyGateBody`）。
///
/// 这份用例钉的是**行为**，不是源文本：链接那几个字有没有单独成段、带不带手势、
/// 手势接没接到调用方给的回调。源码守卫（`fnthink_privacy_policy_test.dart`）
/// 只能回答「main.dart 有没有把跳转接上」，回答不了「这一段是不是可点的」——
/// 而这次要修的缺陷恰恰是"要用户先读，却不给读的路"。
void main() {
  Widget wrap(Widget home) =>
      AppRoot(locale: const Locale('zh'), dark: false, home: home);

  const bodyKey = ValueKey('privacy-gate-body');
  var openCalls = 0;

  Future<AppLocalizations> pumpGate(WidgetTester tester) async {
    await tester.pumpWidget(
      wrap(
        Builder(
          builder: (ctx) {
            return CupertinoPageScaffold(
              child: Center(
                child: PrivacyGateBody(
                  onOpenPolicy: () => openCalls = openCalls + 1,
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.of(tester.element(find.byKey(bodyKey)));
  }

  /// key 挂在 `Text.rich` 上，而 `Text` 不公开它那个 span —— 读它下面真正渲染的
  /// `RichText.text`（跨版本都稳定）。
  TextSpan rootSpan(WidgetTester tester) =>
      tester
              .widget<RichText>(
                find.descendant(
                  of: find.byKey(bodyKey),
                  matching: find.byType(RichText),
                ),
              )
              .text
          as TextSpan;

  TextSpan? findLinkSpan(TextSpan root, String linkText) {
    TextSpan? found;
    void walk(InlineSpan span) {
      if (span is! TextSpan) return;
      if (span.text == linkText) found = span;
      for (final c in span.children ?? const <InlineSpan>[]) {
        walk(c);
      }
    }

    walk(root);
    return found;
  }

  setUp(() => openCalls = 0);

  testWidgets('链接文字单独成段且带可点手势（不是只印在纸上的一句话）', (tester) async {
    final l10n = await pumpGate(tester);
    final link = findLinkSpan(rootSpan(tester), l10n.privacyPolicyLink);

    expect(link, isNotNull, reason: '链接文字没被单独成段 ⇒ 它和正文一样不可点');
    expect(
      link!.recognizer,
      isA<TapGestureRecognizer>(),
      reason: '单独成段却没挂 recognizer ⇒ 看着像链接，点下去什么都没有',
    );
  });

  testWidgets('链接那一段占据可命中的位置，且手势真的接到调用方的回调', (tester) async {
    // 画布撑大：正文有 5 条要点 + 一句带链接的话，默认 800×600 放不下，链接那一行
    // 会掉到视口外 —— 那时"点不到"是测试自己的红，不是产品的。
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final l10n = await pumpGate(tester);
    final link = l10n.privacyPolicyLink;
    final plain = rootSpan(tester).toPlainText();
    final at = plain.indexOf(link);
    expect(at, greaterThanOrEqualTo(0), reason: '渲染出来的正文里没有链接文字');

    final paragraph = tester.renderObject<RenderParagraph>(find.byKey(bodyKey));
    final boxes = paragraph.getBoxesForSelection(
      TextSelection(baseOffset: at, extentOffset: at + link.length),
    );
    expect(boxes, isNotEmpty, reason: '链接那几个字没被排版出来');
    final center = boxes.first.toRect().center;

    final top = tester.getTopLeft(find.byKey(bodyKey));
    expect(
      (top + center).dy,
      lessThan(tester.view.physicalSize.height / tester.view.devicePixelRatio),
      reason: '链接落在视口之外 ⇒ 这一发点不到东西，是测试自己的红',
    );

    expect(openCalls, 0);
    // ⚠ 这里**不**用坐标点击：widget 测试里打在行内 recognizer 上始终不触发
    // （几何量过：点就在链接那一段的矩形中心、也在视口内，down/pump/up 也一样）。
    // 所以拆成两条各自可证伪的断言 —— ① 段落认这个点（真机上手指落下去就是它），
    // ② 那个 recognizer 的回调确实接到了 onOpenPolicy。「手指真点得动」这一条
    // 留给设备侧那一步（release 包已装着，同意门就在屏上）。
    expect(
      paragraph.hitTestSelf(center),
      isTrue,
      reason: '段落不认链接那一段上的点 ⇒ 真机上也点不到',
    );

    final span = findLinkSpan(rootSpan(tester), link);
    (span!.recognizer as TapGestureRecognizer).onTap!();
    expect(openCalls, 1, reason: 'recognizer 接了个空回调 ⇒ 点了什么都不会发生');
  });

  testWidgets('要点来自词条，且链接三段按 前→链接→后 的顺序拼成一句能读的话', (tester) async {
    final l10n = await pumpGate(tester);
    final plain = rootSpan(tester).toPlainText();

    expect(
      plain,
      contains(l10n.privacyBody),
      reason: '弹层没渲染 privacyBody 词条 ⇒ 改 ARB 不会反映到同意门上',
    );
    final before = plain.indexOf(l10n.privacyGateLinkBefore);
    final link = plain.indexOf(l10n.privacyPolicyLink);
    final after = plain.indexOf(l10n.privacyGateLinkAfter);
    expect(before, greaterThanOrEqualTo(0), reason: '链接前段没渲染');
    expect(after, greaterThanOrEqualTo(0), reason: '链接后段没渲染');
    expect(
      link > before && after > link,
      isTrue,
      reason: '三段顺序错了 ⇒ 拼出来不是一句能读的话',
    );
  });
}
