import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'platform_channel.dart';

/// 短信/电话监听配置。
///
/// Dart 与原生读同一份 SharedPreferences（原生 key 带 `flutter.` 前缀），
/// 原生短信/电话链路每次事件都新建 ConfigManager 实时读取，开关秒级生效。
class SmsService {
  static const _channel = AppChannels.notification;

  /// 短信监听总开关（关闭后三条短信链路全部短路：不读、不推、不入历史）
  bool _smsMonitorEnabled = true;

  /// 监听卡选择：'all' | '1' | '2'（同时作用于短信和电话）
  String _simFilter = 'all';

  /// 「监听验证码」开关（关闭后包含验证码的短信整条拦截）
  bool _codeMonitorEnabled = true;

  /// 当前可用 SIM 卡数量（<=1 时"监听卡"选项置灰；读取失败默认 2 不误伤双卡用户）
  int _simCardCount = 2;

  bool get smsMonitorEnabled => _smsMonitorEnabled;
  String get simFilter => _simFilter;
  bool get codeMonitorEnabled => _codeMonitorEnabled;
  int get simCardCount => _simCardCount;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _smsMonitorEnabled = prefs.getBool('sms_monitor_enabled') ?? true;
    _simFilter = prefs.getString('sms_sim_filter') ?? 'all';
    _codeMonitorEnabled = prefs.getBool('sms_code_monitor_enabled') ?? true;
    try {
      _simCardCount = await _channel.invokeMethod<int>('getSimCardCount') ?? 2;
    } catch (e) {
      debugPrint('SmsService: 查询 SIM 卡数量失败: $e');
    }
  }

  Future<void> saveSmsMonitorEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sms_monitor_enabled', value);
    _smsMonitorEnabled = value;
    await _sync('sms_monitor_enabled', value);
  }

  Future<void> saveSimFilter(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('sms_sim_filter', value);
    _simFilter = value;
    await _sync('sms_sim_filter', value);
  }

  Future<void> saveCodeMonitorEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('sms_code_monitor_enabled', value);
    _codeMonitorEnabled = value;
    await _sync('sms_code_monitor_enabled', value);
  }

  Future<void> _sync(String key, dynamic value) async {
    try {
      await _channel.invokeMethod('setSmsSetting', {
        'key': key,
        'value': value,
      });
    } catch (e) {
      debugPrint('SmsService: 同步短信监听配置失败: $e');
    }
  }
}
