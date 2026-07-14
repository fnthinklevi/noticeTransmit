import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PermissionService {
  static const platform = MethodChannel('com.fnthink.notice/notification');

  bool _notificationListenerGranted = false;
  bool _postNotificationGranted = false;
  bool _batteryOptimizationIgnored = false;
  bool _smsGranted = false;
  bool _phoneGranted = false;
  bool _appListGranted = false;

  bool get notificationListenerGranted => _notificationListenerGranted;
  bool get postNotificationGranted => _postNotificationGranted;
  bool get batteryOptimizationIgnored => _batteryOptimizationIgnored;
  bool get smsGranted => _smsGranted;
  bool get phoneGranted => _phoneGranted;
  bool get appListGranted => _appListGranted;

  Future<void> checkAllPermissions() async {
    try {
      final listenerGranted =
          await platform.invokeMethod('isNotificationPermissionGranted')
              as bool?;
      final postGranted =
          await platform.invokeMethod('isPostNotificationPermissionGranted')
              as bool?;
      final batteryOk =
          await platform.invokeMethod('isIgnoringBatteryOptimizations')
              as bool?;
      final smsGranted =
          await platform.invokeMethod('isSmsPermissionGranted') as bool?;
      final phoneGranted =
          await platform.invokeMethod('isPhonePermissionGranted') as bool?;
      final appListGranted =
          await platform.invokeMethod('isAppListPermissionGranted') as bool?;

      _notificationListenerGranted = listenerGranted ?? false;
      _postNotificationGranted = postGranted ?? false;
      _batteryOptimizationIgnored = batteryOk ?? false;
      _smsGranted = smsGranted ?? false;
      _phoneGranted = phoneGranted ?? false;
      _appListGranted = appListGranted ?? false;
    } catch (e) {
      debugPrint('检查权限失败: $e');
    }
  }

  Future<void> _requestPermission(String methodName) async {
    try {
      await platform.invokeMethod(methodName);
    } catch (e) {
      debugPrint('权限请求失败 $methodName: $e');
    }
  }

  Future<void> requestNotificationListenerPermission() =>
      _requestPermission('requestNotificationListenerPermission');
  Future<void> requestPostNotificationPermission() =>
      _requestPermission('requestPostNotificationPermission');
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
  Future<void> requestSmsPermission() =>
      _requestPermission('requestSmsPermission');
  Future<void> requestPhonePermission() =>
      _requestPermission('requestPhonePermission');
  Future<void> requestAppListPermission() =>
      _requestPermission('requestAppListPermission');
}
