import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../services/permission_service.dart';
import '../theme/app_colors.dart';

class PermissionSettingsPage extends StatefulWidget {
  final bool notificationListenerGranted;
  final bool postNotificationGranted;
  final bool batteryOptimizationIgnored;
  final bool smsPermissionGranted;
  final bool phonePermissionGranted;
  final bool appListPermissionGranted;
  final String manufacturer;
  final Future<void> Function() onRefresh;
  final VoidCallback onRequestNotificationListenerPermission;
  final VoidCallback onRequestPostNotificationPermission;
  final VoidCallback onRequestBatteryOptimization;
  final VoidCallback onRequestXiaomiAutoStart;
  final VoidCallback onRequestMeizuBackground;
  final VoidCallback onRequestHuaweiLaunch;
  final VoidCallback onRequestOppoBackground;
  final VoidCallback onRequestVivoBackground;
  final VoidCallback onRequestSmsPermission;
  final VoidCallback onRequestPhonePermission;
  final VoidCallback onRequestAppListPermission;

  const PermissionSettingsPage({
    super.key,
    required this.notificationListenerGranted,
    required this.postNotificationGranted,
    required this.batteryOptimizationIgnored,
    required this.smsPermissionGranted,
    required this.phonePermissionGranted,
    required this.appListPermissionGranted,
    required this.manufacturer,
    required this.onRefresh,
    required this.onRequestNotificationListenerPermission,
    required this.onRequestPostNotificationPermission,
    required this.onRequestBatteryOptimization,
    required this.onRequestXiaomiAutoStart,
    required this.onRequestMeizuBackground,
    required this.onRequestHuaweiLaunch,
    required this.onRequestOppoBackground,
    required this.onRequestVivoBackground,
    required this.onRequestSmsPermission,
    required this.onRequestPhonePermission,
    required this.onRequestAppListPermission,
  });

  @override
  State<PermissionSettingsPage> createState() => _PermissionSettingsPageState();
}

