import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// #176 片3 的形状守卫：B 侧「配对另一台设备」那一格不许长出第二个作者。
///
/// 钉的全是"错了不报错、只是慢慢说假话"或"只在真点过一次时才现形"的那几处：
///  ① **档位名单只有契约那一份作者** —— 界面里写死 `'L3'` 的下场不是编译错误，而是用户点下去
///     换回一句与"口令错"同形的 403（服务端对请求超档是整条拒，不压封顶）；
///  ② **结论只有一个作者** —— 页面自己 `switch (result.status)` 一遍，就会出现"同一个状态在
///     两个页面说两句话"，而用户看哪一句取决于他当时在哪一页；
///  ③ **口令不留副本** —— 一次性凭证被人存起来的那一刻起就不再是一次性的
///     （与 T87 端点口令、[_pairSubmit] 只存结论是同一条红线）；
///  ④ **弹层自持 controller** —— 调用方在 `await` 返回时 dispose 会打在还在跑退场动画的
///     TextField 上，那条崩溃只在真点一次时现形，写页面时完全看不出问题。
void main() {
  final root = projectRoot();
  String read(String rel) =>
      File('$root/$rel').readAsStringSync().replaceAll('\r\n', '\n');

  const dialog = 'lib/widgets/fnthink_pair_dialog.dart';
  const page = 'lib/pages/fnthink_push_page.dart';
  const contract = 'packages/fnthink_push/lib/src/contract.dart';
  const coordinator = 'lib/services/fnthink_receive_coordinator.dart';

  test('档位词表不许抄进界面：弹层里没有一枚 L? 字面量', () {
    final src = stripComments(read(dialog));
    for (final literal in ["'L1'", "'L2'", "'L3'"]) {
      expect(
        src,
        isNot(contains(literal)),
        reason:
            '弹层里写死 $literal ⇒ 改契约那一档时界面不会跟着变，而请求超档在服务端是整条拒：'
            '用户点开的是一句必被拒的话',
      );
    }
    expect(
      RegExp(r'pairRequestableLevels').allMatches(src).length,
      2,
      reason: '两枚 = 初值（最低那一档）+ build 里那一份名单；多一枚就要问是不是自己又数了一遍档位',
    );
  });

  test('够得着哪几档只有契约那一个算法，且它读的是 pair 那条路径', () {
    final src = stripComments(read(contract));
    expect(
      RegExp(r"List<String> get pairRequestableLevels").allMatches(src).length,
      1,
      reason: '读口长出第二个 ⇒ "界面摆出一发必被拒的档位"就没人拦了',
    );
    final block = blockAfter(src, 'List<String> get pairRequestableLevels');
    expect(
      block,
      contains("'clientEvents', 'pair', 'levelCeilingFrom'"),
      reason:
          '必须走 pair 那条路径：复用 pairConfirm 的封顶就等于把"请求能请求到哪"和'
          '"本机答应得到哪"合成一个旋钮，而服务端对这两件事的处理不同（一个整条拒、一个压到封顶）',
    );
    expect(block, isNot(contains("'L2'")), reason: '补一个默认档位 = 在代码里发明一种授权');
  });

  test('那一发只有一个调用点，结论只有一个作者', () {
    final src = stripComments(read(page));
    expect(
      RegExp(r'_coordinator\.pairWithDevice\(').allMatches(src).length,
      1,
      reason: '第二个调用点意味着有人绕过了前置那五句原话（没同意 / 签不出来 / 没登记…）',
    );
    expect(
      RegExp(r'fnthinkPairSubmitText\(').allMatches(src).length,
      1,
      reason: '页面自己 switch 一遍 status ⇒ 同一个状态在两个页面说两句话',
    );
    final submit = blockAfter(src, 'Future<void> _pairWithPeer()');
    expect(
      submit,
      isNot(anyOf([contains('FnthinkPollStatus'), contains('.status ==')])),
      reason: '页面判状态 = 第二份判据；判据在内核（200 还要 requestId + 认识的状态词）',
    );
  });

  test('口令没有第二份副本：弹层与页面都不落盘、不打印', () {
    for (final rel in [dialog, page]) {
      final src = stripComments(read(rel));
      expect(
        src,
        isNot(anyOf([contains('SharedPreferences'), contains('setString')])),
        reason: '$rel 里出现持久化写入 ⇒ "这一把只出现一次"那条红线破了',
      );
      expect(
        RegExp(r'\bprint\(').hasMatch(src),
        isFalse,
        reason: '$rel 里打印 ⇒ 一次性口令进日志，而本站日志脱敏（T89）还没配',
      );
      expect(
        RegExp(r'\bdebugPrint\(').hasMatch(src),
        isFalse,
        reason: '$rel 里打印 ⇒ 一次性口令进日志，而本站日志脱敏（T89）还没配',
      );
    }
    // 页面留的是结论，不是输入：口令/地址码都必须**就地**交出去。
    final pageSrc = stripComments(read(page));
    final submit = blockAfter(pageSrc, 'Future<void> _pairWithPeer()');
    expect(submit, contains('pairingCode: input.code'));
    expect(
      RegExp(
        r'String\w*\s+_pair\w*(Code|Target|Pairing)',
      ).allMatches(pageSrc).length,
      0,
      reason: '页面里出现"装着口令/地址码的字段"= 那份一次性的东西开始有副本',
    );
  });

  test('弹层自己持有 controller，两枚都在 dispose 里释放', () {
    final src = stripComments(read(dialog));
    expect(
      RegExp(r'TextEditingController\(\)').allMatches(src).length,
      2,
      reason: '地址码 + 口令两枚归弹层（调用方建的话，await 返回那一刻就打在退场动画上）',
    );
    final dispose = blockAfter(src, 'void dispose()');
    expect(dispose, contains('_target.dispose()'));
    expect(dispose, contains('_code.dispose()'));
  });

  test('内核离机前拦下的那一发由协调者接住，页面不会崩', () {
    final raw = read(coordinator);
    final start = raw.indexOf('Future<FnthinkPairResult> pairWithDevice(');
    expect(start, isNonNegative, reason: '协调者那一发不见了：页面唯一的入口就悬在半空');
    // 不用 `blockAfter`：它会停在**命名参数表**那个 `{` 上，取到的是参数表而不是函数体
    // （这条在 T06 那批守卫上砸过，页面里 `_answer`/`_revoke` 因此都改成了位置式签名）。
    // 这里的签名要的是读起来清楚，所以按"下一个成员的文档注释"切。
    // ⚠ 先切再剥注释：`stripComments` 会把 `///` 一起抹掉，先剥就没有刀口了。
    final next = raw.indexOf('\n  ///', start);
    final block = stripComments(
      raw.substring(start, next < 0 ? raw.length : next),
    );
    expect(
      block,
      contains('on ArgumentError catch'),
      reason:
          '`pairFields` 对"target 空 / 填了自己"是当场抛。让它穿透到页面，症状是'
          '"点了配对以后屏幕上什么都没有"，而用户其实只是把本机地址码粘错了格子',
    );
    expect(
      RegExp(r'if \(target.isEmpty').allMatches(block).length,
      0,
      reason: '这里只接住它抛的那一句，不重判一遍（重判 = 第二个作者）',
    );
    expect(block, contains('requireEnabled: false'));
  });
}
