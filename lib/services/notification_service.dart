import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:workmanager/workmanager.dart';
import 'archive_worker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../models/notification_record.dart';
import 'platform_channel.dart';
import 'webhook_service.dart';
import 'email_service.dart';

class NotificationService {
  static const _channel = AppChannels.notification;
  static const int _maxRecords = 500;

  final List<NotificationRecord> _records = [];
  bool _serviceRunning = false;
  bool _serviceManuallyStopped = false;

  List<NotificationRecord> get records => _records;
  bool get serviceRunning => _serviceRunning;
  bool get serviceManuallyStopped => _serviceManuallyStopped;

  Future<void> loadRecords() async {
    try {
      await DatabaseHelper().migrateFromSharedPreferences();
    } catch (e) {
      debugPrint('数据库迁移失败: $e');
    }

    try {
      final dbRecords = await DatabaseHelper().getNotifications(
        limit: _maxRecords,
      );
      _records.clear();
      _records.addAll(
        dbRecords.map((e) => NotificationRecord.fromMap(e)).toList(),
      );
    } catch (e) {
      debugPrint('从数据库加载记录失败: $e');
      _records.clear();
    }
  }

  Future<void> loadServiceState() async {
    final prefs = await SharedPreferences.getInstance();
    _serviceManuallyStopped = prefs.getBool('service_manually_stopped') ?? true;
    try {
      _serviceRunning =
          await _channel.invokeMethod('isServiceRunning') as bool? ?? false;
    } catch (e) {
      _serviceRunning = false;
    }
  }

  void addRecord(Map<String, dynamic> record) {
    record['channels'] = _getActiveChannels();
    final notificationRecord = NotificationRecord.fromMap(record);
    _records.insert(0, notificationRecord);
    if (_records.length > _maxRecords) {
      _records.removeRange(_maxRecords, _records.length);
    }
    _saveRecords(notificationRecord.toMap());
  }

  List<String> _getActiveChannels() {
    final channels = <String>[];
    try {
      final webhookService = GetIt.instance<WebhookService>();
      for (final c in webhookService.channels) {
        if (c['enabled'] == true) {
          final type = c['type']?.toString() ?? 'generic';
          channels.add(_webhookTypeLabel(type));
        }
      }
    } catch (_) {}
    try {
      // 从 GetIt 获取已缓存的 EmailService，同步读取已加载的通道
      final emailService = GetIt.instance<EmailService>();
      if (emailService.cachedChannels.any((c) => c.enabled)) {
        channels.add('邮件');
      }
    } catch (_) {}
    return channels;
  }

  String _webhookTypeLabel(String type) {
    switch (type) {
      case '0':
      case 'wechatWork':
        return 'webhook:企业微信';
      case '1':
      case 'dingtalk':
        return 'webhook:钉钉';
      case '2':
      case 'feishu':
        return 'webhook:飞书';
      default:
        return 'webhook:Webhook';
    }
  }

  Future<void> clearRecords() async {
    try {
      await _channel.invokeMethod('clearNotificationRecords');
    } catch (e) {
      // ignore
    }

    await DatabaseHelper().clearAllNotifications();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notification_records');
    _records.clear();
  }

  Future<String> exportRecords(
    String deviceName,
    String deviceModel,
    String manufacturer,
  ) async {
    final directory = await getExternalStorageDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File(
      '${directory?.path}/notification_records_$timestamp.json',
    );

    final exportData = {
      '_warning':
          '此文件包含设备通知记录与应用使用数据，请妥善保管，避免泄露。'
          '导出后建议及时从设备中删除此文件。',
      'exportTime': DateTime.now().toIso8601String(),
      'deviceName': deviceName,
      'deviceModel': deviceModel,
      'manufacturer': manufacturer,
      'totalCount': _records.length,
      'records': _records.map((r) => r.toMap()).toList(),
    };

    await file.writeAsString(jsonEncode(exportData), mode: FileMode.write);
    return file.path;
  }

  Future<void> _saveRecords(Map<String, dynamic> record) async {
    await DatabaseHelper().insertNotification(record);
  }

  Future<List<Map<String, dynamic>>> getStats() async {
    return await DatabaseHelper().getNotificationStats();
  }

  Future<List<Map<String, dynamic>>> getDailyStats(int days) async {
    return await DatabaseHelper().getDailyStats(days);
  }

  Future<int> getCount({String? type}) async {
    return await DatabaseHelper().getNotificationCount(type: type);
  }

  Future<bool> startService() async {
    try {
      await _channel.invokeMethod('startNotificationListener');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('service_manually_stopped', false);
      _serviceRunning = true;
      _serviceManuallyStopped = false;
      return true;
    } catch (e) {
      debugPrint('启动服务失败: $e');
      return false;
    }
  }

  // ========== 每日自动归档 ==========
  // 使用 WorkManager 替代 Timer.periodic，支持 Doze 模式唤醒
  // 幂等保护：SharedPreferences 中记录 lastArchiveDate，防止重复归档

  void startDailyExport() {
    Workmanager().registerPeriodicTask(
      kArchiveTaskName,
      kArchiveTaskName,
      frequency: const Duration(hours: 1),
      constraints: Constraints(
        networkType: NetworkType.not_required,
      ),
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
    debugPrint('[Archive] WorkManager 任务已注册');
  }

  void dispose() {
    Workmanager().cancelByUniqueName(kArchiveTaskName);
  }

  // ========== 多种清除方式 ==========

  /// 清除今日通知
  Future<int> clearToday() async {
    final now = DateTime.now();
    final today =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final toDelete = _records.where((r) => r.time.startsWith(today)).toList();
    for (final r in toDelete) {
      await DatabaseHelper().deleteNotification(r.id);
    }
    _records.removeWhere((r) => r.time.startsWith(today));
    return toDelete.length;
  }

  /// 清除指定日期段内的通知
  Future<int> clearDateRange(DateTime start, DateTime end) async {
    final db = DatabaseHelper();
    final startMs = start.millisecondsSinceEpoch;
    final endMs = end.millisecondsSinceEpoch;
    final toDelete = _records
        .where((r) => r.postTime >= startMs && r.postTime <= endMs)
        .toList();
    for (final r in toDelete) {
      await db.deleteNotification(r.id);
    }
    _records.removeWhere((r) => r.postTime >= startMs && r.postTime <= endMs);
    return toDelete.length;
  }

  /// 构建导出 JSON 字符串
  Future<String> buildExportJson(
    String deviceName,
    String deviceModel,
    String manufacturer,
  ) async {
    final data = {
      '_warning': '此文件包含设备通知记录，请妥善保管。',
      'exportTime': DateTime.now().toIso8601String(),
      'deviceName': deviceName,
      'deviceModel': deviceModel,
      'manufacturer': manufacturer,
      'recordCount': _records.length,
      'records': _records.map((r) => r.toMap()).toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// 清除最近 N 条通知
  Future<int> clearLastN(int n) async {
    if (_records.isEmpty || n <= 0) return 0;
    final count = n < _records.length ? n : _records.length;
    final toDelete = _records.take(count).toList();
    for (final r in toDelete) {
      await DatabaseHelper().deleteNotification(r.id);
    }
    _records.removeRange(0, count);
    return count;
  }

  Future<bool> stopService() async {
    try {
      await _channel.invokeMethod('stopNotificationListener');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('service_manually_stopped', true);
      _serviceRunning = false;
      _serviceManuallyStopped = true;
      return true;
    } catch (e) {
      debugPrint('停止服务失败: $e');
      return false;
    }
  }
}
