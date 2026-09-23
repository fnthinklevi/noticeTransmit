import 'dart:convert';

import '../services/channel_display.dart';

class NotificationRecord {
  final String id;
  final String title;
  final String content;
  final String subText;
  final String packageName;
  final String appName;
  final String type;
  final int postTime;
  final String time;
  final String deviceName;
  // 通知优先级：0=低 / 1=中 / 2=高（来源于系统通知 priority）
  final int priority;
  final List<String> channels;
  // 各推送通道的送达状态：送达键（`chan:<slug>`，见 channel_display）→
  // {'status': 'pending/success/failed', 'message': '...'}
  final Map<String, dynamic> deliveryStatus;

  NotificationRecord({
    required this.id,
    required this.title,
    required this.content,
    required this.subText,
    required this.packageName,
    required this.appName,
    required this.type,
    required this.postTime,
    required this.time,
    required this.deviceName,
    this.priority = 1,
    this.channels = const [],
    this.deliveryStatus = const {},
  });

  factory NotificationRecord.fromMap(Map<String, dynamic> map) {
    // 兼容两种来源：内存/导出（camelCase）与 DB rawQuery 行（snake_case）。
    // 此前 DB 行的 post_time/sub_text 等会静默回退为 0/空串，导致按时间
    // 筛选与排序失真（P1 历史搜索依赖 postTime，必须双键兼容）。
    return NotificationRecord(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      content: map['content'] as String? ?? '',
      subText: (map['subText'] ?? map['sub_text']) as String? ?? '',
      packageName: (map['packageName'] ?? map['package_name']) as String? ?? '',
      appName: (map['appName'] ?? map['app_name']) as String? ?? '',
      type: map['type'] as String? ?? 'normal',
      postTime: (map['postTime'] ?? map['post_time']) as int? ?? 0,
      time: map['time'] as String? ?? '',
      deviceName: (map['deviceName'] ?? map['device_name']) as String? ?? '',
      priority: map['priority'] as int? ?? 1,
      // channels 与 deliveryStatus 的键必须是同一串（历史页用 channels 做键查状态），
      // 因此同样归一：旧导出文件里存的是显示名。
      channels:
          (map['channels'] as List<dynamic>?)
              ?.map((e) => channelDeliveryKey(e.toString()))
              .toList() ??
          [],
      deliveryStatus: _parseDeliveryStatus(
        map['deliveryStatus'] ?? map['delivery_info'],
      ),
    );
  }

  /// 兼容 DB delivery_info（JSON 字符串）与内存对象（Map）两种来源。
  /// 读取即归一为 `chan:<slug>` 键：v11 之前的行存的是本地化显示名
  /// （`webhook:企业微信` / `邮件`），归一后下游（历史页 chip、状态查询、
  /// 手动补推重置）不必再区分新旧格式，也不会因语言切换而分裂出第二套键。
  static Map<String, dynamic> _parseDeliveryStatus(dynamic v) {
    Map<String, dynamic>? raw;
    if (v is Map) {
      raw = Map<String, dynamic>.from(v);
    } else if (v is String && v.isNotEmpty) {
      try {
        final decoded = jsonDecode(v);
        if (decoded is Map) raw = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    if (raw == null) return {};
    return normalizeDeliveryKeys(raw);
  }

  /// F2 批量补推：是否存在失败通道（与 DB 侧 `delivery_info LIKE '%failed%'`
  /// 筛选同口径，见 `DatabaseHelper._buildSearchWhere`）。
  /// 仅统计 Map 形态且 `status == 'failed'` 的通道条目；空/异形值保守判为无失败。
  bool get hasFailedChannel {
    for (final v in deliveryStatus.values) {
      if (v is Map && v['status'] == 'failed') return true;
    }
    return false;
  }

  /// F2 批量补推：失败通道名列表（供 UI 展示明细）
  List<String> get failedChannels {
    final result = <String>[];
    for (final entry in deliveryStatus.entries) {
      final v = entry.value;
      if (v is Map && v['status'] == 'failed') result.add(entry.key);
    }
    return result;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'subText': subText,
      'packageName': packageName,
      'appName': appName,
      'type': type,
      'postTime': postTime,
      'time': time,
      'deviceName': deviceName,
      'priority': priority,
      'channels': channels,
      'deliveryStatus': deliveryStatus,
    };
  }

  NotificationRecord copyWith({
    String? id,
    String? title,
    String? content,
    String? subText,
    String? packageName,
    String? appName,
    String? type,
    int? postTime,
    String? time,
    String? deviceName,
    int? priority,
    List<String>? channels,
    Map<String, dynamic>? deliveryStatus,
  }) {
    return NotificationRecord(
      id: id ?? this.id,
      title: title ?? this.title,
      content: content ?? this.content,
      subText: subText ?? this.subText,
      packageName: packageName ?? this.packageName,
      appName: appName ?? this.appName,
      type: type ?? this.type,
      postTime: postTime ?? this.postTime,
      time: time ?? this.time,
      deviceName: deviceName ?? this.deviceName,
      priority: priority ?? this.priority,
      channels: channels ?? this.channels,
      deliveryStatus: deliveryStatus ?? this.deliveryStatus,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationRecord &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
