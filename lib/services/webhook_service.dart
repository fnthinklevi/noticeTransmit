import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import 'channel_config_codec.dart';
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
    // 写加密副本（C2）：flutter_secure_storage 加密文件（EncryptedSharedPreferences），
    // 原生端 SecurePrefs 用同一文件/主密钥读取 `secure_webhook_channels`，含 secret。
    // 与原生 setWebhookChannels 的写入同 key 同值（幂等），双端均保持最新 ——
    // 「同值」由下面两处都走 [ChannelConfigCodec.webhookToNative] 保证，不再各发一份。
    final native = _channels
        .map<Map<String, dynamic>>(ChannelConfigCodec.webhookToNative)
        .toList();
    try {
      await SecureStorageService().saveWebhookChannels(jsonEncode(native));
    } catch (e) {
      debugPrint('WebhookService: 写入加密副本失败: $e');
    }
    try {
      await AppChannels.notification.invokeMethod('setWebhookChannels', {
        'channels': native,
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
    // DB 行契约（列名、'null' 脏数据清洗）统一在 ChannelConfigCodec
    final dbRows = channels
        .map<Map<String, dynamic>>(ChannelConfigCodec.webhookToDb)
        .toList();
    await _db.saveWebhookChannels(dbRows);

    // ⚠ 内存里必须存**归一化后的形状**，不是调用方传进来的原始 Map：
    // 调用方可能是备份恢复（文件里的形状不可信：`enabled` 可能是 0/1、键可能是 snake_case），
    // 而设置页按 UI 形状读它并做过硬转型 —— 一旦 DB 形状漏进内存，页面直接打死、
    // 表现为"恢复备份后打不开 webhook 设置页"。走一遍 codec 就等于复用 loadChannels 的归一化。
    _channels = dbRows
        .map<Map<String, dynamic>>(ChannelConfigCodec.webhookFromDb)
        .toList();

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

  /// DB 行格式 → UI 使用的 camelCase 格式（映射规则见 [ChannelConfigCodec]）
  Map<String, dynamic> _dbRowToUi(Map<String, dynamic> row) =>
      ChannelConfigCodec.webhookFromDb(row);
}
