import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import 'engine_rule_codec.dart';
import 'engine_rule_repository.dart';
import 'platform_channel.dart';

/// 自建应用通道体系的温度规则服务（与 BatteryService 电量规则拆分独立）。
///
/// 规则住在加密库的 `engine_rules` 表（T20，与电量规则同表不同族），经
/// [EngineRuleRepository] 同时刷 prefs 旧键镜像 —— 原生 `BatteryMonitor` 轮询判定
/// 温度 crossing 时读的还是那份镜像（T21/T22 切主路径后再撤，见该文件注释）。
///
/// 是 [ChangeNotifier]：每个写操作都 `notifyListeners()`。设置页是**路由**推进去的，
/// 父页 `setState`  rebuild 不到它 —— 此前页面拿的是 push 那一刻的 `List` 引用，
/// 而本服务的写操作又是 `_rules = [..._rules, rule]` **整体换新**，于是页面永远停在
/// 旧列表上（保存不刷新、开关点完弹回）。改由页面订阅，见 `temperature_page.dart`。
class TemperatureService extends ChangeNotifier {
  TemperatureService({EngineRuleStore? store})
    : _ruleStore = EngineRuleRepository(
        family: EngineRuleCodec.familyTemperature,
        prefsKey: 'temperature_rules',
        store: store,
      );

  static const _channel = AppChannels.notification;

  /// 规则存储咽喉（T20 起 DB 为准，prefs 旧键是原生镜像 + 回退）
  final EngineRuleRepository _ruleStore;

  /// 温度规则类型 —— Dart 侧唯一定义处，必须与 Kotlin
  /// `BatteryMonitor.TEMP_RULE_TYPES` 逐字一致（由
  /// test/services/battery_temperature_contract_test.dart 实测比对）。
  /// 两端字符串不一致不会有任何编译期报错，规则只会静默不触发。
  static const Set<String> tempRuleTypes = <String>{
    'battery_temp_above',
    'device_temp_above',
    'screen_temp_above',
  };

  bool _notifyEnabled = true;
  List<Map<String, dynamic>> _rules = [];

  bool get notifyEnabled => _notifyEnabled;
  List<Map<String, dynamic>> get rules => _rules;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _notifyEnabled = prefs.getBool('temperature_notify_enabled') ?? true;
    // 温度族**没有**默认规则可播：电量页那五条是出厂预置，温度页出厂为空是设计如此。
    _rules = await _ruleStore.load();
    notifyListeners();
  }

  Future<void> saveNotifyEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('temperature_notify_enabled', value);
    _notifyEnabled = value;
    notifyListeners();

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

  /// 所有规则写操作（增/删/改/停/恢复/加载）的唯一出口 —— 广播也放这里，
  /// 免得新增一个写方法就漏一次通知（漏了就是"改了界面不刷新"）。
  /// 落点自 T20 起是 `engine_rules` 表，镜像与原生重载在 [EngineRuleRepository] 里做。
  Future<void> _syncRules() async {
    // 本地状态一落定就广播：**不等落库**。等一次平台通道/磁盘往返的代价实测就是
    // "改了不刷新"（界面停在旧列表上）。
    notifyListeners();
    try {
      await _ruleStore.save(_rules);
    } catch (e) {
      debugPrint('TemperatureService: 规则保存失败: $e');
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
}
