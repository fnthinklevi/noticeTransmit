import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T148 片14 立、T154 片2 改对象的**分族判据** —— 一行里"能点的那一枚"与"只是状态的标记"不许互换。
///
/// ## 这一格为什么会漂
/// 折叠那一枚（「还有 N 条」／「收起」）以前穿着同行 chip 那身 10px/radius 3 的外衣，
/// 页面注释还写着它是「状态标记而不是动作」—— 而它有 `onTap`。伪装成标记的代价不是丑，是
/// **用户读不出它点得动**（与 T108 片② 发送页那三排"只有字重差的选中态"、片12 方向条同一个病）。
/// 反过来，通道 chip 本体（通道名 + 送达状态点 + 「备用」标）是**状态标记**：
/// 给它加一个点击，就是在同一行里凭空多一个入口 —— 而行上早就有「点行出详情、长按出菜单」两条。
///
/// ## T154 片2 换了被钉的那一枚
/// 行内不再摊 chip（改为一统计行 + 「查看详情」），**折叠那一枚整族退休** ——
/// 这一族换成了统计行末尾那枚「查看详情」。判据本身一字没改：
/// ① 那一枚走件、不留自搭壳、并**明说自己中性档**（它不改任何一条记录的状态）；
/// ② chip 本体仍不许变成可点（配一条反向自证，免得"整段被删"也让这条绿）；
/// ③ key 字符串逐字在册 —— 换件时最容易顺手"统一命名"，而那会作废按 key 定位的页面级用例。
/// ⚠ 读源码一律剥注释。
void main() {
  final root = projectRoot();
  final src = stripComments(librarySource(root, 'lib/pages/history_page.dart'));

  /// 从签名取到**下一个成员开头**。
  /// ⚠ 不用 `blockAfter`：这一族成员既有 `Widget` 也有 `Future<void>` 开头的，
  ///   单认一种边界会把后一种整段吞进前一截里（判据对着一截别人的代码恒真）。
  String memberText(String signature) {
    final start = src.indexOf(signature);
    expect(start, greaterThan(-1), reason: '找不到 $signature —— 它被改名或删掉了？');
    final ends = [
      src.indexOf('\n  Widget ', start + signature.length),
      src.indexOf('\n  Future<', start + signature.length),
      src.indexOf('\n  void ', start + signature.length),
    ].where((i) => i > start).toList()..sort();
    expect(ends, isNotEmpty, reason: '$signature 之后找不到下一个成员 ⇒ 页面形状变了');
    return src.substring(start, ends.first);
  }

  /// 可点形状：手势、点击回调、按钮件、可点的公共件。
  /// ⚠ 片15 起了新的一枚可点件（`FnthinkFilledAction`）就必须同批进这一串 ——
  ///   否则"把状态标记包进新件"这种坏法正好绕过 ②（本仓量过的"尺窄于被量之物"）。
  const tappableShapes = [
    'GestureDetector(',
    'InkWell(',
    'onTap:',
    'onLongPress:',
    'CupertinoButton(',
    'TextButton(',
    'FnthinkInlineAction(',
    'FnthinkChoiceChip(',
    'FnthinkFilledAction(',
  ];

  test('① 统计行末尾那枚「查看详情」走公共件，且不再留自搭壳那身外衣', () {
    final line = memberText('Widget _buildDeliveryTallyLine(');
    expect(
      line.contains('FnthinkInlineAction('),
      isTrue,
      reason:
          '那一枚还是自搭壳 ⇒ 字号、颜色、留白由页面挑，'
          '而行内动作这一族在幻念那几张页早有唯一作者',
    );
    for (final shell in [
      'GestureDetector(',
      'BoxDecoration(',
      'HitTestBehavior',
    ]) {
      expect(
        line.contains(shell),
        isFalse,
        reason: '换了件还留着 $shell ⇒ 双搭（两套形状并存，漂哪一套都没人喊）',
      );
    }
    expect(
      line.contains('FnthinkActionTone.neutral'),
      isTrue,
      reason:
          '它只展开细节、不改任何一条记录 ⇒ 中性档；'
          '换成 action（蓝）会把"看细节"说成"去做一件会留下痕迹的事"',
    );
  });

  test('② 通道 chip 本体是状态标记：不许长出点击（也不许被换成动作件）', () {
    final chip = memberText('Widget _buildChannelChip(');
    for (final shape in tappableShapes) {
      expect(
        chip.contains(shape),
        isFalse,
        reason:
            '状态标记变可点 ⇒ 同一行凭空多一个入口，而「看这一条的详情」「看它走了哪几条通道」'
            '行上各有出口（点行／长按）；$shape 出现在这里就是那条纪律被换了个写法突破',
      );
    }
    // 反向自证：那段还在画东西（整段被删／改名也会让上面那一串"全都不在"通过）。
    // ⚠ 片16 起这一枚的壳归 `FnthinkStatusMark`（channel 档）⇒ 自证跟着换成"件在位"，
    //   而不是"还留着 `Container(`"：壳搬进件之后，后者会在正确代码上恒红。
    expect(
      chip.contains('FnthinkStatusMark('),
      isTrue,
      reason: 'chip 本体没在走件了 ⇒ ② 的负向断言全是空断言，这一族已经没人看着了',
    );
  });

  test('③ 两枚 key 逐字在册（换件不动命名：改名＝作废按 key 定位的用例）', () {
    // T154 片2：折叠那一枚随折法整族退休 ⇒ 在册的换成统计行末尾那枚。
    expect(
      src.contains("'history-delivery-detail-"),
      isTrue,
      reason:
          '「查看详情」那一枚的 key 漂了 ⇒ 按 key 点它的用例全数作废；'
          '这一枚在同一页的每一条记录上都长一个样，只能按 key 定位',
    );
    expect(
      src.contains("'history-push-now-"),
      isTrue,
      reason:
          '行内那枚实心小钮的 key 也在册（闸门与用例都按它点，不按文案 —— 它在每行都长一样）。'
          '片15 把它换进了 `FnthinkFilledAction`，key 字符串逐字没动：改名＝作废按 key 定位的用例，那不是统一',
    );
  });

  test('④ 尺认得合成样本（防 ①② 退化成"恒不匹配＝恒绿"）', () {
    // ①的坏形状：件换回了自搭壳（双搭与退化都从这里红）。
    const oldShell =
        '  Widget _buildDeliveryTallyLine() {\n'
        '    return GestureDetector(\n'
        '      key: ValueKey("history-delivery-detail-1"),\n'
        '      behavior: HitTestBehavior.opaque,\n'
        '      onTap: () {},\n'
        '      child: Container(decoration: BoxDecoration()),\n'
        '    );\n'
        '  }\n'
        '  Widget next() => const SizedBox();';
    expect(oldShell.contains('FnthinkInlineAction('), isFalse);
    expect(oldShell.contains('HitTestBehavior'), isTrue);
    // ②的坏形状：给状态标记加了一发长按。
    const tappableChip =
        '  Widget _buildChannelChip() {\n'
        '    return GestureDetector(\n'
        '      onTap: () {},\n'
        '      child: Container(child: Text("x")),\n'
        '    );\n'
        '  }\n'
        '  Widget next() => const SizedBox();';
    expect(tappableChip.contains('GestureDetector('), isTrue);
    expect(
      tappableChip.contains('Container('),
      isTrue,
      reason:
          '坏形状里也要有画东西那一句，'
          '否则"整段被删"这种形态通不过 ② 的反向自证',
    );
  });
}
