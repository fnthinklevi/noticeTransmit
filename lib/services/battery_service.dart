import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import 'engine_rule_codec.dart';
import 'engine_rule_repository.dart';
import 'platform_channel.dart';

/// 电量告警设置的服务（与 [TemperatureService] 同构）。
///
/// 是 [ChangeNotifier]：每个写操作都广播。电量页从"父页装配回调 + 传快照"改成
/// 订阅本服务（T16 为温度页立的先例），原因有两条：① 设置页是路由推进去的，父页
/// `setState` rebuild 不到它；② 中间 tab 换成了「通知引擎」骨架页，电量页变成它
/// push 出去的子页 —— 再造一层"父页持有回调往下传"的形状，就是第三份接线。
class BatteryService extends ChangeNotifier {
  BatteryService({EngineRuleStore? store})
    : _ruleStore = EngineRuleRepository(
        family: EngineRuleCodec.familyBattery,
        prefsKey: 'battery_rules',
        store: store,
      );

  static const _channel = AppChannels.notification;

  /// 规则存储咽喉（T20 起 DB 为准，prefs 旧键是原生镜像 + 回退）。
  final EngineRuleRepository _ruleStore;

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
    _rules = await _ruleStore.load(seed: _defaultRules);
    notifyListeners();
  }

  Future<void> saveNotifyEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('battery_notify_enabled', value);
    _notifyEnabled = value;
    // 先广播再调原生：界面不等平台通道往返（开关"点完弹回"的成因之一就是反序）
    notifyListeners();

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

  /// 规则落库 + 同步原生的**唯一**出口，广播也收在这里（T16 的先例）：
  /// 写操作散在五处，逐个补 notify 迟早漏一个。
  ///
  /// 落点自 T20 起是 `engine_rules` 表（[EngineRuleRepository] 里还顺带刷原生镜像、
  /// 通知服务重载）。这里只兜住"库写不进去"：内存里的编辑保留，界面不吞掉用户的操作。
  Future<void> _syncRules() async {
    notifyListeners();
    try {
      await _ruleStore.save(_rules);
    } catch (e) {
      debugPrint('BatteryService: 规则保存失败: $e');
    }
  }

  /// N5 备份恢复：整体恢复电量设置（开关 + 规则），走既有原生同步链路。
  /// 参数为 null 的部分保持当前值不变。
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
      _applyStatus(result['level'] ?? -1, result['isCharging'] ?? false);
    } catch (e) {
      debugPrint('BatteryService: 获取电池状态失败: $e');
    }
  }

  void updateBatteryStatus(Map<String, dynamic> data) {
    _applyStatus(data['level'] ?? -1, data['isCharging'] ?? false);
  }

  /// 只在**真的变了**才广播：本服务每 30 秒轮询一次，无条件 notify 等于每 30 秒
  /// 重建一次电量页（而且看不出是哪次变更引起的重建）。
  void _applyStatus(int level, bool isCharging) {
    if (level == _currentLevel && isCharging == _currentIsCharging) return;
    _currentLevel = level;
    _currentIsCharging = isCharging;
    notifyListeners();
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

  @override
  void dispose() {
    _isDisposed = true;
    stopRefreshTimer();
    super.dispose();
  }
}
