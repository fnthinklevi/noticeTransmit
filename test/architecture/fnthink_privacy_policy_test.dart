import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T56-3：应用内隐私政策（privacy_policy_page 全走 ARB）必须讲清"幻念推送经服务器中转"。
///
/// 钉的是**两个语言都不得漏**这件事 —— 隐私政策是法律口径，只补中文、英文留一句"通知绝不上云"，
/// 后果是英文用户在同意门之外读到与现实相反的承诺（与落地页那版是同一类缺陷的两个入口）。
void main() {
  Map<String, dynamic> arb(String path) =>
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

  final zh = arb('lib/l10n/arb/app_zh.arb');
  final en = arb('lib/l10n/arb/app_en.arb');
  final zhBody = zh['privacyInfoContent'] as String;
  final enBody = en['privacyInfoContent'] as String;

  test('中文隐私政策含幻念推送中转的四条边界（同意/暂存/不上传密钥/审计只存元数据）', () {
    for (final fact in [
      '幻念推送',
      '一次性显式同意',
      '加密暂存',
      '最长保留 7 天',
      '配对口令与身份私钥不上传',
      '审计日志只保存投递所需的元数据（不含正文）',
      '自行部署', // T75 那第四情形：自部署也由这段一并讲清
    ]) {
      expect(zhBody, contains(fact), reason: '中文隐私政策漏了「$fact」');
    }
  });

  test('英文隐私政策同样含这些边界（不许只在中文里补、英文留一句"绝不上云"）', () {
    for (final fact in [
      'Fnthink Push',
      'explicit',
      'encrypted',
      '7 days',
      'never uploaded',
      'metadata needed for delivery',
      'self-host',
    ]) {
      expect(
        enBody,
        contains(fact),
        reason: 'English privacy policy is missing "$fact"',
      );
    }
  });

  /// T92 第②件：对外文档替应用内文案许了一个诺 —— 那句话今天才补上，
  /// 本用例钉的是**引用与被引用两侧不许再分叉**。
  ///
  /// 为什么写成条件式而不是无条件要求应用内含某句：只有当 `GITHUB_PAGES.md`
  /// 还在说"应用内隐私说明里也写着这一点"时，应用内才**必须**写着它。
  /// 哪天对外文档删掉那句引用，本用例应当安静下来（否则就成了没人许过的诺的通行证）。
  test('对外文档引用了应用内隐私说明 ⇒ 应用内必须真的写着第三方实例那一条', () {
    const claimNeedle = '应用内隐私说明里也写着';
    final pages = File('server/GITHUB_PAGES.md').readAsStringSync();
    final claimsIt = pages.contains(claimNeedle);

    // 先钉住这个条件本身成立：引用还在（否则下面三条断言全是空转，
    // 而"空转的守卫"正是本仓反复踩过的那类假绿）。
    expect(
      claimsIt,
      isTrue,
      reason:
          'GITHUB_PAGES.md 里那句「$claimNeedle…」被删或改写了 —— '
          '本用例的判据主语随之消失，请连同它一起处置，别让它空转。',
    );

    for (final fact in ['别人运营的实例', '信得过的实例', '存储形态']) {
      expect(zhBody, contains(fact), reason: '中文隐私政策漏了第三方实例那条的「$fact」');
    }
    for (final fact in [
      'run by someone else',
      'storage form',
      'instances you trust',
    ]) {
      expect(
        enBody,
        contains(fact),
        reason: 'English privacy policy is missing "$fact"',
      );
    }
    // 措辞红线（维护者 2026-10-06 认的口径）：讲的是**类别**与**存储形态**，
    // 不写"差别在谁能看到正文"，也不写"自部署更私密" —— 落盘加密用的是服务端自己的
    // 密钥（messagestore.js:55 的 envKey ← store.js:48 的 ENCRYPTION_KEY），
    // 所以两种形态对方都读得到，把差别写成"谁能看到"是不实陈述。
    expect(zhBody, isNot(contains('自部署更私密')));
    expect(enBody, isNot(contains('more private')));
  });

  // ===== 同意门那一侧（`privacyBody`）=====
  // 上面这几条只读 `privacyInfoContent`（应用内说明页），于是「落地页修了、说明页
  // 补了、同意门还留着那句全称量词」三件事同时成立而全场全绿 —— 缺口正落在两把尺的
  // 覆盖缝里。同意门是用户点"同意"**之前**唯一读得到的一段话，必须同判。
  final zhGate = zh['privacyBody'] as String;
  final enGate = en['privacyBody'] as String;

  test('同意门（privacyBody）两个语言都写明"经服务器中转"', () {
    for (final fact in ['服务器中转', '不出本机']) {
      expect(zhGate, contains(fact), reason: '同意门中文漏了「$fact」');
    }
    for (final fact in [
      'relayed through the server',
      'never leaves this device',
    ]) {
      expect(enGate, contains(fact), reason: '同意门英文漏了 "$fact"');
    }
  });

  test('同意门与说明页都不许再出现那句全称量词（本次修掉的实陈述本体）', () {
    final bodies = {
      'zh 同意门': zhGate,
      'en 同意门': enGate,
      'zh 说明页': zhBody,
      'en 说明页': enBody,
    };
    for (final e in bodies.entries) {
      // 幻念推送经服务器中转 ⇒ "所有通知内容仅在设备本地处理"这一句在任何一处都是假的。
      expect(
        e.value,
        isNot(contains('所有通知内容仅在设备本地')),
        reason: '${e.key} 又写回了那句全称量词',
      );
      expect(
        e.value,
        isNot(contains('All notification content is matched against rules')),
        reason: '${e.key} 又写回了那句全称量词（英文）',
      );
      expect(
        e.value,
        isNot(contains('All notifications are processed on-device')),
        reason: '${e.key} 又写回了那句全称量词（英文·同意门版）',
      );
    }
  });

  /// T124 片C-1：远程读取（通话记录）这一条**同批**进了说明页与权限清单，
  /// 两个语言都不得漏 —— 只补一边的后果与上面那条全称量词同源：另一边读到的是
  /// 一份少了「对面能读这台什么」的说明，而代码已经能读了。
  /// 片C-2 把定位一并扩进来（同一条披露句 + 权限清单各加一条）。
  test('说明页披露远程读取（默认关、单独开）与通话记录/定位那两条权限（两个语言）', () {
    for (final fact in ['远程读取', '默认关', '通话记录', '最近一次定位', '一张照片']) {
      expect(zhBody, contains(fact), reason: '中文隐私政策漏了「$fact」');
    }
    for (final fact in [
      'Remote reading',
      'off by default',
      'call-log',
      'last known location',
      'photo taken',
    ]) {
      expect(
        enBody,
        contains(fact),
        reason: 'English privacy policy is missing "$fact"',
      );
    }
    for (final fact in [
      'READ_CALL_LOG',
      '通话记录',
      'ACCESS_FINE_LOCATION',
      'ACCESS_COARSE_LOCATION',
      'CAMERA',
      '拍一张',
    ]) {
      expect(zh['privacyPermContent'] as String, contains(fact));
    }
    for (final fact in ['READ_CALL_LOG', 'ACCESS_FINE_LOCATION', 'CAMERA']) {
      expect(en['privacyPermContent'] as String, contains(fact));
    }
  });

  test('main.dart 里那个链接真的通向全文页（同一函数体内 onOpenPolicy ⇒ push 全文页）', () {
    final src = File('lib/main.dart').readAsStringSync();
    // 先验主语在场：否则下面每条都是空转（"文件里根本没有这个东西"不能当成"它是对的"）。
    final head = src.indexOf('void _showPrivacyDialog(');
    expect(
      head,
      greaterThan(-1),
      reason: '同意门那个方法不叫 _showPrivacyDialog 了 ⇒ 本条判据的主语已消失，请连同它一起处置',
    );
    final end = src.indexOf('\n  }\n', head);
    expect(end, greaterThan(head), reason: '读不到 _showPrivacyDialog 的函数体结尾');
    // 取**整个函数体**而不是固定字符窗口：窗口会被注释和 format 折行推出范围，
    // 那只会造出"守卫自己红"的假信号（本条第一版就栽在这里）。
    final body = src.substring(head, end);

    expect(
      body.contains('PrivacyGateBody('),
      isTrue,
      reason: '同意门不再用 PrivacyGateBody ⇒ 链接那一层没人画了',
    );
    final atCallback = body.indexOf('onOpenPolicy');
    final atPage = body.indexOf('PrivacyPolicyPage');
    expect(atCallback, greaterThan(-1), reason: '没给 onOpenPolicy ⇒ 链接画出来了却没人接');
    expect(
      atPage,
      greaterThan(-1),
      reason: '函数体里不出现 PrivacyPolicyPage ⇒ 点了链接不去全文页，"请先阅读"没法执行',
    );
    expect(
      atCallback < atPage,
      isTrue,
      reason: '全文页出现在 onOpenPolicy 之前 ⇒ 它多半挂在别处（不是那个回调要推的东西）',
    );
  });

  test('三个链接词条两侧都在、都非空、且都有调用点', () {
    const keys = [
      'privacyGateLinkBefore',
      'privacyPolicyLink',
      'privacyGateLinkAfter',
    ];
    final shell = File('lib/widgets/privacy_gate_body.dart').readAsStringSync();
    for (final k in keys) {
      for (final e in {'zh': zh, 'en': en}.entries) {
        final v = e.value[k];
        expect(v, isA<String>(), reason: '${e.key} 缺词条 $k');
        expect(
          (v as String).trim().isNotEmpty,
          isTrue,
          reason: '${e.key} 的 $k 是空串',
        );
      }
      expect(shell.contains('l10n.$k'), isTrue, reason: '$k 没有调用点 ⇒ 它会变成死词条');
    }
  });
}
