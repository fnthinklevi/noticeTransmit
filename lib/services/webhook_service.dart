import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'platform_channel.dart';
import 'secure_storage_service.dart';

class WebhookService {
  static const _channel = AppChannels.notification;

  List<Map<String, dynamic>> _channels = [];
  final SecureStorageService _secureStorage = SecureStorageService();

  List<Map<String, dynamic>> get channels => _channels;

  Future<void> loadChannels() async {
    List<Map<String, dynamic>> channels = [];
    bool loadedFromNative = false;

    // 1. 优先从原生端加载（原生端通过 MethodChannel 接收 Flutter 端数据）
    try {
      final List<dynamic> result = await _channel.invokeMethod(
        'getWebhookChannels',
      );
      channels = result.map((e) => Map<String, dynamic>.from(e)).toList();
      loadedFromNative = true;
    } catch (e) {
      // 2. 原生端加载失败，尝试从加密存储读取
      channels = await _loadFromSecureStorage();
      if (channels.isEmpty) {
        // 3. 加密存储为空，从 SharedPreferences 迁移旧数据
        channels = await _loadFromLegacyStorage();
        if (channels.isNotEmpty) {
          // 首次迁移：写入加密存储并清理明文
          await _saveToSecureStorage(channels);
          await _clearLegacyStorage();
        }
      }
    }

    // 从原生端加载成功后，同步到加密存储
    if (loadedFromNative && channels.isNotEmpty) {
      await _saveToSecureStorage(channels);
    }

    _channels = channels;
    await _syncEnabledUrls();
  }

  Future<void> saveChannels(List<Map<String, dynamic>> channels) async {
    // 1. 主存储：加密保存到 flutter_secure_storage
    await _saveToSecureStorage(channels);

    // 2. 同步到原生端（原生后台服务需要读取这些 URL）
    try {
      await _channel.invokeMethod('setWebhookChannels', {'channels': channels});
    } catch (e) {
      debugPrint('WebhookService: 保存通道到原生端失败: $e');
    }

    _channels = channels;
    await _syncEnabledUrls();
  }

  Future<void> _syncEnabledUrls() async {
    final enabledUrls = _channels
        .where((c) => c['enabled'] == true)
        .map((c) => c['url'] as String)
        .toList();

    if (enabledUrls.isNotEmpty) {
      try {
        await _channel.invokeMethod('setWebhookUrls', {'urls': enabledUrls});
      } catch (e) {
        debugPrint('WebhookService: 同步启用URL失败: $e');
      }
    }
  }

  // ========== 加密存储操作 ==========

  Future<void> _saveToSecureStorage(List<Map<String, dynamic>> channels) async {
    await _secureStorage.saveWebhookChannels(jsonEncode(channels));
  }

  Future<List<Map<String, dynamic>>> _loadFromSecureStorage() async {
    try {
      final jsonStr = await _secureStorage.loadWebhookChannels();
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> list = jsonDecode(jsonStr);
        return list.map((e) => Map<String, dynamic>.from(e)).toList();
      }
    } catch (e) {
      debugPrint('WebhookService: 加密存储读取失败: $e');
    }
    return [];
  }

  // ========== 旧版明文存储（仅用于首次迁移） ==========

  Future<List<Map<String, dynamic>>> _loadFromLegacyStorage() async {
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> channels = [];

    // 尝试新格式
    final urlsJson = prefs.getString('webhook_channels');
    if (urlsJson != null) {
      try {
        final List<dynamic> list = jsonDecode(urlsJson);
        channels = list.map((e) => Map<String, dynamic>.from(e)).toList();
        if (channels.isNotEmpty) return channels;
      } catch (_) {}
    }

    // 尝试旧 URL 列表格式
    final oldUrlsJson = prefs.getString('webhook_urls');
    if (oldUrlsJson != null) {
      try {
        final List<dynamic> list = jsonDecode(oldUrlsJson);
        channels = list
            .map((e) => {'url': e.toString(), 'enabled': true})
            .toList();
        if (channels.isNotEmpty) return channels;
      } catch (_) {}
    }

    // 尝试最旧单 URL 格式
    final singleUrl = prefs.getString('webhook_url');
    if (singleUrl != null && singleUrl.isNotEmpty) {
      channels = [{'url': singleUrl, 'enabled': true}];
    }

    return channels;
  }

  Future<void> _clearLegacyStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('webhook_channels');
      await prefs.remove('webhook_urls');
      await prefs.remove('webhook_url');
    } catch (e) {
      debugPrint('WebhookService: 清理旧存储失败: $e');
    }
  }
}
