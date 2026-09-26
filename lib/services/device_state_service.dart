import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import 'engine_rule_codec.dart';
import 'engine_rule_repository.dart';
import 'platform_channel.dart';

/// T24：设备状态告警（亮度 + 网络）服务。
///
/// 与 [BatteryService] / [TemperatureService] 同形（规则住 `engine_rules` 表，族名
/// `device_state`），但**两族规则共用一族** —— 引擎是按 `type` 路由的，为"亮度/网络"
/// 各开一族就会多出一份 prefs 镜像键、一条重载链路、一份备份槽位，而它们要的语义
/// 完全一样（"设备到了某个状态要不要提醒"）。
///
/// 页面订阅本服务（T16 立的先例）：这些规则页是路由推进去的，父页 `setState` 到不了，
/// 传快照就会得到"保存不刷新、开关点完弹回"。
class DeviceStateService extends ChangeNotifier {
  DeviceStateService({EngineRuleStore? store})
    : _ruleStore = EngineRuleRepository(
        family: EngineRuleCodec.familyDeviceState,
        prefsKey: 'device_state_rules',
        store: store,
      );

  static const _channel = AppChannels.notification;

  /// 触发类型 —— Dart 侧唯一定义处，必须与 Kotlin `NotificationEngine.DEVICE_STATE_RULE_TYPES`
  /// 逐字一致（由 test/architecture/device_state_contract_test.dart 实测比对）。
  /// 两端字符串不一致不会有任何编译期报错，规则只会静默不触发。
  static const Set<String> deviceStateRuleTypes = <String>{
    'brightness_below',
    'brightness_above',
    'network_connected',
    'network_disconnected',
  };

  /// 只有亮度两型用阈值；网络两型的 `value` 恒为 0（存储列不允许 null）。
  static const Set<String> brightnessTypes = <String>{
    'brightness_below',
    'brightness_above',
  };

  /// 亮度阈值范围（百分比）。与温度那族 30-90℃ 同理：**边界也进跨端守卫**，
  /// 因为引擎按"跨越"判定，页面能配出的阈值必须都在引擎可判的值域内。
  static const int minBrightness = 1;
  static const int maxBrightness = 99;

  final EngineRuleRepository _ruleStore;

  bool _notifyEnabled = true;
  List<Map<String, dynamic>> _rules = [];

  bool get notifyEnabled => _notifyEnabled;
  List<Map<String, dynamic>> get rules => _rules;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _notifyEnabled = prefs.getBool('device_state_notify_enabled') ?? true;
    // 这一族没有出厂规则：亮度/网络告警都是"用户主动要才推"的东西。
    _rules = await _ruleStore.load();
    notifyListeners();
  }

  Future<void> saveNotifyEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('device_state_notify_enabled', value);
    _notifyEnabled = value;
    // 先广播再调原生：界面不等平台通道往返（"点完弹回"的成因之一就是反序）。
    notifyListeners();
    try {
      // 复用通用布尔写通道（它顺带让服务重载）。方法名里的 battery 是历史包袱：
      // 三族走的是同一句 `prefs.putBoolean("flutter.<key>") + notifyServiceConfigChanged()`，
      // 为一枚开关再新增一个方法是方法数只降不升这条规矩不允许的。
      await _channel.invokeMethod('setBatterySetting', {
        'key': 'device_state_notify_enabled',
        'value': value,
      });
    } catch (e) {
      debugPrint('DeviceStateService: 设置推送开关失败: $e');
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
      if (r['id'] == id) return {...r, 'enabled': enabled};
      return r;
    }).toList();
    await _syncRules();
  }

  /// 所有写操作的唯一出口（与电量/温度族同一条规矩）：广播放这里，
  /// 免得新增一个写方法就漏一次通知。落点是 `engine_rules` 表，
  /// 镜像与原生重载在 [EngineRuleRepository] 里做。
  Future<void> _syncRules() async {
    notifyListeners();
    try {
      await _ruleStore.save(_rules);
    } catch (e) {
      debugPrint('DeviceStateService: 规则保存失败: $e');
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
