import 'package:flutter/foundation.dart';

/// 邮件通知通道模型
///
/// 存储 SMTP 配置信息，密码存储在加密 SQLCipher 数据库中。
@immutable
class EmailChannel {
  /// 端口与 SSL 的**兜底默认值**：只在读到缺键的旧行时使用。
  ///
  /// 表单真正预填的是原生描述符里 `smtpPort.defaultValue` / `useSSL.defaultValue`
  /// （T08-C2）。这两个常量和它必须相等 —— 相等关系由
  /// `test/widgets/email_settings_page_test.dart` 拿导出快照核对；
  /// 此前 `465` 同时抄在页面三处、模型两处、`EmailManager` 一处，
  /// 改一处就会变成"界面显示 A、发信用 B"。
  static const int defaultSmtpPort = 465;
  static const bool defaultUseSsl = true;

  final String id;
  final String name;
  final bool enabled;

  /// 主备角色（T11）：'primary' | 'backup' | 'none'。
  /// 取值与缺省归一的口径在 `ChannelConfigCodec.normalizeRole`，别在别处再写一套。
  final String role;
  final String smtpHost;
  final int smtpPort;
  final String username;
  final String? password;
  final String fromEmail;
  final String toEmail;
  final bool useSSL;
  final String? subjectTemplate;
  final String? bodyTemplate;

  const EmailChannel({
    required this.id,
    required this.name,
    this.enabled = true,
    this.role = 'primary',
    required this.smtpHost,
    required this.smtpPort,
    required this.username,
    this.password,
    required this.fromEmail,
    required this.toEmail,
    this.useSSL = defaultUseSsl,
    this.subjectTemplate,
    this.bodyTemplate,
  });

  factory EmailChannel.fromMap(Map<String, dynamic> map) {
    return EmailChannel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      enabled: map['enabled'] != false && map['enabled'] != 0,
      role: map['role']?.toString() ?? 'primary',
      smtpHost: map['smtpHost']?.toString() ?? '',
      smtpPort:
          int.tryParse(map['smtpPort']?.toString() ?? '') ?? defaultSmtpPort,
      username: map['username']?.toString() ?? '',
      password: map['password']?.toString(),
      fromEmail: map['fromEmail']?.toString() ?? '',
      toEmail: map['toEmail']?.toString() ?? '',
      useSSL: map['useSSL'] != false && map['useSSL'] != 0,
      subjectTemplate: map['subjectTemplate']?.toString(),
      bodyTemplate: map['bodyTemplate']?.toString(),
    );
  }

  /// 从加密数据库行（snake_case）构造
  factory EmailChannel.fromDbRow(Map<String, dynamic> row) {
    return EmailChannel(
      id: row['id']?.toString() ?? '',
      name: row['name']?.toString() ?? '',
      enabled: row['enabled'] == 1 || row['enabled'] == true,
      role: row['role']?.toString() ?? 'primary',
      smtpHost: row['smtp_host']?.toString() ?? '',
      smtpPort:
          int.tryParse(row['smtp_port']?.toString() ?? '') ?? defaultSmtpPort,
      username: row['username']?.toString() ?? '',
      password: row['password']?.toString(),
      fromEmail: row['from_email']?.toString() ?? '',
      toEmail: row['to_email']?.toString() ?? '',
      useSSL: row['use_ssl'] == 1 || row['use_ssl'] == true,
      subjectTemplate: row['subject_template']?.toString(),
      bodyTemplate: row['body_template']?.toString(),
    );
  }

  Map<String, dynamic> toMap({bool includePassword = false}) {
    final map = <String, dynamic>{
      'id': id,
      'name': name,
      'enabled': enabled,
      'role': role,
      'smtpHost': smtpHost,
      'smtpPort': smtpPort,
      'username': username,
      'fromEmail': fromEmail,
      'toEmail': toEmail,
      'useSSL': useSSL,
    };
    if (subjectTemplate != null) {
      map['subjectTemplate'] = subjectTemplate;
    }
    if (bodyTemplate != null) {
      map['bodyTemplate'] = bodyTemplate;
    }
    if (includePassword && password != null) {
      map['password'] = password;
    }
    return map;
  }

  EmailChannel copyWith({
    String? id,
    String? name,
    bool? enabled,
    String? role,
    String? smtpHost,
    int? smtpPort,
    String? username,
    String? password,
    String? fromEmail,
    String? toEmail,
    bool? useSSL,
    String? subjectTemplate,
    String? bodyTemplate,
  }) {
    return EmailChannel(
      id: id ?? this.id,
      name: name ?? this.name,
      enabled: enabled ?? this.enabled,
      role: role ?? this.role,
      smtpHost: smtpHost ?? this.smtpHost,
      smtpPort: smtpPort ?? this.smtpPort,
      username: username ?? this.username,
      password: password ?? this.password,
      fromEmail: fromEmail ?? this.fromEmail,
      toEmail: toEmail ?? this.toEmail,
      useSSL: useSSL ?? this.useSSL,
      subjectTemplate: subjectTemplate ?? this.subjectTemplate,
      bodyTemplate: bodyTemplate ?? this.bodyTemplate,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmailChannel &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          enabled == other.enabled &&
          smtpHost == other.smtpHost &&
          smtpPort == other.smtpPort &&
          username == other.username &&
          fromEmail == other.fromEmail &&
          toEmail == other.toEmail &&
          useSSL == other.useSSL &&
          subjectTemplate == other.subjectTemplate &&
          bodyTemplate == other.bodyTemplate;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    enabled,
    smtpHost,
    smtpPort,
    username,
    fromEmail,
    toEmail,
    useSSL,
    subjectTemplate,
    bodyTemplate,
  );
}
