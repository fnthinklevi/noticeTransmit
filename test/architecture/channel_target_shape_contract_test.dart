import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_l2_actions.dart';

import '../support/source_guards.dart';

/// T134 片4：通道目标那三段的**形状只有一个作者**（契约 `capabilities.l2.channelTargetShape`）。
///
/// 这一族过去踩过同一坑两次（模板变量、动作表）：形状在几处各写一遍，改契约时只红一边，
/// 而没红的那一边读起来完全正常。这一页钉的是行为用例钉不到的那一维：
/// - 本机那份族表（`kFnthinkRemoteChannelFamilies`）**只是界面选项**，判据不许读它；
/// - 契约那一节在**两侧都有读者**（Dart 拆串那一层 + 服务端写表那一闸），
///   否则它是一块装饰 —— 而装饰性声明比缺声明更贵：它让读代码的人以为已经有人在管。
void main() {
  final root = projectRoot();
  final contract = FnthinkContract.readFile();
  final actionsSource = stripComments(
    librarySource(root, 'lib/services/fnthink_l2_actions.dart'),
  );

  test('本机那份族表与契约那份逐字相同（同序：发送页默认取第一项）', () {
    expect(
      kFnthinkRemoteChannelFamilies,
      contract.l2ChannelTargetFamilies,
      reason:
          '两份一旦分叉，表现是"界面上能选、对面判词表外"或反过来 —— '
          '两边的错误信息都读起来像用户的错',
    );
    // 幻念那一族**不在**这里：它的启停只有 `save()` 一条路（会连带重验目标），
    // 形状与"设一个布尔"不是一件事。这一条不是形式检查 —— 往任一份里加一族，
    // 就是在扩大"对面能动我这台"的范围，那要单独拍。
    expect(kFnthinkRemoteChannelFamilies, isNot(contains('fnthink')));
  });

  test('拆串那一层读的是契约，不读本机那份常量', () {
    // 用 blockAfter 按花括号配对取函数体：全文件 indexOf 会命中前面的同名片段
    //（`buildChannelArgument` 的文档里也写着那个常量名）。
    final body = blockAfter(
      actionsSource,
      'RemoteChannelTarget? parseChannelTarget(',
    );
    expect(
      body,
      contains('l2ChannelTargetFamilies'),
      reason: '判据一旦回到本机那份常量，契约加一族就不会被任何一侧执行到',
    );
    expect(
      body,
      isNot(contains('kFnthinkRemoteChannelFamilies')),
      reason: '族表在这里是第二份判据：界面选项与判据必须分家，否则两份会各自漂',
    );
    expect(
      body,
      isNot(contains("'on'")),
      reason: '目标词按契约那两个词的**位置**读；写死字面量就是第三个作者',
    );
  });

  test('契约那一节两侧都有读者（不是装饰性声明）', () {
    // Dart 这一侧：四个读口都真被拆串/拼串那两层用到。
    for (final reader in [
      'l2ChannelTargetFamilies',
      'l2ChannelTargetSeparator',
      'l2ChannelTargetSegmentsOf',
      'l2ChannelTargetWords',
    ]) {
      expect(
        actionsSource,
        contains(reader),
        reason: '契约声明了 $reader 却没人读 ⇒ 那块声明是给下一个改代码的人看的假保障',
      );
    }
    // 服务端那一侧：写授权表之前照同一节验形状。
    final js = stripComments(
      librarySource(root, 'server/lib/fnthink/capabilities.js'),
    );
    expect(
      js,
      contains('channelTargetShape'),
      reason: '服务端不读那一节的话，勾进去的三段串没人验过，而屏幕上写着"已授权"',
    );
  });

  test('拼出来的串拆得回来：契约里每一族 × 两个目标档全组合', () {
    for (final family in contract.l2ChannelTargetFamilies) {
      for (final wanted in [true, false]) {
        final built = buildChannelArgument(
          contract,
          family: family,
          id: 'chan-7',
          enabled: wanted,
        );
        final parsed = parseChannelTarget(contract, built);
        expect(parsed, isNotNull, reason: '自己拼的串自己拆不开：$built');
        expect(parsed!.family, family);
        expect(parsed.id, 'chan-7');
        expect(parsed.enabled, wanted);
        // 段数按契约：拼出来刚好那么多段（多一段少一段都要被拆串那一层拒掉）。
        expect(
          built.split(contract.l2ChannelTargetSeparator).length,
          contract.l2ChannelTargetSegmentsOf(),
        );
      }
    }
  });

  test('段分隔符与勾选项的分隔符是两枚不同的字符', () {
    // 同一枚的话 `channel:toggle/webhook:acme:off` 就有两种拆法：
    // 按第一段切会把 `channel:toggle` 切错，按最后一段切会把目标档读成动作名。
    expect(
      contract.l2ChannelTargetSeparator,
      isNot(contract.grantItemSeparator),
      reason: '两枚撞车时，同意屏勾出的串与对面拆出的串会各说一套',
    );
  });
}
