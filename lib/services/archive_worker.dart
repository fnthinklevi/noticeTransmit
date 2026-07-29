import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:get_it/get_it.dart';
import '../database/database_helper.dart';
import '../models/notification_record.dart';

const String kArchiveTaskName = 'dailyNotificationArchive';
const String kLastArchiveKey = 'last_archive_date';

/// WorkManager 回调入口（必须是 top-level 函数）
@pragma('vm:entry-point')
void archiveCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    if (taskName == kArchiveTaskName) {
      await _performDailyArchive();
    }
    return true;
  });
}

/// 从数据库读取昨日记录并导出为 JSON 文件
Future<void> _performDailyArchive() async {
  try {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // 幂等检查
    final prefs = await SharedPreferences.getInstance();
    final lastArchive = prefs.getString(kLastArchiveKey);
    if (lastArchive == today) {
      debugPrint('[Archive] 今日已归档，跳过');
      return;
    }

    final db = GetIt.instance.isRegistered<DatabaseHelper>()
        ? GetIt.instance<DatabaseHelper>()
        : DatabaseHelper();
    final allRecords = await db.getNotifications();

    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    final todayRecords = allRecords
        .map((m) => NotificationRecord.fromMap(m))
        .where((r) => r.time.startsWith(yesterdayStr))
        .toList();

    if (todayRecords.isEmpty) {
      await prefs.setString(kLastArchiveKey, today);
      debugPrint('[Archive] $yesterdayStr 无记录可归档');
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/history-$yesterdayStr.json');
    await file.writeAsString(
      jsonEncode(todayRecords.map((r) => r.toMap()).toList()),
    );

    for (final r in todayRecords) {
      await db.deleteNotification(r.id);
    }

    await prefs.setString(kLastArchiveKey, today);
    debugPrint(
      '[Archive] $yesterdayStr: ${todayRecords.length} 条 → ${file.path}',
    );
  } catch (e, stack) {
    debugPrint('[Archive] 归档失败: $e\n$stack');
  }
}

/// App 前台启动时兜底执行一次归档
Future<void> performArchiveOnBoot() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    if (prefs.getString(kLastArchiveKey) == today) return;

    final db = GetIt.instance.isRegistered<DatabaseHelper>()
        ? GetIt.instance<DatabaseHelper>()
        : DatabaseHelper();
    final allRecords = await db.getNotifications();
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    final oldRecords = allRecords
        .where((r) => (r['time'] as String?)?.startsWith(yesterdayStr) == true)
        .toList();

    if (oldRecords.isNotEmpty) {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/history-$yesterdayStr.json');
      await file.writeAsString(jsonEncode(oldRecords));
      for (final r in oldRecords) {
        await db.deleteNotification(r['id']?.toString() ?? '');
      }
      debugPrint('[Archive] 前台兜底: $yesterdayStr ${oldRecords.length} 条');
    }
    await prefs.setString(kLastArchiveKey, today);
  } catch (e) {
    debugPrint('[Archive] 前台兜底失败: $e');
  }
}
