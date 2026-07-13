import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../models/notification_record.dart';

class NotificationService {
  static const platform = MethodChannel('com.fnthink.notice/notification');
  static const int _maxRecords = 500;

  final List<NotificationRecord> _records = [];
  bool _serviceRunning = false;
  bool _serviceManuallyStopped = false;

  List<NotificationRecord> get records => _records;
  bool get serviceRunning => _serviceRunning;
  bool get serviceManuallyStopped => _serviceManuallyStopped;

  Future<void> loadRecords() async {
    await DatabaseHelper().migrateFromSharedPreferences();

    try {
      final List<dynamic> result = await platform.invokeMethod(
        'getNotificationRecords',
      );
      _records.clear();
      _records.addAll(
        result
            .map(
              (e) => NotificationRecord.fromMap(Map<String, dynamic>.from(e)),
            )
            .toList(),
      );
    } catch (e) {
      final dbRecords = await DatabaseHelper().getNotifications(
        limit: _maxRecords,
      );
      _records.clear();
      _records.addAll(
        dbRecords.map((e) => NotificationRecord.fromMap(e)).toList(),
      );
    }
  }

  Future<void> loadServiceState() async {
    final prefs = await SharedPreferences.getInstance();
    _serviceManuallyStopped =
        prefs.getBool('service_manually_stopped') ?? false;
    _serviceRunning = await FlutterForegroundTask.isRunningService;
  }

  void addRecord(Map<String, dynamic> record) {
    _records.insert(0, NotificationRecord.fromMap(record));
    if (_records.length > _maxRecords) {
      _records.removeRange(_maxRecords, _records.length);
    }
    _saveRecords(record);
  }

  Future<void> clearRecords() async {
    try {
      await platform.invokeMethod('clearNotificationRecords');
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

    final prefs = await SharedPreferences.getInstance();
    final recordsJson = jsonEncode(
      _records.take(_maxRecords).map((r) => r.toMap()).toList(),
    );
    await prefs.setString('notification_records', recordsJson);
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

  void initForegroundTask() {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'notification_monitor',
        channelName: '通知监听服务',
        channelDescription: '后台运行通知监听服务',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: true,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  Future<bool> startService() async {
    final result = await FlutterForegroundTask.startService(
      notificationTitle: '通知监听中',
      notificationText: '正在监听通知栏消息并推送',
      callback: _foregroundTaskCallback,
    );

    final isSuccess = result is ServiceRequestSuccess;

    _serviceRunning = isSuccess;
    _serviceManuallyStopped = !isSuccess;

    if (isSuccess) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('service_manually_stopped', false);

      try {
        await platform.invokeMethod('startNotificationListener');
      } catch (e) {
        // ignore
      }
    }

    return isSuccess;
  }

  Future<bool> stopService() async {
    final result = await FlutterForegroundTask.stopService();
    final isStopped = result is ServiceRequestSuccess;

    _serviceRunning = !isStopped;
    _serviceManuallyStopped = isStopped;

    if (isStopped) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('service_manually_stopped', true);
    }

    return isStopped;
  }

  @pragma('vm:entry-point')
  static void _foregroundTaskCallback() {
    FlutterForegroundTask.setTaskHandler(NotificationTaskHandler());
  }
}

class NotificationTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // ignore
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    // ignore
  }

  @override
  void onNotificationButtonPressed(String id) {}

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp('/');
  }
}
