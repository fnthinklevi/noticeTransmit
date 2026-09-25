import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

enum WebhookChannelType {
  generic,
  wechatWork,
  dingtalk,
  feishu,
  telegram,
  bark,
  serverChan,
  pushPlus,
  ntfy,
  gotify,
  slack,
  discord,
}

extension WebhookChannelTypeExtension on WebhookChannelType {
  String get value {
    switch (this) {
      case WebhookChannelType.generic:
        return 'generic';
      case WebhookChannelType.wechatWork:
        return 'wechat_work';
      case WebhookChannelType.dingtalk:
        return 'dingtalk';
      case WebhookChannelType.feishu:
        return 'feishu';
      case WebhookChannelType.telegram:
        return 'telegram';
      case WebhookChannelType.bark:
        return 'bark';
      case WebhookChannelType.serverChan:
        return 'server_chan';
      case WebhookChannelType.pushPlus:
        return 'push_plus';
      case WebhookChannelType.ntfy:
        return 'ntfy';
      case WebhookChannelType.gotify:
        return 'gotify';
      case WebhookChannelType.slack:
        return 'slack';
      case WebhookChannelType.discord:
        return 'discord';
    }
  }

  // 签名能力与提示文案只在 UI 层判定（webhook_settings_page 的
  // _supportsSigning / _signingHint，提示走 l10n）。此处此前另存过一份
  // supportsSigning（12 臂全 false）与 signingHint（硬编码中文），零调用点、
  // 且与 UI 判定矛盾（UI 排除 6 个平台，这里全 false）——已删，勿再留第二处真相。
}

// 消息格式档位不再是 Dart 枚举（T08-B）：名单只在原生 `TemplateEngine.formatOptions`，界面用 token 字符串。
// 枚举的两个恶果都修掉了：加一个格式要改两处；`fromValue` 会把不认得的存量值静默回退成 default
// （用户打开设置页看一眼，存着的格式就被改了）。
class WebhookChannel {
  final String id;
  final String name;
  final String url;
  final WebhookChannelType type;
  final bool enabled;
  final String? secret;

  /// 消息格式档位（token 字符串，名单来自原生 `TemplateEngine.formatOptions`）。
  final String messageFormat;
  final String? messageTemplate;

  WebhookChannel({
    required this.id,
    this.name = '',
    required this.url,
    required this.type,
    this.enabled = true,
    this.secret,
    this.messageFormat = 'default',
    this.messageTemplate,
  });

  /// 平台 host 匹配规则（与 Kotlin 端 `ChannelRegistry` 各通道的 `hosts` 一致；
  /// 一致性由 `channel_descriptor_export_contract_test` 按导出快照核对）
  static const _platformRules = <(WebhookChannelType, List<String>)>[
    (WebhookChannelType.wechatWork, ['qyapi.weixin.qq.com']),
    (WebhookChannelType.dingtalk, ['oapi.dingtalk.com']),
    (WebhookChannelType.feishu, ['open.feishu.cn', 'open.larksuite.com']),
    (WebhookChannelType.telegram, ['api.telegram.org']),
    (WebhookChannelType.bark, ['api.day.app', 'bark.gugu.ovh']),
    (WebhookChannelType.serverChan, ['sctapi.ftqq.com']),
    (WebhookChannelType.pushPlus, ['www.pushplus.plus', 'pushplus.plus']),
    // ntfy 官方托管 host 可枚举（原生侧同一张表里有它）：漏这一行的表现是
    // URL 填 ntfy.sh 时界面显示「自动识别 · 通用 Webhook」，而原生按 ntfy 发送
    // （text/plain + Bearer 头）—— 显示与判定分叉。跨语言一致性由
    // channel_descriptor_export_contract_test 按导出快照核对。
    (WebhookChannelType.ntfy, ['ntfy.sh']),
    (WebhookChannelType.slack, ['hooks.slack.com']),
    (WebhookChannelType.discord, ['discord.com', 'discordapp.com']),
    // 自建 ntfy / Gotify 的 host 不可枚举：类型由用户手动选择
    //（detectTypeFromUrl 兜底 generic，原生侧同样回退 GENERIC）
  ];

