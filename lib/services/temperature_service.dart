import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'platform_channel.dart';

/// 自建应用通道体系的温度规则服务（与 BatteryService 电量规则拆分独立）。
///
/// 管理 `temperature_rules` 表（SharedPreferences 加密 DB），经 MethodChannel
/// 同步到原生（SecurePrefs），原生 BatteryMonitor 轮询判定温度 crossing。
class TemperatureService {
  static const _channel = AppChannels.notification;

  bool _notifyEnabled = true;
  List<Map<String, dynamic>> _rules = [];

  bool get notifyEnabled => _notifyEnabled;
  List<Map<String, dynamic>> get rules => _rules;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _notifyEnabled = prefs.getBool('temperature_notify_enabled') ?? true;
    _rules = _loadRules(prefs);
    await _syncRules();
  }

  Future<void> saveNotifyEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('temperature_notify_enabled', value);
    _notifyEnabled = value;

    try {
      await _channel.invokeMethod('setTemperatureSetting', {
        'key': 'temperature_notify_enabled',
        'value': value,
      });
    } catch (e) {
      debugPrint('TemperatureService: 设置推送开关失败: $e');
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
    await prefs.setString('temperature_rules', jsonEncode(_rules));

    try {
      await _channel.invokeMethod('setTemperatureRules', {'rules': _rules});
    } catch (e) {
      debugPrint('TemperatureService: 规则同步失败: $e');
    }
  }

  Future<void> restoreSettings({
    bool? notifyEnabled,
    List<Map<String, dynamic>>? rules,
  }) async {
    if (notifyEnabled != null) {
      await saveNotifyEnabled(notifyEnabled);
    }
    if (rules != null) {
      _rules = rules;
      await _syncRules();
    }
  }

  List<Map<String, dynamic>> _loadRules(SharedPreferences prefs) {
    final jsonStr = prefs.getString('temperature_rules');
    if (jsonStr != null) {
      try {
        final List<dynamic> list = jsonDecode(jsonStr);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {}
    }
    return [];
  }
}
