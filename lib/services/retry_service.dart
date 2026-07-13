import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class RetryService {
  static const int maxRetries = 5;
  static const Duration initialRetryDelay = Duration(minutes: 1);
  static const Duration maxRetryDelay = Duration(hours: 1);
  static const int maxPendingNotifications = 100;

  final List<Map<String, dynamic>> _pendingNotifications = [];
  Timer? _retryTimer;
  bool _isRunning = false;

  Future<void> init() async {
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
    final pending = {
      'id': notification['id'] ?? '',
      'title': notification['title'] ?? '',
      'content': notification['content'] ?? '',
      'packageName': notification['packageName'] ?? '',
      'appName': notification['appName'] ?? '',
      'postTime': notification['postTime'] ?? 0,
      'time': notification['time'] ?? '',
      'type': notification['type'] ?? 'other',
      'deviceName': notification['deviceName'] ?? '',
      'webhookUrl': webhookUrl,
      'retryCount': 0,
      'lastRetryTime': 0,
      'statusCode': statusCode,
      'errorMessage': errorMessage,
      'addedTime': DateTime.now().millisecondsSinceEpoch,
    };

    _pendingNotifications.insert(0, pending);
    if (_pendingNotifications.length > maxPendingNotifications) {
      _pendingNotifications.removeLast();
    }

    await _savePendingNotifications();
  }

  Future<void> retryAllPending() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final successfulIds = <String>[];

    for (var pending in _pendingNotifications) {
      final retryCount = pending['retryCount'] as int;
      if (retryCount >= maxRetries) {
        successfulIds.add(pending['id'] as String);
        continue;
      }

      final lastRetryTime = pending['lastRetryTime'] as int;
      final delay = _calculateDelay(retryCount);
      if (now - lastRetryTime < delay.inMilliseconds) {
        continue;
      }

      final success = await _sendNotification(pending);
      if (success) {
        successfulIds.add(pending['id'] as String);
      } else {
        pending['retryCount'] = retryCount + 1;
        pending['lastRetryTime'] = now;
      }
    }

    _pendingNotifications.removeWhere((p) => successfulIds.contains(p['id']));
    await _savePendingNotifications();
  }

  Future<bool> _sendNotification(Map<String, dynamic> pending) async {
    try {
      final url = pending['webhookUrl'] as String;
      final payload = {
        'title': pending['title'],
        'content': pending['content'],
        'appName': pending['appName'],
        'packageName': pending['packageName'],
        'time': pending['time'],
        'deviceName': pending['deviceName'],
        'type': pending['type'],
        'retryCount': pending['retryCount'],
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

    _retryTimer = Timer.periodic(const Duration(minutes: 2), (_) async {
      await retryAllPending();
    });
  }

  Future<void> _loadPendingNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('pending_notifications');
      if (json != null) {
        final List<dynamic> list = jsonDecode(json);
        _pendingNotifications.clear();
        _pendingNotifications.addAll(
          list.map((e) => Map<String, dynamic>.from(e)).toList(),
        );
      }
    } catch (_) {}
  }

  Future<void> _savePendingNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'pending_notifications',
        jsonEncode(_pendingNotifications),
      );
    } catch (_) {}
  }

  List<Map<String, dynamic>> get pendingNotifications => _pendingNotifications;

  Future<void> clearPendingNotification(String id) async {
    _pendingNotifications.removeWhere((p) => p['id'] == id);
    await _savePendingNotifications();
  }

  Future<void> clearAllPending() async {
    _pendingNotifications.clear();
    await _savePendingNotifications();
  }
}
