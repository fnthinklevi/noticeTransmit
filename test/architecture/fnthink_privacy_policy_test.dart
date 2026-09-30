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
}
