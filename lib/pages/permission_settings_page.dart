import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import '../l10n/app_localizations.dart';
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
  final VoidCallback onAppListPermissionGranted;

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
    required this.onAppListPermissionGranted,
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
      final wasGranted = _appListPermissionGranted;
      await _permissionService.checkAllPermissions();
      if (!wasGranted && _appListPermissionGranted) {
        widget.onAppListPermissionGranted();
      }
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

  void _showAppListPermissionDialog() {
    final l10n = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.cardBg(ctx),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.apps, size: 44, color: AppColors.blue),
            const SizedBox(height: 14),
            Text(
              l10n.appListPermTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(ctx),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.appListPermMsg,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppColors.primaryLabel(ctx),
              ),
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceEvenly,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              l10n.reject,
              style: TextStyle(
                color: AppColors.secondaryLabel(ctx),
                fontSize: 15,
              ),
            ),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              widget.onRequestAppListPermission();
            },
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.blue,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(l10n.allow, style: const TextStyle(fontSize: 15)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.permSettingsTitle)),
      body: RefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _buildSectionHeader(l10n.essentialPerms, context),
            _buildGroup([
              _buildPermissionTile(
                icon: Icons.notifications_active,
                title: l10n.notifAccessPerm,
                subtitle: _notificationListenerGranted
                    ? l10n.enabled
                    : l10n.disabled,
                isOn: _notificationListenerGranted,
                onTap: _notificationListenerGranted
                    ? null
                    : widget.onRequestNotificationListenerPermission,
                context: context,
              ),
              _buildDivider(context),
              _buildPermissionTile(
                icon: Icons.notification_add,
                title: l10n.allowNotifications,
                subtitle: _postNotificationGranted
                    ? l10n.enabled
                    : l10n.disabled,
                isOn: _postNotificationGranted,
                onTap: _postNotificationGranted
                    ? null
                    : widget.onRequestPostNotificationPermission,
                context: context,
              ),
              _buildDivider(context),
              _buildPermissionTile(
                icon: Icons.battery_full,
                title: l10n.ignoreBatteryOpt,
                subtitle: _batteryOptimizationIgnored
                    ? l10n.enabled
                    : l10n.disabled,
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
              _buildSectionHeader(l10n.vendorBgSettings, context),
              _buildGroup([
                if (_isXiaomi)
                  _buildPermissionTile(
                    icon: Icons.rocket_launch,
                    title: l10n.xiaomiAutoStart,
                    subtitle: l10n.clickToSettings,
                    isOn: false,
                    onTap: widget.onRequestXiaomiAutoStart,
                    isWarning: true,
                    context: context,
                  ),
                if (_isMeizu)
                  _buildPermissionTile(
                    icon: Icons.rocket_launch,
                    title: l10n.meizuBgRun,
                    subtitle: l10n.clickToSettings,
                    isOn: false,
                    onTap: widget.onRequestMeizuBackground,
                    isWarning: true,
                    context: context,
                  ),
                if (_isHuawei)
                  _buildPermissionTile(
                    icon: Icons.rocket_launch,
                    title: l10n.huaweiProtected,
                    subtitle: l10n.clickToSettings,
                    isOn: false,
                    onTap: widget.onRequestHuaweiLaunch,
                    isWarning: true,
                    context: context,
                  ),
                if (_isOppo)
                  _buildPermissionTile(
                    icon: Icons.rocket_launch,
                    title: l10n.oppoAutoStart,
                    subtitle: l10n.clickToSettings,
                    isOn: false,
                    onTap: widget.onRequestOppoBackground,
                    isWarning: true,
                    context: context,
                  ),
                if (_isVivo)
                  _buildPermissionTile(
                    icon: Icons.rocket_launch,
                    title: l10n.vivoBgStart,
                    subtitle: l10n.clickToSettings,
                    isOn: false,
                    onTap: widget.onRequestVivoBackground,
                    isWarning: true,
                    context: context,
                  ),
                if (_isSamsung)
                  _buildPermissionTile(
                    icon: Icons.info_outline,
                    title: l10n.samsungSettings,
                    subtitle: l10n.samsungSmartManagerDesc,
                    isOn: false,
                    onTap: null,
                    isWarning: true,
                    context: context,
                  ),
                if (_isStockAndroid)
                  _buildPermissionTile(
                    icon: Icons.info_outline,
                    title: l10n.nativeAndroid,
                    subtitle: l10n.nativeBatteryOptDesc,
                    isOn: false,
                    onTap: null,
                    isWarning: true,
                    context: context,
                  ),
              ], context),
              const SizedBox(height: 24),
            ],
            _buildSectionHeader(l10n.optionalPerms, context),
            _buildGroup([
              _buildPermissionTile(
                icon: Icons.message,
                title: l10n.smsPerm,
                subtitle: _smsPermissionGranted ? l10n.enabled : l10n.disabled,
                isOn: _smsPermissionGranted,
                onTap: _smsPermissionGranted
                    ? null
                    : widget.onRequestSmsPermission,
                context: context,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(52, 0, 16, 12),
                child: Text(
                  l10n.smsPermDesc,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ),
              _buildDivider(context),
              _buildPermissionTile(
                icon: Icons.call,
                title: l10n.phonePerm,
                subtitle: _phonePermissionGranted
                    ? l10n.enabled
                    : l10n.disabled,
                isOn: _phonePermissionGranted,
                onTap: _phonePermissionGranted
                    ? null
                    : widget.onRequestPhonePermission,
                context: context,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(52, 0, 16, 12),
                child: Text(
                  l10n.phonePermDesc,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ),
              _buildDivider(context),
              _buildPermissionTile(
                icon: Icons.apps,
                title: l10n.appListPerm,
                subtitle: _appListPermissionGranted
                    ? l10n.enabled
                    : l10n.disabled,
                isOn: _appListPermissionGranted,
                onTap: _appListPermissionGranted
                    ? null
                    : _showAppListPermissionDialog,
                context: context,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(52, 0, 16, 12),
                child: Text(
                  l10n.appListPermExtra,
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
                l10n.appListPermDesc,
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
