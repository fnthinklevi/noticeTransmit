import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../database/database_helper.dart';
import 'platform_channel.dart';

/// 自建应用通道服务（应用通道体系，与 WebhookService 并列）。
///
/// 管理企微自建应用 / 飞书自建应用等通道：配置存于加密 DB（app_channels 表），
/// 经 MethodChannel 同步到原生（SecurePrefs），原生经 AppChannelSender 走
/// 「凭据换 token → 消息端点」两阶段推送；送达结果回传与 webhook 通道同链路。
class AppChannelService {
  static const _channel = AppChannels.notification;

  final AppChannelStore _store;

  AppChannelService({AppChannelStore? store})
    : _store = store ?? DatabaseHelper();

  List<Map<String, dynamic>> _channels = [];
  List<Map<String, dynamic>> get channels => _channels;

  int get enabledCount => _channels.where((c) => c['enabled'] == true).length;

  /// 加载通道（DB）并同步原生
  Future<void> loadChannels() async {
    final rows = await _store.getAppChannels();
    _channels = rows.map(_rowToUi).toList();
    await _syncToNative();
  }

  /// 保存通道（归一化 → DB → 同步原生）
  Future<void> saveChannels(List<Map<String, dynamic>> channels) async {
    final normalized = channels.map((c) {
      final row = Map<String, dynamic>.from(c);
      row['appType'] = c['appType']?.toString() ?? 'wecom_app';
      row['name'] = c['name'] ?? '';
      row['baseUrl'] = c['baseUrl']?.toString() ?? '';
      row['secret'] = c['secret'] == 'null' ? null : c['secret'];
      row['message_format'] = c['message_format']?.toString() ?? 'default';
      // config 统一为 Map（UI 编辑态），DB 层负责 JSON 序列化
      if (row['config'] is String) {
        try {
          row['config'] = jsonDecode(row['config'] as String);
        } catch (_) {
          row['config'] = <String, dynamic>{};
        }
      }
      row['config'] ??= <String, dynamic>{};
      return row;
    }).toList();
    await _store.saveAppChannels(normalized);
    _channels = normalized;
    await _syncToNative();
  }

  /// 原生同步：完整通道（含 secret）交由 AppChannelSender 使用
  Future<void> _syncToNative() async {
    try {
      await _channel.invokeMethod('setAppChannels', {'channels': _channels});
    } catch (e) {
      debugPrint('AppChannelService: 同步自建应用通道失败: $e');
    }
  }

  /// DB 行 → UI Map
  Map<String, dynamic> _rowToUi(Map<String, dynamic> row) {
    Map<String, dynamic> config = {};
    final raw = row['config']?.toString();
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) config = decoded;
      } catch (_) {}
    }
    return {
      'id': row['id'],
      'name': row['name'] ?? '',
      'appType': row['app_type']?.toString() ?? 'wecom_app',
      'baseUrl': row['base_url']?.toString() ?? '',
      'enabled': row['enabled'] == 1 || row['enabled'] == true,
      'secret': row['secret'] == 'null' ? null : row['secret'],
      'config': config,
      'message_format': row['message_format'] ?? 'default',
    };
  }
}
