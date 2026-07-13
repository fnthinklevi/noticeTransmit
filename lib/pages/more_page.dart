import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../update_manager.dart';
import 'stats_page.dart';

class MorePage extends StatelessWidget {
  final List<Map<String, dynamic>> webhookChannels;
  final String deviceName;
  final int enabledPackagesCount;
  final int blacklistCount;
  final int whitelistCount;
  final int ruleCount;
  final bool isCheckingUpdate;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;
  final VoidCallback onOpenWebhookSettings;
  final VoidCallback onShowDeviceNameDialog;
  final VoidCallback onShowAboutDialog;
  final VoidCallback onOpenAppFilter;
  final VoidCallback onOpenKeywords;
  final VoidCallback onOpenRules;
  final VoidCallback onCheckUpdate;
  final VoidCallback onOpenPrivacyPolicy;

  const MorePage({
    super.key,
    required this.webhookChannels,
    required this.deviceName,
    required this.enabledPackagesCount,
    required this.blacklistCount,
    required this.whitelistCount,
    required this.ruleCount,
    required this.isCheckingUpdate,
    required this.themeMode,
    required this.onThemeModeChanged,
    required this.onOpenWebhookSettings,
    required this.onShowDeviceNameDialog,
    required this.onShowAboutDialog,
    required this.onOpenAppFilter,
    required this.onOpenKeywords,
    required this.onOpenRules,
    required this.onCheckUpdate,
    required this.onOpenPrivacyPolicy,
  });

  @override
  Widget build(BuildContext context) {
    final enabledCount = webhookChannels
        .where((c) => c['enabled'] == true)
        .length;
    return Scaffold(
      appBar: AppBar(title: const Text('更多')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _buildSectionHeader('外观设置', context),
          _buildGroup([_buildThemeTile(context)], context),
          const SizedBox(height: 24),
          _buildSectionHeader('推送设置', context),
          _buildGroup([
            _buildNavTile(
              icon: Icons.link,
              iconColor: const Color(0xFF007AFF),
              title: 'Webhook 推送通道',
              subtitle: webhookChannels.isEmpty
                  ? '未配置'
                  : '已配置 ${webhookChannels.length} 个 · 启用 $enabledCount 个',
              onTap: onOpenWebhookSettings,
              context: context,
            ),
            _buildDivider(context),
            _buildNavTile(
              icon: Icons.apps,
              iconColor: const Color(0xFFAF52DE),
              title: '应用筛选',
              subtitle: enabledPackagesCount > 0
                  ? '已选择 $enabledPackagesCount 个应用'
                  : '全部应用都推送',
              onTap: onOpenAppFilter,
              context: context,
            ),
            _buildDivider(context),
            _buildNavTile(
              icon: Icons.filter_list,
              iconColor: const Color(0xFFFF9500),
              title: '关键词过滤',
              subtitle: '白名单 $whitelistCount 条 · 黑名单 $blacklistCount 条',
              onTap: onOpenKeywords,
              context: context,
            ),
            _buildDivider(context),
            _buildNavTile(
              icon: Icons.rule,
              iconColor: const Color(0xFFAF52DE),
              title: '规则引擎',
              subtitle: ruleCount > 0 ? '$ruleCount 条规则' : '点击添加规则',
              onTap: onOpenRules,
              context: context,
            ),
          ], context),
          const SizedBox(height: 24),
          _buildSectionHeader('设备', context),
          _buildGroup([
            _buildNavTile(
              icon: Icons.smartphone,
              iconColor: const Color(0xFF34C759),
              title: '设备名称',
              subtitle: deviceName.isEmpty ? '未设置' : deviceName,
              onTap: onShowDeviceNameDialog,
              context: context,
            ),
            _buildDivider(context),
            _buildNavTile(
              icon: Icons.bar_chart,
              iconColor: const Color(0xFF5856D6),
              title: '推送统计',
              subtitle: '查看推送数据统计',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const StatsPage()),
              ),
              context: context,
            ),
          ], context),
          const SizedBox(height: 24),
          _buildSectionHeader('关于与更新', context),
          _buildGroup([
            _buildNavTile(
              icon: Icons.update,
              iconColor: const Color(0xFF007AFF),
              title: '检查更新',
              subtitle: isCheckingUpdate ? '正在检查...' : '点击检查新版本',
              trailing: isCheckingUpdate
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: isCheckingUpdate ? null : onCheckUpdate,
              context: context,
            ),
            _buildDivider(context),
            _buildNavTile(
              icon: Icons.privacy_tip_outlined,
              iconColor: const Color(0xFF34C759),
              title: '隐私政策',
              subtitle: '数据采集与隐私保护说明',
              onTap: onOpenPrivacyPolicy,
              context: context,
            ),
            _buildDivider(context),
            _buildNavTile(
              icon: Icons.info_outline,
              iconColor: const Color(0xFF8E8E93),
              title: '关于',
              subtitle: '版本信息、作者介绍',
              onTap: onShowAboutDialog,
              context: context,
            ),
          ], context),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'v${AppUpdateManager.instance.currentVersion} (build ${AppUpdateManager.instance.currentBuild})',
              style: TextStyle(
                color: AppColors.secondaryLabel(context),
                fontSize: 12,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
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

  Widget _buildThemeTile(BuildContext context) {
    final themeNames = {
      ThemeMode.system: '跟随系统',
      ThemeMode.light: '浅色模式',
      ThemeMode.dark: '深色模式',
    };
    final themeIcons = {
      ThemeMode.system: Icons.brightness_auto,
      ThemeMode.light: Icons.light_mode,
      ThemeMode.dark: Icons.dark_mode,
    };
    final themeIconColors = {
      ThemeMode.system: const Color(0xFF8E8E93),
      ThemeMode.light: const Color(0xFFFF9500),
      ThemeMode.dark: const Color(0xFF5856D6),
    };
    return InkWell(
      onTap: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.cardBg(context),
            title: Text(
              '深色模式',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(context),
              ),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 4),
                ...ThemeMode.values.map(
                  (mode) => ListTile(
                    onTap: () {
                      onThemeModeChanged(mode);
                      Navigator.pop(context);
                    },
                    leading: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: (themeIconColors[mode] ?? Colors.grey)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        themeIcons[mode] ?? Icons.brightness_auto,
                        color: themeIconColors[mode] ?? Colors.grey,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      themeNames[mode] ?? '',
                      style: TextStyle(color: AppColors.primaryLabel(context)),
                    ),
                    trailing: themeMode == mode
                        ? const Icon(Icons.check, color: Color(0xFF007AFF))
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                ),
              ],
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF5AC8FA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.dark_mode, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '深色模式',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: AppColors.primaryLabel(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    themeNames[themeMode] ?? '跟随系统',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: AppColors.tertiaryLabel(context),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
    required BuildContext context,
    Widget? trailing,
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
            if (trailing != null)
              trailing
            else if (onTap != null)
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
