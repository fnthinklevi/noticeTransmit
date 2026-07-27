import 'package:flutter/foundation.dart';
import '../database/database_helper.dart';
import 'platform_channel.dart';

/// Webhook 通道持久化服务
///
/// 存储策略（v1.5.45+）：
///   1. 主存储 → 加密 SQLCipher 数据库（webhook_channels 表，AES-256）
///   2. 同步到原生端 → MethodChannel（供后台 NotificationMonitorService 读取 URL）
class WebhookService {
  final DatabaseHelper _db = DatabaseHelper();

  List<Map<String, dynamic>> _channels = [];
  List<Map<String, dynamic>> get channels => _channels;

  /// 从加密数据库加载 Webhook 通道
  Future<void> loadChannels() async {
    _channels = await _db.getWebhookChannels();
    // 将 DB 格式转为 UI 期望格式
    _channels = _channels.map((row) => _dbRowToUi(row)).toList();
    await _syncEnabledUrls();
  }

  /// 保存所有 Webhook 通道到加密数据库
  Future<void> saveChannels(List<Map<String, dynamic>> channels) async {
    // 1. 主存储：加密 SQLCipher
    final dbRows = channels.map((c) {
      final row = Map<String, dynamic>.from(c);
      // 确保有正确的 DB 字段
      row['url'] = c['url'] ?? '';
      row['channel_type'] =
          c['channelType']?.toString() ?? c['type']?.toString() ?? 'generic';
      row['name'] = c['name'] ?? '';
      row['secret'] = c['secret'];
      return row;
    }).toList();
    await _db.saveWebhookChannels(dbRows);

    // 2. 同步到原生端
    try {
      await AppChannels.notification.invokeMethod('setWebhookChannels', {
        'channels': channels,
      });
    } catch (e) {
      debugPrint('WebhookService: 同步到原生端失败: $e');
    }

    _channels = channels;
    await _syncEnabledUrls();
  }

  /// 同步启用的 URL 到原生端
  Future<void> _syncEnabledUrls() async {
    final enabledUrls = _channels
        .where((c) => c['enabled'] == true)
        .map((c) => c['url'] as String)
        .toList();

    try {
      await AppChannels.notification.invokeMethod('setWebhookUrls', {
        'urls': enabledUrls,
      });
    } catch (e) {
      debugPrint('WebhookService: 同步启用URL失败: $e');
    }
  }

  /// DB 行格式 → UI 使用的 camelCase 格式
  Map<String, dynamic> _dbRowToUi(Map<String, dynamic> row) {
    return {
      'id': row['id'],
      'name': row['name'],
      'url': row['url'],
      'channelType': row['channel_type'] ?? 'generic',
      'type': row['channel_type'] ?? 'generic',
      'enabled': row['enabled'] == 1 || row['enabled'] == true,
      'secret': row['secret'],
    };
  }
}