  /// 仅供跨语言一致性守卫读取（`channel_descriptor_export_contract_test`）
  @visibleForTesting
  static List<(WebhookChannelType, List<String>)> get platformRules =>
      _platformRules;

  static WebhookChannelType detectTypeFromUrl(String url) {
    final host = _extractHost(url);
    if (host == null) return WebhookChannelType.generic;

    // host 精确匹配（与 Kotlin 端一致），新增平台只需在 _platformRules 中追加一行
    for (final (type, hosts) in _platformRules) {
      if (hosts.contains(host)) return type;
    }
    return WebhookChannelType.generic;
  }

  /// 从 URL 提取小写 host（与 Kotlin 端 WebhookPayloadBuilder.extractHost 保持一致）。
  static String? _extractHost(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return null;

    // 优先使用 Dart 的 Uri 解析，正确提取 host（含端口、凭据等边界场景）
    try {
      final uri = Uri.parse(trimmed);
      final host = uri.host;
      if (host.isNotEmpty) return host.toLowerCase();
    } catch (_) {
      // 解析失败时走下方手动兜底
    }

    var lower = trimmed.toLowerCase();
    if (lower.startsWith('https://')) {
      lower = lower.substring(8);
    } else if (lower.startsWith('http://')) {
      lower = lower.substring(7);
    }
    // 找到 host 结束位置（首个 / ? # 之一）
    var endIdx = -1;
    for (final ch in const ['/', '?', '#']) {
      final i = lower.indexOf(ch);
      if (i >= 0 && (endIdx < 0 || i < endIdx)) endIdx = i;
    }
    final hostPort = endIdx >= 0 ? lower.substring(0, endIdx) : lower;
    if (hostPort.isEmpty) return null;
    // 去掉 credentials（user:pass@host）中的 userinfo 部分
    final atIdx = hostPort.lastIndexOf('@');
    final hostWithOptionalPort = atIdx >= 0
        ? hostPort.substring(atIdx + 1)
        : hostPort;
    // 去掉端口（webhook URL 不会用到 IPv6 字面量 host）
    final colonIdx = hostWithOptionalPort.lastIndexOf(':');
    final host = colonIdx >= 0
        ? hostWithOptionalPort.substring(0, colonIdx)
        : hostWithOptionalPort;
    return host.isEmpty ? null : host;
  }

  factory WebhookChannel.fromMap(Map<String, dynamic> map) {
    final url = map['url'] as String? ?? '';
    final typeStr = map['type'] as String?;
    WebhookChannelType type;
    if (typeStr != null) {
      type = WebhookChannelType.values.firstWhere(
        (t) => t.value == typeStr,
        orElse: () {
          debugPrint('警告：未知的 WebhookChannelType 值: $typeStr，使用 URL 检测');
          return detectTypeFromUrl(url);
        },
      );
    } else {
      type = detectTypeFromUrl(url);
    }
    return WebhookChannel(
      id: map['id'] as String? ?? const Uuid().v4(),
      name: map['name'] as String? ?? '',
      url: url,
      type: type,
      enabled: map['enabled'] as bool? ?? true,
      secret: map['secret'] as String?,
      // 原样收下，不认识的也留着：旧实现回退成 default，等于"看一眼页面就改设置"
      messageFormat: map['message_format'] as String? ?? 'default',
      messageTemplate: map['message_template'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'type': type.value,
      'enabled': enabled,
      if (secret != null && secret!.isNotEmpty) 'secret': secret,
      'message_format': messageFormat,
      if (messageTemplate != null && messageTemplate!.isNotEmpty)
        'message_template': messageTemplate,
    };
  }

  WebhookChannel copyWith({
    String? id,
    String? name,
    String? url,
    WebhookChannelType? type,
    bool? enabled,
    String? secret,
    String? messageFormat,
    String? messageTemplate,
  }) {
    return WebhookChannel(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
      secret: secret ?? this.secret,
      messageFormat: messageFormat ?? this.messageFormat,
      messageTemplate: messageTemplate ?? this.messageTemplate,
    );
  }
}
