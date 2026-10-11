import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T128 片3：「对面自报的名字」这一路只有一个作者，一处一列都不许多。
///
/// 这一族的错法各有一个具体表现：
///  ① 页面自己拼 `"$地址码 ($名字)"` —— 于是"地址码不能被名字替掉"这条纪律只在某一处成立，
///     下一处（收件行的发送方、幻念通道页的目标选择器）迟早写成"只显名字"，
///     而那时用户核对的已经不是那 18 位；
///  ② 屏幕上的名字直接读 `peer.alias` 或 `request.peerName` —— 两个名字各有作者、各有覆盖规则，
///     页面自己挑一个就是把"谁优先"这条判断抄进界面；
///  ③ 服务端把名字**快照**进配对请求表 —— 对面改了名之后本机永远读到旧的那一个（两个作者）；
///  ④ 包内解析器写 `'peerName'` 字面量 —— 契约换键名那天这一格读不到，
///     而屏幕上只是"这台没名字"，与真相（键名漂了）分不出来。
///
/// ⚠ 写法：断言打在**剥注释 + 抹掉空白**之后的源码上（`dart format` 把一行折成三行时，
/// 逐行字面量比对的守卫会红成"守卫坏了"，而该说的"作者换了"没人知道）。
/// 唯一例外是那条 `' ('`：它比的正是空白 ⇒ 单独走未压空白的版本。
void main() {
  final root = projectRoot();
  const page = 'lib/pages/fnthink_peers_page.dart';
  const model = 'lib/models/fnthink_peer.dart';
  const db = 'lib/database/database_helper.dart';
  const coordinator = 'lib/services/fnthink_receive_coordinator.dart';
  const kernel = 'packages/fnthink_push/lib/src/receive_kernel.dart';
  const pairstoreJs = 'server/lib/fnthink/pairstore.js';
  const devicestoreJs = 'server/lib/fnthink/devicestore.js';

  String stripped(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  String compact(String rel) => stripped(rel).replaceAll(RegExp(r'\s+'), '');

  test('两处"是谁"各走一个作者：名单行走 whoLabel，请求行走 label', () {
    final src = compact(page);
    expect(
      src.contains('l10n.fnthinkPeerLine('),
      isTrue,
      reason: '名单行换了写法 ⇒ 下面那条 whoLabel 断言就管不着了（先确认还在本题里）',
    );
    expect(
      src.contains('peer.whoLabel,'),
      isTrue,
      reason: '名单那一行的称呼由模型给（本机起的优先于对面自报的）',
    );
    expect(
      src.contains('l10n.fnthinkPairRequestLine(request.label,'),
      isTrue,
      reason:
          '待确认那一条还没进名单，它那份"这台是谁"必须由请求自己给；'
          '页面拼一份的话同一台设备在屏幕上下两栏会写成两种样子',
    );
    expect(
      src.contains('l10n.fnthinkPairAskMsg(request.label,'),
      isTrue,
      reason: '用户点同意时看到的那一句，必须与列表里那一行是同一份称呼',
    );
    // 负向：不许有人把裸地址码直接递进这三句里（那等于名字永远不出现）。
    for (final forbidden in [
      'l10n.fnthinkPairRequestLine(request.requester,',
      'l10n.fnthinkPairAskMsg(request.requester,',
      'l10n.fnthinkPeerLine(peer.peerAddress,',
    ]) {
      expect(
        src.contains(forbidden),
        isFalse,
        reason: '$forbidden 还在 ⇒ 屏幕上那一行只剩地址码，读到的名字永远不出现',
      );
    }
    expect(
      stripped(page).contains("' ('"),
      isFalse,
      reason: '页面里出现 " (…)" 拼接 ⇒ 称呼的格式有了第二个作者',
    );
  });

  test('名字的格式只有一位作者：模型与包内都调 fnthinkPeerLabel', () {
    final modelSrc = compact(model);
    expect(
      modelSrc.contains('StringgetwhoLabel=>fnthinkPeerLabel('),
      isTrue,
      reason: '模型自己拼括号 ⇒ 与请求行那份会各漂一次（片3 起这一份有两个读者）',
    );
    expect(
      modelSrc.contains(r'($alias)'),
      isFalse,
      reason: '旧的拼法还留在模型里：那就是没换成公共作者',
    );
    final kernelSrc = compact(kernel);
    expect(
      'fnthinkPeerLabel({'.allMatches(kernelSrc).length,
      1,
      reason: '格式函数在包里只能有一个定义处',
    );
    expect(
      'fnthinkPeerLabel('.allMatches(kernelSrc).length,
      greaterThan(1),
      reason: '定义处之外没有读者 ⇒ 这个作者是装饰（两面解析器都要用它）',
    );
  });

  test('`peer_name` 那一列只有模型与名单咽喉碰得到', () {
    final writers = <String>[];
    for (final file in Directory('$root/lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final rel = file.path.substring(root.length + 1).replaceAll(r'\', '/');
      if (compact(rel).contains("'peer_name'")) writers.add(rel);
    }
    expect(
      writers.toSet(),
      {model, db},
      reason:
          '列名只许在模型（toDbRow / fromDbRow）与咽喉（迁移 + upsert）里出现；'
          '别处出现就是有人绕过咽喉直接写这一格。实到 $writers',
    );
  });

  test('服务端不快照名字：投影现取设备表，名单来自契约', () {
    final js = compact(pairstoreJs);
    expect(
      js.contains('incomingFields(contract)'),
      isTrue,
      reason: '接收面又回成字面量清单 ⇒ 契约声明的键与这一面实际回的键没有连接',
    );
    expect(
      js.contains('registeredNameOf(contract,devices,nameSubject)'),
      isTrue,
      reason:
          '名字必须是**现取**设备表那一份；存进请求表就是第二个作者'
          '（对面改名后本机永远读到旧的那个）',
    );
    expect(
      js.contains(
        'projectRecord(contract,fields,devices,record,record.requester)',
      ),
      isTrue,
      reason: '接收面按 requester 取名字（这一面的"对面"就是发起方）',
    );
    expect(
      js.contains(
        'projectRecord(contract,fields,devices,record,record.target)',
      ),
      isTrue,
      reason: '发起面按 target 取名字（那一面的"对面"是被请求那台）',
    );
    expect(
      js.contains('requester:record.requester,'),
      isFalse,
      reason: '旧的那七行对象字面量还在：投影没改成按名单拼',
    );
    expect(
      js.contains('name:record.requesterName'),
      isFalse,
      reason: '请求表里根本没有这一列（也不许有）—— 它是快照，会过期',
    );
  });

  test('设备名长度的作者只有一位：登记那一发读契约那枚数', () {
    final js = compact(devicestoreJs);
    expect(
      js.contains('record.name=clampPeerName(contract,input.name);'),
      isTrue,
      reason: '登记那一发截的长度必须读契约，否则设备侧与服务端各夹一个数',
    );
    expect(
      js.contains('functionpeerNameMaxChars(contract){'),
      isTrue,
      reason: '取那一枚旋钮的函数没了 ⇒ `slice(0,60)` 那种字面量会重新长回来',
    );
    expect(
      js.contains('.pairing||{}).peerNameMaxChars'),
      isTrue,
      reason: '函数在但不读契约，就是装饰',
    );
  });

  test('包内解析器不写线上键名字面量（两处都从契约取）', () {
    final kernelSrc = compact(kernel);
    expect(
      kernelSrc.contains("'peerName'"),
      isFalse,
      reason:
          '写了字面量就等于绕开契约那枚 `pairing.peerNameField`：'
          '契约改名后这一格永远读不到，而屏幕上显示的是"这台没名字" —— '
          '与真相（键名漂了）在界面上分不出来',
    );
    expect(
      'contract.peerNameField'.allMatches(kernelSrc).length,
      greaterThan(0),
      reason: '一个读者都没有 ⇒ 那枚旋钮是装饰',
    );
    expect(
      kernelSrc.contains('contract.peerNameMaxChars'),
      isTrue,
      reason: '长度不夹 ⇒ 自部署方直接改设备表就能送来一个超长名字',
    );
  });

  test('升格与同意两条写入路径都把名字交给咽喉（漏一条就是那半边的名字永远空着）', () {
    final src = compact(coordinator);
    expect(
      src.contains('peerName:request.peerName,'),
      isTrue,
      reason: '同意那一发（接收面）：本机点同意时写的名字来自请求',
    );
    expect(
      src.contains('peerName:sent.peerName,'),
      isTrue,
      reason: '升格那一发（发起面）：那一行的名字来自 sentPairRequests',
    );
  });

  test('咽喉只按"非空读数"写那一格：空读数不许把已读到的名字抹掉', () {
    final src = compact(db);
    expect(
      src.contains("if(peer.peerName.isEmpty)values.remove('peer_name');"),
      isTrue,
      reason: 'refreshed 那一支：空读数 = 这一发没带读数，不是"它说自己没名字"',
    );
    expect(
      src.contains("{'peer_name':peer.peerName}"),
      isTrue,
      reason: 'alreadyPresent 那一支：唯一能动的一格就是名字',
    );
    expect(
      src.contains('if(peer.peerName.isNotEmpty){'),
      isTrue,
      reason: '上面那条赋值必须被非空判断包着；无判断就是拿空串覆盖已有名字',
    );
  });

  test('v24 那一列的迁移分支与 dbVersion 同号（棘轮本体在 database_helper_test，这里钉形状）', () {
    final src = compact(db);
    expect(
      src.contains('if(oldVersion<24)'),
      isTrue,
      reason: '迁移分支没了 ⇒ 老库升上来没有这一列，第一次读就崩',
    );
    expect(
      src.contains('staticconstintdbVersion=24;'),
      isTrue,
      reason: '版本号没抬 ⇒ onUpgrade 永远不跑那一支',
    );
  });
}
