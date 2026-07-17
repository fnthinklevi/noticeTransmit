import 'package:flutter/material.dart';
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
  bool _isLoading = true;

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
    } catch (_) {}
    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: const Text('推送统计'),
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
                  _buildAppStats(context),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCards(BuildContext context) {
    final todayCount = _dailyStats.firstOrNull?['count'] as int? ?? 0;
    final totalCount = _stats.fold(
      0,
      (sum, item) => sum + (item['count'] as int? ?? 0),
    );

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
                const Text('今日推送', style: TextStyle(fontSize: 13)),
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
                const Text('总推送数', style: TextStyle(fontSize: 13)),
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
                const Text('应用数', style: TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyStats(BuildContext context) {
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
            '近7天推送趋势',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.primaryLabel(context),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: _dailyStats.map((stat) {
              final date = stat['date'] as String? ?? '';
              final count = stat['count'] as int? ?? 0;
              final day = date.split('-').last;
              final barHeight = maxCount > 0
                  ? (count / maxCount * 80).toDouble().clamp(4.0, 80.0)
                  : 4.0;

              return Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: 80,
                      child: Stack(
                        alignment: Alignment.bottomCenter,
                        children: [
                          Container(
                            width: 24,
                            decoration: BoxDecoration(
                              color: AppColors.separator(context),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          Container(
                            width: 24,
                            height: barHeight,
                            decoration: BoxDecoration(
                              color: AppColors.blue,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      day,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.secondaryLabel(context),
                      ),
                    ),
                    Text(
                      count.toString(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.primaryLabel(context),
                      ),
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

  Widget _buildAppStats(BuildContext context) {
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
            '应用推送排行',
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
                  : ((pkgName != null && pkgName.isNotEmpty) ? pkgName : '未知');
              final count = stat['count'] as int? ?? 0;
              final totalCount = _stats.fold(
                0,
                (sum, item) => sum + (item['count'] as int? ?? 0),
              );
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
