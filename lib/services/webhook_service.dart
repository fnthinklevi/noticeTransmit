import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'platform_channel.dart';

class WebhookService {
  static const _channel = AppChannels.notification;

  List<Map<String, dynamic>> _channels = [];

  List<Map<String, dynamic>> get channels => _channels;

  Future<void> loadChannels() async {
    final prefs = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> channels = [];
    bool loadedFromNative = false;

    try {
      final List<dynamic> result = await _channel.invokeMethod(
        'getWebhookChannels',
      );
      channels = result.map((e) => Map<String, dynamic>.from(e)).toList();
      loadedFromNative = true;
    } catch (e) {
      final urlsJson = prefs.getString('webhook_channels');
      if (urlsJson != null) {
        try {
          final List<dynamic> list = jsonDecode(urlsJson);
          channels = list.map((e) => Map<String, dynamic>.from(e)).toList();
        } catch (_) {
          channels = [];
        }
      } else {
        final oldUrlsJson = prefs.getString('webhook_urls');
        if (oldUrlsJson != null) {
          try {
            final List<dynamic> list = jsonDecode(oldUrlsJson);
            channels = list
                .map((e) => {'url': e.toString(), 'enabled': true})
                .toList();
          } catch (_) {
            channels = [];
          }
        } else {
          final singleUrl = prefs.getString('webhook_url');
          if (singleUrl != null && singleUrl.isNotEmpty) {
            channels = [
              {'url': singleUrl, 'enabled': true},
            ];
          }
        }
      }
    }

    if (loadedFromNative && channels.isNotEmpty) {
      await prefs.setString('webhook_channels', jsonEncode(channels));
    }

    _channels = channels;
    await _syncEnabledUrls();
  }

  Future<void> saveChannels(List<Map<String, dynamic>> channels) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('webhook_channels', jsonEncode(channels));

    try {
      await _channel.invokeMethod('setWebhookChannels', {'channels': channels});
    } catch (e) {
      debugPrint('WebhookService: 保存通道失败: $e');
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
}
