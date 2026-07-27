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

/// 从数据库读取当日记录并导出为 JSON 文件
Future<void> _performDailyArchive() async {
  try {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    // 幂等检查：当日已归档则跳过
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

    final todayRecords = allRecords
        .map((m) => NotificationRecord.fromMap(m))
        .where((r) => r.time.startsWith(today))
        .toList();

    if (todayRecords.isEmpty) {
      // 无记录也标记已处理，避免重复检查
      await prefs.setString(kLastArchiveKey, today);
      debugPrint('[Archive] $today 无记录可归档');
      return;
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/history-$today.json');
    await file.writeAsString(
      jsonEncode(todayRecords.map((r) => r.toMap()).toList()),
    );

    // 删除已归档记录
    for (final r in todayRecords) {
      await db.deleteNotification(r.id);
    }

    // 标记已归档
    await prefs.setString(kLastArchiveKey, today);
    debugPrint('[Archive] $today: ${todayRecords.length} 条 → ${file.path}');
  } catch (e, stack) {
    debugPrint('[Archive] 归档失败: $e\n$stack');
  }
}
