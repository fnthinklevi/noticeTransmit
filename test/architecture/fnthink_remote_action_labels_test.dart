import 'dart:io';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/services/fnthink_l2_actions.dart';
import 'package:notice_transmit/services/fnthink_l3_settings.dart';
import 'package:notice_transmit/services/fnthink_remote_action_labels.dart';

import '../support/source_guards.dart';

/// T124 A 片：远程指令那一路"参数由界面生成"的三条同步判据。
///
/// 这一组不判界面画成什么样（那在 `test/widgets/fnthink_send_page_test.dart`），
/// 判的是**发送侧拼出来的东西，对面那台必须认得**：
///  ① 人话标签的名单与契约那份动作表**双向差集为空** —— 契约加一项而这里没配，
///     界面上那一格就永远不出现（对面已经能收了）；这里多配一项，画出来的是一个
///     压根不存在的动作。两种都只在这一条上红。
///  ② 拼参数与拆参数是同一份形状（往返）—— 发送侧改了分隔符而收件侧没改，
///     表现是"指令发得出去、对面记成执行失败"，两头日志互相看不懂。
///  ③ 族表与谓词同步，且**幻念那一族不在里面**：把远程启停开给第四族是扩大
///     "对面能动我这台的范围"，那是单独一次决定，不是加一族显示顺带做的事。
void main() {
  final contract = FnthinkContract.readFile();
  final zh = lookupAppLocalizations(const Locale('zh'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('人话标签的键集 == 契约那两份动作表（双向差集，不多不少）', () {
    final contractActions = {
      ...contract.l2Actions,
      ...contract.l3Settings.keys,
    };
    final labeled = kFnthinkRemoteActionLabels.keys.toSet();
    expect(
      contractActions.difference(labeled),
      isEmpty,
      reason: '契约里有而这里没配 ⇒ 那一格在界面上永远不出现，而对面已经能收它了',
    );
    expect(
      labeled.difference(contractActions),
      isEmpty,
      reason: '这里多配了一项 ⇒ 界面会画一个契约里不存在的动作',
    );
  });

  test('每一项都真的换成了人话（画给用户的不许是契约那个裸名）', () {
    for (final action in kFnthinkRemoteActionLabels.keys) {
      for (final l10n in [zh, en]) {
        final label = fnthinkRemoteActionLabel(l10n, action);
        expect(label, isNotEmpty, reason: '$action 那一格是空的');
        expect(
          label,
          isNot(action),
          reason: '$action 没有配词条 —— 回退成裸名是"看得见没配"，但守卫要它当场红',
        );
        expect(
          hasFnthinkRemoteActionLabel(action),
          isTrue,
          reason: '$action 不在映射里，页面拿到的就是裸名',
        );
      }
    }
    // 没配的那一项必须**看得见地**回裸名（不许编一句假话盖住）。
    expect(
      fnthinkRemoteActionLabel(zh, 'no-such-action'),
      'no-such-action',
      reason: '回退形状变了 ⇒ 上面那条"没配就红"会跟着失效，两处一起改',
    );
  });

  test('拼出来的通道参数，对面那台拆得回来（往返，三族 × 开／关）', () {
    for (final family in kFnthinkRemoteChannelFamilies) {
      for (final want in [true, false]) {
        final built = buildChannelArgument(
          contract,
          family: family,
          id: 'chan-42',
          enabled: want,
        );
        final parsed = parseChannelTarget(contract, built);
        expect(parsed, isNotNull, reason: '拼出来的串对面拆不开：$built');
        expect(parsed!.family, family);
        expect(parsed.id, 'chan-42');
        expect(parsed.enabled, want);
      }
    }
  });

  test('拼出来的 L3 item 带目标值，且 parseL3Item 认它（幂等那一条）', () {
    for (final want in [true, false]) {
      final item = buildL3Item(contract, key: 'monitoring', want: want);
      final parsed = parseL3Item(contract, item, confirmedThisTime: true);
      expect(parsed, isA<FnthinkL3Ok>());
      final setting = (parsed as FnthinkL3Ok).setting;
      expect(
        setting.targetValue,
        want,
        reason: '不带目标值 = 对面"读当前再翻"，重投一次回到原状 ⇒ 发送侧必须带',
      );
    }
    // 裸 key 仍收（老对端形状），但那是**对面**的兼容，不是本页该产出的东西。
    expect(
      parseL3Item(
        contract,
        buildL3Item(contract, key: 'monitoring'),
        confirmedThisTime: true,
      ),
      isA<FnthinkL3Ok>(),
    );
  });

  test('族认不认得由契约说；幻念那一族不在可远程启停的范围里', () {
    // 判据的唯一出处是契约 `l2.channelTargetShape.families`（本机那份常量从片4 起只剩
    // "发送侧把这几族画成可点的选项"一个用途；两份相等由 `channel_target_shape_contract_test.dart` 钉）。
    // 这里验的是**执行那一侧真的按契约判**，不是按本机那份常量判。
    String wire(String family) => buildChannelArgument(
      contract,
      family: family,
      id: 'acme',
      enabled: false,
    );
    for (final family in contract.l2ChannelTargetFamilies) {
      expect(
        parseChannelTarget(contract, wire(family)),
        isNotNull,
        reason: '$family 在契约里却被本机拆成 null ⇒ 两份读法分叉了',
      );
    }
    for (final other in ['fnthink', 'sms', '', 'Webhook']) {
      expect(
        parseChannelTarget(contract, wire(other)),
        isNull,
        reason: '$other 不该被认 —— 认了就等于把远程启停开给一族没拍过的通道',
      );
    }
  });

  String historyPage() => stripComments(
    File('${projectRoot()}/lib/pages/remote_history_page.dart')
        .readAsStringSync(),
  );

  test('历史页那一行的**名**走那张表，契约裸名不许出现在插值里（T146 片2）', () {
    final src = historyPage();
    expect(
      src,
      contains('fnthinkRemoteActionLabel('),
      reason: '人话的唯一作者是这张表；页面绕过它自己翻译 = 第二套词表（T146 差异③的来路）',
    );
    expect(
      src,
      isNot(contains('row.item}')),
      reason:
          '把 `row.item` 直接插进字符串 ⇒ 画给用户的是契约那个裸名。'
          '判据打在"插值"上而不是打在某一串具体措辞上：换写法（多拼一段、挪进别的格子）照样拦得住',
    );
  });

  test('历史页那一行的**参数**那一格有作者，引导语不许写成页内字面量（T146 片2）', () {
    final src = historyPage();
    expect(
      src,
      contains('l10n.remoteHistoryArgument('),
      reason: '参数那一格没有作者 ⇒ `argument` 上了表却没上屏（"开了还是关了"读不出来）',
    );
    expect(
      src,
      isNot(contains("'参数：")),
      reason: '那句引导的唯一作者是 ARB；页面里再写一遍就是第二份可以朝不同方向写错的实现',
    );
  });
}
