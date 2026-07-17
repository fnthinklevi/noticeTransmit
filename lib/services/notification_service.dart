import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../models/notification_record.dart';
import 'platform_channel.dart';

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
      print('数据库迁移失败: $e');
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
    _serviceManuallyStopped =
        prefs.getBool('service_manually_stopped') ?? false;
    try {
      _serviceRunning =
          await _channel.invokeMethod('isServiceRunning') as bool? ?? false;
    } catch (e) {
      _serviceRunning = false;
    }
  }

  void addRecord(Map<String, dynamic> record) {
    final notificationRecord = NotificationRecord.fromMap(record);
    _records.insert(0, notificationRecord);
    if (_records.length > _maxRecords) {
      _records.removeRange(_maxRecords, _records.length);
    }
    _saveRecords(notificationRecord.toMap());
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
      '_warning': '此文件包含设备通知记录与应用使用数据，请妥善保管，避免泄露。'
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
