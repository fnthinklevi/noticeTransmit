import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/home_service_status.dart';
import '../theme/app_colors.dart';
import '../widgets/channel_health_badge.dart';
import '../widgets/pull_to_refresh_list.dart';

class NotificationPage extends StatelessWidget {
  final bool notificationPermissionGranted;
  final bool foregroundServiceRunning;

  /// 推送开关（原生 `push_active`），null = 没读到。与上面那一个是**两件事**：
  /// 监听可以开着而发送被用户从通知栏/桌面小部件单独暂停 —— 那种时刻这一格既不是
  /// "运行中"（说了像一切照旧）也不是"已停止"（监听明明在跑），所以有第三态。
  final bool? pushActive;
  final int notificationCount;
  final List<Map<String, String>> activeChannels;
  final bool smsMonitorEnabled;
  final VoidCallback onStartService;
  final VoidCallback onStopService;

  /// 暂停态下点那一圈要做的**唯一**一件事：把发送打开（不停监听、不重启监听）。
  final VoidCallback onResumePush;
  final Future<void> Function() onRefresh;
  final VoidCallback onOpenHistory;
  final VoidCallback onOpenPermissionSettings;
  final VoidCallback onOpenChannelStatus;
  final ValueChanged<bool> onToggleSmsMonitor;
  final VoidCallback onOpenSmsMonitorSettings;

  /// 首页「幻念收件」入口卡：未读数由外层注入，**页面不数**（数法只有一处，
  /// `FnthinkInboxService.unreadCount`）。这一格与历史页收件档、详情里那个点必须是同一个数，
  /// 否则表现是"首页说还有 3 条，点进去只有 2 条"。
  final int fnthinkInboxUnread;

  /// 这一格的去处（打开历史页的收件档）。没接上时**整格不画** —— 见 build 里那段注释。
  final VoidCallback? onOpenInbox;

