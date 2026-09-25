import 'package:flutter/foundation.dart';

import '../database/database_helper.dart';
import 'channel_config_codec.dart';
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
    _channels = rows
        .map<Map<String, dynamic>>(ChannelConfigCodec.appFromDb)
        .toList();
    await _syncToNative();
  }

  /// 保存通道（归一化 → DB → 同步原生）
  Future<void> saveChannels(List<Map<String, dynamic>> channels) async {
    final normalized = channels
        .map<Map<String, dynamic>>(ChannelConfigCodec.appToDb)
        .toList();
    await _store.saveAppChannels(normalized);
    // 与 WebhookService 同一条规矩：内存里放**归一化后的 UI 形状**，
    // 不要把 DB 行（config 是 JSON 字符串、enabled 是 0/1）直接当 UI 列表用。
    _channels = normalized
        .map<Map<String, dynamic>>(ChannelConfigCodec.appFromDb)
        .toList();
    await _syncToNative();
  }

  /// 保存/新增**一条**通道（T07：「列表页 → 单通道详情页」的写入咽喉）。
  ///
  /// 底层仍是整表 delete+insert（`app_channels` 没有按 id 的 UPDATE 路径，动 DB 会牵动
  /// 迁移与备份格式），但**调用方只描述一条**：同 id 就地替换（与已有行合并，没提到的
  /// 键保留原值），id 为空则追加。此前详情页自己攥着整表、保存时整表重写 ⇒ 从列表进来
  /// 只改一条时，别的通道会被这份快照覆盖掉。
  Future<void> saveChannel(Map<String, dynamic> channel) async {
    final id = ChannelConfigCodec.nullableText(channel['id']) ?? '';
    final next = List<Map<String, dynamic>>.from(_channels);
    final at = id.isEmpty
        ? -1
        : next.indexWhere(
            (c) => (ChannelConfigCodec.nullableText(c['id']) ?? '') == id,
          );
    if (at >= 0) {
      next[at] = <String, dynamic>{...next[at], ...channel};
    } else {
      next.add(channel);
    }
    await saveChannels(next);
  }

  /// 删除一条通道（按 id）。找不到就什么都不做 —— 静默"保存成功"比不保存更糟。
  /// 返回是否真的删掉了，调用据此决定要不要清健康缓存。
  Future<bool> deleteChannel(String id) async {
    if (id.isEmpty) return false;
    final next = _channels
        .where((c) => (ChannelConfigCodec.nullableText(c['id']) ?? '') != id)
        .toList();
    if (next.length == _channels.length) return false;
    await saveChannels(next);
    return true;
  }

  /// 启停一条通道（列表页的开关用；不碰其它行）。
  Future<void> setEnabled(String id, bool enabled) async {
    final next = _channels
        .map<Map<String, dynamic>>(
          (c) => (ChannelConfigCodec.nullableText(c['id']) ?? '') == id
              ? <String, dynamic>{...c, 'enabled': enabled}
              : c,
        )
        .toList();
    await saveChannels(next);
  }

  /// 原生同步：完整通道（含 secret）交由 AppChannelSender 使用。
  ///
  /// 只在这里做 UI → 原生契约键的映射（见 [toNativePayload]），`_channels` 保持
  /// UI 形状供页面与送达标签使用。
  Future<void> _syncToNative() async {
    try {
      await _channel.invokeMethod('setAppChannels', {
        'channels': _channels.map(toNativePayload).toList(),
      });
    } catch (e) {
      debugPrint('AppChannelService: 同步自建应用通道失败: $e');
    }
  }

  /// 自建应用通道的跨端契约边界：原生 `ConfigManager.getAppChannelConfigs()` 读的是
  /// `type` / `base_url`（与 app_channels 表列名同源），UI 侧用的是 `appType` / `baseUrl`。
  /// 直接把 UI Map 下发会让原生解析出空 type → `AppChannelRegistry.spec("")` 返回 null
  /// → 每条自建应用推送静默落到「未知应用通道类型」，而应用内「测试」按钮走的是另一条
  /// 读 `appType` 的路径，因此表现为「测试成功、真实推送永远失败」。
  static Map<String, dynamic> toNativePayload(Map<String, dynamic> ui) =>
      ChannelConfigCodec.appToNative(ui);
}
