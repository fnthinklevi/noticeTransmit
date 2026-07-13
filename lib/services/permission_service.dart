import 'package:flutter/services.dart';

class PermissionService {
  static const platform = MethodChannel('com.fnthink.notice/notification');

  bool _notificationGranted = false;
  bool _batteryOptimizationIgnored = false;
  bool _smsGranted = false;
  bool _phoneGranted = false;
  bool _appListGranted = false;

  bool get notificationGranted => _notificationGranted;
  bool get batteryOptimizationIgnored => _batteryOptimizationIgnored;
  bool get smsGranted => _smsGranted;
  bool get phoneGranted => _phoneGranted;
  bool get appListGranted => _appListGranted;

  Future<void> checkAllPermissions() async {
    try {
      final granted =
          await platform.invokeMethod('isNotificationPermissionGranted')
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

      _notificationGranted = granted ?? false;
      _batteryOptimizationIgnored = batteryOk ?? false;
      _smsGranted = smsGranted ?? false;
      _phoneGranted = phoneGranted ?? false;
      _appListGranted = appListGranted ?? false;
    } catch (e) {
      // ignore
    }
  }

  Future<void> requestNotificationPermission() async {
    try {
      await platform.invokeMethod('requestNotificationPermission');
    } catch (e) {
      // ignore
    }
  }

  Future<void> requestBatteryOptimization() async {
    try {
      await platform.invokeMethod('requestBatteryOptimization');
    } catch (e) {
      // ignore
    }
  }

  Future<void> requestXiaomiAutoStart() async {
    try {
      await platform.invokeMethod('requestXiaomiAutoStart');
    } catch (e) {
      // ignore
    }
  }

  Future<void> requestMeizuBackground() async {
    try {
      await platform.invokeMethod('requestMeizuBackground');
    } catch (e) {
      // ignore
    }
  }

  Future<void> requestHuaweiLaunch() async {
    try {
      await platform.invokeMethod('requestHuaweiLaunch');
    } catch (e) {
      // ignore
    }
  }

  Future<void> requestOppoBackground() async {
    try {
      await platform.invokeMethod('requestOppoBackground');
    } catch (e) {
      // ignore
    }
  }

  Future<void> requestVivoBackground() async {
    try {
      await platform.invokeMethod('requestVivoBackground');
    } catch (e) {
      // ignore
    }
  }

  Future<void> requestSmsPermission() async {
    try {
      await platform.invokeMethod('requestSmsPermission');
    } catch (e) {
      // ignore
    }
  }

  Future<void> requestPhonePermission() async {
    try {
      await platform.invokeMethod('requestPhonePermission');
    } catch (e) {
      // ignore
    }
  }

  Future<void> requestAppListPermission() async {
    try {
      await platform.invokeMethod('requestAppListPermission');
    } catch (e) {
      // ignore
    }
  }
}
