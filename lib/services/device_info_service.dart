import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/device_snapshot.dart';
import 'platform_channel.dart';

class DeviceInfoService {
  static const _channel = AppChannels.notification;

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
          await _channel.invokeMethod('getDeviceName') as String?;
      if (nativeDeviceName != null && nativeDeviceName.isNotEmpty) {
        _deviceName = nativeDeviceName;
        await prefs.setString('device_name', nativeDeviceName);
      }
    } catch (e) {
      _deviceName = prefs.getString('device_name') ?? '';
    }

    try {
      _deviceModel = await _channel.invokeMethod('getDeviceModel') ?? '';
      _manufacturer = await _channel.invokeMethod('getManufacturer') ?? '';
    } catch (e) {
      debugPrint('获取设备信息失败: $e');
    }
  }

  Future<void> saveDeviceName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('device_name', name);
    _deviceName = name;

    try {
      await _channel.invokeMethod('setDeviceName', {'name': name});
    } catch (_) {}
  }

  /// T17：设备快照，**一次**调用读全（型号/版本/网络/电量与温度/存储/内存/亮度/运行时长）。
  ///
  /// 之前这些要发四五次 invokeMethod（`getDeviceModel` / `getManufacturer` /
  /// `getBatteryStatus` …），每次都是一个跨进程往返、各自 catch、还凑不出"同一时刻的
  /// 设备状态"。T18 的详情页要一次显示 10 项，逐条读会明显闪烁。
  ///
  /// 返回 null 只代表**这次调用失败**（通道异常），字段级"读不到"由
  /// [DeviceSnapshot.unavailable] 表达 —— 所以调用方不能把 null 当成"全是 0"。
  ///
  /// ⚠ 必须带超时：平台通道没有"永不回复"这个选项。页面在 `initState` 里 await 它，
  /// 原生那侧一旦不回话，界面就永远停在转圈（T25 的 `previewTest` 就是这么把整轮
  /// 发版闸门挂住的，见 base.md（83））。
  Future<DeviceSnapshot?> getDeviceSnapshot() async {
    try {
      final raw = await _channel
          .invokeMethod<Map<Object?, Object?>>('getDeviceSnapshot')
          .timeout(
            const Duration(seconds: 8),
            onTimeout: () => throw TimeoutException('原生 8s 未回复'),
          );
      return raw == null ? null : DeviceSnapshot.fromMap(raw);
    } catch (e) {
      debugPrint('获取设备快照失败: $e');
      return null;
    }
  }
}
