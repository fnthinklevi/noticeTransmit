import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'platform_channel.dart';

class BatteryService {
  static const _channel = AppChannels.notification;

  bool _notifyEnabled = true;
  List<Map<String, dynamic>> _rules = [];
  int _currentLevel = -1;
  bool _currentIsCharging = false;
  Timer? _refreshTimer;
  bool _isDisposed = false;

  bool get notifyEnabled => _notifyEnabled;
  List<Map<String, dynamic>> get rules => _rules;
  int get currentLevel => _currentLevel;
  bool get currentIsCharging => _currentIsCharging;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _notifyEnabled = prefs.getBool('battery_notify_enabled') ?? true;
    _rules = _loadRules(prefs);
    await _syncRules();
  }

  Future<void> saveNotifyEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('battery_notify_enabled', value);
    _notifyEnabled = value;

    try {
      await _channel.invokeMethod('setBatterySetting', {
        'key': 'battery_notify_enabled',
        'value': value,
      });
    } catch (e) {
      debugPrint('BatteryService: 设置推送开关失败: $e');
    }
  }

  Future<void> addRule(Map<String, dynamic> rule) async {
    _rules = [..._rules, rule];
    await _syncRules();
  }

  Future<void> deleteRule(String id) async {
    _rules = _rules.where((r) => r['id'] != id).toList();
    await _syncRules();
  }

  Future<void> updateRule(String id, Map<String, dynamic> newRule) async {
    _rules = _rules.map((r) {
      if (r['id'] == id) return newRule;
      return r;
    }).toList();
    await _syncRules();
  }

  Future<void> toggleRule(String id, bool enabled) async {
    _rules = _rules.map((r) {
      if (r['id'] == id) {
        return {...r, 'enabled': enabled};
      }
      return r;
    }).toList();
    await _syncRules();
  }

  Future<void> _syncRules() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('battery_rules', jsonEncode(_rules));

    try {
      await _channel.invokeMethod('setBatteryRules', {'rules': _rules});
    } catch (e) {
      debugPrint('BatteryService: 规则同步失败: $e');
    }
  }

  List<Map<String, dynamic>> _loadRules(SharedPreferences prefs) {
    final jsonStr = prefs.getString('battery_rules');
    if (jsonStr != null) {
      try {
        final List<dynamic> list = jsonDecode(jsonStr);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }
    return _defaultRules();
  }

  List<Map<String, dynamic>> _defaultRules() {
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

  Future<void> refreshStatus() async {
    try {
      final result = await _channel.invokeMethod('getBatteryStatus');
      _currentLevel = result['level'] ?? -1;
      _currentIsCharging = result['isCharging'] ?? false;
    } catch (e) {
      debugPrint('BatteryService: 获取电池状态失败: $e');
    }
  }

  void updateBatteryStatus(Map<String, dynamic> data) {
    _currentLevel = data['level'] ?? -1;
    _currentIsCharging = data['isCharging'] ?? false;
  }

  void startRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!_isDisposed) {
        refreshStatus();
      } else {
        timer.cancel();
      }
    });
  }

  void stopRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void dispose() {
    _isDisposed = true;
    stopRefreshTimer();
  }
}
