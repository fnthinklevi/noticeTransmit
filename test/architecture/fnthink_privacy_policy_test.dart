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
}
