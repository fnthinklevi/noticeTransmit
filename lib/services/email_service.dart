import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_helper.dart';
import '../models/email_channel.dart';
import 'channel_health_store.dart';
import 'platform_channel.dart';

/// 邮件通道持久化服务
///
/// 存储策略（v1.5.46+）：
///   1. 主存储 → 加密 SQLCipher 数据库（email_channels 表，AES-256）
///   2. 同步到原生端 → MethodChannel（供后台 NotificationMonitorService 读取）
class EmailService {
  final EmailChannelStore _db;

  /// [store] 用于测试注入伪存储；默认使用 SQLCipher 加密库 [DatabaseHelper]
  EmailService({EmailChannelStore? store}) : _db = store ?? DatabaseHelper();

  List<EmailChannel> cachedChannels = [];

  /// 测试结果落**健康度单点**（第 6 步）。此前这里是自己一个 `email_test_results`
  /// JSON Map：没有时间戳（说不出「多久以前」）也没有耗时，于是首页的邮件状态与
  /// webhook / 应用通道页的徽标是三套行为。旧键由 `ChannelHealthStore.load()` 读穿迁移。
  Future<void> saveTestResult(
    String channelId,
    bool success, {
    int latencyMs = 0,
  }) => GetIt.instance<ChannelHealthStore>().record(
    'email',
    channelId,
    reachable: success,
    latencyMs: latencyMs,
  );

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

  // ── 单条写入咽喉（T08-C2，与 webhook / 自建应用两族同形）────────────────
  //
  // 页面过去攥着整表快照做"只改一条"：任何一次列表错位都会覆盖别的通道，而邮件页
  // 的编辑弹层每次新建 9 个 controller、按下标写回（`_channels[index] = channel`），
  // 是同一类缺陷的另一个实例。底层仍是整表写（改 DB 会牵动迁移与备份格式），
  // 但**页面拿不到整表**：它只交出正在编辑的那一条。
  //
  // ⚠ 三个方法都以**数据库当前内容**为准做合并，不读 `cachedChannels`：
  // 内存缓存可能是空的（本进程从没 load 过），拿它当基线会把整表写成只剩这一条。

  /// 按 id 就地替换；id 不在表里（新增）则追加。
  Future<void> saveChannel(EmailChannel channel) async {
    final current = await loadChannels();
    final i = channel.id.isEmpty
        ? -1
        : current.indexWhere((c) => c.id == channel.id);
    if (i >= 0) {
      current[i] = channel;
    } else {
      current.add(channel);
    }
    await saveChannels(current);
  }

  /// 删除一条；**找不到就返回 false 且一个字都不写**（避免"删不掉却把表重写一遍"）。
  Future<bool> deleteChannel(String id) async {
    final current = await loadChannels();
    final before = current.length;
    current.removeWhere((c) => c.id == id);
    if (current.length == before) return false;
    await saveChannels(current);
    return true;
  }

  /// 只翻启停：其余字段原样（页面不再为了改一个开关重建整表）。
  Future<bool> setEnabled(String id, bool enabled) async {
    final current = await loadChannels();
    final i = current.indexWhere((c) => c.id == id);
    if (i < 0) return false;
    current[i] = current[i].copyWith(enabled: enabled);
    await saveChannels(current);
    return true;
  }

  /// 从加密数据库加载邮件通道（含密码），若无数据则从旧存储迁移
  Future<List<EmailChannel>> loadChannels() async {
    var rows = await _db.getEmailChannels();
    if (rows.isEmpty) {
      rows = await _migrateFromLegacyStorage();
    }
    final channels = rows.map((row) => EmailChannel.fromDbRow(row)).toList();

    cachedChannels = List.from(channels);
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
