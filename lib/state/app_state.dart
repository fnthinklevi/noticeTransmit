import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/notification_record.dart';
import '../models/notification_rule.dart';

class AppState extends ChangeNotifier {
  static const int _maxRecords = 500;

  bool _notificationPermissionGranted = false;
  bool _batteryOptimizationIgnored = false;
  bool _foregroundServiceRunning = false;
  bool _smsPermissionGranted = false;
  bool _phonePermissionGranted = false;
  bool _appListPermissionGranted = false;
  bool _serviceManuallyStopped = false;

  List<Map<String, dynamic>> _webhookChannels = [];

  String _deviceName = '';
  String _deviceModel = '';
  String _manufacturer = '';

  final List<NotificationRecord> _notificationRecords = [];

  bool _batteryNotifyEnabled = true;
  List<Map<String, dynamic>> _batteryRules = [];
  int _currentBatteryLevel = -1;
  bool _currentIsCharging = false;

  Set<String> _enabledPackages = {};
  List<String> _blacklistKeywords = [];
  List<String> _whitelistKeywords = [];
  List<NotificationRule> _notificationRules = [];

  bool _isCheckingUpdate = false;
  bool _isDownloading = false;

  bool get notificationPermissionGranted => _notificationPermissionGranted;
  set notificationPermissionGranted(bool value) {
    _notificationPermissionGranted = value;
    notifyListeners();
  }

  bool get batteryOptimizationIgnored => _batteryOptimizationIgnored;
  set batteryOptimizationIgnored(bool value) {
    _batteryOptimizationIgnored = value;
    notifyListeners();
  }

  bool get foregroundServiceRunning => _foregroundServiceRunning;
  set foregroundServiceRunning(bool value) {
    _foregroundServiceRunning = value;
    notifyListeners();
  }

  bool get smsPermissionGranted => _smsPermissionGranted;
  set smsPermissionGranted(bool value) {
    _smsPermissionGranted = value;
    notifyListeners();
  }

  bool get phonePermissionGranted => _phonePermissionGranted;
  set phonePermissionGranted(bool value) {
    _phonePermissionGranted = value;
    notifyListeners();
  }

  bool get appListPermissionGranted => _appListPermissionGranted;
  set appListPermissionGranted(bool value) {
    _appListPermissionGranted = value;
    notifyListeners();
  }

  bool get serviceManuallyStopped => _serviceManuallyStopped;
  set serviceManuallyStopped(bool value) {
    _serviceManuallyStopped = value;
    notifyListeners();
  }

  List<Map<String, dynamic>> get webhookChannels => _webhookChannels;
  set webhookChannels(List<Map<String, dynamic>> value) {
    _webhookChannels = value;
    notifyListeners();
  }

  String get deviceName => _deviceName;
  set deviceName(String value) {
    _deviceName = value;
    notifyListeners();
  }

  String get deviceModel => _deviceModel;
  set deviceModel(String value) {
    _deviceModel = value;
    notifyListeners();
  }

  String get manufacturer => _manufacturer;
  set manufacturer(String value) {
    _manufacturer = value;
    notifyListeners();
  }

  List<NotificationRecord> get notificationRecords => _notificationRecords;

  bool get batteryNotifyEnabled => _batteryNotifyEnabled;
  set batteryNotifyEnabled(bool value) {
    _batteryNotifyEnabled = value;
    notifyListeners();
  }

  List<Map<String, dynamic>> get batteryRules => _batteryRules;
  set batteryRules(List<Map<String, dynamic>> value) {
    _batteryRules = value;
    notifyListeners();
  }

  int get currentBatteryLevel => _currentBatteryLevel;
  set currentBatteryLevel(int value) {
    _currentBatteryLevel = value;
    notifyListeners();
  }

  bool get currentIsCharging => _currentIsCharging;
  set currentIsCharging(bool value) {
    _currentIsCharging = value;
    notifyListeners();
  }

  Set<String> get enabledPackages => _enabledPackages;
  set enabledPackages(Set<String> value) {
    _enabledPackages = value;
    notifyListeners();
  }

  List<String> get blacklistKeywords => _blacklistKeywords;
  set blacklistKeywords(List<String> value) {
    _blacklistKeywords = value;
    notifyListeners();
  }

  List<String> get whitelistKeywords => _whitelistKeywords;
  set whitelistKeywords(List<String> value) {
    _whitelistKeywords = value;
    notifyListeners();
  }

  List<NotificationRule> get notificationRules => _notificationRules;
  set notificationRules(List<NotificationRule> value) {
    _notificationRules = value;
    notifyListeners();
  }

  bool get isCheckingUpdate => _isCheckingUpdate;
  set isCheckingUpdate(bool value) {
    _isCheckingUpdate = value;
    notifyListeners();
  }

  bool get isDownloading => _isDownloading;
  set isDownloading(bool value) {
    _isDownloading = value;
    notifyListeners();
  }

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    _serviceManuallyStopped =
        prefs.getBool('service_manually_stopped') ?? false;
    _batteryNotifyEnabled = prefs.getBool('battery_notify_enabled') ?? true;
    _deviceName = prefs.getString('device_name') ?? '';

