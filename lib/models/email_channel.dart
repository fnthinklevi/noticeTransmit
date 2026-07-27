import 'package:flutter/foundation.dart';

/// 邮件通知通道模型
///
/// 存储 SMTP 配置信息，密码存储在加密 SQLCipher 数据库中。
@immutable
class EmailChannel {
  final String id;
  final String name;
  final bool enabled;
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
    required this.smtpHost,
    required this.smtpPort,
    required this.username,
    this.password,
    required this.fromEmail,
    required this.toEmail,
    this.useSSL = true,
    this.subjectTemplate,
    this.bodyTemplate,
  });

  factory EmailChannel.fromMap(Map<String, dynamic> map) {
    return EmailChannel(
      id: map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      enabled: map['enabled'] != false && map['enabled'] != 0,
      smtpHost: map['smtpHost']?.toString() ?? '',
      smtpPort: int.tryParse(map['smtpPort']?.toString() ?? '465') ?? 465,
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
      smtpHost: row['smtp_host']?.toString() ?? '',
      smtpPort: int.tryParse(row['smtp_port']?.toString() ?? '465') ?? 465,
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

  String get defaultSubject => subjectTemplate ?? '🔔 %appName% — %title%';

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
