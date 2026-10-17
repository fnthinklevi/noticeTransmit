import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T141① 的守卫：收件历史页把指令原文换成「一条远程指令（状态/原因）」这一刀，
/// 三条判据各钉一种静默腐烂。锚点判据照本仓规矩：锚点找不到 = 守卫空转，先自红。
String read(String path) => File(path).readAsStringSync();

/// 剥两种注释（顺序无关的粗剥，判据只落在代码形状上）。
String strip(String code) => code
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//[^\n]*'), '');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final page = strip(read('lib/pages/history_page.dart'));
  final remoteHistory = strip(read('lib/pages/remote_history_page.dart'));
  final words = strip(
    read('lib/services/fnthink_remote_execution_state_words.dart'),
  );

  test('状态词 switch 全仓只有一位作者（state_words 文件）', () {
    expect(
      words,
      contains('RemoteExecutionStates.pending =>'),
      reason: '锚点：作者文件里没词 = 本守卫空转',
    );
    expect(
      words,
      contains('fnthinkRemoteExecutionStateWord'),
      reason: '锚点：作者函数不在 = 守卫量的是不存在的东西',
    );
    expect(
      remoteHistory,
      isNot(contains('=> l10n.remoteHistory')),
      reason:
          '远程历史页抄了第二份状态词 switch ⇒ 契约加一档时两处各改一半'
          '（颜色 switch 留在页里是另一件事，它映射的是 AppColors 不是词条）',
    );
    expect(
      remoteHistory,
      contains('fnthinkRemoteExecutionStateWord('),
      reason: '抽走之后必须真的走唯一作者，不是把 switch 挪个名字留在页里',
    );
    expect(
      page,
      isNot(contains('RemoteExecutionStates.')),
      reason: '收件历史页不许自己判状态（词表外的状态由作者兜「不认得」）',
    );
  });

  test('收件行的状态与理由只走既有作者，不手翻、不硬编码', () {
    expect(
      page,
      contains('fnthinkRemoteExecutionStateWord('),
      reason: '锚点：状态词作者没被用 = 本守卫空转',
    );
    expect(
      page,
      contains('remoteReasonText('),
      reason: '理由必须走 T144 词表（词表外原样带出），半翻比不翻更坏',
    );
    expect(
      page,
      contains('fnthinkRemoteActionLabel('),
      reason: '动作人话走 T124 片A 那位唯一作者',
    );
    expect(
      page,
      isNot(contains('remoteHistoryFailed')),
      reason: '页面里出现状态词条名 = 第二份翻译',
    );
    expect(
      page,
      isNot(contains('remoteHistoryPending')),
      reason: '页面里出现状态词条名 = 第二份翻译',
    );
  });

  test('指令判据只用包侧作者（信封 decode），本页不出现前缀字面量', () {
    expect(
      page,
      contains('RemoteCommandEnvelope.decode('),
      reason: '锚点：显示层必须经唯一作者判「是不是指令」',
    );
    expect(
      page,
      isNot(contains('FRX1')),
      reason: '前缀字面量的全 lib/ 禁令在 fnthink_receive_wiring_test，此处点本页的名',
    );
  });
}
