import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../models/webhook_channel.dart';
import 'platform_channel.dart';
import 'secure_storage_service.dart';

/// Webhook 通道持久化服务
///
/// 存储策略（v1.5.46+）：
///   1. 主存储 → 加密 SQLCipher 数据库（webhook_channels 表，AES-256）
///   2. 同步到原生端 → MethodChannel（供后台 NotificationMonitorService 读取 URL）
class WebhookService {
  final WebhookChannelStore _db;

  /// [store] 用于测试注入伪存储；默认使用 SQLCipher 加密库 [DatabaseHelper]
  WebhookService({WebhookChannelStore? store})
    : _db = store ?? DatabaseHelper();

  List<Map<String, dynamic>> _channels = [];
  List<Map<String, dynamic>> get channels => _channels;

  /// 从加密数据库加载 Webhook 通道，若无数据则从旧存储迁移
  Future<void> loadChannels() async {
    _channels = await _db.getWebhookChannels();
    if (_channels.isEmpty) {
      _channels = await _migrateFromLegacyStorage();
    }
    _channels = _channels.map((row) => _dbRowToUi(row)).toList();
    // 同步完整通道到原生端（含 secret/type/template），确保后台服务始终能读到
    await _syncToNative();
  }

  /// 同步完整通道配置 + 启用 URL 到原生端
  Future<void> _syncToNative() async {
    try {
      await AppChannels.notification.invokeMethod('setWebhookChannels', {
        'channels': _channels,
      });
    } catch (e) {
      debugPrint('WebhookService: 同步通道到原生端失败: $e');
    }
    await _syncEnabledUrls();
  }

  /// 从旧存储（flutter_secure_storage / SharedPreferences）迁移到加密数据库
  Future<List<Map<String, dynamic>>> _migrateFromLegacyStorage() async {
    List<Map<String, dynamic>> channels = [];

    // 1. 尝试 flutter_secure_storage
    try {
      final ss = SecureStorageService();
      final jsonStr = await ss.loadWebhookChannels();
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final list = jsonDecode(jsonStr) as List<dynamic>;
        channels = list.map((e) => Map<String, dynamic>.from(e)).toList();
        if (channels.isNotEmpty) {
          await _db.saveWebhookChannels(channels);
          return channels;
        }
      }
    } catch (_) {}

    // 2. 尝试 SharedPreferences 旧格式
    try {
      final prefs = await SharedPreferences.getInstance();
      final urlsJson = prefs.getString('webhook_channels');
      if (urlsJson != null) {
        final list = jsonDecode(urlsJson) as List<dynamic>;
        channels = list.map((e) {
          final m = Map<String, dynamic>.from(e);
          m['channel_type'] = m['type']?.toString() ?? 'generic';
          m['url'] = m['url'] ?? '';
          m['name'] = m['name'] ?? '';
          return m;
        }).toList();
        if (channels.isNotEmpty) {
          await _db.saveWebhookChannels(channels);
          // 迁移完成后清理明文源头，避免 webhook 密钥以明文 XML 永久残留
          await prefs.remove('webhook_channels');
          return channels;
        }
      }
    } catch (_) {}

    // 3. 尝试最旧单 URL 格式
    try {
      final prefs = await SharedPreferences.getInstance();
      final singleUrl = prefs.getString('webhook_url');
      if (singleUrl != null && singleUrl.isNotEmpty) {
        channels = [
          {
            'id': 'legacy_1',
            'url': singleUrl,
            'name': '旧配置',
            'channel_type': 'generic',
            'enabled': true,
          },
        ];
        await _db.saveWebhookChannels(channels);
        // 迁移完成后清理明文源头，避免 webhook URL 以明文 XML 永久残留
        await prefs.remove('webhook_url');
        return channels;
      }
    } catch (_) {}

    return [];
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
      row['secret'] = c['secret'] == 'null' ? null : c['secret'];
      // 过滤历史脏数据：旧版本 JSON 序列化曾把 null 存成字符串 "null"
      row['message_format'] = c['message_format'] ?? 'default';
      row['message_template'] = c['message_template'] == 'null'
          ? null
          : c['message_template'];
      return row;
    }).toList();
    await _db.saveWebhookChannels(dbRows);

    _channels = channels;

    // 同步到原生端（完整通道 + 启用 URL）
    await _syncToNative();
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
    final url = row['url']?.toString() ?? '';
    var channelType = row['channel_type']?.toString() ?? '';
    // 仅当历史数据未存渠道类型（空值）时按 URL 识别；显式保存的 generic 视为用户手动选择，不重探测覆盖
    if (channelType.isEmpty) {
      channelType = WebhookChannel.detectTypeFromUrl(url).value;
    }
    return {
      'id': row['id'],
      'name': row['name'],
      'url': url,
      'channelType': channelType,
      'type': channelType,
      'enabled': row['enabled'] == 1 || row['enabled'] == true,
      // 旧版本 JSON 序列化曾把 null 存成字符串 "null"，此处过滤，避免误判已配置
      'secret': row['secret'] == 'null' ? null : row['secret'],
      // v6: 推送模板系统字段（UI 展示 / 再次保存时透传，防止重启后模板丢失）
      'message_format': row['message_format'] ?? 'default',
      'message_template': row['message_template'] == 'null'
          ? null
          : row['message_template'],
    };
  }
}
