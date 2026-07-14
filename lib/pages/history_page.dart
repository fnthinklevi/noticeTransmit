import 'dart:convert';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../models/notification_record.dart';

class HistoryPage extends StatefulWidget {
  final List<NotificationRecord> records;
  final Future<void> Function() onClear;
  final Future<String> Function() onExport;

  const HistoryPage({
    super.key,
    required this.records,
    required this.onClear,
    required this.onExport,
  });

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

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
        return const Color(0xFF34C759);
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
        return const Color(0xFF007AFF);
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
      const Color(0xFF007AFF),
      const Color(0xFFFF9500),
      const Color(0xFF34C759),
      const Color(0xFFFF3B30),
      const Color(0xFFAF52DE),
      const Color(0xFF5856D6),
      const Color(0xFF00C7BE),
      const Color(0xFFFF2D55),
      const Color(0xFFFFCC00),
    ];
    return colors[hash.abs() % colors.length];
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

  Future<void> _handleClear() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.cardBg(context),
        title: Text(
          '确认清空',
          style: TextStyle(color: AppColors.primaryLabel(context)),
        ),
        content: Text(
          '确定要清空全部 ${widget.records.length} 条记录吗？',
          style: TextStyle(color: AppColors.primaryLabel(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFF3B30),
            ),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await widget.onClear();
      setState(() {});
    }
  }

  Future<void> _handleExport() async {
    try {
      final path = await widget.onExport();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已导出到: $path'),
          backgroundColor: const Color(0xFF34C759),
          duration: const Duration(seconds: 5),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导出失败: $e'),
          backgroundColor: const Color(0xFFFF3B30),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showRecordDetail(NotificationRecord record) {
    final appName = record.appName.isNotEmpty ? record.appName : '通知详情';
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
                  '详细信息',
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
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '关闭',
              style: TextStyle(
                color: Color(0xFF007AFF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
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
    final type = record.type;
    final title = record.title.isNotEmpty ? record.title : '（无标题）';
    final content = record.content;
    final appName = record.appName;
    final time = _formatTime(record.postTime);
    final isKnownType = _isKnownType(type);
    final color = isKnownType ? _getTypeColor(type) : _getAppColor(appName);
    final label = isKnownType ? _getTypeLabel(type) : appName;

    final List<Widget> columnChildren = [
      Row(
        children: [
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

    return InkWell(
      onTap: () => _showRecordDetail(record),
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
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final records = _filteredRecords;
    return Scaffold(
      backgroundColor: AppColors.bgColor(context),
      appBar: AppBar(
        title: Text('历史记录 (${records.length})'),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: '导出 JSON',
            onPressed: widget.records.isEmpty ? null : _handleExport,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: '清空记录',
            onPressed: widget.records.isEmpty ? null : _handleClear,
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
                  hintText: '搜索标题/内容/应用',
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
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
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
                          widget.records.isEmpty ? '暂无推送记录' : '没有匹配的记录',
                          style: TextStyle(
                            color: AppColors.secondaryLabel(context),
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: records.length,
                    separatorBuilder: (_, _) => Padding(
                      padding: const EdgeInsets.only(left: 56),
                      child: Divider(
                        height: 0.5,
                        thickness: 0.5,
                        color: AppColors.separator(context),
                      ),
                    ),
                    itemBuilder: (context, index) => _buildRecordItem(
                      context,
                      records[index],
                      index,
                      records.length,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
