import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart';

/// T199 ②：重建前留下的旧库备份（`.corrupt-*`）。
///
/// 只描述文件事实，不打开库：扫描本身必须是便宜的，页面才有资格在每次重建后
/// 问一句「要不要恢复」。真正的可读性由 [DatabaseHelper.restoreFromBackup]
/// 在用户确认之后用 `PRAGMA integrity_check` 回答。
class DatabaseBackupInfo {
  const DatabaseBackupInfo({
    required this.path,
    required this.sizeBytes,
    required this.modifiedAt,
  });

  final String path;
  final int sizeBytes;
  final DateTime modifiedAt;

  String get fileName => p.basename(path);
}

/// 打开旧库备份失败 / 备份未通过完整性校验。
///
/// 抛出它的路径**没有覆盖当前库**：恢复前的校验与覆盖是两个独立步骤，
/// 校验不通过时直接停止，当前库与原备份都保持原样。
class DatabaseRestoreException implements Exception {
  DatabaseRestoreException(this.reason);

  final String reason;

  @override
  String toString() => '旧库备份无法恢复：$reason';
}

/// 旧库备份的发现逻辑（纯文件层，可注入临时目录做测试）。
class DatabaseRecovery {
  DatabaseRecovery({Future<String> Function()? databasesPath})
    : _databasesPath = databasesPath ?? getDatabasesPath;

  final Future<String> Function() _databasesPath;

  /// `_backupDatabaseFile` 生成的固定后缀；`.before-restore-*` 是回滚副本，不在此列。
  static const backupSuffix = '.corrupt-';

  static const encryptedDbName = 'notice_transmit_encrypted.db';
  static const oldDbName = 'notice_transmit.db';

  /// 最新的一份旧库备份；没有就是 null。
  Future<DatabaseBackupInfo?> latestBackup() async {
    final dir = Directory(await _databasesPath());
    if (!await dir.exists()) return null;

    DatabaseBackupInfo? latest;
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (!isBackupFileName(name)) continue;
      final stat = await entity.stat();
      final info = DatabaseBackupInfo(
        path: entity.path,
        sizeBytes: stat.size,
        modifiedAt: stat.modified,
      );
      if (latest == null || info.modifiedAt.isAfter(latest.modifiedAt)) {
        latest = info;
      }
    }
    return latest;
  }

  /// 用只读句柄确认这份备份真的能打开、且 `PRAGMA integrity_check` 回 `ok`。
  ///
  /// 放在这个文件而不是 `database_helper.dart`：那是**校验**，不是业务开库，
  /// 不参与 `dbVersion` / `onUpgrade` 那套版本约束；调用方拿到失败就停止，
  /// 当前库一个字节都不动。
  static Future<void> verifyReadable(String path, String password) async {
    Database? backup;
    try {
      backup = await openDatabase(path, password: password, readOnly: true);
      final rows = await backup.rawQuery('PRAGMA integrity_check');
      final verdict = rows.isEmpty
          ? 'empty'
          : '${rows.first.values.first ?? 'empty'}'.toLowerCase();
      if (verdict != 'ok') {
        throw DatabaseRestoreException('integrity_check=$verdict');
      }
    } on DatabaseRestoreException {
      rethrow;
    } catch (e) {
      throw DatabaseRestoreException('$e');
    } finally {
      try {
        await backup?.close();
      } catch (_) {}
    }
  }

  /// 只认 `_backupDatabaseFile` 产出的两种文件名。
  static bool isBackupFileName(String name) =>
      name.startsWith('$encryptedDbName$backupSuffix') ||
      name.startsWith('$oldDbName$backupSuffix');

  /// 备份时间用本机时区；页面只需要「哪一天那一份」，不做跨时区换算。
  static String formatMoment(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }

  /// 页面只说人话，不暴露字节数。两位小数足够判断「是不是那份大库」。
  static String formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }
}
