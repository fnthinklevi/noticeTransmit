import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

enum WebhookChannelType { generic, wechatWork, dingtalk, feishu }

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
    }
  }
}

class WebhookChannel {
  final String id;
  final String name;
  final String url;
  final WebhookChannelType type;
  final bool enabled;

  WebhookChannel({
    required this.id,
    this.name = '',
    required this.url,
    required this.type,
    this.enabled = true,
  });

  static WebhookChannelType detectTypeFromUrl(String url) {
    final lowerUrl = url.toLowerCase();
    if (lowerUrl.contains('qyapi.weixin.qq.com') ||
        lowerUrl.contains('weixin.qq.com')) {
      return WebhookChannelType.wechatWork;
    } else if (lowerUrl.contains('oapi.dingtalk.com') ||
        lowerUrl.contains('dingtalk')) {
      return WebhookChannelType.dingtalk;
    } else if (lowerUrl.contains('feishu.cn') ||
        lowerUrl.contains('larksuite.com')) {
      return WebhookChannelType.feishu;
    }
    return WebhookChannelType.generic;
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
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'type': type.value,
      'enabled': enabled,
    };
  }

  WebhookChannel copyWith({
    String? id,
    String? name,
    String? url,
    WebhookChannelType? type,
    bool? enabled,
  }) {
    return WebhookChannel(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      type: type ?? this.type,
      enabled: enabled ?? this.enabled,
    );
  }
}
