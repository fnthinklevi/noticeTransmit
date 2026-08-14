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

    // 拉取原生端离线缓存（软件被杀期间的通知），通过 id 去重后合并入库
    await _drainOfflineCache();
  }

  /// 拉取原生 HistoryCache 缓存的离线通知，按 id 去重后入库。
  /// 修复"软件关闭重开后推送历史记录消失"问题。
  Future<void> _drainOfflineCache() async {
    try {
      final cached = await _channel.invokeMethod<List<dynamic>>(
        'drainOfflineCache',
      );
      if (cached == null || cached.isEmpty) return;

      // 获取现有 id 集合，避免重复入库
      final existingIds = _records.map((r) => r.id).toSet();

      var merged = 0;
      for (final item in cached) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = map['id']?.toString() ?? '';
        if (id.isEmpty || existingIds.contains(id)) continue;

        map['channels'] = _getActiveChannels();
        map['deliveryStatus'] = _buildInitialDeliveries(map['channels']);
        final record = NotificationRecord.fromMap(map);
        _records.insert(0, record);
        await DatabaseHelper().insertNotification(record.toMap());
        merged++;
      }

      // 超出上限时截断
      if (_records.length > _maxRecords) {
        _records.removeRange(_maxRecords, _records.length);
      }

      if (merged > 0) {
        debugPrint('[HistoryCache] 合并 $merged 条离线通知');
      }
    } catch (e) {
      debugPrint('拉取离线缓存失败: $e');
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
    record['deliveryStatus'] = _buildInitialDeliveries(record['channels']);
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
      case 'wechat_work':
        return 'webhook:企业微信';
      case '1':
      case 'dingtalk':
        return 'webhook:钉钉';
      case '2':
      case 'feishu':
        return 'webhook:飞书';
      case 'telegram':
        return 'webhook:Telegram';
      case 'bark':
        return 'webhook:Bark';
      default:
        return 'webhook:Webhook';
    }
  }

  /// 初始送达状态：所有启用通道标记为 pending（发送中）
  Map<String, dynamic> _buildInitialDeliveries(List<String> channels) {
    final result = <String, dynamic>{};
    for (final c in channels) {
      result[c] = {'status': 'pending', 'message': ''};
    }
    return result;
  }

  /// Kotlin 端 WebhookType 枚举名 → 通道标签（与 _webhookTypeLabel 保持一致）
  String _deliveryLabel(String kotlinType) {
    switch (kotlinType) {
      case 'WECHAT_WORK':
        return 'webhook:企业微信';
      case 'DINGTALK':
        return 'webhook:钉钉';
      case 'FEISHU':
        return 'webhook:飞书';
      case 'TELEGRAM':
        return 'webhook:Telegram';
      case 'BARK':
        return 'webhook:Bark';
      default:
        return 'webhook:Webhook';
    }
  }

  /// 更新单条记录的送达状态（Kotlin 端 onDeliveryResult 回传）
  Future<void> updateDelivery(
    String notificationId,
    String kotlinType,
    String status,
    String message,
  ) async {
    if (notificationId.isEmpty) return;
    final idx = _records.indexWhere((r) => r.id == notificationId);
    if (idx < 0) return;
    final label = _deliveryLabel(kotlinType);
    final updated = Map<String, dynamic>.from(_records[idx].deliveryStatus);
    updated[label] = {
      'status': status == 'SUCCESS' ? 'success' : 'failed',
      'message': message,
    };
    final newRecord = _records[idx].copyWith(deliveryStatus: updated);
    _records[idx] = newRecord;
    try {
      await DatabaseHelper().updateNotificationDelivery(newRecord.id, updated);
    } catch (e) {
      // DB 持久化失败不影响内存送达状态显示
      debugPrint('更新送达状态到 DB 失败: $e');
    }
  }

  /// 统一统计：总数（DB），三处统计共用同一数据源
  Future<int> getTotalCount() async {
    try {
      return await DatabaseHelper().getNotificationCount();
    } catch (e) {
      debugPrint('获取总记录数失败: $e');
      return _records.length;
    }
  }

  /// 统一统计：今日数（DB，本地时区），三处统计共用同一数据源
  Future<int> getTodayCount() async {
    try {
      return await DatabaseHelper().getTodayCount();
    } catch (e) {
      debugPrint('获取今日记录数失败: $e');
      final now = DateTime.now();
      final today =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      return _records.where((r) => r.time.startsWith(today)).length;
    }
  }

  /// 状态栏计数统一：把 DB 今日数同步为原生当日计数基数
  Future<void> syncDailyCountToNative() async {
    try {
      final count = await getTodayCount();
      final now = DateTime.now();
      final date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
      await _channel.invokeMethod('syncDailyPushCount', {
        'count': count,
        'date': date,
      });
    } catch (e) {
      debugPrint('同步今日计数到原生失败: $e');
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
    try {
      await DatabaseHelper().insertNotification(record);
    } catch (e) {
      // DB 持久化失败不阻塞内存记录显示（避免未处理异步异常）
      debugPrint('保存通知记录到 DB 失败: $e');
    }
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
      constraints: Constraints(networkType: NetworkType.not_required),
      existingWorkPolicy: ExistingWorkPolicy.replace,
      initialDelay: const Duration(minutes: 1),
    );
    debugPrint('[Archive] WorkManager 任务已注册');
    // 前台兜底：App 启动后立即检查并执行一次归档
    performArchiveOnBoot();
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
