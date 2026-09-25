/// 设备快照（T17 的数据源，消费方是 T18 的「设备状态」页）。
///
/// 对应原生 `DeviceSnapshot.normalize()` 的输出。**字段名就是跨端契约**：两端各写一份
/// 字符串，改一侧不会有任何编译期报错 —— 由
/// `test/services/device_snapshot_test.dart` 与 Dart 里出现的 `map['x']` 逐名比对钉住。
///
/// 数值一律可空：原生把"读不到"表达为**缺字段 + 记进 `unavailable`**，不是 0/-1。
/// 这里若把 null 兜成 0，就把未知伪装成了已知（存储读不到会显示成"已用满"）。
class DeviceSnapshot {
  final String? model;
  final String? brand;
  final String? manufacturer;
  final String? osVersion;
  final int? sdkInt;

  /// `wifi` / `cellular` / `vpn` / `ethernet` / `other` / `none`
  final String? network;

  final int? batteryLevel;
  final bool? batteryCharging;
  final double? batteryTemperatureC;

  final double? storageTotalMb;
  final double? storageFreeMb;
  final double? memoryTotalMb;
  final double? memoryAvailableMb;

  final int? brightnessPercent;

  /// `auto` / `manual`
  final String? brightnessMode;

  final int? uptimeSeconds;
  final int capturedAtMs;

  /// 原生明确报告"这一项没读到"的字段名
  final List<String> unavailable;

  const DeviceSnapshot({
    this.model,
    this.brand,
    this.manufacturer,
    this.osVersion,
    this.sdkInt,
    this.network,
    this.batteryLevel,
    this.batteryCharging,
    this.batteryTemperatureC,
    this.storageTotalMb,
    this.storageFreeMb,
    this.memoryTotalMb,
    this.memoryAvailableMb,
    this.brightnessPercent,
    this.brightnessMode,
    this.uptimeSeconds,
    this.capturedAtMs = 0,
    this.unavailable = const [],
  });

  factory DeviceSnapshot.fromMap(Map<dynamic, dynamic> map) {
    String? str(String key) {
      final v = (map[key] as String?)?.trim();
      return (v == null || v.isEmpty) ? null : v;
    }

    int? intOf(String key) => (map[key] as num?)?.toInt();
    double? doubleOf(String key) => (map[key] as num?)?.toDouble();

    return DeviceSnapshot(
      model: str('model'),
      brand: str('brand'),
      manufacturer: str('manufacturer'),
      osVersion: str('osVersion'),
      sdkInt: intOf('sdkInt'),
      network: str('network'),
      batteryLevel: intOf('batteryLevel'),
      batteryCharging: map['batteryCharging'] as bool?,
      batteryTemperatureC: doubleOf('batteryTemperatureC'),
      storageTotalMb: doubleOf('storageTotalMb'),
      storageFreeMb: doubleOf('storageFreeMb'),
      memoryTotalMb: doubleOf('memoryTotalMb'),
      memoryAvailableMb: doubleOf('memoryAvailableMb'),
      brightnessPercent: intOf('brightnessPercent'),
      brightnessMode: str('brightnessMode'),
      uptimeSeconds: intOf('uptimeSeconds'),
      capturedAtMs: intOf('capturedAtMs') ?? 0,
      unavailable:
          (map['unavailable'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }

  /// 存储已用（MB）：两端都读到才有意义，一边缺就返回 null（不做"总量-可用≈已用"的猜测，
  /// 因为读不到的那侧会被当成 0）。
  double? get storageUsedMb {
    final total = storageTotalMb;
    final free = storageFreeMb;
    if (total == null || free == null) return null;
    return total - free;
  }

  bool isMissing(String field) => unavailable.contains(field);
}
