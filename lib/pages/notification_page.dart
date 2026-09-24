import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';

class NotificationPage extends StatelessWidget {
  final bool notificationPermissionGranted;
  final bool foregroundServiceRunning;
  final int notificationCount;
  final List<Map<String, String>> activeChannels;
  final bool smsMonitorEnabled;
  final VoidCallback onStartService;
  final VoidCallback onStopService;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenPermissionSettings;
  final ValueChanged<bool> onToggleSmsMonitor;
  final VoidCallback onOpenSmsMonitorSettings;

  const NotificationPage({
    super.key,
    required this.notificationPermissionGranted,
    required this.foregroundServiceRunning,
    required this.notificationCount,
    this.activeChannels = const [],
    this.smsMonitorEnabled = true,
    required this.onStartService,
    required this.onStopService,
    required this.onRefresh,
    required this.onOpenHistory,
    required this.onOpenPermissionSettings,
    required this.onToggleSmsMonitor,
    required this.onOpenSmsMonitorSettings,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appName)),
      body: RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
          children: [
            const SizedBox(height: 40),
            Center(
              child: GestureDetector(
                onTap: foregroundServiceRunning
                    ? onStopService
                    : onStartService,
                child: Container(
                  // 冒烟测试的稳定锚点：文案不可点、图标在页内不唯一，
                  // 只有这个圆形按钮是真正的服务启停控件。
                  key: const ValueKey<String>('service-toggle'),
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: foregroundServiceRunning
                        ? AppColors.green
                        : AppColors.red,
                    boxShadow: [
                      BoxShadow(
                        color:
                            (foregroundServiceRunning
                                    ? AppColors.green
                                    : AppColors.red)
                                .withValues(alpha: 0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        foregroundServiceRunning
                            ? Icons.notifications_active
                            : Icons.notifications_off,
                        size: 48,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        foregroundServiceRunning ? l10n.running : l10n.stopped,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Center(
              child: Text(
                foregroundServiceRunning
                    ? l10n.serviceRunning
                    : l10n.serviceStopped,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
            if (foregroundServiceRunning) ...[
              const SizedBox(height: 16),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.cardBg(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.separator(context)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.router_outlined,
                          size: 14,
                          color: AppColors.blue,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          l10n.currentChannels,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.secondaryLabel(context),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (activeChannels.isNotEmpty)
                      ...activeChannels.map((c) {
                        final label = c['label'] ?? '';
                        // 三态：正常 / 异常 / 未知（没有新鲜的探测结果）。
                        // 未知既不是绿灯也不是红灯 —— 之前只有二态，webhook 与应用通道
                        // 从没探过也被算成"正常"（T01 的病灶）。
                        final isOk = (c['status'] ?? 'unknown') == 'ok';
                        final isUnknown =
                            (c['status'] ?? 'unknown') == 'unknown';
                        final statusColor = isOk
                            ? AppColors.green
                            : isUnknown
                            ? AppColors.tertiaryLabel(context)
                            : AppColors.red;
                        final statusText = isOk
                            ? l10n.statusOk
                            : isUnknown
                            ? l10n.statusUnknown
                            : l10n.statusError;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: statusColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                statusText,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: statusColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // 「类型：子类型/通道名」可能很长（自定义通道名），
                              // 原来用 Spacer + 不定宽 Text 在窄屏会溢出报错
                              Expanded(
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.end,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColors.secondaryLabel(context),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      })
                    else
                      Text(
                        l10n.noChannels,
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.tertiaryLabel(context),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            _buildSmsMonitorCard(context, l10n),
            const SizedBox(height: 40),
            _buildQuickAction(
              icon: Icons.settings,
              iconColor: AppColors.blue,
              title: l10n.permSettings,
              subtitle: l10n.permSettingsDesc,
              onTap: onOpenPermissionSettings,
              context: context,
            ),
            const SizedBox(height: 12),
            _buildQuickAction(
              icon: Icons.history,
              iconColor: AppColors.green,
              title: l10n.pushHistory,
              subtitle: l10n.recordCount(notificationCount),
              onTap: onOpenHistory,
              context: context,
            ),
          ],
        ),
      ),
    );
  }

  /// 首页"短信监听"卡片：开关直接切换总监听开关，点击卡片进入细化设置页
  Widget _buildSmsMonitorCard(BuildContext context, AppLocalizations l10n) {
    return InkWell(
      onTap: onOpenSmsMonitorSettings,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.sms_outlined,
                size: 22,
                color: AppColors.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.smsMonitor,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryLabel(context),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.smsMonitorDesc,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppColors.secondaryLabel(context),
                    ),
                  ),
                ],
              ),
            ),
            CupertinoSwitch(
              value: smsMonitorEnabled,
              onChanged: onToggleSmsMonitor,
            ),
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

  Widget _buildQuickAction({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required BuildContext context,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 22, color: iconColor),
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
                      fontWeight: FontWeight.w600,
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
