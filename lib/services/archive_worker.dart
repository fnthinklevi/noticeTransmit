import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';
import 'package:get_it/get_it.dart';
import '../database/database_helper.dart';
import '../models/notification_record.dart';
import 'platform_channel.dart';

const String kArchiveTaskName = 'dailyNotificationArchive';
const String kLastArchiveKey = 'last_archive_date';

/// 自动归档目录模式标记（'custom' = 用户选择的 SAF 自定义目录）。
/// 原生侧把目录 treeUri 持久化在裸 key `archive_dir_uri`（Dart SharedPreferences
/// 读不到非 flutter. 前缀的 key），选择成功后由设置页同步写此标记。
const String kArchiveDirModeKey = 'archive_dir_mode';

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

/// 从数据库读取昨日记录并导出为 JSON 文件。
///
/// P1 约定：**所有推送历史全量保留在数据库**，归档仅是导出备份，不再删除
/// 源记录（旧实现归档后逐条删除，导致历史数据只剩归档文件）。
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

    // 用户已设置自定义归档目录（SAF）时，后台 isolate 没有 MethodChannel
    // handler 无法写入，直接留待前台启动兜底（performArchiveOnBoot）完成；
    // 此处不置位 lastArchiveDate，保证前台启动一定会重试
    if (prefs.getString(kArchiveDirModeKey) == 'custom') {
      debugPrint('[Archive] 自定义目录模式，等待前台兜底归档');
      return;
    }

    final db = GetIt.instance.isRegistered<DatabaseHelper>()
        ? GetIt.instance<DatabaseHelper>()
        : DatabaseHelper();
    // 全量读取（getNotifications 默认 limit=100，昨日记录超 100 条会漏归档）
    final allRecords = await db.getAllNotifications();

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

    // P1：归档后不删除数据库记录，全部历史全量保留

    await prefs.setString(kLastArchiveKey, today);
    debugPrint(
      '[Archive] $yesterdayStr: ${todayRecords.length} 条 → ${file.path}',
    );
  } catch (e, stack) {
    debugPrint('[Archive] 归档失败: $e\n$stack');
  }
}

/// App 前台启动时兜底执行一次归档。
/// 前台可调用 MethodChannel：自定义归档目录（SAF）走原生 writeArchiveFile，
/// 写失败或未设置时回退应用专属目录。
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
    final allRecords = await db.getAllNotifications();
    final yesterday = now.subtract(const Duration(days: 1));
    final yesterdayStr =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    final oldRecords = allRecords
        .map((m) => NotificationRecord.fromMap(m))
        .where((r) => r.time.startsWith(yesterdayStr))
        .toList();

    if (oldRecords.isNotEmpty) {
      // 统一导出格式：camelCase 的 NotificationRecord.toMap()（与
      // WorkManager 后台路径一致；旧实现直接写 DB snake_case 原始行）
      final content = jsonEncode(oldRecords.map((r) => r.toMap()).toList());
      final fileName = 'history-$yesterdayStr.json';
      var wrote = false;
      if (prefs.getString(kArchiveDirModeKey) == 'custom') {
        try {
          final res = await AppChannels.notification
              .invokeMethod<Map<dynamic, dynamic>>('writeArchiveFile', {
                'fileName': fileName,
                'content': content,
              });
          wrote = res?['success'] == true;
          if (!wrote) {
            debugPrint('[Archive] 自定义目录写入失败: ${res?['message']}');
          }
        } catch (e) {
          debugPrint('[Archive] 自定义目录写入异常: $e');
        }
      }
      if (!wrote) {
        final dir = await getApplicationDocumentsDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsString(content);
      }
      // P1：归档后不删除数据库记录
      debugPrint('[Archive] 前台兜底: $yesterdayStr ${oldRecords.length} 条');
    }
    await prefs.setString(kLastArchiveKey, today);
  } catch (e) {
    debugPrint('[Archive] 前台兜底失败: $e');
  }
}
