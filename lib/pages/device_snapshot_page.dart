import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../l10n/app_localizations.dart';
import '../models/device_snapshot.dart';
import '../services/device_info_service.dart';
import '../services/notification_service.dart';
import '../theme/app_colors.dart';

/// 设备状态页（T18）：T17 那份 `getDeviceSnapshot` 的第一个消费方。
///
/// 一次读取、十一项状态。数值**不做 0 兜底** —— 原生把"读不到"表达成缺字段 +
/// `unavailable` 名单，这里就按名单显示「这台设备读不到」。把未知画成 0 会把
/// "存储读不到"显示成"已用满"，那是把猜测端上界面。
///
/// 「推送设备信息」不自建推送链路：先落一条历史记录，再交给原生 `pushRecordNow`，
/// 走哪条通道、主备怎么切都由原生那一份路由决定（T12）。
class DeviceSnapshotPage extends StatefulWidget {
  const DeviceSnapshotPage({super.key});

  @override
  State<DeviceSnapshotPage> createState() => _DeviceSnapshotPageState();
}

class _DeviceSnapshotPageState extends State<DeviceSnapshotPage> {
  final DeviceInfoService _device = GetIt.instance<DeviceInfoService>();

  DeviceSnapshot? _snapshot;
  bool _loading = true;
  bool _pushing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final snap = await _device.getDeviceSnapshot();
    if (!mounted) return;
    setState(() {
      _snapshot = snap;
      _loading = false;
    });
  }

  Future<void> _push() async {
    final snap = _snapshot;
    if (snap == null || _pushing) return;
    final l10n = AppLocalizations.of(context);
    setState(() => _pushing = true);
    await GetIt.instance<NotificationService>().pushSynthesizedRecord(
      title: l10n.deviceStatusEntry,
      content: _summary(snap, l10n),
      deviceName: _device.deviceName,
    );
    if (!mounted) return;
    setState(() => _pushing = false);
    // 只说"已交给通道"：送达结果要等原生回传，此刻任何"成功/失败"的说法都是猜。
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.pushDeviceInfoSent)));
  }

  /// 一行一项：`(字段名, 标签, 取值)`。字段名必须与原生 `DeviceSnapshot.KEY_*` 逐字一致 ——
  /// 不一致时"读不到"永远不显示，界面会把缺字段当成空字符串。
  List<(String, String, String?)> _rows(
    DeviceSnapshot s,
    AppLocalizations l10n,
  ) {
    return [
      ('model', l10n.snapshotModel, s.model),
      ('brand', l10n.snapshotBrand, s.brand),
      ('manufacturer', l10n.snapshotManufacturer, s.manufacturer),
      (
        'osVersion',
        l10n.snapshotSystemVersion,
        s.osVersion == null
            ? null
            : (s.sdkInt == null
                  ? 'Android ${s.osVersion}'
                  : l10n.snapshotSystemVersionValue(s.osVersion!, s.sdkInt!)),
      ),
      ('network', l10n.snapshotNetwork, _networkLabel(s.network, l10n)),
      (
        'batteryLevel',
        l10n.snapshotBattery,
        s.batteryLevel == null
            ? null
            : l10n.snapshotBatteryValue(
                s.batteryLevel!,
                s.batteryCharging == null
                    ? l10n.unreadableField
                    : (s.batteryCharging!
                          ? l10n.batteryChargingState
                          : l10n.batteryDischargingState),
              ),
      ),
      (
        'batteryTemperatureC',
        l10n.snapshotBatteryTemp,
        s.batteryTemperatureC == null
            ? null
            : l10n.snapshotBatteryTempValue(
                s.batteryTemperatureC!.toStringAsFixed(1),
              ),
      ),
      (
        'storageTotalMb',
        l10n.snapshotStorage,
        s.storageUsedMb == null || s.storageTotalMb == null
            ? null
            : l10n.snapshotStorageValue(
                _gb(s.storageUsedMb!),
                _gb(s.storageTotalMb!),
              ),
      ),
      (
        'memoryAvailableMb',
        l10n.snapshotMemory,
        s.memoryAvailableMb == null || s.memoryTotalMb == null
            ? null
            : l10n.snapshotMemoryValue(
                _gb(s.memoryAvailableMb!),
                _gb(s.memoryTotalMb!),
              ),
      ),
      (
        'brightnessPercent',
        l10n.snapshotBrightness,
        s.brightnessPercent == null
            ? null
            : l10n.snapshotBrightnessValue(
                s.brightnessPercent!,
                switch (s.brightnessMode) {
                  'auto' => l10n.brightnessModeAuto,
                  'manual' => l10n.brightnessModeManual,
                  // 模式缺字段只影响括号里那半句，阈值读数本身是有的
                  _ => l10n.unreadableField,
                },
              ),
      ),
      (
        'uptimeSeconds',
        l10n.snapshotUptime,
        s.uptimeSeconds == null
            ? null
            : l10n.snapshotUptimeValue(
                s.uptimeSeconds! ~/ 86400,
                (s.uptimeSeconds! % 86400) ~/ 3600,
                (s.uptimeSeconds! % 3600) ~/ 60,
              ),
      ),
    ];
  }

  String _summary(DeviceSnapshot s, AppLocalizations l10n) {
    final unreadable = l10n.unreadableField;
    return _rows(
      s,
      l10n,
    ).map((r) => '${r.$2}: ${r.$3 ?? unreadable}').join('\n');
  }

  static String _gb(double mb) => (mb / 1024).toStringAsFixed(1);

  static String? _networkLabel(String? type, AppLocalizations l10n) =>
      switch (type) {
        'wifi' => l10n.netWifi,
        'cellular' => l10n.netCellular,
        'vpn' => l10n.netVpn,
        'ethernet' => l10n.netEthernet,
        'none' => l10n.netNone,
        // 未知枚举原样显示：宁可看见生词，也不要把它翻译成"其他"再让人以为已经归类
        'other' || null => type == null ? null : l10n.netOther,
        _ => type,
      };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final snap = _snapshot;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.deviceStatusEntry),
        actions: [
          IconButton(
            key: const ValueKey('device-status-refresh'),
            icon: const Icon(Icons.refresh),
            tooltip: l10n.deviceStatusRefresh,
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            l10n.deviceStatusDesc,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.secondaryLabel(context),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (snap == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  l10n.deviceStatusSnapshotFailed,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ),
            )
          else ...[
            Container(
              key: const ValueKey('device-status-rows'),
              decoration: BoxDecoration(
                color: AppColors.cardBg(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.separator(context)),
              ),
              child: Column(
                children: [
                  for (final (index, row) in _rows(snap, l10n).indexed) ...[
                    if (index > 0)
                      Container(
                        height: 0.5,
                        color: AppColors.separator(context),
                      ),
                    _row(l10n, row.$2, row.$3 ?? l10n.unreadableField),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                l10n.snapshotCapturedAt(_formatTime(snap.capturedAtMs)),
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.pushDeviceInfoDesc,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.secondaryLabel(context),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              key: const ValueKey('device-status-push'),
              icon: const Icon(Icons.send_outlined),
              label: Text(
                _pushing ? l10n.pushDeviceInfoBusy : l10n.pushDeviceInfo,
              ),
              onPressed: _pushing ? null : _push,
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(AppLocalizations l10n, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 14))),
        ],
      ),
    );
  }
}

String _formatTime(int ms) {
  if (ms <= 0) return '—';
  final t = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
}