    _batteryRules = _loadBatteryRules(prefs);
    _webhookChannels = _loadWebhookChannels(prefs);
    _notificationRules = _loadNotificationRules(prefs);
    _notificationRecords.clear();
    _notificationRecords.addAll(_loadNotificationRecords(prefs));

    notifyListeners();
  }

  Future<void> saveSettings() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool('service_manually_stopped', _serviceManuallyStopped);
    await prefs.setBool('battery_notify_enabled', _batteryNotifyEnabled);
    await prefs.setString('device_name', _deviceName);

    await prefs.setString('battery_rules', jsonEncode(_batteryRules));
    await prefs.setString('webhook_channels', jsonEncode(_webhookChannels));
    await prefs.setString(
      'notification_rules',
      jsonEncode(_notificationRules.map((r) => r.toMap()).toList()),
    );
    await _saveNotificationRecords(prefs);
  }

  List<Map<String, dynamic>> _loadBatteryRules(SharedPreferences prefs) {
    final jsonStr = prefs.getString('battery_rules');
    if (jsonStr != null) {
      try {
        final List<dynamic> list = jsonDecode(jsonStr);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }
    return _defaultBatteryRules();
  }

  List<Map<String, dynamic>> _defaultBatteryRules() {
    return [
      {
        'id': 'charging',
        'type': 'charging',
        'value': 0,
        'enabled': true,
        'title': '开始充电',
        'content': '',
      },
      {
        'id': 'full',
        'type': 'level_above',
        'value': 100,
        'enabled': true,
        'title': '电量充满',
        'content': '',
      },
      {
        'id': 'low30',
        'type': 'level_below',
        'value': 30,
        'enabled': true,
        'title': '电量低于30%',
        'content': '',
      },
      {
        'id': 'low20',
        'type': 'level_below',
        'value': 20,
        'enabled': true,
        'title': '电量低于20%',
        'content': '',
      },
      {
        'id': 'discharging',
        'type': 'discharging',
        'value': 0,
        'enabled': false,
        'title': '断开充电',
        'content': '',
      },
    ];
  }

  List<Map<String, dynamic>> _loadWebhookChannels(SharedPreferences prefs) {
    final urlsJson = prefs.getString('webhook_channels');
    if (urlsJson != null) {
      try {
        final List<dynamic> list = jsonDecode(urlsJson);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }

    final oldUrlsJson = prefs.getString('webhook_urls');
    if (oldUrlsJson != null) {
      try {
        final List<dynamic> list = jsonDecode(oldUrlsJson);
        return list.map((e) => {'url': e.toString(), 'enabled': true}).toList();
      } catch (_) {}
    }

    final singleUrl = prefs.getString('webhook_url');
    if (singleUrl != null && singleUrl.isNotEmpty) {
      return [
        {'url': singleUrl, 'enabled': true},
      ];
    }

    return [];
  }

  List<NotificationRule> _loadNotificationRules(SharedPreferences prefs) {
    final jsonStr = prefs.getString('notification_rules');
    if (jsonStr != null) {
      try {
        final List<dynamic> list = jsonDecode(jsonStr);
        return list
            .map((e) => NotificationRule.fromMap(Map<String, dynamic>.from(e)))
            .toList();
      } catch (_) {}
    }
    return NotificationRule.defaultRules();
  }

  List<NotificationRecord> _loadNotificationRecords(SharedPreferences prefs) {
    final recordsJson = prefs.getString('notification_records');
    if (recordsJson != null) {
      try {
        final List<dynamic> list = jsonDecode(recordsJson);
        return list
            .map(
              (e) => NotificationRecord.fromMap(Map<String, dynamic>.from(e)),
            )
            .toList();
      } catch (_) {}
    }
    return [];
  }

  Future<void> _saveNotificationRecords(SharedPreferences prefs) async {
    final recordsJson = jsonEncode(
      _notificationRecords.take(_maxRecords).map((r) => r.toMap()).toList(),
    );
    await prefs.setString('notification_records', recordsJson);
  }

  void addNotificationRecord(Map<String, dynamic> record) {
    _notificationRecords.insert(0, NotificationRecord.fromMap(record));
    if (_notificationRecords.length > _maxRecords) {
      _notificationRecords.removeRange(
        _maxRecords,
        _notificationRecords.length,
      );
    }
    notifyListeners();
    _saveNotificationRecordsAsync();
  }

  void removeNotificationRecord(String id) {
    _notificationRecords.removeWhere((r) => r.id == id);
    notifyListeners();
    _saveNotificationRecordsAsync();
  }

  Future<void> _saveNotificationRecordsAsync() async {
    final prefs = await SharedPreferences.getInstance();
    await _saveNotificationRecords(prefs);
  }

  Future<void> clearNotificationRecords() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('notification_records');
    _notificationRecords.clear();
    notifyListeners();
  }
}
