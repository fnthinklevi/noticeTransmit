/// T199：数据库打开失败的**分诊**与诊断计数。
///
/// 旧行为只有一个 `catch (e)`：任何异常都当成“库文件损坏”，把健康库改名成
/// `.corrupt-*` 再重建空库。一次 `SqfliteSqlCipherOpenDatabaseOptions` 的类型转换错误
/// 就这样清掉了整库推送历史。
///
/// 这里只回答一个问题：**这个异常像不像“文件本身坏了”**。像才允许走备份重建；
/// 不像（类型错误/参数错误/缺插件/锁库/迁移 SQL 写错）一律原样上抛，绝不改名。
library;

/// 打开失败的分类结果。`corruption` 才触发“备份原库 + 重建”；`unavailable` 保留原库。
enum DatabaseOpenFailureKind { corruption, unavailable }

class DatabaseOpenTriage {
  /// 只认 SQLite/SQLCipher 对**文件内容**的判决。
  ///
  /// ⚠ 负向清单同样重要：`duplicate column` / `no such table` 是迁移 SQL 写错，
  /// `type '...' is not a subtype` 是代码/依赖问题，`database is locked` 是暂时状态，
  /// `unable to open database file` 是权限/磁盘问题 —— 这些都不许触发改名重建。
  static DatabaseOpenFailureKind classify(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('duplicate column') ||
        text.contains('no such table') ||
        text.contains('is not a subtype') ||
        text.contains('type \'') ||
        text.contains('database is locked') ||
        text.contains('unable to open database file')) {
      return DatabaseOpenFailureKind.unavailable;
    }
    if (text.contains('not a database') ||
        text.contains('database disk image is malformed') ||
        text.contains('database is corrupt') ||
        text.contains('database corrupt') ||
        text.contains('file is encrypted or is not a database')) {
      return DatabaseOpenFailureKind.corruption;
    }
    // 认不出的异常一律按“不能证明它坏了”处理：保留原库是唯一可逆的选择。
    return DatabaseOpenFailureKind.unavailable;
  }

  static bool isCorruption(Object error) =>
      classify(error) == DatabaseOpenFailureKind.corruption;
}

/// 打不开库时抛给页面的显式错误（原库未改名、未清空）。
class DatabaseUnavailableException implements Exception {
  DatabaseUnavailableException(this.cause);

  final Object cause;

  @override
  String toString() => '数据库暂时打不开（原库已保留）：$cause';
}

/// 只读诊断计数；页面/日志读它，不参与任何业务判据。
class DatabaseHealth {
  static int openFailures = 0;
  static String? lastOpenError;
  static int writeFailures = 0;
  static String? lastWriteError;

  static void recordOpenFailure(Object error) {
    openFailures++;
    lastOpenError = error.toString();
  }

  static void recordWriteFailure(Object error) {
    writeFailures++;
    lastWriteError = error.toString();
  }

  static void clearOpenFailure() {
    openFailures = 0;
    lastOpenError = null;
  }

  static Map<String, Object?> snapshot() => {
    'openFailures': openFailures,
    'lastOpenError': lastOpenError,
    'writeFailures': writeFailures,
    'lastWriteError': lastWriteError,
  };
}
