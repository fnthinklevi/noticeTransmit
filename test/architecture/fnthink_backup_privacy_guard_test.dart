import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T59 的隐私边界守卫（静态源码那一半，行为那一半在 `test/services/fnthink_backup_test.dart`）。
///
/// 断的是**清单**而不是某一行的写法：这一格里"进什么"必须是白名单，
/// 因为多进一项的代价不在今天 —— 泄露的是"文件将来落到别人手里的那一天"。
///
/// 判据原文（维护者 2026-10-01）：备份恢复的是「意图」，不恢复「身份」，也不携带「凭证」。
void main() {
  final root = projectRoot();
  String code(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  final backup = code('lib/services/fnthink_backup.dart');
  // `BackupService` 的恢复分支也在这份黑名单里：凭证可以"从别处漏进恢复路径"，
  // 那里才是真正会写进 prefs 的地方。
  final service = code('lib/services/backup_service.dart');

  group('幻念推送那一格的白名单', () {
    test('类别里只允许那四个字段（新增必须显式登记）', () {
      final fields = RegExp(
        r"static const field\w+ = '([a-z_]+)';",
      ).allMatches(backup).map((m) => m.group(1)!).toSet();
      expect(
        fields,
        {
          'receive_enabled',
          'host',
          'consent_version',
          // T88 之后加进来的第四项：它仍然只是"这台希望多久问一次货"这一句意图。
          'poll_seconds',
        },
        reason:
            '多一个字段就要先过"它是意图还是身份/凭证"这一问；'
            '少了字段说明恢复回来的配置不完整（界面仍显示"备份成功"）',
      );
    });

    test('身份/凭证/名单/收件正文/发出记录这些名字，备份这一路一个都不许出现', () {
      for (final banned in const [
        'FnthinkPeerService',
        'FnthinkInboxService',
        'FnthinkCredentialStore',
        'FnthinkIdentityService',
        'addressCode',
        'passphrase',
        'keyPair',
        'endpointSecret',
        'grantRelayConsent',
      ]) {
        for (final (where, src) in [
          ('fnthink_backup.dart', backup),
          ('backup_service.dart', service),
        ]) {
          expect(
            src,
            isNot(contains(banned)),
            reason:
                '$where 里出现了 $banned ⇒ 这一格开始携带身份/凭证，或直接替用户点同意门'
                '（"恢复=重新问一次同意"这条判据就没了）',
          );
        }
      }
    });

    test('同意门只能由 apply 自己按版本号写，不许借 settings 的授权口子', () {
      // 上一条钉的是"别调 grantRelayConsent"，这条钉的是"确实有一条版本号判定在"：
      // 没有它，恢复路径就只能"全恢复"或"全不恢复"，而这两者都不是用户想要的。
      expect(
        backup,
        contains('requiredConsentVersion'),
        reason: '版本号判定退场 ⇒ 政策改版后旧备份会静默把同意门带回"已同意"',
      );
      expect(
        backup,
        contains('keyConsentVersion'),
        reason: '写的必须是 FnthinkSettings 那把键（单点），自己拼字符串会长出第二套键名',
      );
    });
  });
}