  const NotificationPage({
    super.key,
    required this.notificationPermissionGranted,
    required this.foregroundServiceRunning,
    required this.pushActive,
    required this.notificationCount,
    this.activeChannels = const [],
    this.smsMonitorEnabled = false,
    required this.onStartService,
    required this.onStopService,
    required this.onResumePush,
    required this.onRefresh,
    required this.onOpenHistory,
    required this.onOpenPermissionSettings,
    required this.onOpenChannelStatus,
    required this.onToggleSmsMonitor,
    required this.onOpenSmsMonitorSettings,
    this.fnthinkInboxUnread = 0,
    this.onOpenInbox,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 三态判定只有一处作者（`homeServiceTone`）：颜色、那句话、点下去做什么，
    // 三样都必须从同一个结论派生 —— 各判一次就会出现"圈是橙的、点它却停了监听"。
    final tone = homeServiceTone(
      listening: foregroundServiceRunning,
      pushActive: pushActive,
    );
    final toneColor = switch (tone) {
      HomeServiceTone.listening => AppColors.green,
      HomeServiceTone.paused => AppColors.orange,
      HomeServiceTone.stopped => AppColors.red,
    };
    final toneIcon = switch (tone) {
      HomeServiceTone.listening => Icons.notifications_active,
      // 监听在跑、发送被暂停 —— Material 这枚图标画的正是"铃铛在、斜杠拦着"。
      HomeServiceTone.paused => Icons.notifications_paused,
      HomeServiceTone.stopped => Icons.notifications_off,
    };
    final toneLabel = switch (tone) {
      HomeServiceTone.listening => l10n.running,
      HomeServiceTone.paused => l10n.pushPausedShort,
      HomeServiceTone.stopped => l10n.stopped,
    };
    final toneHint = switch (tone) {
      HomeServiceTone.listening => l10n.serviceRunning,
      HomeServiceTone.paused => l10n.servicePausedWhileListening,
      HomeServiceTone.stopped => l10n.serviceStopped,
    };
    final toneTap = switch (tone) {
      // ⚠ 暂停态那一下是"恢复推送"，**不是**"停止监听"：用户此刻要的是把发送打开，
      //   而监听正在跑。把这两件事混在一起，症状是"我只是想恢复推送，通知却整台不再读了"。
      HomeServiceTone.paused => onResumePush,
      HomeServiceTone.listening => onStopService,
      HomeServiceTone.stopped => onStartService,
    };
    return Scaffold(
      // 顶栏只留标题。曾经有过三格（T43 `fd4fce7`：设置／推送历史／添加设备），
      // 2026-10-06 维护者判为多此一举并删掉 —— 三格的目标都另有路：设置＝底部「更多」，
      // 历史＝本页那张卡，配对名单＝幻念推送页与通知引擎页各有一处。
      appBar: AppBar(title: Text(l10n.appName)),
      body: PullToRefreshList(
        onRefresh: onRefresh,
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        children: [
          const SizedBox(height: 40),
          Center(
            child: GestureDetector(
              onTap: toneTap,
              child: Container(
                // 冒烟测试的稳定锚点：文案不可点、图标在页内不唯一，
                // 只有这个圆形按钮是真正的服务启停控件。
                key: const ValueKey<String>('service-toggle'),
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: toneColor,
                  boxShadow: [
                    BoxShadow(
                      color: toneColor.withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(toneIcon, size: 48, color: Colors.white),
                    const SizedBox(height: 8),
                    Text(
                      toneLabel,
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
              toneHint,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.secondaryLabel(context),
              ),
            ),
          ),
          // 通道卡**常驻**（不再只在监听运行时才显示）：
          // 「配了哪些通道、最近探到过不通」与"服务此刻在不在跑"是两件事，
          // 服务停着的时候反而更需要看到这两行；入口也才稳定可点。
          const SizedBox(height: 16),
          // 整张卡可点 → 通道状态页（T10）。卡片本身只做"有几条、大致怎样"，
          // 明细与主备设置都在那一页；不铺开的理由是首页要留给监听状态与快捷入口。
          InkWell(
            onTap: onOpenChannelStatus,
            borderRadius: BorderRadius.circular(12),
            child: Container(
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
                      const Spacer(),
                      Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: AppColors.tertiaryLabel(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (activeChannels.isNotEmpty)
                    ...activeChannels.map((c) {
                      final label = c['label'] ?? '';
                      // 四态（T115 决定一）：正常 / 异常 / 过期 / 未知。
                      // 未知既不是绿灯也不是红灯 —— 之前只有二态，webhook 与应用通道
                      // 从没探过也被算成"正常"（T01 的病灶）。
                      // `stale` 敢说"正常"的唯一前提是**同一行就写着上次探测于何时**；
                      // 时间来自条目带进来的 `probedAt`，拿不出时间就退回未知 ——
                      // 只说正常、不带上次时间正是那句禁令要防的半句谎。
                      // （判定本身在 `channelHealthStateForDisplay`，页面不重判。）
                      final rawStatus = c['status'] ?? 'unknown';
                      final ageText = rawStatus == 'stale'
                          ? channelHealthAgoLabel(
                              l10n,
                              int.tryParse(c['probedAt'] ?? ''),
                            )
                          : null;
                      final isStale = rawStatus == 'stale' && ageText != null;
                      final isOk = rawStatus == 'ok' || isStale;
                      final isError = rawStatus == 'error';
                      final isUnknown = !isOk && !isError;
                      final statusColor = isOk
                          ? AppColors.green
                          : isUnknown
                          ? AppColors.tertiaryLabel(context)
                          : AppColors.red;
                      final statusText = isStale
                          ? '${l10n.statusOk} · $ageText'
                          : isOk
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
                            // Flexible：过期那一档把这枚文字加长了（「状态正常 · 3 天前探测」），
                            // 右边的标签是 Expanded —— 放不下时先让这里收缩，而不是把行撑破。
                            Flexible(
                              child: Text(
                                statusText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: statusColor,
                                ),
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
          ),
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
          // 「幻念收件」这一格**只在有货的时候出现**：这台从没接收过、或都读完了，首页就不该多出
          // 一格跟他无关的入口（"新功能不许改变用户看到的默认界面"那条不变量）。读完了想再翻收件档，
          // 走「推送历史」那一格切过去 —— 门一直开着，这一格只是短的那条路。
          // 出口没接上时同样不画：画一个点不动的入口比不画更糟（与幻念推送页那条"死路按钮"同族）。
          if (onOpenInbox != null && fnthinkInboxUnread > 0) ...[
            const SizedBox(height: 12),
            _buildQuickAction(
              icon: Icons.mark_email_unread_outlined,
              iconColor: AppColors.purple,
              title: l10n.fnthinkInboxEntry,
              subtitle: l10n.fnthinkInboxUnread(fnthinkInboxUnread),
              onTap: onOpenInbox!,
              context: context,
            ),
          ],
        ],
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
