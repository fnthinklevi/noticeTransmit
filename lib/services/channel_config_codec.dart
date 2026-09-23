import 'dart:convert';

import '../models/webhook_channel.dart';

/// 通道配置的**三向映射单点**：UI 形状 ↔ DB 行 ↔ 原生载荷（第 6 步）。
///
/// 为什么要有它：此前 webhook 与自建应用通道各自写一份 camel↔snake 归一化和
/// `'null'` 脏数据清洗（`webhook_service` 两处、`app_channel_service` 两处），
/// 同一件事四份实现，漏洗一处就是「界面上看着有值、原生读到空」——
/// 自建通道 `appType`/`baseUrl` 与原生 `type`/`base_url` 断裂就是这么来的
/// （表现为「测试成功、真实推送永远失败」）。
///
/// ⚠️ 三个方向的键集合**不相同，且都是契约**：
/// - **DB 行**用列名（snake：`channel_type` / `app_type` / `base_url` / `message_format`）；
/// - **UI 形状**给页面用 camel（`channelType` / `baseUrl`），webhook 侧同时保留
///   `type` 别名（历史读者：`notification_service`、送达回传都按 `type` 取）；
/// - **原生载荷**：webhook 走 [webhookToNative]（今天等于 UI 形状 —— 原生只读其中
///   `url`/`type`/`enabled`/`secret`/`message_format`/`message_template`，
///   多余键无害；已有 `webhook_service_save_chain_test` 钉住该形状，改它属契约变更，
///   另开批次），应用通道走 [appToNative]（原生读 `type`/`base_url`，与 UI 键不同名，
///   所以必须显式映射）。
///   两侧都由 `channel_native_payload_test` 跨语言核对「原生读的键我们是否都给了」。
class ChannelConfigCodec {
  ChannelConfigCodec._();

  /// 历史脏数据：老版本 JSON 序列化把 null 写成了字符串 `"null"`。
  /// 不洗掉的后果是「看起来配了密钥/模板」——判空全部失效。
  static String? nullableText(Object? value) {
    if (value == null) return null;
    final text = value.toString();
    return text == 'null' ? null : text;
  }

  /// SQLite 的 BOOLEAN 在 Android 侧存成 0/1，JSON 侧是真 bool：两种都要认。
  static bool flag(Object? value) => value == 1 || value == true;

  // ── Webhook ──────────────────────────────────────────────────────────

  /// DB 行 → UI
  static Map<String, dynamic> webhookFromDb(Map<String, dynamic> row) {
    final url = row['url']?.toString() ?? '';
    var channelType = row['channel_type']?.toString() ?? '';
    // 仅当历史数据未存渠道类型（空值）时按 URL 识别；显式保存的 generic 视为
    // 用户手动选择，不重探测覆盖。
    if (channelType.isEmpty) {
      channelType = WebhookChannel.detectTypeFromUrl(url).value;
    }
    return {
      'id': row['id'],
      'name': row['name'],
      'url': url,
      'channelType': channelType,
      'type': channelType,
      'enabled': flag(row['enabled']),
      'secret': nullableText(row['secret']),
      'message_format': row['message_format'] ?? 'default',
      'message_template': nullableText(row['message_template']),
      // v9 的 extra_config 不再进 UI（roadmap D4 / ㊷）：原生解析了它但全链路无人消费，
      // wecom_app 的 corpid/agentid/touser 早在 v10 搬进 app_channels.config。
      // DB 列保留（见 database_helper 的 DDL 与 v9→v10 搬家 SELECT）。
    };
  }

  /// UI → DB 行（列名 + `'null'` 脏数据清洗）
  ///
  /// 入口是**白名单式整表复制**，所以历史上带过 `extra_config` 的输入（老备份恢复、
  /// 手造 Map）会顺流写进 DB 行与原生载荷。㊷ 按 D4=B 显式摘掉它：列保留在 schema 里，
  /// 但没有任何一条链路再读写它。
  static Map<String, dynamic> webhookToDb(Map<String, dynamic> ui) {
    final row = Map<String, dynamic>.from(ui);
    row.remove('extra_config');
    row.remove('extraConfig');
    row['url'] = ui['url'] ?? '';
    row['channel_type'] =
        ui['channelType']?.toString() ?? ui['type']?.toString() ?? 'generic';
    row['name'] = ui['name'] ?? '';
    row['secret'] = nullableText(ui['secret']);
    row['message_format'] = ui['message_format'] ?? 'default';
    row['message_template'] = nullableText(ui['message_template']);
    return row;
  }

  /// UI → 原生载荷（含 secret；另写进加密副本，两处同形）
  static Map<String, dynamic> webhookToNative(Map<String, dynamic> ui) {
    final payload = Map<String, dynamic>.from(ui);
    payload.remove('extra_config');
    payload.remove('extraConfig');
    return payload;
  }

  // ── 自建应用通道 ─────────────────────────────────────────────────────

  /// DB 行 → UI（`config` 的 JSON 字符串解码成 Map）
  static Map<String, dynamic> appFromDb(Map<String, dynamic> row) {
    Map<String, dynamic> config = {};
    final raw = nullableText(row['config']);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) config = decoded;
      } catch (_) {
        // 坏 JSON 按「无扩展参数」处理：清空比抛异常好（抛在 onUpgrade/加载链上
        // 会连带整表读不出来）
        config = {};
      }
    }
    return {
      'id': row['id'],
      'name': row['name'] ?? '',
      'appType': row['app_type']?.toString() ?? 'wecom_app',
      'baseUrl': row['base_url']?.toString() ?? '',
      'enabled': flag(row['enabled']),
      'secret': nullableText(row['secret']),
      'config': config,
      'message_format': row['message_format'] ?? 'default',
    };
  }

  /// UI → DB 行（config 编码成 JSON 字符串；键名沿用 DatabaseHelper 期望）
  static Map<String, dynamic> appToDb(Map<String, dynamic> ui) {
    final row = Map<String, dynamic>.from(ui);
    row['appType'] = ui['appType']?.toString() ?? 'wecom_app';
    row['name'] = ui['name'] ?? '';
    row['baseUrl'] = ui['baseUrl']?.toString() ?? '';
    row['secret'] = nullableText(ui['secret']);
    row['message_format'] = ui['message_format']?.toString() ?? 'default';
    final config = ui['config'];
    row['config'] = config is String ? _decodeOrEmpty(config) : (config ?? {});
    return row;
  }

  /// UI → 原生载荷：原生 `ConfigManager.getAppChannelConfigs()` 读的是
  /// `type` / `base_url`（与 app_channels 表列名同源），UI 用的是 `appType` / `baseUrl`。
  /// 直接把 UI Map 下发 → 原生解析出空 type → 每条自建应用推送静默落到
  /// 「未知应用通道类型」，而「测试」按钮走另一条读 `appType` 的路径 ⇒
  /// 测试成功、真实推送永远失败（㉑ 实测）。
  static Map<String, dynamic> appToNative(Map<String, dynamic> ui) => {
    'id': ui['id'],
    'name': ui['name'] ?? '',
    'type': ui['appType']?.toString() ?? 'wecom_app',
    'base_url': ui['baseUrl']?.toString() ?? '',
    'secret': ui['secret'],
    'config': ui['config'] ?? <String, dynamic>{},
    'message_format': ui['message_format'] ?? 'default',
    'enabled': ui['enabled'] == true,
  };

  static Map<String, dynamic> _decodeOrEmpty(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return <String, dynamic>{};
  }
}
