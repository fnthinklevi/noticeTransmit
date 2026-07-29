import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../models/email_channel.dart';
import 'platform_channel.dart';

/// 邮件通道持久化服务
///
/// 存储策略（v1.5.46+）：
///   1. 主存储 → 加密 SQLCipher 数据库（email_channels 表，AES-256）
///   2. 同步到原生端 → MethodChannel（供后台 NotificationMonitorService 读取）
class EmailService {
  final DatabaseHelper _db = DatabaseHelper();
  List<EmailChannel> cachedChannels = [];
  final Map<String, bool> cachedTestResults = {};
  static const _testResultsKey = 'email_test_results';

  /// 加载通道时同步恢复测试结果
  Future<void> _loadTestResults() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final data = prefs.getString(_testResultsKey);
      if (data != null) {
        final map = jsonDecode(data) as Map<String, dynamic>;
        cachedTestResults.clear();
        map.forEach((k, v) => cachedTestResults[k] = v == true);
      }
    } catch (_) {}
  }

  /// 持久化测试结果
  Future<void> saveTestResult(String channelId, bool success) async {
    cachedTestResults[channelId] = success;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_testResultsKey, jsonEncode(cachedTestResults));
    } catch (e) {
      debugPrint('EmailService: 保存测试结果失败: $e');
    }
  }

  /// 保存所有邮件通道（含密码）到加密数据库
  Future<void> saveChannels(List<EmailChannel> channels) async {
    cachedChannels = List.from(channels);

    // 1. 主存储：加密 SQLCipher
    await _db.saveEmailChannels(
      channels.map((c) => c.toMap(includePassword: true)).toList(),
    );

    // 2. 同步到原生端（供后台服务分发使用）
    await _syncToNative(channels);
  }

  /// 从加密数据库加载邮件通道（含密码），若无数据则从旧存储迁移
  Future<List<EmailChannel>> loadChannels() async {
    var rows = await _db.getEmailChannels();
    if (rows.isEmpty) {
      rows = await _migrateFromLegacyStorage();
    }
    final channels = rows.map((row) => EmailChannel.fromDbRow(row)).toList();

    cachedChannels = List.from(channels);
    await _loadTestResults();
    return channels;
  }

  /// 从旧 SharedPreferences 迁移到加密数据库
  Future<List<Map<String, dynamic>>> _migrateFromLegacyStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('email_channels');
      if (list == null || list.isEmpty) return [];

      final channels = list
          .map((s) => jsonDecode(s) as Map<String, dynamic>)
          .toList();
      if (channels.isNotEmpty) {
        await _db.saveEmailChannels(channels);
        return channels;
      }
    } catch (_) {}
    return [];
  }

  /// 同步到原生端（含密码），供后台 NotificationMonitorService 分发邮件
  Future<void> _syncToNative(List<EmailChannel> channels) async {
    try {
      await AppChannels.notification.invokeMethod('setEmailChannels', {
        'channels': channels
            .map((c) => c.toMap(includePassword: true))
            .toList(),
      });
    } catch (e) {
      debugPrint('EmailService: 同步到原生端失败: $e');
    }
  }

  /// 测试邮件发送，返回 {success: bool, message: String}
  Future<Map<String, dynamic>?> testEmail(EmailChannel channel) async {
    try {
      final result = await AppChannels.notification.invokeMethod(
        'testEmail',
        channel.toMap(includePassword: true),
      );
      if (result is Map) {
        return {
          'success': result['success'] == true,
          'message': result['message']?.toString() ?? '未知结果',
        };
      }
      return {'success': false, 'message': '未收到服务端响应'};
    } catch (e) {
      debugPrint('EmailService: 测试邮件失败: $e');
      return {'success': false, 'message': '测试异常: $e'};
    }
  }
}
