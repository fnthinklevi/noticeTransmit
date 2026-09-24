import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'platform_channel.dart';

/// 「读取已安装应用列表」的可见性状态，与原生 `AppListState` 一一对应（跨端契约）。
///
/// 为什么不是 bool：`QUERY_ALL_PACKAGES` 是安装期权限，AOSP 又没给它建 AppOps 映射
/// （真机实测 `permissionToOp == null`）⇒ 系统**给不出**明确的授予/拒绝读数。
/// 布尔只能把"不知道"压成其中一边，旧实现压成了"已授予"，于是权限页恒显已授予、
/// 筛选页跳过引导直接扫描 —— 用户即便在系统里拒绝，也照样能看到应用列表。
enum AppListPermission {
  granted,
  denied,
  unknown;

  /// 未知/缺失值一律退回 [unknown]（绝不默认已授予）。大小写不敏感。
  static AppListPermission fromWire(String? value) {
    return switch (value?.toLowerCase()) {
      'granted' => AppListPermission.granted,
      'denied' => AppListPermission.denied,
      _ => AppListPermission.unknown,
    };
  }
}

class PermissionService {
  static const _channel = AppChannels.notification;

  bool _notificationListenerGranted = false;
  bool _postNotificationGranted = false;
  bool _batteryOptimizationIgnored = false;
  bool _smsGranted = false;
  bool _phoneGranted = false;
  AppListPermission _appList = AppListPermission.unknown;

  bool get notificationListenerGranted => _notificationListenerGranted;
  bool get postNotificationGranted => _postNotificationGranted;
  bool get batteryOptimizationIgnored => _batteryOptimizationIgnored;
  bool get smsGranted => _smsGranted;
  bool get phoneGranted => _phoneGranted;

  /// 只有**有证据**可读才算已授予。`unknown`（系统不给明确状态）不得显示成"已授予"——
  /// 旧实现用布尔承载，把 unknown 压成了 true，权限页因此在所有 Android 11+ 设备上恒显已授予。
  bool get appListGranted => _appList == AppListPermission.granted;
  AppListPermission get appListPermission => _appList;

  Future<void> checkAllPermissions() async {
    try {
      final listenerGranted =
          await _channel.invokeMethod('isNotificationPermissionGranted')
              as bool?;
      final postGranted =
          await _channel.invokeMethod('isPostNotificationPermissionGranted')
              as bool?;
      final batteryOk =
          await _channel.invokeMethod('isIgnoringBatteryOptimizations')
              as bool?;
      final smsGranted =
          await _channel.invokeMethod('isSmsPermissionGranted') as bool?;
      final phoneGranted =
          await _channel.invokeMethod('isPhonePermissionGranted') as bool?;
      final appListState =
          await _channel.invokeMethod('getAppListPermissionState') as String?;

      _notificationListenerGranted = listenerGranted ?? false;
      _postNotificationGranted = postGranted ?? false;
      _batteryOptimizationIgnored = batteryOk ?? false;
      _smsGranted = smsGranted ?? false;
      _phoneGranted = phoneGranted ?? false;
      _appList = AppListPermission.fromWire(appListState);
    } catch (e) {
      debugPrint('检查权限失败: $e');
    }
  }

  Future<void> _requestPermission(String methodName) async {
    try {
      await _channel.invokeMethod(methodName);
    } catch (e) {
      debugPrint('权限请求失败 $methodName: $e');
    }
  }

  Future<void> requestNotificationListenerPermission() =>
      _requestPermission('requestNotificationListenerPermission');

  Future<void> requestPostNotificationPermission() async {
    final status = await Permission.notification.request();
    if (status == PermissionStatus.granted) {
      _postNotificationGranted = true;
    }
  }

  Future<void> requestBatteryOptimization() =>
      _requestPermission('requestBatteryOptimization');

  Future<void> requestXiaomiAutoStart() =>
      _requestPermission('requestXiaomiAutoStart');

  Future<void> requestMeizuBackground() =>
      _requestPermission('requestMeizuBackground');

  Future<void> requestHuaweiLaunch() =>
      _requestPermission('requestHuaweiLaunch');

  Future<void> requestOppoBackground() =>
      _requestPermission('requestOppoBackground');

  Future<void> requestVivoBackground() =>
      _requestPermission('requestVivoBackground');

  /// B1 精确闹钟：查询开关状态 / 系统授权状态 / 切换开关 / 引导授权
  Future<bool> isExactAlarmEnabled() async {
    try {
      return await _channel.invokeMethod('isExactAlarmEnabled') as bool? ??
          false;
    } catch (e) {
      debugPrint('查询精确闹钟开关失败: $e');
      return false;
    }
  }

  Future<bool> canScheduleExactAlarms() async {
    try {
      return await _channel.invokeMethod('canScheduleExactAlarms') as bool? ??
          false;
    } catch (e) {
      debugPrint('查询精确闹钟授权失败: $e');
      return false;
    }
  }

  Future<void> setExactAlarmEnabled(bool enabled) async {
    try {
      await _channel.invokeMethod('setExactAlarmEnabled', {'enabled': enabled});
    } catch (e) {
      debugPrint('切换精确闹钟失败: $e');
    }
  }

  Future<void> requestExactAlarmPermission() =>
      _requestPermission('requestExactAlarmPermission');

  Future<void> requestSmsPermission() async {
    final status = await Permission.sms.request();
    if (status == PermissionStatus.granted) {
      _smsGranted = true;
    }
  }

  Future<void> requestPhonePermission() async {
    final status = await Permission.phone.request();
    if (status == PermissionStatus.granted) {
      _phoneGranted = true;
    }
  }

  Future<void> requestAppListPermission() =>
      _requestPermission('requestQueryAllPackagesPermission');
}
