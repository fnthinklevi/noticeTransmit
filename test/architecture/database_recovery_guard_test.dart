import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T199 ②：旧库恢复的顺序守卫。
///
/// 行为用例在 `test/database/database_recovery_test.dart`；这里只钉**装配点**：
///  ① 恢复必须先只读校验、再动当前库；
///  ② 覆盖前当前库要另存为 `.before-restore-*`，失败要能改回来；
///  ③ 页面只在本次启动经历开库失败时询问，并记住「暂不」。
void main() {
  final root = projectRoot();
  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  test('恢复先校验、后覆盖，且当前库有回滚副本', () {
    final src = read('lib/database/database_helper.dart');
    final restore = blockAfter(src, 'Future<void> restoreFromBackup(');
    expect(restore, contains('DatabaseRecovery.verifyReadable'));
    expect(restore, contains('.before-restore-'));
    expect(restore, contains('rename(dbPath)'));

    final verify = blockAfter(
      read('lib/database/database_recovery.dart'),
      'static Future<void> verifyReadable(',
    );
    expect(verify, contains('readOnly: true'));
    expect(verify, contains('PRAGMA integrity_check'));
    expect(verify, contains('DatabaseRestoreException'));
  });

  test('页面只在开库失败过时询问，并记住暂不', () {
    final src = read('lib/pages/main_page.dart');
    expect(src, contains('DatabaseHealth.openFailures > 0'));
    expect(src, contains('_offerDatabaseRecovery()'));
    expect(src, contains('db_recovery_dismissed_path'));
    expect(src, contains('restoreFromBackup'));
    expect(src, contains('latestBackup'));
  });

  test('中英词条齐全', () {
    final zh = File('$root/lib/l10n/arb/app_zh.arb').readAsStringSync();
    final en = File('$root/lib/l10n/arb/app_en.arb').readAsStringSync();
    for (final key in const [
      'databaseRecoveryTitle',
      'databaseRecoveryBody',
      'databaseRecoveryConfirm',
      'databaseRecoveryDone',
      'databaseRecoveryFailed',
    ]) {
      expect(zh, contains('"$key"'), reason: '中文缺 $key');
      expect(en, contains('"$key"'), reason: '英文缺 $key');
    }
  });
}
