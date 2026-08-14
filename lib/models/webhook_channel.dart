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
    }
  }

  String get label {
    switch (this) {
      case WebhookChannelType.generic:
        return '通用 Webhook';
      case WebhookChannelType.wechatWork:
        return '企业微信群机器人';
      case WebhookChannelType.dingtalk:
        return '钉钉群机器人';
      case WebhookChannelType.feishu:
        return '飞书群机器人';
      case WebhookChannelType.telegram:
        return 'Telegram';
      case WebhookChannelType.bark:
        return 'Bark';
      case WebhookChannelType.serverChan:
        return 'Server酱';
      case WebhookChannelType.pushPlus:
        return 'PushPlus';
    }
  }

  /// 是否支持 HMAC 签名（用于 UI 显示 secret 输入框）
  bool get supportsSigning {
    switch (this) {
      case WebhookChannelType.generic:
      case WebhookChannelType.wechatWork:
      case WebhookChannelType.dingtalk:
      case WebhookChannelType.feishu:
        return true;
      case WebhookChannelType.telegram:
      case WebhookChannelType.bark:
      case WebhookChannelType.serverChan:
      case WebhookChannelType.pushPlus:
        return false;
    }
  }

  /// 签名说明文案（用户在 UI 中看到的提示）
  String get signingHint {
    switch (this) {
      case WebhookChannelType.wechatWork:
        return '企业微信群机器人开启「签名校验」后生成的密钥';
      case WebhookChannelType.dingtalk:
        return '钉钉机器人开启「加签」后生成的密钥（SEC 开头）';
      case WebhookChannelType.feishu:
        return '飞书自定义机器人开启「签名校验」后的密钥';
      case WebhookChannelType.generic:
        return '自建服务端校验签名用的密钥（通过 X-Signature 头传递）';
      case WebhookChannelType.telegram:
        return 'Telegram 使用 Bot Token 鉴权，无需签名密钥';
      case WebhookChannelType.bark:
        return 'Bark 使用设备 Key 鉴权，无需签名密钥';
      case WebhookChannelType.serverChan:
        return 'Server酱 使用 SendKey 鉴权，无需签名密钥';
      case WebhookChannelType.pushPlus:
        return 'PushPlus 使用 Token 鉴权，无需签名密钥';
    }
  }
}

enum WebhookMessageFormat {
  /// 平台默认格式（企微/钉钉/飞书走文本，通用走 JSON）
  defaultFormat,

  /// 纯文本（无格式）
  text,

  /// Markdown（企微/钉钉/飞书走 markdown msgtype）
  markdown,

  /// 自定义 JSON body（通用 webhook）
  json,

  /// XML body（通用 webhook，Content-Type: application/xml）
  xml;

  String get value {
    switch (this) {
      case WebhookMessageFormat.defaultFormat:
        return 'default';
      case WebhookMessageFormat.text:
        return 'text';
      case WebhookMessageFormat.markdown:
        return 'markdown';
      case WebhookMessageFormat.json:
        return 'json';
      case WebhookMessageFormat.xml:
        return 'xml';
    }
  }

  String get label {
    switch (this) {
      case WebhookMessageFormat.defaultFormat:
        return '默认格式';
      case WebhookMessageFormat.text:
        return '纯文本';
      case WebhookMessageFormat.markdown:
        return 'Markdown';
      case WebhookMessageFormat.json:
        return 'JSON';
      case WebhookMessageFormat.xml:
        return 'XML';
    }
  }

  static WebhookMessageFormat fromValue(String? value) {
    switch (value) {
      case 'text':
        return WebhookMessageFormat.text;
      case 'markdown':
        return WebhookMessageFormat.markdown;
      case 'json':
        return WebhookMessageFormat.json;
      case 'xml':
        return WebhookMessageFormat.xml;
      default:
        return WebhookMessageFormat.defaultFormat;
    }
  }
}

class WebhookChannel {
  final String id;
  final String name;
  final String url;
  final WebhookChannelType type;
  final bool enabled;
  final String? secret;
  final WebhookMessageFormat messageFormat;
  final String? messageTemplate;

  WebhookChannel({
    required this.id,
    this.name = '',
    required this.url,
    required this.type,
    this.enabled = true,
    this.secret,
    this.messageFormat = WebhookMessageFormat.defaultFormat,
    this.messageTemplate,
  });

  /// 平台 host 匹配规则（与 Kotlin 端 WebhookPayloadBuilder.PLATFORM_RULES 保持一致）
  static const _platformRules = <(WebhookChannelType, List<String>)>[
    (WebhookChannelType.wechatWork, ['qyapi.weixin.qq.com']),
    (WebhookChannelType.dingtalk, ['oapi.dingtalk.com']),
    (WebhookChannelType.feishu, ['open.feishu.cn', 'open.larksuite.com']),
    (WebhookChannelType.telegram, ['api.telegram.org']),
    (WebhookChannelType.bark, ['api.day.app', 'bark.gugu.ovh']),
    (WebhookChannelType.serverChan, ['sctapi.ftqq.com']),
    (WebhookChannelType.pushPlus, ['www.pushplus.plus', 'pushplus.plus']),
  ];

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
      messageFormat: WebhookMessageFormat.fromValue(
        map['message_format'] as String?,
      ),
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
      'message_format': messageFormat.value,
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
    WebhookMessageFormat? messageFormat,
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
