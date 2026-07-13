import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
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
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      _deviceModel = androidInfo.model;
      _manufacturer = androidInfo.manufacturer;
    } catch (e) {
      // ignore
    }

    try {
      final model = await platform.invokeMethod('getDeviceModel') as String?;
      final manu = await platform.invokeMethod('getManufacturer') as String?;
      if (model != null) _deviceModel = model;
      if (manu != null) _manufacturer = manu;
    } catch (e) {
      // ignore
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
