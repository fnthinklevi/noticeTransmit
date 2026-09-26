import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../l10n/app_localizations.dart';
import '../services/battery_service.dart';
import '../services/device_state_service.dart';
import '../services/temperature_service.dart';
import '../theme/app_colors.dart';
import 'battery_page.dart';
import 'device_state_page.dart';
import 'temperature_page.dart';

/// 「通知引擎」tab 的骨架页（T15）。
///
/// 这一格管的是**设备侧触发**的告警：电量、温度。与「更多 → 规则约束」不是一回事 ——
/// 那边判"这条已到达的通知要不要转"，这边判"设备自己到了某个状态要不要提醒"。
/// 二分口径来自 roadmap §3，把两件事放进同一个列表会让人以为规则约束也能配温度阈值。
///
/// 入口只放**今天真的能用**的两个：
/// - 设备状态（T17 快照 + T18 详情页）还没建，不放占位行 —— 点了没反应的行比没有这行更糟；
/// - 「幻念收件」跳转同理，等 T42/T59 落地再加（本 tab 只放跳转，配置入口按 T42 归「更多」）。
///
/// 两条入口的目标页都**订阅各自的服务**（T16 立的先例），所以本页不往下传回调：
/// 传了就会有第三份"父页接线"，而父页 rebuild 根本到不了被 push 出去的子页。
class NotificationEnginePage extends StatefulWidget {
  const NotificationEnginePage({super.key});

  @override
  State<NotificationEnginePage> createState() => _NotificationEnginePageState();
}

class _NotificationEnginePageState extends State<NotificationEnginePage> {
  final BatteryService _battery = GetIt.instance<BatteryService>();
  final TemperatureService _temperature = GetIt.instance<TemperatureService>();
  final DeviceStateService _deviceState = GetIt.instance<DeviceStateService>();

  @override
  void initState() {
    super.initState();
    _battery.addListener(_onServiceChanged);
    _temperature.addListener(_onServiceChanged);
    _deviceState.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    // 三个服务都是 GetIt 里的长生命周期单例：只摘监听，不 dispose
    _battery.removeListener(_onServiceChanged);
    _temperature.removeListener(_onServiceChanged);
    _deviceState.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  /// 副标题 = 启用中的规则数；开关关了就把「已暂停」带上 ——
  /// 规则还在但一条都不会推，只报数字会让人以为"配了就会响"。
  String _summary(
    AppLocalizations l10n,
    List<Map<String, dynamic>> rules,
    bool paused,
  ) {
    final count = rules.where((r) => r['enabled'] == true).length;
    final base = count == 0 ? l10n.ruleEmpty : l10n.ruleCount(count);
    return paused ? '$base · ${l10n.pushPausedByUser}' : base;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notificationEngineTitle)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          Text(
            l10n.notificationEngineDesc,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.secondaryLabel(context),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.separator(context)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _entry(
                  key: const ValueKey('engine-battery'),
                  icon: Icons.battery_std,
                  iconColor: AppColors.green,
                  title: l10n.engineBatteryEntry,
                  subtitle: _summary(
                    l10n,
                    _battery.rules,
                    !_battery.notifyEnabled,
                  ),
                  page: const BatteryPage(),
                ),
                _divider(),
                _entry(
                  key: const ValueKey('engine-temperature'),
                  icon: Icons.thermostat,
                  iconColor: AppColors.red,
                  title: l10n.engineTemperatureEntry,
                  subtitle: _summary(
                    l10n,
                    _temperature.rules,
                    !_temperature.notifyEnabled,
                  ),
                  page: const TemperaturePage(),
                ),
                _divider(),
                // T24：亮度与网络（同一族 device_state，引擎按 type 路由）
                _entry(
                  key: const ValueKey('engine-device-state'),
                  icon: Icons.brightness_medium,
                  iconColor: AppColors.orange,
                  title: l10n.deviceStateEntry,
                  subtitle: _summary(
                    l10n,
                    _deviceState.rules,
                    !_deviceState.notifyEnabled,
                  ),
                  page: const DeviceStatePage(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _constraintCard(l10n),
        ],
      ),
    );
  }

  /// T23：设备态告警要不要也过一遍关键词约束。
  ///
  /// 放在这一页而不是电量页/温度页各一枚：它一次作用于**两族**，两处开关迟早会出现
  /// 一个开一个关，而"设备态告警受不受约束"不可能同时有两个答案。
  /// 描述文案里明写了"应用黑白名单不适用"—— 这类告警是本机自己产生的，
  /// 让它受"只转发这些应用"管辖只会得到"配了白名单之后电量告警永远不来"。
  Widget _constraintCard(AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.separator(context)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.engineConstraintEntry,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.engineConstraintDesc,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          CupertinoSwitch(
            key: const ValueKey('engine-device-constraint'),
            value: _battery.deviceAlertsRespectConstraints,
            onChanged: (v) => _battery.saveDeviceAlertsRespectConstraints(v),
          ),
        ],
      ),
    );
  }

  /// 与「更多」页入口行同一形状（InkWell + 色块图标 + 标题/副标题 + 左缩进分隔线）。
  ///
  /// ⚠ 不用 `ListTile`：它把水波纹画在**最近的 Material** 上，放进带底色的 Container 里
  /// 会被那层背景盖住，Flutter 直接断言报错（MorePage 正因如此用 InkWell）。
  /// MorePage 的 `_buildNavTile` 是私有方法，抽成共用组件是 T05 的活。
  Widget _entry({
    required Key key,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Widget page,
  }) {
    return InkWell(
      key: key,
      onTap: () =>
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: iconColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: AppColors.tertiaryLabel(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _divider() {
    return Padding(
      padding: const EdgeInsets.only(left: 52),
      child: Divider(
        height: 0.5,
        thickness: 0.5,
        color: AppColors.separator(context),
      ),
    );
  }
}
