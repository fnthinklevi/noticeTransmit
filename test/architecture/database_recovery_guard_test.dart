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
    // WAL 之后主库与 -wal/-shm 必须整份搬运：只挪主文件会把最近提交留在旧 WAL 里。
    expect(restore, contains('_moveBundle(dbPath, rollbackPath)'));
    expect(restore, contains('_copyBundle(backupPath, dbPath)'));
    expect(restore, contains('_moveBundle(rollbackPath, dbPath)'));

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

  test('迁移前快照必须拍在开库之前，版本标记只在成功之后写', () {
    final src = read('lib/database/database_helper.dart');
    final init = blockAfter(src, 'Future<Database> _initDatabase() async');
    final snapshotAt = init.indexOf(
      '_snapshotBeforeMigrationIfNeeded(encryptedPath)',
    );
    final openAt = init.indexOf('openDatabase(');
    expect(snapshotAt, greaterThan(-1), reason: '迁移前快照的调用被摘掉了');
    expect(
      openAt,
      greaterThan(snapshotAt),
      reason: '快照晚于开库 = onUpgrade 已经跑过，留的不是迁移前原件',
    );
    expect(
      init.contains('_recordOpenSuccess('),
      isTrue,
      reason: '成功打开后不记录版本 ⇒ 每次启动都重拍一份快照',
    );
    expect(src, contains("_lastOpenedVersionKey = 'db_last_opened_version'"));
    final success = blockAfter(src, 'Future<Database> _recordOpenSuccess(');
    expect(
      success.contains('setInt(_lastOpenedVersionKey, dbVersion)'),
      isTrue,
      reason: '版本标记必须写当前 dbVersion；写别的号会让下次误判「版本没变」',
    );
    expect(
      success.contains('_pruneMigrationSnapshots'),
      isTrue,
      reason: '快照不清到只剩最新一份 ⇒ 每升一版就多一份整库副本',
    );
  });

  test('迁移失败必须把快照路径交给页面，而不是只写日志', () {
    final helper = read('lib/database/database_helper.dart');
    expect(
      helper.contains('migrationSnapshotPath: migrationSnapshotPath'),
      isTrue,
      reason: '开库失败时异常不带快照路径 ⇒ 页面无法给「恢复迁移前备份」入口',
    );
    final triage = read('lib/database/database_open_triage.dart');
    expect(triage, contains('migrationSnapshotPath'));

    final page = read('lib/pages/main_page.dart');
    expect(page, contains('error.migrationSnapshotPath'));
    expect(
      page,
      contains('askDatabaseOpenFailure'),
      reason: '三档选择必须走公共弹层（取消/重试/恢复三档各有语义）',
    );
    expect(page, contains('_restoreMigrationSnapshot'));
    expect(
      page,
      contains('restoreFromBackup(snapshotPath)'),
      reason: '恢复必须走已经带「先校验、后覆盖、失败回滚」的唯一入口',
    );
  });

  test('迁移备份的中英词条齐全', () {
    final zh = File('$root/lib/l10n/arb/app_zh.arb').readAsStringSync();
    final en = File('$root/lib/l10n/arb/app_en.arb').readAsStringSync();
    for (final key in const [
      'databaseMigrationBackupTitle',
      'databaseMigrationBackupBody',
      'databaseMigrationRestore',
      'databaseMigrationRestoreDone',
      'databaseMigrationRestoreFailed',
    ]) {
      expect(zh, contains('"$key"'), reason: '中文缺 $key');
      expect(en, contains('"$key"'), reason: '英文缺 $key');
    }
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
