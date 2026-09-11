import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../services/archive_worker.dart' show kArchiveDirModeKey;
import '../services/filter_service.dart';
import '../services/notification_service.dart';
import '../services/platform_channel.dart';
import '../theme/app_colors.dart';
import '../database/database_helper.dart';
import '../models/notification_record.dart';

class HistoryPage extends StatefulWidget {
  final List<NotificationRecord> records;
  final Future<void> Function() onClear;
  final Future<Map<String, dynamic>> Function() onExport;
  final Future<int> Function() onClearToday;
  final Future<int> Function(int n) onClearLastN;
  // 历史记录"现在推送"：暂停状态下未实际发送的消息可手动补推
  final Future<void> Function(NotificationRecord record)? onPushNow;

  const HistoryPage({
    super.key,
    required this.records,
    required this.onClear,
    required this.onExport,
    required this.onClearToday,
    required this.onClearLastN,
    this.onPushNow,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // ── P1 全量历史搜索/筛选 ──
  // 时间范围（按日）：null 表示未启用时间段筛选；start 含当日 0 点，end 含当日
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  String _filterAppName = '';
  String _filterPackageName = '';
  // 送达状态筛选：all / success / failed
  String _filterDelivery = 'all';
  // 非 null 时为 DB 搜索模式（全量历史分页加载），null 为常规模式（内存 records）
  List<NotificationRecord>? _searchResults;
  bool _hasMore = false;
  bool _loadingMore = false;
  Timer? _debounce;
  final ScrollController _scrollController = ScrollController();
  static const int _pageSize = 200;

  // ── F2 批量补推 ──
  bool _batchMode = false;
  final Set<String> _batchSelected = {};

  /// 当前展示的记录（搜索模式取 DB 结果，否则取内存过滤结果）
  List<NotificationRecord> get _displayedRecords =>
      _searchResults ?? _filteredRecords;

  /// 可补推池：当前展示列表中的失败记录（与 DB `%failed%` 筛选同口径）
  List<NotificationRecord> get _batchPool =>
      _displayedRecords.where((r) => r.hasFailedChannel).toList();

  void _enterBatchMode() {
    final l10n = AppLocalizations.of(context);
    final pool = _batchPool;
    if (pool.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.batchPushNoFailed)));
      return;
    }
    setState(() {
      _batchMode = true;
      // 默认全选当前列表中的失败记录，用户可再取消
      _batchSelected
        ..clear()
        ..addAll(pool.map((r) => r.id));
    });
  }

  void _exitBatchMode() {
    setState(() {
      _batchMode = false;
      _batchSelected.clear();
    });
  }

  void _toggleBatchSelect(NotificationRecord record) {
    if (!record.hasFailedChannel) return; // 非失败记录不可选
    setState(() {
      if (_batchSelected.contains(record.id)) {
        _batchSelected.remove(record.id);
      } else {
        _batchSelected.add(record.id);
      }
    });
  }

  void _selectAllFailed() {
    setState(() {
      _batchSelected
        ..clear()
        ..addAll(_batchPool.map((r) => r.id));
    });
  }

  /// 批量补推：二次确认 → 逐条顺序提交（带进度）→ 汇总反馈
  Future<void> _runBatchPush() async {
    final l10n = AppLocalizations.of(context);
    final targets = _displayedRecords
        .where((r) => _batchSelected.contains(r.id))
        .toList();
    if (targets.isEmpty) return;
    if (widget.onPushNow == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.batchPushUnsupported)));
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardBg(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          l10n.batchPushConfirmTitle,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(dialogContext),
          ),
        ),
        content: Text(
          l10n.batchPushConfirmMsg(targets.length),
          style: TextStyle(
            fontSize: 14,
            height: 1.4,
            color: AppColors.primaryLabel(dialogContext),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              l10n.cancel,
              style: TextStyle(color: AppColors.secondaryLabel(dialogContext)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              l10n.confirm,
              style: const TextStyle(
                color: AppColors.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final progress = ValueNotifier<int>(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardBg(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, done, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.batchPushRunning(done, targets.length),
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.primaryLabel(dialogContext),
                ),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: targets.isEmpty ? 0 : done / targets.length,
                backgroundColor: AppColors.inputBg(dialogContext),
                color: AppColors.blue,
              ),
            ],
          ),
        ),
      ),
    );

    var submitted = 0;
    for (final record in targets) {
      try {
        await widget.onPushNow!(record);
        submitted++;
      } catch (e) {
        debugPrint('批量补推失败（${record.id}）: $e');
      }
      progress.value = submitted;
    }
    progress.dispose();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    setState(() {
      _batchMode = false;
      _batchSelected.clear();
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.batchPushDone(submitted))));
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  List<NotificationRecord> get _filteredRecords {
    if (_searchQuery.isEmpty) return widget.records;
    final q = _searchQuery.toLowerCase();
    return widget.records.where((r) {
      final title = r.title.toLowerCase();
      final content = r.content.toLowerCase();
      final app = r.appName.toLowerCase();
      final pkg = r.packageName.toLowerCase();
      return title.contains(q) ||
          content.contains(q) ||
          app.contains(q) ||
          pkg.contains(q);
    }).toList();
  }

  // ── P1 全量历史搜索/筛选逻辑 ──

  bool get _hasActiveFilter =>
      _searchQuery.isNotEmpty ||
      _rangeStart != null ||
      _filterAppName.isNotEmpty ||
      _filterPackageName.isNotEmpty ||
      _filterDelivery != 'all';

  /// 查询起始毫秒（含）：起始日 0 点
  int? get _startTimeMs => _rangeStart == null
      ? null
      : DateTime(
          _rangeStart!.year,
          _rangeStart!.month,
          _rangeStart!.day,
        ).millisecondsSinceEpoch;

  /// 查询结束毫秒（不含）：结束日次日 0 点（当日整天包含在内）
  int? get _endTimeMs => _rangeEnd == null
      ? null
      : DateTime(
          _rangeEnd!.year,
          _rangeEnd!.month,
          _rangeEnd!.day + 1,
        ).millisecondsSinceEpoch;

  /// 滚动触底自动加载下一页
  void _onScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.extentAfter < 240 &&
        _hasMore &&
        !_loadingMore &&
        _searchResults != null) {
      _loadSearch(reset: false);
    }
  }

  /// 触发搜索：有关键字或筛选条件走 DB 全量搜索，否则回常规内存模式。
  /// 关键字输入带 300ms 防抖；面板应用时 immediate 立即查询。
  void _refreshSearch({bool immediate = false}) {
    _debounce?.cancel();
    if (!_hasActiveFilter) {
      setState(() {
        _searchResults = null;
        _hasMore = false;
      });
      return;
    }
    if (immediate) {
      _loadSearch(reset: true);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _loadSearch(reset: true);
    });
  }

  Future<void> _loadSearch({required bool reset}) async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    final offset = reset ? 0 : (_searchResults?.length ?? 0);
    try {
      final service = GetIt.instance<NotificationService>();
      final (records, hasMore) = await service.searchRecords(
        keyword: _searchQuery.isEmpty ? null : _searchQuery,
        startTime: _startTimeMs,
        endTime: _endTimeMs,
        appName: _filterAppName.isEmpty ? null : _filterAppName,
        packageName: _filterPackageName.isEmpty ? null : _filterPackageName,
        deliveryFilter: _filterDelivery == 'all' ? null : _filterDelivery,
        limit: _pageSize,
        offset: offset,
      );
      if (!mounted) return;
      setState(() {
        _searchResults = reset ? records : [...?_searchResults, ...records];
        _hasMore = hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('历史搜索失败: $e');
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  void _clearAllFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _rangeStart = null;
      _rangeEnd = null;
      _filterAppName = '';
      _filterPackageName = '';
      _filterDelivery = 'all';
      _searchResults = null;
      _hasMore = false;
    });
  }

  /// 时间范围摘要（筛选条显示用），如 09-01 ~ 09-07 或单日 2026-09-08
  String get _rangeSummary {
    if (_rangeStart == null) return '';
    String fmt(DateTime d) =>
        '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (_rangeEnd == null) return fmt(_rangeStart!);
    return '${fmt(_rangeStart!)} ~ ${fmt(_rangeEnd!)}';
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    final ms = timestamp is int
        ? timestamp
        : int.tryParse(timestamp.toString()) ?? 0;
    if (ms == 0) return '';
    final dt = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  Color _getTypeColor(String? type) {
    switch (type) {
      case 'sms':
        return const Color(0xFFFF9500);
      case 'call_incoming':
      case 'call_answered':
      case 'call_ended':
        return AppColors.green;
      case 'wechat':
        return const Color(0xFF07C160);
      case 'qq':
        return const Color(0xFF12B7F5);
      case 'alipay':
        return const Color(0xFF1677FF);
      case 'system':
        return const Color(0xFF8E8E93);
      case 'battery_charging':
      case 'battery_full':
      case 'battery_low_30':
      case 'battery_low_20':
        return AppColors.blue;
      default:
        return const Color(0xFF5856D6);
    }
  }

  bool _isKnownType(String? type) {
    const knownTypes = {
      'sms',
      'call_incoming',
      'call_answered',
      'call_ended',
      'wechat',
      'qq',
      'alipay',
      'system',
      'battery_charging',
      'battery_full',
      'battery_low_30',
      'battery_low_20',
      'test',
    };
    return knownTypes.contains(type);
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

  Color _getChannelColor(String channel) {
    // 通道名随软件语言（企业微信/WeCom、飞书/Feishu、钉钉/DingTalk、邮件/Email），
    // 双语关键词都识别，保证历史记录跨语言显示时品牌色不丢失
    final lower = channel.toLowerCase();
    if (channel.contains('企业微信') || lower.contains('wecom')) {
      return const Color(0xFF2BAA3E);
    }
    if (channel.contains('飞书') || lower.contains('feishu')) {
      return const Color(0xFF3370FF);
    }
    if (channel.contains('钉钉') || lower.contains('dingtalk')) {
      return const Color(0xFF0089FF);
    }
    if (channel.contains('邮件') || lower.contains('email')) {
      return AppColors.orange;
    }
    return Colors.grey;
  }

  /// 渠道 chip + 送达状态小圆点与文字（成功/失败/发送中；无状态记录仅显示渠道名）
  /// 失败时在 chip 下方内联显示失败原因
  Widget _buildChannelChip(
    String channel,
    Color chipColor,
    String status,
    String message,
    AppLocalizations l10n,
  ) {
    final chip = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(channel, style: TextStyle(fontSize: 10, color: chipColor)),
          if (status.isNotEmpty) ...[
            const SizedBox(width: 3),
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: _deliveryStatusColor(status),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              _deliveryStatusText(status, l10n),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: _deliveryStatusColor(status),
              ),
            ),
          ],
        ],
      ),
    );
    // 推送失败/被拦截：原因内联显示在 chip 下方（长按 chip 仍可查看完整信息）。
    // 拦截原因由原生生成，如"黑名单（命中: xxx）"/"应用过滤"
    if ((status == 'failed' || status == 'intercepted') && message.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          chip,
          const SizedBox(height: 1),
          Text(
            message,
            style: TextStyle(fontSize: 9, color: _deliveryStatusColor(status)),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }
    if (message.isEmpty) return chip;
    return Tooltip(message: message, child: chip);
  }

  /// "现在推送"小按钮：iOS 风格圆角蓝底，点击手动补推暂停期间未发送的消息
  Widget _buildPushNowButton(NotificationRecord record, AppLocalizations l10n) {
    return GestureDetector(
      onTap: () => widget.onPushNow!(record),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.blue,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.send, size: 11, color: Colors.white),
            const SizedBox(width: 3),
            Text(
              l10n.pushNow,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _deliveryStatusText(String status, AppLocalizations l10n) {
    switch (status) {
      case 'success':
        return l10n.deliverySuccess;
      case 'failed':
        return l10n.deliveryFailed;
      case 'intercepted':
        return l10n.deliveryIntercepted;
      case 'paused':
        return l10n.pushPausedByUser;
      default:
        return l10n.deliveryPending;
    }
  }

  Color _deliveryStatusColor(String status) {
    switch (status) {
      case 'success':
        return AppColors.green;
      case 'failed':
        return AppColors.red;
      case 'intercepted':
      case 'paused':
        return AppColors.orange;
      default:
        return AppColors.blue;
    }
  }

  /// 优先级徽标（0=低 / 2=高，中优先级不显示以减少噪音）
  Widget _buildPriorityBadge(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String _getTypeLabel(String? type) {
    switch (type) {
      case 'sms':
        return '短信';
      case 'call_incoming':
        return '来电';
      case 'call_answered':
        return '接听';
      case 'call_ended':
        return '挂断';
      case 'wechat':
        return '微信';
      case 'qq':
        return 'QQ';
      case 'alipay':
        return '支付宝';
      case 'system':
        return '系统';
      case 'test':
        return '测试';
      case 'battery_charging':
        return '充电';
      case 'battery_full':
        return '充满';
      case 'battery_low_30':
        return '低电量30%';
      case 'battery_low_20':
        return '低电量20%';
      default:
        return '通知';
    }
  }

  // ── P1 筛选面板 ──

  bool _sameDay(DateTime? a, DateTime? b) =>
      a != null &&
      b != null &&
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day;

  Widget _filterChip(String label, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.blue.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: active ? AppColors.blue : AppColors.separator(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: active ? AppColors.blue : AppColors.primaryLabel(context),
          ),
        ),
      ),
    );
  }

  /// P1 筛选面板（iOS 风格底部弹层）：时间段/日、应用名、包名、送达状态。
  /// 面板内为局部草稿，「应用筛选」后生效；下拉关闭不保存。
  Future<void> _showFilterPanel() async {
    final l10n = AppLocalizations.of(context);
    final today = DateTime.now();
    final today0 = DateTime(today.year, today.month, today.day);
    final yesterday0 = today0.subtract(const Duration(days: 1));
    DateTime? start = _rangeStart;
    DateTime? end = _rangeEnd;
    final appNameCtrl = TextEditingController(text: _filterAppName);
    final pkgCtrl = TextEditingController(text: _filterPackageName);
    var delivery = _filterDelivery;

    Widget timeChips(void Function(void Function()) setSheet) {
      final is7 =
          start != null &&
          end != null &&
          _sameDay(start, today0.subtract(const Duration(days: 6))) &&
          _sameDay(end, today0);
      final is30 =
          start != null &&
          end != null &&
          _sameDay(start, today0.subtract(const Duration(days: 29))) &&
          _sameDay(end, today0);
      final isCustom =
          start != null &&
          !_sameDay(start, today0) &&
          !_sameDay(start, yesterday0) &&
          !is7 &&
          !is30;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _filterChip(
            l10n.filterTimeAll,
            start == null,
            () => setSheet(() {
              start = null;
              end = null;
            }),
          ),
          _filterChip(
            l10n.filterToday,
            _sameDay(start, today0) && _sameDay(end, today0),
            () => setSheet(() {
              start = today0;
              end = today0;
            }),
          ),
          _filterChip(
            l10n.filterYesterday,
            _sameDay(start, yesterday0) && _sameDay(end, yesterday0),
            () => setSheet(() {
              start = yesterday0;
              end = yesterday0;
            }),
          ),
          _filterChip(
            l10n.filterLast7Days,
            is7,
            () => setSheet(() {
              start = today0.subtract(const Duration(days: 6));
              end = today0;
            }),
          ),
          _filterChip(
            l10n.filterLast30Days,
            is30,
            () => setSheet(() {
              start = today0.subtract(const Duration(days: 29));
              end = today0;
            }),
          ),
          _filterChip(l10n.filterCustomRange, isCustom, () async {
            // 用页面 context 打开日期选择器（面板 builder 内的 sheetContext
            // 不在 timeChips 闭包作用域内）
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: today0.add(const Duration(days: 1)),
              initialDateRange: (start != null && end != null)
                  ? DateTimeRange(start: start!, end: end!)
                  : null,
            );
            if (picked != null) {
              setSheet(() {
                start = picked.start;
                end = picked.end;
              });
            }
          }),
        ],
      );
    }

    Widget deliveryChips(void Function(void Function()) setSheet) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _filterChip(
            l10n.deliveryAll,
            delivery == 'all',
            () => setSheet(() => delivery = 'all'),
          ),
          _filterChip(
            l10n.deliverySuccessOnly,
            delivery == 'success',
            () => setSheet(() => delivery = 'success'),
          ),
          _filterChip(
            l10n.deliveryFailedOnly,
            delivery == 'failed',
            () => setSheet(() => delivery = 'failed'),
          ),
        ],
      );
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: BoxDecoration(
            color: AppColors.cardBg(sheetContext),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.separator(sheetContext),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.filterTitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryLabel(sheetContext),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  l10n.filterDateRange,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryLabel(sheetContext),
                  ),
                ),
                const SizedBox(height: 8),
                timeChips(setSheet),
                if (start != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _sameDay(start, end)
                        ? '${start!.year}-${start!.month.toString().padLeft(2, '0')}-${start!.day.toString().padLeft(2, '0')}'
                        : '${start!.year}-${start!.month.toString().padLeft(2, '0')}-${start!.day.toString().padLeft(2, '0')}'
                              ' ~ ${end!.year}-${end!.month.toString().padLeft(2, '0')}-${end!.day.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.secondaryLabel(sheetContext),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: appNameCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.filterAppName,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.primaryLabel(sheetContext),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pkgCtrl,
                  decoration: InputDecoration(
                    labelText: l10n.filterPackageName,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.primaryLabel(sheetContext),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.filterDeliveryStatus,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.secondaryLabel(sheetContext),
                  ),
                ),
                const SizedBox(height: 8),
                deliveryChips(setSheet),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _clearAllFilters();
                        },
                        child: Text(
                          l10n.filterReset,
                          style: TextStyle(
                            color: AppColors.secondaryLabel(sheetContext),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          if (!mounted) return;
                          setState(() {
                            _rangeStart = start;
                            _rangeEnd = end;
                            _filterAppName = appNameCtrl.text.trim();
                            _filterPackageName = pkgCtrl.text.trim();
                            _filterDelivery = delivery;
                          });
                          _refreshSearch(immediate: true);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.blue,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(l10n.filterApply),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// P1：自动保存路径设置（iOS 风格弹窗）：查看当前归档目录、
  /// 选择自定义文件夹（SAF，原生持久化授权）或恢复默认应用专属目录
  Future<void> _showArchivePathDialog() async {
    final l10n = AppLocalizations.of(context);
    String? saved;
    try {
      saved = await AppChannels.notification.invokeMethod<String>(
        'getArchiveDirectory',
      );
    } catch (_) {}
    if (!mounted) return;

    final action = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardBg(dialogContext),
        title: Text(
          l10n.autoSavePath,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(dialogContext),
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.autoSavePathDesc,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.secondaryLabel(dialogContext),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                saved == null ? l10n.archivePathDefault : _prettyTreeUri(saved),
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.primaryLabel(dialogContext),
                ),
              ),
              const SizedBox(height: 4),
              ListTile(
                dense: true,
                leading: const Icon(Icons.folder_open, size: 20),
                title: Text(
                  l10n.chooseFolder,
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.primaryLabel(dialogContext),
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                onTap: () => Navigator.pop(dialogContext, 'pick'),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.restore, size: 20),
                title: Text(
                  l10n.resetToDefault,
                  style: TextStyle(
                    fontSize: 15,
                    color: saved == null
                        ? AppColors.tertiaryLabel(dialogContext)
                        : AppColors.primaryLabel(dialogContext),
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                onTap: saved == null
                    ? null
                    : () => Navigator.pop(dialogContext, 'reset'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, null),
            child: Text(l10n.cancel),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
    if (action == null || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    if (action == 'pick') {
      try {
        final uri = await AppChannels.notification.invokeMethod<String>(
          'pickArchiveDirectory',
        );
        if (!mounted) return;
        if (uri != null) {
          await prefs.setString(kArchiveDirModeKey, 'custom');
          if (!mounted) return;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(l10n.archivePathUpdated),
                duration: const Duration(seconds: 2),
              ),
            );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(e.toString())));
        }
      }
    } else if (action == 'reset') {
      try {
        await AppChannels.notification.invokeMethod('clearArchiveDirectory');
      } catch (_) {}
      await prefs.setString(kArchiveDirModeKey, 'default');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.archivePathReset),
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  /// SAF treeUri 转可读路径（content://.../tree/primary%3ADownload%2Fxxx/... → Download/xxx）
  String _prettyTreeUri(String uri) {
    try {
      final idx = uri.indexOf('/tree/');
      if (idx >= 0) {
        var part = uri.substring(idx + 6);
        final slash = part.indexOf('/');
        if (slash >= 0) part = part.substring(0, slash);
        part = Uri.decodeComponent(part).replaceFirst(':', '/');
        return part.startsWith('/') ? '存储根目录$part' : part;
      }
    } catch (_) {}
    return uri;
  }

  Future<void> _handleExport() async {
    final l10n = AppLocalizations.of(context);
    try {
      final result = await widget.onExport();
      if (!mounted) return;
      final message = result['message']?.toString() ?? '';
      if (message.isEmpty || message == l10n.exportCancelled) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 送达日志查询/展示用
  final DatabaseHelper _dbHelper = DatabaseHelper();

  // ── 快捷屏蔽（长按记录菜单与详情页按钮共用）──

  FilterService get _filterService => GetIt.instance<FilterService>();

  void _showToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  /// 屏蔽该应用：按当前过滤模式分流。
  /// - allow（白名单）模式：仅选中应用会被推送 → 应用在名单中则移出即屏蔽；
  ///   不在名单中说明本就不推送，提示无需操作。
  /// - block（黑名单）模式：应用加入屏蔽名单；已在名单中提示无需操作。
  /// 返回后由调用方刷新列表显示。
  Future<void> _blockApp(NotificationRecord record) async {
    final l10n = AppLocalizations.of(context);
    final pkg = record.packageName;
    final app = record.appName.isNotEmpty ? record.appName : pkg;
    if (pkg.isEmpty) {
      _showToast(l10n.historyBlockNoAppName);
      return;
    }
    final filterService = _filterService;
    if (filterService.appFilterMode == 'allow') {
      if (!filterService.enabledPackages.contains(pkg)) {
        _showToast(l10n.historyBlockAppAlreadyExcluded(app));
        return;
      }
      final remaining = filterService.enabledPackages
          .where((p) => p != pkg)
          .toList();
      await filterService.saveAppFilter('allow', remaining);
      _showToast(l10n.historyBlockAppRemoved(app));
    } else {
      if (filterService.enabledPackages.contains(pkg)) {
        _showToast(l10n.historyBlockAppAlreadyBlocked(app));
        return;
      }
      await filterService.saveAppFilter('block', [
        ...filterService.enabledPackages,
        pkg,
      ]);
      _showToast(l10n.historyBlockAppAdded(app));
    }
    if (mounted) setState(() {});
  }

  /// 屏蔽含本通知内容的通知：弹窗预填通知全文（正文为空时用标题），
  /// 可编辑后加入黑名单关键词（黑名单匹配为「标题/内容包含关键词」）。
  Future<void> _blockContent(NotificationRecord record) async {
    final l10n = AppLocalizations.of(context);
    final initialText = record.content.isNotEmpty
        ? record.content
        : record.title;
    if (initialText.isEmpty) {
      _showToast(l10n.historyBlockNoText);
      return;
    }
    final controller = TextEditingController(text: initialText);
    final keyword = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardBg(dialogContext),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(
          l10n.historyBlockContentDialogTitle,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(dialogContext),
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.primaryLabel(dialogContext),
              ),
              decoration: InputDecoration(
                fillColor: AppColors.inputBg(dialogContext),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: AppColors.separator(dialogContext),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.blue),
                ),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.historyBlockContentEditHint,
              style: TextStyle(
                fontSize: 12,
                color: AppColors.secondaryLabel(dialogContext),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              l10n.cancel,
              style: TextStyle(
                fontSize: 16,
                color: AppColors.secondaryLabel(dialogContext),
              ),
            ),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: Text(
              l10n.save,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.blue,
              ),
            ),
          ),
        ],
      ),
    );
    if (keyword == null || keyword.isEmpty) return;
    final filterService = _filterService;
    if (filterService.blacklistKeywords.contains(keyword)) {
      _showToast(l10n.historyBlockContentDuplicate);
      return;
    }
    await filterService.saveBlacklistKeywords([
      ...filterService.blacklistKeywords,
      keyword,
    ]);
    _showToast(l10n.historyBlockContentSuccess);
    if (mounted) setState(() {});
  }

  /// 长按记录弹出操作菜单（屏蔽应用 / 屏蔽内容）
  void _showRecordActionsSheet(NotificationRecord record) {
    final l10n = AppLocalizations.of(context);
    final isAllowMode = _filterService.appFilterMode == 'allow';
    final inList = _filterService.enabledPackages.contains(record.packageName);
    // 副标题动态说明当前模式下将执行的动作（或已屏蔽状态）
    final blockAppDesc = isAllowMode
        ? (inList
              ? l10n.historyActionBlockAppDescAllow
              : l10n.historyActionBlockAppDescAlreadyExcluded)
        : (inList
              ? l10n.historyActionBlockAppDescAlreadyBlocked
              : l10n.historyActionBlockAppDescBlock);
    final textPreview = record.content.isNotEmpty
        ? record.content
        : record.title;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: AppColors.cardBg(sheetContext),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.separator(sheetContext),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.block, color: AppColors.red),
                title: Text(
                  l10n.historyActionBlockApp,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryLabel(sheetContext),
                  ),
                ),
                subtitle: Text(
                  blockAppDesc,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryLabel(sheetContext),
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _blockApp(record);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.playlist_remove,
                  color: Color(0xFFFF9500),
                ),
                title: Text(
                  l10n.historyActionBlockContent,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.primaryLabel(sheetContext),
                  ),
                ),
                subtitle: Text(
                  textPreview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.secondaryLabel(sheetContext),
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _blockContent(record);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRecordDetail(NotificationRecord record) async {
    final l10n = AppLocalizations.of(context);
    final appName = record.appName.isNotEmpty
        ? record.appName
        : l10n.notificationDetail;
    // Q2：送达日志（webhook_delivery_log）随详情一并查出，DB 异常静默降级
    List<Map<String, dynamic>> deliveryLogs = [];
    try {
      deliveryLogs = await _dbHelper.getDeliveryLogsByNotification(record.id);
    } catch (_) {}
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        title: Text(
          appName,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(context),
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.detailInfo,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.inputBg(context),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: SelectableText(
                    const JsonEncoder.withIndent('  ').convert(record.toMap()),
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: AppColors.primaryLabel(context),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.deliveryLogTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.secondaryLabel(context),
                  ),
                ),
                const SizedBox(height: 8),
                if (deliveryLogs.isEmpty)
                  Text(
                    l10n.deliveryLogEmpty,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.secondaryLabel(context),
                    ),
                  )
                else ...[
                  for (final log in deliveryLogs)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            margin: const EdgeInsets.only(top: 5),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: log['status'] == 'success'
                                  ? AppColors.green
                                  : AppColors.red,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${log['tag']} · HTTP ${log['http_code'] ?? '-'}'
                              ' · ${log['message'] ?? ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primaryLabel(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _blockApp(record);
            },
            icon: const Icon(Icons.block, size: 16),
            label: Text(
              l10n.historyActionBlockAppShort,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _blockContent(record);
            },
            icon: const Icon(Icons.playlist_remove, size: 16),
            label: Text(
              l10n.historyActionBlockContentShort,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.close,
              style: const TextStyle(
                color: AppColors.blue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        actionsOverflowButtonSpacing: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  Widget _buildRecordItem(
    BuildContext context,
    NotificationRecord record,
    int index,
    int total,
  ) {
    final l10n = AppLocalizations.of(context);
    final type = record.type;
    final title = record.title.isNotEmpty ? record.title : l10n.noTitle;
    final content = record.content;
    final appName = record.appName;
    final time = _formatTime(record.postTime);
    final isKnownType = _isKnownType(type);
    final color = isKnownType ? _getTypeColor(type) : _getAppColor(appName);
    final label = isKnownType ? _getTypeLabel(type) : appName;

    final List<Widget> columnChildren = [
      Row(
        children: [
          if (record.priority == 2) ...[
            _buildPriorityBadge(context, '高', AppColors.red),
            const SizedBox(width: 6),
          ] else if (record.priority == 0) ...[
            _buildPriorityBadge(context, '低', Colors.grey),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: AppColors.primaryLabel(context),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            time,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.secondaryLabel(context),
            ),
          ),
        ],
      ),
    ];

    if (content.isNotEmpty) {
      columnChildren.add(const SizedBox(height: 3));
      columnChildren.add(
        Text(
          content,
          style: TextStyle(
            fontSize: 13,
            color: AppColors.secondaryLabel(context),
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    if (appName.isNotEmpty) {
      columnChildren.add(const SizedBox(height: 3));
      columnChildren.add(
        Text(
          appName,
          style: TextStyle(
            fontSize: 11,
            color: AppColors.secondaryLabel(context),
          ),
        ),
      );
    }

    // 推送渠道标签 + 各通道送达状态（重启后 channels 为空时回退用 deliveryStatus 键）
    final displayChannels = record.channels.isNotEmpty
        ? record.channels
        : record.deliveryStatus.keys.toList();
    // 是否存在被用户暂停（未实际发送）的通道 → 显示"现在推送"按钮
    final hasPausedChannel = displayChannels.any((c) {
      final info = record.deliveryStatus[c];
      return info is Map && info['status'] == 'paused';
    });
    if (displayChannels.isNotEmpty) {
      columnChildren.add(const SizedBox(height: 4));
      columnChildren.add(
        Wrap(
          spacing: 4,
          runSpacing: 2,
          children: displayChannels.map((c) {
            final chipColor = _getChannelColor(c);
            final statusInfo = record.deliveryStatus[c];
            final status = statusInfo is Map
                ? (statusInfo['status']?.toString() ?? '')
                : '';
            final message = statusInfo is Map
                ? (statusInfo['message']?.toString() ?? '')
                : '';
            return _buildChannelChip(c, chipColor, status, message, l10n);
          }).toList(),
        ),
      );
      // 暂停状态下未发送：提供手动补推入口
      if (hasPausedChannel && widget.onPushNow != null) {
        columnChildren.add(const SizedBox(height: 6));
        columnChildren.add(_buildPushNowButton(record, l10n));
      }
    } else {
      columnChildren.add(const SizedBox(height: 4));
      columnChildren.add(
        Text(
          l10n.noChannels,
          style: TextStyle(
            fontSize: 10,
            color: AppColors.secondaryLabel(context),
          ),
        ),
      );
    }

    final item = InkWell(
      // F2：批量模式下点行切换选中（不打开详情），长按菜单禁用
      onTap: _batchMode
          ? () => _toggleBatchSelect(record)
          : () => _showRecordDetail(record),
      onLongPress: _batchMode ? null : () => _showRecordActionsSheet(record),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.cardBg(context),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(index == 0 ? 12 : 0),
            topRight: Radius.circular(index == 0 ? 12 : 0),
            bottomLeft: Radius.circular(index == total - 1 ? 12 : 0),
            bottomRight: Radius.circular(index == total - 1 ? 12 : 0),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  label.isNotEmpty ? label.substring(0, 1) : '通',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: columnChildren,
              ),
            ),
          ],
        ),
      ),
    );

    // F2：批量模式左侧加勾选框（非失败记录不可选，置灰）
    if (!_batchMode) return item;
    final selectable = record.hasFailedChannel;
    return Row(
      children: [
        Checkbox(
          value: _batchSelected.contains(record.id),
          activeColor: AppColors.blue,
          onChanged: selectable ? (_) => _toggleBatchSelect(record) : null,
        ),
        Expanded(
          child: Opacity(opacity: selectable ? 1 : 0.5, child: item),
        ),
      ],
    );
  }

  /// F2：批量模式底部操作栏（取消 / 补推 N 条）
  Widget _buildBatchBar(BuildContext context, AppLocalizations l10n) {
    final count = _batchSelected.length;
    return Container(
      color: AppColors.cardBg(context),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              TextButton(
                onPressed: _exitBatchMode,
                child: Text(
                  l10n.cancel,
                  style: TextStyle(color: AppColors.secondaryLabel(context)),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: count == 0 ? null : _runBatchPush,
                icon: const Icon(Icons.replay, size: 18),
                label: Text(l10n.batchPushAction(count)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 清除记录入口：iOS 风格弹窗（替代 Material PopupMenuButton）
  Future<void> _showClearOptions() async {
    final l10n = AppLocalizations.of(context);
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        title: Text(
          l10n.clearRecords,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: AppColors.primaryLabel(context),
          ),
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  l10n.clearToday,
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                onTap: () => Navigator.pop(dialogContext, 'today'),
              ),
              ListTile(
                dense: true,
                title: Text(
                  l10n.clearLast10,
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                onTap: () => Navigator.pop(dialogContext, 'last10'),
              ),
              ListTile(
                dense: true,
                title: Text(
                  l10n.clearLast50,
                  style: TextStyle(
                    fontSize: 15,
                    color: AppColors.primaryLabel(context),
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                onTap: () => Navigator.pop(dialogContext, 'last50'),
              ),
              ListTile(
                dense: true,
                title: Text(
                  l10n.clearAll,
                  style: const TextStyle(color: Colors.red, fontSize: 15),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                onTap: () => Navigator.pop(dialogContext, 'all'),
              ),
            ],
          ),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
    if (selected == null || !mounted) return;

    int deleted = 0;
    switch (selected) {
      case 'today':
        deleted = await widget.onClearToday();
        break;
      case 'last10':
        deleted = await widget.onClearLastN(10);
        break;
      case 'last50':
        deleted = await widget.onClearLastN(50);
        break;
      case 'all':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: AppColors.cardBg(ctx),
            title: Text(
              l10n.confirmClear,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: AppColors.primaryLabel(ctx),
              ),
            ),
            content: Text(
              l10n.clearConfirmMsg(widget.records.length),
              style: TextStyle(color: AppColors.primaryLabel(ctx)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.cancel),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  l10n.confirm,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        );
        if (confirm == true) {
          await widget.onClear();
          deleted = widget.records.length;
        }
        break;
    }
    if (deleted > 0 && mounted) {
      setState(() {});
      if (!mounted) return;
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.clearedN(deleted)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final searchMode = _searchResults != null;
    final records = _searchResults ?? _filteredRecords;
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        leading: _batchMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: l10n.cancel,
                onPressed: _exitBatchMode,
              )
            : null,
        title: Text(
          _batchMode
              ? l10n.batchSelectedCount(_batchSelected.length)
              : searchMode
              ? l10n.searchResultCount(records.length)
              : l10n.historyTitle(records.length),
        ),
        actions: _batchMode
            ? [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  tooltip: l10n.batchSelectAll,
                  onPressed: _selectAllFailed,
                ),
                IconButton(
                  icon: const Icon(Icons.deselect),
                  tooltip: l10n.batchSelectNone,
                  onPressed: () => setState(_batchSelected.clear),
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.replay),
                  tooltip: l10n.batchPushEntry,
                  onPressed: _enterBatchMode,
                ),
                IconButton(
                  icon: Icon(
                    Icons.filter_list,
                    color: _hasActiveFilter ? AppColors.blue : null,
                  ),
                  tooltip: l10n.filterTitle,
                  onPressed: _showFilterPanel,
                ),
                IconButton(
                  icon: const Icon(Icons.folder_open),
                  tooltip: l10n.autoSavePath,
                  onPressed: _showArchivePathDialog,
                ),
                IconButton(
                  icon: const Icon(Icons.ios_share),
                  tooltip: l10n.exportJson,
                  onPressed: widget.records.isEmpty ? null : _handleExport,
                ),
                IconButton(
                  icon: const Icon(Icons.cleaning_services_outlined),
                  tooltip: l10n.clearRecords,
                  onPressed: widget.records.isEmpty ? null : _showClearOptions,
                ),
              ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.inputBg(context),
                borderRadius: BorderRadius.circular(10),
              ),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: l10n.searchHint,
                  hintStyle: TextStyle(
                    fontSize: 14,
                    color: AppColors.secondaryLabel(context),
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    size: 18,
                    color: AppColors.secondaryLabel(context),
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.cancel,
                            size: 18,
                            color: AppColors.secondaryLabel(context),
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _searchQuery = '';
                            });
                            _refreshSearch();
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  isDense: true,
                ),
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.primaryLabel(context),
                ),
                onChanged: (v) {
                  setState(() => _searchQuery = v);
                  _refreshSearch();
                },
              ),
            ),
          ),
          // 激活筛选条：显示当前时间范围摘要 + 一键清除
          if (_hasActiveFilter)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _clearAllFilters,
                    child: Row(
                      children: [
                        const Icon(
                          Icons.close,
                          size: 14,
                          color: AppColors.blue,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          l10n.clearSearchFilter,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.blue,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (_rangeStart != null)
                    Text(
                      _rangeSummary,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondaryLabel(context),
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: records.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 56,
                          color: AppColors.tertiaryLabel(context),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          searchMode || widget.records.isNotEmpty
                              ? l10n.noMatchRecords
                              : l10n.noRecords,
                          style: TextStyle(
                            color: AppColors.secondaryLabel(context),
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount:
                        records.length + (searchMode && _hasMore ? 1 : 0),
                    separatorBuilder: (_, _) => Padding(
                      padding: const EdgeInsets.only(left: 56),
                      child: Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: AppColors.separator(context),
                      ),
                    ),
                    itemBuilder: (context, index) {
                      // 末尾加载指示：搜索模式且可能有下一页
                      if (index >= records.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: _loadingMore
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(
                                    l10n.loadMoreHint,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.tertiaryLabel(context),
                                    ),
                                  ),
                          ),
                        );
                      }
                      return _buildRecordItem(
                        context,
                        records[index],
                        index,
                        records.length,
                      );
                    },
                  ),
          ),
          // F2：批量模式底部操作栏
          if (_batchMode) _buildBatchBar(context, l10n),
        ],
      ),
    );
  }
}
