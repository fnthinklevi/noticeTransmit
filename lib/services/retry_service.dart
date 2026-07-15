import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';

class RetryService {
  static const int maxRetries = 5;
  static const Duration initialRetryDelay = Duration(minutes: 1);
  static const Duration maxRetryDelay = Duration(hours: 1);
  static const int maxPendingNotifications = 100;

  final List<Map<String, dynamic>> _pendingNotifications = [];
  Timer? _retryTimer;
  bool _isRunning = false;

  Future<void> init() async {
    await _migrateFromSharedPreferences();
    await _loadPendingNotifications();
    _startRetryTimer();
  }

  void dispose() {
    _retryTimer?.cancel();
    _isRunning = false;
  }

  Future<void> addFailedNotification(
    Map<String, dynamic> notification,
    String webhookUrl,
    int statusCode,
    String errorMessage,
  ) async {
    final notificationData = jsonEncode(notification);
    final pending = {
      'id': notification['id'] ?? '',
      'notification_data': notificationData,
      'webhook_url': webhookUrl,
      'retry_count': 0,
      'last_retry_time': 0,
      'added_time': DateTime.now().millisecondsSinceEpoch,
      'status_code': statusCode,
      'error_message': errorMessage,
    };

    _pendingNotifications.insert(0, pending);
    if (_pendingNotifications.length > maxPendingNotifications) {
      _pendingNotifications.removeLast();
    }

    await DatabaseHelper().insertPendingNotification(pending);
  }

  Future<void> retryAllPending() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final successfulIds = <String>[];

    for (var pending in _pendingNotifications) {
      final retryCount = pending['retry_count'] as int;
      if (retryCount >= maxRetries) {
        successfulIds.add(pending['id'] as String);
        continue;
      }

      final lastRetryTime = pending['last_retry_time'] as int;
      final delay = _calculateDelay(retryCount);
      if (now - lastRetryTime < delay.inMilliseconds) {
        continue;
      }

      final success = await _sendNotification(pending);
      if (success) {
        successfulIds.add(pending['id'] as String);
      } else {
        pending['retry_count'] = retryCount + 1;
        pending['last_retry_time'] = now;
        await DatabaseHelper().updatePendingNotification(pending);
      }
    }

    _pendingNotifications.removeWhere((p) => successfulIds.contains(p['id']));
    for (final id in successfulIds) {
      await DatabaseHelper().deletePendingNotification(id);
    }
  }

  Future<bool> _sendNotification(Map<String, dynamic> pending) async {
    try {
      final url = pending['webhook_url'] as String;
      final notificationData = jsonDecode(
        pending['notification_data'] as String,
      );
      final payload = {
        'title': notificationData['title'],
        'content': notificationData['content'],
        'appName': notificationData['appName'],
        'packageName': notificationData['packageName'],
        'time': notificationData['time'],
        'deviceName': notificationData['deviceName'],
        'type': notificationData['type'],
        'retryCount': pending['retry_count'],
      };

      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'User-Agent': 'NotificationMonitor/1.0',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
    } catch (_) {}

    return false;
  }

  Duration _calculateDelay(int retryCount) {
    final delay = initialRetryDelay * (1 << retryCount);
    return delay > maxRetryDelay ? maxRetryDelay : delay;
  }

  void _startRetryTimer() {
    if (_isRunning) return;
    _isRunning = true;

    _retryTimer = Timer.periodic(const Duration(minutes: 2), (timer) async {
      if (_isRunning) {
        await retryAllPending();
      } else {
        timer.cancel();
      }
    });
  }

  Future<void> _loadPendingNotifications() async {
    try {
      final dbPending = await DatabaseHelper().getPendingNotifications();
      _pendingNotifications.clear();
      _pendingNotifications.addAll(dbPending);
    } catch (_) {}
  }

  Future<void> _migrateFromSharedPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString('pending_notifications');
      if (jsonStr == null || jsonStr == '[]') return;

      final List<dynamic> list = jsonDecode(jsonStr);
      if (list.isEmpty) return;

      for (final item in list) {
        if (item is Map<String, dynamic>) {
          final notification = {
            'id': item['id'] ?? '',
            'title': item['title'] ?? '',
            'content': item['content'] ?? '',
            'packageName': item['packageName'] ?? '',
            'appName': item['appName'] ?? '',
            'postTime': item['postTime'] ?? 0,
            'time': item['time'] ?? '',
            'type': item['type'] ?? 'other',
            'deviceName': item['deviceName'] ?? '',
          };
          await DatabaseHelper().insertPendingNotification({
            'id': item['id'] ?? '',
            'notification_data': jsonEncode(notification),
            'webhook_url': item['webhookUrl'] ?? '',
            'retry_count': item['retryCount'] ?? 0,
            'last_retry_time': item['lastRetryTime'] ?? 0,
            'added_time':
                item['addedTime'] ?? DateTime.now().millisecondsSinceEpoch,
            'status_code': item['statusCode'],
            'error_message': item['errorMessage'],
          });
        }
      }

      await prefs.remove('pending_notifications');
    } catch (_) {}
  }

  List<Map<String, dynamic>> get pendingNotifications => _pendingNotifications;

  Future<void> clearPendingNotification(String id) async {
    _pendingNotifications.removeWhere((p) => p['id'] == id);
    await DatabaseHelper().deletePendingNotification(id);
  }

  Future<void> clearAllPending() async {
    _pendingNotifications.clear();
    await DatabaseHelper().clearAllPendingNotifications();
  }
}
