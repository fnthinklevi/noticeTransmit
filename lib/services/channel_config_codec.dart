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

  // ── 主备角色（T11）────────────────────────────────────────────────────
  //
  // 三族共用同一套取值。存 DB 列 `role`、进 UI 与原生载荷都叫 `role`。
  //
  // ⚠ 缺省与非法值一律按 **primary**：
  //   - 老库/老备份没有这一列 ⇒ 它们本来就是"全量推给每条通道"，primary 才不改语义；
  //   - 读到不认识的值只可能来自更新的版本或手改的文件，此时**宁可多推一条也不静默不推**
  //     （none 会让这条通道彻底不出现在推送里，误判成 none 就是丢通知）。

  /// 主通道：正常路径，全量推。
  static const String rolePrimary = 'primary';

  /// 备用通道：**只在所有主通道都不可用时**才推（判据见 T12）。
  static const String roleBackup = 'backup';

  /// 不参与推送：保留配置但不推（与"关掉启用开关"不同，这里是为了主备编排时排除它）。
  static const String roleNone = 'none';

  /// 任意形状的角色值 → 规范值。
  static String normalizeRole(Object? value) {
    final text = nullableText(value)?.trim().toLowerCase();
    if (text == roleBackup || text == roleNone) return text!;
    return rolePrimary;
  }

  // ── Webhook ──────────────────────────────────────────────────────────

  /// DB 行 → UI
  static Map<String, dynamic> webhookFromDb(Map<String, dynamic> row) {
    final url = row['url']?.toString() ?? '';
    var channelType =
        row['channel_type']?.toString() ??
        row['channelType']?.toString() ??
        row['type']?.toString() ??
        '';
    // 仅当历史数据未存渠道类型（空值）时按 URL 识别；显式保存的 generic 视为
    // 用户手动选择，不重探测覆盖。
    if (channelType.isEmpty) {
      channelType = WebhookChannel.detectTypeFromUrl(url).value;
    }
    return {
      'id': row['id']?.toString() ?? '',
      'name': row['name'] ?? '',
      'url': url,
      'channelType': channelType,
      'type': channelType,
      'enabled': flag(row['enabled']),
      'role': normalizeRole(row['role']),
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
    // ⚠ 必须连 DB 列名一起认：备份恢复传进来的行可能只有 `channel_type`（文件形状不受控），
    // 只读 camel 键会把通道类型静默写成 generic —— 恢复一次备份就丢一次类型。
    row['channel_type'] =
        ui['channelType']?.toString() ??
        ui['type']?.toString() ??
        ui['channel_type']?.toString() ??
        'generic';
    row['name'] = ui['name'] ?? '';
    row['role'] = normalizeRole(ui['role']);
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
    // role **显式给**，不靠"整份拷贝"：调用方可能是备份恢复（文件形状不受控，
    // 老文件就没有这个键），漏给原生 = 原生按主通道读，用户设的"备用/不参与"失效。
    // 这条是 channel_config_codec_test 的跨端键集合守卫抓出来的。
    payload['role'] = normalizeRole(ui['role']);
    return payload;
  }

  // ── 自建应用通道 ─────────────────────────────────────────────────────

  /// DB 行 → UI（`config` 的 JSON 字符串解码成 Map）
  static Map<String, dynamic> appFromDb(Map<String, dynamic> row) {
    Map<String, dynamic> config = {};
    final rawConfig = row['config'];
    if (rawConfig is Map) {
      // 内存里的行可能已经是 Map（appToDb 不编码，编码在 DatabaseHelper 落库时做）
      config = Map<String, dynamic>.from(rawConfig);
    } else {
      final raw = nullableText(rawConfig);
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
    }
    // ⚠ 两套键名都要认：本函数现在同时是"DB 行 → UI"和"任意形状 → 规范 UI"的归一化器
    // （saveChannels 保存后也走它）。只读 snake 的话，把 UI 形状喂进来会得到
    // appType='wecom_app'、baseUrl=''、config={} —— 等于把飞书通道改成企微并丢掉扩展参数。
    return {
      'id': row['id']?.toString() ?? '',
      'name': row['name'] ?? '',
      'appType':
          row['app_type']?.toString() ??
          row['appType']?.toString() ??
          'wecom_app',
      'baseUrl':
          row['base_url']?.toString() ?? row['baseUrl']?.toString() ?? '',
      'enabled': flag(row['enabled']),
      'role': normalizeRole(row['role']),
      'secret': nullableText(row['secret']),
      'config': config,
      'message_format': row['message_format'] ?? 'default',
    };
  }

  /// UI → DB 行（config 编码成 JSON 字符串；键名沿用 DatabaseHelper 期望）
  static Map<String, dynamic> appToDb(Map<String, dynamic> ui) {
    final row = Map<String, dynamic>.from(ui);
    // 同上：`app_type` / `base_url` 是 DB 与原生载荷用的键名，备份文件里可能就是这套，
    // 不认就会把飞书通道静默改成企微（类型丢+基址丢，属数据级缺陷）。
    row['appType'] =
        ui['appType']?.toString() ?? ui['app_type']?.toString() ?? 'wecom_app';
    row['name'] = ui['name'] ?? '';
    row['role'] = normalizeRole(ui['role']);
    row['baseUrl'] =
        ui['baseUrl']?.toString() ?? ui['base_url']?.toString() ?? '';
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
    'role': normalizeRole(ui['role']),
  };

  /// UI → 「测试 / 非侵入探测」载荷（`testAppChannel` 与 6e 的 `probeAppChannelToken` 共用一份）。
  ///
  /// ⚠ 与 [appToNative] **不是同一套键**：下发给 `ConfigManager` 的那份读 `type` / `base_url`
  /// （与表列名同源），而这两个方法的原生入口读 `appType` / `baseUrl`（UI 口径）。
  /// 两套键并存的风险是"探测说通、实发失败"这类分裂没人发现 ⇒ 原生实际读的键集合
  /// 由 `channel_config_codec_test` 的跨语言守卫钉住（它去解析
  /// `MainActivity.appChannelTarget` 里的 `configMap["…"]`），键名一漂移就红。
  static Map<String, dynamic> appProbePayload(Map<String, dynamic> ui) => {
    'appType': ui['appType'],
    'name': ui['name'] ?? '',
    'baseUrl': ui['baseUrl']?.toString() ?? '',
    'secret': ui['secret'],
    'config': ui['config'] ?? <String, dynamic>{},
  };

  static Map<String, dynamic> _decodeOrEmpty(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return <String, dynamic>{};
  }
}