class _PermissionSettingsPageState extends State<PermissionSettingsPage>
    with WidgetsBindingObserver {
  final PermissionService _permissionService =
      GetIt.instance<PermissionService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    if (state == AppLifecycleState.resumed) {
      await _permissionService.checkAllPermissions();
      if (mounted) setState(() {});
    }
  }

  bool get _notificationListenerGranted =>
      _permissionService.notificationListenerGranted;
  bool get _postNotificationGranted =>
      _permissionService.postNotificationGranted;
  bool get _batteryOptimizationIgnored =>
      _permissionService.batteryOptimizationIgnored;
  bool get _smsPermissionGranted => _permissionService.smsGranted;
  bool get _phonePermissionGranted => _permissionService.phoneGranted;
  bool get _appListPermissionGranted => _permissionService.appListGranted;
  bool get _isXiaomi =>
      widget.manufacturer.toLowerCase().contains('xiaomi') ||
      widget.manufacturer.toLowerCase().contains('redmi') ||
      widget.manufacturer.toLowerCase().contains('mi ');

  bool get _isMeizu => widget.manufacturer.toLowerCase().contains('meizu');

  bool get _isHuawei =>
      widget.manufacturer.toLowerCase().contains('huawei') ||
      widget.manufacturer.toLowerCase().contains('honor');

  bool get _isOppo =>
      widget.manufacturer.toLowerCase().contains('oppo') ||
      widget.manufacturer.toLowerCase().contains('realme') ||
      widget.manufacturer.toLowerCase().contains('oneplus');

  bool get _isVivo =>
      widget.manufacturer.toLowerCase().contains('vivo') ||
      widget.manufacturer.toLowerCase().contains('iqoo');

  bool get _isSamsung => widget.manufacturer.toLowerCase().contains('samsung');

  bool get _isStockAndroid =>
      widget.manufacturer.toLowerCase().contains('google') ||
      widget.manufacturer.toLowerCase().contains('android') ||
      !_isXiaomi &&
          !_isMeizu &&
          !_isHuawei &&
          !_isOppo &&
          !_isVivo &&
          !_isSamsung;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('权限设置')),
      body: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _buildSectionHeader('必要权限', context),
            _buildGroup([
              _buildPermissionTile(
                icon: Icons.notifications_active,
                title: '通知访问权限',
                subtitle: _notificationListenerGranted ? '已开启' : '未开启',
                isOn: _notificationListenerGranted,
                onTap: _notificationListenerGranted
                    ? null
                    : widget.onRequestNotificationListenerPermission,
                context: context,
              ),
              _buildDivider(context),
              _buildPermissionTile(
                icon: Icons.notification_add,
                title: '允许通知',
                subtitle: _postNotificationGranted ? '已开启' : '未开启',
                isOn: _postNotificationGranted,
                onTap: _postNotificationGranted
                    ? null
                    : widget.onRequestPostNotificationPermission,
                context: context,
              ),
              _buildDivider(context),
              _buildPermissionTile(
                icon: Icons.battery_full,
                title: '忽略电池优化',
                subtitle: _batteryOptimizationIgnored ? '已开启' : '未开启',
                isOn: _batteryOptimizationIgnored,
                onTap: _batteryOptimizationIgnored
                    ? null
                    : widget.onRequestBatteryOptimization,
                context: context,
              ),
            ], context),
            const SizedBox(height: 24),
            if (_isXiaomi ||
                _isMeizu ||
                _isHuawei ||
                _isOppo ||
                _isVivo ||
                _isSamsung ||
                _isStockAndroid) ...[
              _buildSectionHeader('厂商后台设置', context),
              _buildGroup([
                if (_isXiaomi)
                  _buildPermissionTile(
                    icon: Icons.rocket_launch,
                    title: '小米自启动',
                    subtitle: '点击前往设置',
                    isOn: false,
                    onTap: widget.onRequestXiaomiAutoStart,
                    isWarning: true,
                    context: context,
                  ),
                if (_isMeizu)
                  _buildPermissionTile(
                    icon: Icons.rocket_launch,
                    title: '魅族后台运行',
                    subtitle: '点击前往设置',
                    isOn: false,
                    onTap: widget.onRequestMeizuBackground,
                    isWarning: true,
                    context: context,
                  ),
                if (_isHuawei)
                  _buildPermissionTile(
                    icon: Icons.rocket_launch,
                    title: '华为自启动/受保护应用',
                    subtitle: '点击前往设置',
                    isOn: false,
                    onTap: widget.onRequestHuaweiLaunch,
                    isWarning: true,
                    context: context,
                  ),
                if (_isOppo)
                  _buildPermissionTile(
                    icon: Icons.rocket_launch,
                    title: 'OPPO自启动管理',
                    subtitle: '点击前往设置',
                    isOn: false,
                    onTap: widget.onRequestOppoBackground,
                    isWarning: true,
                    context: context,
                  ),
                if (_isVivo)
                  _buildPermissionTile(
                    icon: Icons.rocket_launch,
                    title: 'vivo后台启动管理',
                    subtitle: '点击前往设置',
                    isOn: false,
                    onTap: widget.onRequestVivoBackground,
                    isWarning: true,
                    context: context,
                  ),
                if (_isSamsung)
                  _buildPermissionTile(
                    icon: Icons.info_outline,
                    title: '三星设备设置',
                    subtitle: '请在智能管理器中将本应用加入自启动白名单',
                    isOn: false,
                    onTap: null,
                    isWarning: true,
                    context: context,
                  ),
                if (_isStockAndroid)
                  _buildPermissionTile(
                    icon: Icons.info_outline,
                    title: '原生Android设置',
                    subtitle: '请在系统设置中确认电池优化已关闭',
                    isOn: false,
                    onTap: null,
                    isWarning: true,
                    context: context,
                  ),
              ], context),
              const SizedBox(height: 24),
            ],
            _buildSectionHeader('非必要权限', context),
            _buildGroup([
              _buildPermissionTile(
                icon: Icons.message,
                title: '短信权限',
                subtitle: _smsPermissionGranted ? '已开启' : '未开启',
                isOn: _smsPermissionGranted,
                onTap: _smsPermissionGranted
                    ? null
                    : widget.onRequestSmsPermission,
                context: context,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(52, 0, 16, 12),
                child: Text(
                  '用于获取短信发送者号码和内容，实现短信通知推送功能',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ),
              _buildDivider(context),
              _buildPermissionTile(
                icon: Icons.call,
                title: '电话权限',
                subtitle: _phonePermissionGranted ? '已开启' : '未开启',
                isOn: _phonePermissionGranted,
                onTap: _phonePermissionGranted
                    ? null
                    : widget.onRequestPhonePermission,
                context: context,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(52, 0, 16, 12),
                child: Text(
                  '用于获取来电号码和通话状态，实现来电通知推送功能',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ),
              _buildDivider(context),
              _buildPermissionTile(
                icon: Icons.apps,
                title: '应用列表权限',
                subtitle: _appListPermissionGranted ? '已开启' : '未开启',
                isOn: _appListPermissionGranted,
                onTap: _appListPermissionGranted
                    ? null
                    : widget.onRequestAppListPermission,
                context: context,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(52, 0, 16, 12),
                child: Text(
                  '用于获取已安装应用列表，支持按应用过滤通知功能',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ),
            ], context),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                '非必要权限用于提升特定功能的准确性，不开启不影响核心功能使用',
                style: TextStyle(
                  color: AppColors.secondaryLabel(context),
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppColors.secondaryLabel(context),
        ),
      ),
    );
  }

  Widget _buildGroup(List<Widget> children, BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }

  Widget _buildDivider(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 52),
      child: Divider(
        height: 0.5,
        thickness: 0.5,
        color: AppColors.separator(context),
      ),
    );
  }

  Widget _buildPermissionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isOn,
    required VoidCallback? onTap,
    required BuildContext context,
    bool isWarning = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: isOn
                    ? AppColors.green
                    : isWarning
                    ? const Color(0xFFFF9500)
                    : AppColors.blue,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      color: AppColors.primaryLabel(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.tertiaryLabel(context),
              ),
          ],
        ),
      ),
    );
  }
}
