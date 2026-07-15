import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'platform_channel.dart';

class PermissionService {
  static const _channel = AppChannels.notification;

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
      final appListGranted =
          await _channel.invokeMethod('isAppListPermissionGranted') as bool?;

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
      _requestPermission('requestAppListPermission');
}
