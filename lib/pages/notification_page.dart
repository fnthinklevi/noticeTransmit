import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class NotificationPage extends StatelessWidget {
  final bool notificationPermissionGranted;
  final bool foregroundServiceRunning;
  final int notificationCount;
  final VoidCallback onStartService;
  final VoidCallback onStopService;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenPermissionSettings;

  const NotificationPage({
    super.key,
    required this.notificationPermissionGranted,
    required this.foregroundServiceRunning,
    required this.notificationCount,
    required this.onStartService,
    required this.onStopService,
    required this.onRefresh,
    required this.onOpenHistory,
    required this.onOpenPermissionSettings,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('通知推送助手')),
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
                        foregroundServiceRunning ? '运行中' : '已停止',
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
                    ? '通知监听服务正在运行，点击可停止'
                    : '通知监听服务未启动，点击可启动',
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
            ),
            const SizedBox(height: 40),
            _buildQuickAction(
              icon: Icons.settings,
              iconColor: AppColors.blue,
              title: '权限设置',
              subtitle: '配置通知、电池、后台运行等权限',
              onTap: onOpenPermissionSettings,
              context: context,
            ),
            const SizedBox(height: 12),
            _buildQuickAction(
              icon: Icons.history,
              iconColor: AppColors.green,
              title: '推送历史',
              subtitle: '共 $notificationCount 条记录',
              onTap: onOpenHistory,
              context: context,
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
