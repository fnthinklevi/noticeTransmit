import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../theme/app_colors.dart';

/// T246 排查卡的读数快照。
///
/// [batteryExempt] = 电池优化白名单（deviceidle 豁免）状态——官方语义：白名单内的
/// 应用在 Doze 期间可继续使用网络并持有 partial wake lock；未豁免的应用深睡下
/// 网络被挂起（PRD §2 引用 developer.android.com 原文）。
/// [failureCount] = 近 24 小时**全部**推送失败次数（送达日志口径，不区分失败种类）。
class LockscreenDiagnosticData {
  const LockscreenDiagnosticData({
    required this.batteryExempt,
    required this.failureCount,
    this.latestFailureAt,
  });

  final bool batteryExempt;
  final int failureCount;
  final DateTime? latestFailureAt;
}

/// T246：「锁屏后推送失败？」自助排查卡（通道状态页）。
///
/// 三个事实一块说完：豁免状态（未豁免给一键申请入口）、近 24h 失败计数、
/// 一段**与官方文档严格一致**的解释（用户对误导性文案零容忍——这里的每一句
/// 都能对应到 developer.android.com 的 Doze/豁免原文，见 PRD §2）。
/// 数据由调用方注入（[data] + [onRequestExempt]），本组件不做 IO——
/// widget 用例才能把"豁免/未豁免、有失败/无失败"四种形状都钉住。
class LockscreenDiagnosticCard extends StatelessWidget {
  const LockscreenDiagnosticCard({
    required this.data,
    required this.onRequestExempt,
    super.key,
  });

  final LockscreenDiagnosticData data;
  final VoidCallback onRequestExempt;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: AppColors.blue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline, size: 16, color: AppColors.blue),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  l10n.lockscreenDiagTitle,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  data.batteryExempt
                      ? l10n.lockscreenDiagExemptOk
                      : l10n.lockscreenDiagExemptMissing,
                  style: TextStyle(
                    fontSize: 13,
                    color: data.batteryExempt
                        ? AppColors.systemGreen(context)
                        : AppColors.primaryLabel(context),
                  ),
                ),
              ),
              if (!data.batteryExempt)
                TextButton(
                  key: const ValueKey('lockscreen-diag-go-settings'),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    minimumSize: const Size(0, 32),
                  ),
                  onPressed: onRequestExempt,
                  child: Text(l10n.lockscreenDiagGoSettings),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            data.failureCount > 0
                ? (data.latestFailureAt == null
                      ? l10n.lockscreenDiagFailCount(data.failureCount)
                      : l10n.lockscreenDiagFailCountWithTime(
                          data.failureCount,
                          _two(data.latestFailureAt!.month),
                          _two(data.latestFailureAt!.day),
                          _two(data.latestFailureAt!.hour),
                          _two(data.latestFailureAt!.minute),
                        ))
                : l10n.lockscreenDiagFailNone,
            style: TextStyle(
              fontSize: 13,
              color: data.failureCount > 0
                  ? AppColors.red
                  : AppColors.secondaryLabel(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.lockscreenDiagExplain,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ],
      ),
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
