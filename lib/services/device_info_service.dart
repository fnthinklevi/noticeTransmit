import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DeviceInfoService {
  static const platform = MethodChannel('com.fnthink.notice/notification');

  String _deviceName = '';
  String _deviceModel = '';
  String _manufacturer = '';

  String get deviceName => _deviceName;
  String get deviceModel => _deviceModel;
  String get manufacturer => _manufacturer;

  Future<void> loadDeviceInfo() async {
    final prefs = await SharedPreferences.getInstance();

    try {
      final nativeDeviceName =
          await platform.invokeMethod('getDeviceName') as String?;
      if (nativeDeviceName != null && nativeDeviceName.isNotEmpty) {
        _deviceName = nativeDeviceName;
        await prefs.setString('device_name', nativeDeviceName);
      }
    } catch (e) {
      _deviceName = prefs.getString('device_name') ?? '';
    }

    try {
      _deviceModel = await platform.invokeMethod('getDeviceModel') ?? '';
      _manufacturer = await platform.invokeMethod('getManufacturer') ?? '';
    } catch (e) {
      debugPrint('获取设备信息失败: $e');
    }
  }

  Future<void> saveDeviceName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_name', name);
    _deviceName = name;

    try {
      await platform.invokeMethod('setDeviceName', {'name': name});
    } catch (_) {}
  }
}
