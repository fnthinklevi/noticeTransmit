import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/channel_display.dart';
import '../services/notification_service.dart';
import '../theme/app_colors.dart';
import 'package:get_it/get_it.dart';

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  final NotificationService _notificationService =
      GetIt.instance<NotificationService>();
  List<Map<String, dynamic>> _stats = [];
  List<Map<String, dynamic>> _dailyStats = [];
  // 今日/总数统一以 DB 为准（与首页推送记录、状态栏推送统计共用同一数据源）
  int _todayCount = 0;
  int _totalCount = 0;
  bool _isLoading = true;
  // 送达健康：7/30 天可切换
  int _healthDays = 7;
  List<Map<String, dynamic>> _channelRates = [];
  List<Map<String, dynamic>> _failureReasons = [];
  List<Map<String, dynamic>> _hourlyDistribution = [];

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);
    try {
      _stats = await _notificationService.getStats();
      _dailyStats = await _notificationService.getDailyStats(7);
      _todayCount = await _notificationService.getTodayCount();
      _totalCount = await _notificationService.getTotalCount();
      await _loadHealthStats();
    } catch (e) {
      // 统计读取失败此前被完全吞掉，页面照常渲染成全 0（用户以为是「没有数据」）。
      // 至少留下可诊断的痕迹；错误态 UI 待补。
      debugPrint('统计加载失败: $e');
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  Future<void> _loadHealthStats() async {
    try {
      _channelRates = await _notificationService.getChannelSuccessRates(
        days: _healthDays,
      );
      _failureReasons = await _notificationService.getTopFailureReasons(
        days: _healthDays,
      );
      _hourlyDistribution = await _notificationService.getHourlyDistribution(
        days: _healthDays,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: Text(l10n.pushStats),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadStats),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildSummaryCards(context),
                  const SizedBox(height: 20),
                  _buildDailyStats(context),
                  const SizedBox(height: 20),
                  _buildDeliveryHealth(context),
                  const SizedBox(height: 20),
                  _buildAppStats(context),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCards(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final todayCount = _todayCount;
    final totalCount = _totalCount;

    return Row(
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg(context),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  todayCount.toString(),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.blue,
                  ),
                ),
                const SizedBox(height: 4),
                Text(l10n.statsToday, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg(context),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  totalCount.toString(),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.green,
                  ),
                ),
                const SizedBox(height: 4),
                Text(l10n.statsTotal, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.cardBg(context),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(
                  _stats.length.toString(),
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFAF52DE),
                  ),
                ),
                const SizedBox(height: 4),
                Text(l10n.statsApps, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyStats(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final maxCount = _dailyStats.isEmpty
        ? 0
        : _dailyStats
              .map((s) => s['count'] as int? ?? 0)
              .reduce((a, b) => a > b ? a : b);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.statsTrend,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryLabel(context),
            ),
          ),
          const SizedBox(height: 12),
          if (_dailyStats.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  l10n.statsNoData,
                  style: TextStyle(
                    color: AppColors.secondaryLabel(context),
                    fontSize: 14,
                  ),
                ),
              ),
            )
          else
            ..._dailyStats.map((stat) {
              final date = stat['date'] as String? ?? '';
              final count = stat['count'] as int? ?? 0;
              final ratio = maxCount > 0 ? count / maxCount : 0.0;
              final dayLabel = _formatDayLabel(date);

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(
                        dayLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: AppColors.secondaryLabel(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Container(
                            height: 24,
                            decoration: BoxDecoration(
                              color: AppColors.separator(context),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: ratio.clamp(0.02, 1.0),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppColors.blue,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 36,
                      child: Text(
                        '$count',
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryLabel(context),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  /// 送达健康：通道成功率排行 / 失败原因 TOP / 高峰时段分布
  /// （webhook_delivery_log + notifications 聚合，7/30 天可切换）
  Widget _buildDeliveryHealth(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.statsDeliveryHealth,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
              ),
              _rangeToggle(context, '7', l10n.statsRange7),
              const SizedBox(width: 6),
              _rangeToggle(context, '30', l10n.statsRange30),
            ],
          ),
          const SizedBox(height: 14),
          if (_channelRates.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Text(
                  l10n.statsNoDeliveryData,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
              ),
            )
          else ...[
            Text(
              l10n.statsChannelSuccess,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.secondaryLabel(context),
              ),
            ),
            const SizedBox(height: 8),
            ..._channelRates.take(8).map(_buildChannelRateRow),
            if (_failureReasons.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                l10n.statsFailureTop,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
              const SizedBox(height: 6),
              ..._failureReasons.map(_buildFailureReasonRow),
            ],
            if (_hourlyDistribution.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                l10n.statsHourly,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondaryLabel(context),
                ),
              ),
              const SizedBox(height: 8),
              _buildHourlyBars(context),
            ],
          ],
        ],
      ),
    );
  }

  Widget _rangeToggle(BuildContext context, String days, String label) {
    final selected = _healthDays.toString() == days;
    return GestureDetector(
      onTap: selected
          ? null
          : () async {
              setState(() => _healthDays = int.parse(days));
              await _loadHealthStats();
              if (mounted) setState(() {});
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.blue
              : AppColors.secondaryLabel(context).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : AppColors.secondaryLabel(context),
          ),
        ),
      ),
    );
  }

  Widget _buildChannelRateRow(Map<String, dynamic> row) {
    // tag 存的是送达键（chan:<slug>），此处换算成当前语言的显示名
    final tag = channelTypeDisplayName(row['tag']?.toString() ?? '');
    final total = (row['total'] as num?)?.toInt() ?? 0;
    final success = (row['success'] as num?)?.toInt() ?? 0;
    final ratio = total > 0 ? success / total : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(
              tag,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.primaryLabel(context),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.inputBg(context),
                borderRadius: BorderRadius.circular(4),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: ratio.clamp(0.0, 1.0),
                child: Container(
                  decoration: BoxDecoration(
                    color: ratio >= 0.9
                        ? AppColors.green
                        : (ratio >= 0.6
                              ? AppColors.systemOrange(context)
                              : AppColors.red),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 74,
            child: Text(
              '$success/$total',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFailureReasonRow(Map<String, dynamic> row) {
    final l10n = AppLocalizations.of(context);
    final code = (row['code'] as num?)?.toInt() ?? -1;
    final cnt = (row['cnt'] as num?)?.toInt() ?? 0;
    final label = code <= 0 ? l10n.statsFailNetwork : 'HTTP $code';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 15, color: AppColors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.primaryLabel(context),
              ),
            ),
          ),
          Text(
            l10n.statsFailCount(cnt),
            style: TextStyle(
              fontSize: 12,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHourlyBars(BuildContext context) {
    final counts = List<int>.filled(24, 0);
    for (final row in _hourlyDistribution) {
      final hour = (row['hour'] as num?)?.toInt() ?? -1;
      if (hour >= 0 && hour < 24) {
        counts[hour] = (row['cnt'] as num?)?.toInt() ?? 0;
      }
    }
    final maxCnt = counts.reduce((a, b) => a > b ? a : b);
    return SizedBox(
      height: 72,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var h = 0; h < 24; h++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 1),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Container(
                      height: maxCnt > 0 ? 52 * counts[h] / maxCnt : 0.5,
                      decoration: BoxDecoration(
                        color: counts[h] > 0
                            ? AppColors.blue
                            : AppColors.separator(context),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDayLabel(String date) {
    // date 格式: "2026-07-19"
    if (date.length < 10) return date;
    final month = int.tryParse(date.substring(5, 7)) ?? 0;
    final day = int.tryParse(date.substring(8, 10)) ?? 0;
    return '$month/$day';
  }

  Widget _buildAppStats(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final sortedStats = List<Map<String, dynamic>>.from(_stats)
      ..sort(
        (a, b) => (b['count'] as int? ?? 0).compareTo(a['count'] as int? ?? 0),
      );

    final topStats = sortedStats.take(10).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardBg(context),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.statsRank,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryLabel(context),
            ),
          ),
          const SizedBox(height: 12),
          Column(
            children: topStats.map((stat) {
              final rawName = stat['appName'] as String?;
              final pkgName = stat['packageName'] as String?;
              final appName = (rawName != null && rawName.isNotEmpty)
                  ? rawName
                  : ((pkgName != null && pkgName.isNotEmpty)
                        ? pkgName
                        : l10n.unknown);
              final count = stat['count'] as int? ?? 0;
              final totalCount = _totalCount;
              final percentage = totalCount > 0
                  ? (count / totalCount * 100)
                  : 0;

              return Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.separator(context)),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: _getAppColor(appName).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          appName.isNotEmpty ? appName.substring(0, 1) : '?',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _getAppColor(appName),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            appName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: AppColors.primaryLabel(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            height: 6,
                            decoration: BoxDecoration(
                              color: AppColors.inputBg(context),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: FractionallySizedBox(
                              widthFactor: percentage / 100,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: _getAppColor(appName),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          count.toString(),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryLabel(context),
                          ),
                        ),
                        Text(
                          '${percentage.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.secondaryLabel(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Color _getAppColor(String appName) {
    if (appName.isEmpty) return const Color(0xFF5856D6);
    final hash = appName.hashCode;
    final colors = [
      AppColors.blue,
      const Color(0xFFFF9500),
      AppColors.green,
      AppColors.red,
      const Color(0xFFAF52DE),
      const Color(0xFF5856D6),
      const Color(0xFF00C7BE),
      const Color(0xFFFF2D55),
      const Color(0xFFFFCC00),
    ];
    return colors[hash.abs() % colors.length];
  }
}
