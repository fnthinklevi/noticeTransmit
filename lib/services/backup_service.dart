import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:get_it/get_it.dart';

import '../models/email_channel.dart';
import '../models/notification_rule.dart';
import 'battery_service.dart';
import 'device_info_service.dart';
import 'email_service.dart';
import 'filter_service.dart';
import 'locale_service.dart';
import 'sms_service.dart';
import 'theme_service.dart';
import 'webhook_service.dart';

/// P1 配置备份与恢复。
///
/// 容器格式（.nbackup，JSON 文本）：文件头携带版本号与 KDF 参数（盐/迭代次数），
/// 密文为 AES-256-GCM（口令经 PBKDF2-HMAC-SHA256 派生，210000 次迭代）。
/// 备份内容（N5 起 11 类，对齐 base.md §10.2「升级设置保留要求」）：
/// Webhook/邮件通道（含凭据）、通知规则、短信监听设置、应用过滤与黑白名单关键词、
/// **电池规则与电量通知开关、主题/语言、设备名**；不含通知历史与送达日志。
class BackupService {
  static const formatId = 'notice-backup';
  static const formatVersion = 2;

  /// 支持解密的容器版本：v2（当前，含电池/设备名/偏好三新类别）与 v1（旧备份，
  /// 无新类别字段——恢复时三类自然跳过，保证 v1 备份文件仍可恢复）。
  static const supportedVersions = {1, 2};
  static const kdfIterations = 210000;
  static const minPasswordLength = 8;

  final _aes = AesGcm.with256bits();
  final _kdf = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: kdfIterations,
    bits: 256,
  );
  final _random = Random.secure();

  // ── 数据收集 ─────────────────────────────────────────────────────────

  /// 收集全部可备份配置（服务当前内存态，未加载时先 load）。
  Future<Map<String, dynamic>> collectBackupData() async {
    final webhook = GetIt.instance<WebhookService>();
    if (webhook.channels.isEmpty) await webhook.loadChannels();
    final emailChannels = await GetIt.instance<EmailService>().loadChannels();
    final filter = GetIt.instance<FilterService>();
    await filter.loadSettings();
    final sms = GetIt.instance<SmsService>();
    await sms.loadSettings();
    // N5 新增三类：电池规则/电量开关、设备名、主题/语言
    final battery = GetIt.instance<BatteryService>();
    await battery.loadSettings();
    final device = GetIt.instance<DeviceInfoService>();
    await device.loadDeviceInfo();
    final theme = GetIt.instance<ThemeService>();
    final locale = GetIt.instance<LocaleService>();

    return {
      'webhookChannels': webhook.channels,
      'emailChannels': emailChannels
          .map((c) => c.toMap(includePassword: true))
          .toList(),
      'notificationRules': filter.notificationRules
          .map((r) => r.toMap())
          .toList(),
      'smsSettings': {
        'sms_monitor_enabled': sms.smsMonitorEnabled,
        'sms_code_monitor_enabled': sms.codeMonitorEnabled,
        'sms_sim_filter': sms.simFilter,
      },
      'appFilter': {
        'mode': filter.appFilterMode,
        'packages': filter.enabledPackages.toList(),
      },
      'blacklistKeywords': filter.blacklistKeywords,
      'whitelistKeywords': filter.whitelistKeywords,
      'battery': {
        'notify_enabled': battery.notifyEnabled,
        'rules': battery.rules,
      },
      'deviceName': device.deviceName,
      'preferences': {
        'theme_mode': theme.themeMode.name,
        'app_language': locale.language.name,
      },
    };
  }

  // ── 加密 / 解密 ──────────────────────────────────────────────────────

  /// 加密明文数据为备份容器（Map，可 jsonEncode 后写 .nbackup 文件）。
  Future<Map<String, dynamic>> encryptBackup(
    Map<String, dynamic> data,
    String password,
  ) async {
    _assertPassword(password);
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final key = await _deriveKey(password, salt);
    final box = await _aes.encrypt(
      utf8.encode(jsonEncode(data)),
      secretKey: key,
      nonce: nonce,
    );
    return {
      'format': formatId,
      'version': formatVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'kdf': {
        'algorithm': 'PBKDF2-HMAC-SHA256',
        'iterations': kdfIterations,
        'salt': base64Encode(salt),
      },
      'cipher': 'AES-256-GCM',
      'nonce': base64Encode(box.nonce),
      'mac': base64Encode(box.mac.bytes),
      'ciphertext': base64Encode(box.cipherText),
    };
  }

  /// 解密备份容器并还原明文数据。
  /// 口令错误 / 密文被篡改时抛 [SecretBoxAuthenticationError]。
  Future<Map<String, dynamic>> decryptBackup(
    Map<String, dynamic> container,
    String password,
  ) async {
    _assertPassword(password);
    validateContainer(container);
    final kdf = container['kdf'] as Map<String, dynamic>;
    final salt = _decodeB64(kdf['salt'], 'kdf.salt');
    final nonce = _decodeB64(container['nonce'], 'nonce');
    final mac = _decodeB64(container['mac'], 'mac');
    final cipherText = _decodeB64(container['ciphertext'], 'ciphertext');
    // KDF 参数从文件头读取（迭代次数随容器走），前向兼容参数变化
    final iterations = (kdf['iterations'] as num?)?.toInt() ?? kdfIterations;
    final key = await _kdfFor(
      iterations,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    final clear = await _aes.decrypt(
      SecretBox(cipherText, nonce: nonce, mac: Mac(mac)),
      secretKey: key,
    );
    final payload = jsonDecode(utf8.decode(clear));
    if (payload is! Map<String, dynamic>) {
      throw const FormatException('备份内容不是合法的配置对象');
    }
    return payload;
  }

  // ── 内容校验 ─────────────────────────────────────────────────────────

  /// 容器结构校验（解密前调用，供 UI 预检）。非法抛 [FormatException]。
  /// 支持 v1（旧备份，无电池/设备名/偏好三类）与 v2（当前）。
  void validateContainer(Map<String, dynamic> c) {
    if (c['format'] != formatId) {
      throw const FormatException('不是有效备份文件（format 不符）');
    }
    final version = (c['version'] as num?)?.toInt() ?? 0;
    if (!supportedVersions.contains(version)) {
      throw const FormatException('备份格式版本不受支持');
    }
    final kdf = c['kdf'];
    if (kdf is! Map<String, dynamic> ||
        kdf['algorithm'] != 'PBKDF2-HMAC-SHA256') {
      throw const FormatException('KDF 参数不受支持');
    }
    for (final key in ['nonce', 'mac', 'ciphertext']) {
      if ((c[key] as String?)?.isEmpty ?? true) {
        throw FormatException('容器缺少 $key');
      }
    }
  }

  /// 字段级校验：返回 (合法 payload, 被跳过的非法 webhook 数)。
  /// Webhook URL 必须 https://（与原生保存链路一致）。
  (Map<String, dynamic>, int) validatePayload(Map<String, dynamic> payload) {
    var skipped = 0;
    final rawWebhooks = payload['webhookChannels'];
    final webhooks = rawWebhooks is List
        ? rawWebhooks
              .whereType<Map>()
              .map((m) {
                final item = Map<String, dynamic>.from(m);
                final url = item['url']?.toString() ?? '';
                final ok = Uri.tryParse(url)?.scheme == 'https';
                if (!ok) skipped++;
                return ok ? item : null;
              })
              .whereType<Map<String, dynamic>>()
              .toList()
        : <Map<String, dynamic>>[];
    final fixed = Map<String, dynamic>.from(payload);
    fixed['webhookChannels'] = webhooks;
    return (fixed, skipped);
  }

  // ── 冲突检测 / 恢复 ──────────────────────────────────────────────────

  /// 各类别当前是否已有配置（恢复冲突策略的判定依据）。
  Future<Map<String, bool>> detectExisting() async {
    final webhook = GetIt.instance<WebhookService>();
    if (webhook.channels.isEmpty) await webhook.loadChannels();
    final email = GetIt.instance<EmailService>();
    final emailChannels = await email.loadChannels();
    final filter = GetIt.instance<FilterService>();
    await filter.loadSettings();
    final battery = GetIt.instance<BatteryService>();
    await battery.loadSettings();
    final device = GetIt.instance<DeviceInfoService>();
    await device.loadDeviceInfo();
    final theme = GetIt.instance<ThemeService>();
    final locale = GetIt.instance<LocaleService>();
    return {
      'webhookChannels': webhook.channels.isNotEmpty,
      'emailChannels': emailChannels.isNotEmpty,
      'notificationRules': filter.notificationRules.isNotEmpty,
      'appFilter': filter.enabledPackages.isNotEmpty,
      'blacklistKeywords': filter.blacklistKeywords.isNotEmpty,
      'whitelistKeywords': filter.whitelistKeywords.isNotEmpty,
      // N5：电池 = 有自定义规则即视为已有配置；设备名 = 非空；
      // 偏好 = 主题或语言存在非默认（非 system）值
      'battery': battery.rules.isNotEmpty,
      'deviceName': device.deviceName.isNotEmpty,
      'preferences':
          theme.themeMode != ThemeMode.system ||
          locale.language != AppLanguage.system,
    };
  }

  /// 按冲突策略恢复配置（全部走既有保存链路 → 自动同步原生）。
  /// [overwriteExisting] = false 时跳过「当前已有配置」的类别。
  Future<RestoreReport> restorePayload(
    Map<String, dynamic> payload, {
    required bool overwriteExisting,
  }) async {
    final existing = await detectExisting();
    final report = RestoreReport();

    Future<void> restore(
      String category,
      Future<bool> Function() doRestore,
    ) async {
      if (!overwriteExisting && (existing[category] ?? false)) {
        report.skippedCategories.add(category);
        return;
      }
      report.restored[category] = await doRestore() ? 1 : 0;
    }

    final webhook = payload['webhookChannels'];
    if (webhook is List) {
      await restore('webhookChannels', () async {
        await GetIt.instance<WebhookService>().saveChannels(
          webhook.whereType<Map>().map((m) {
            final item = Map<String, dynamic>.from(m);
            // secret 缺省置空串，避免原生把缺省误读
            item['secret'] ??= '';
            return item;
          }).toList(),
        );
        return true;
      });
    }

    final emailRaw = payload['emailChannels'];
    if (emailRaw is List) {
      await restore('emailChannels', () async {
        final channels = emailRaw
            .whereType<Map>()
            .map((m) => EmailChannel.fromMap(Map<String, dynamic>.from(m)))
            .toList();
        await GetIt.instance<EmailService>().saveChannels(channels);
        return true;
      });
    }

    final rules = payload['notificationRules'];
    if (rules is List) {
      await restore('notificationRules', () async {
        await GetIt.instance<FilterService>().saveNotificationRules(
          rules
              .whereType<Map>()
              .map(
                (m) => NotificationRule.fromMap(Map<String, dynamic>.from(m)),
              )
              .toList(),
        );
        return true;
      });
    }

    final sms = payload['smsSettings'];
    if (sms is Map) {
      await restore('smsSettings', () async {
        final smsService = GetIt.instance<SmsService>();
        if (sms['sms_monitor_enabled'] is bool) {
          await smsService.saveSmsMonitorEnabled(
            sms['sms_monitor_enabled'] as bool,
          );
        }
        if (sms['sms_code_monitor_enabled'] is bool) {
          await smsService.saveCodeMonitorEnabled(
            sms['sms_code_monitor_enabled'] as bool,
          );
        }
        if (sms['sms_sim_filter'] is String) {
          await smsService.saveSimFilter(sms['sms_sim_filter'] as String);
        }
        return true;
      });
    }

    final appFilter = payload['appFilter'];
    if (appFilter is Map) {
      await restore('appFilter', () async {
        await GetIt.instance<FilterService>().saveAppFilter(
          appFilter['mode']?.toString() ?? 'allow',
          List<String>.from(appFilter['packages'] ?? const []),
        );
        return true;
      });
    }

    for (final entry in {
      'blacklistKeywords': 'saveBlacklistKeywords',
      'whitelistKeywords': 'saveWhitelistKeywords',
    }.entries) {
      final raw = payload[entry.key];
      if (raw is List) {
        await restore(entry.key, () async {
          final keywords = List<String>.from(raw);
          final filter = GetIt.instance<FilterService>();
          if (entry.key == 'blacklistKeywords') {
            await filter.saveBlacklistKeywords(keywords);
          } else {
            await filter.saveWhitelistKeywords(keywords);
          }
          return true;
        });
      }
    }

    // ── N5 新增三类（v1 备份无这些字段，自然跳过）──

    final battery = payload['battery'];
    if (battery is Map) {
      await restore('battery', () async {
        final rules = (battery['rules'] as List?)
            ?.whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
        final notify = battery['notify_enabled'];
        await GetIt.instance<BatteryService>().restoreSettings(
          notifyEnabled: notify is bool ? notify : null,
          rules: rules,
        );
        return true;
      });
    }

    final deviceName = payload['deviceName'];
    if (deviceName is String) {
      await restore('deviceName', () async {
        await GetIt.instance<DeviceInfoService>().saveDeviceName(deviceName);
        return true;
      });
    }

    // 偏好（主题/语言）放最后恢复：语言切换会立即改变 UI 文案
    final preferences = payload['preferences'];
    if (preferences is Map) {
      await restore('preferences', () async {
        final themeMode = preferences['theme_mode']?.toString();
        if (themeMode != null) {
          final mode = ThemeMode.values.firstWhere(
            (e) => e.name == themeMode,
            orElse: () => ThemeMode.system,
          );
          await GetIt.instance<ThemeService>().setThemeMode(mode);
        }
        final lang = preferences['app_language']?.toString();
        if (lang != null) {
          final language = AppLanguage.values.firstWhere(
            (e) => e.name == lang,
            orElse: () => AppLanguage.system,
          );
          await GetIt.instance<LocaleService>().setLanguage(language);
        }
        return true;
      });
    }
    return report;
  }

  // ── 内部工具 ─────────────────────────────────────────────────────────

  /// 按迭代次数构造 KDF（解密以文件头参数为准）
  Pbkdf2 _kdfFor(int iterations) =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iterations, bits: 256);

  Future<SecretKey> _deriveKey(String password, Uint8List salt) =>
      _kdf.deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

  Uint8List _randomBytes(int n) =>
      Uint8List.fromList(List.generate(n, (_) => _random.nextInt(256)));

  void _assertPassword(String password) {
    if (password.length < minPasswordLength) {
      throw const FormatException('口令至少 $minPasswordLength 位');
    }
  }

  Uint8List _decodeB64(Object? value, String field) {
    final s = value?.toString() ?? '';
    try {
      return base64Decode(s);
    } catch (_) {
      throw FormatException('容器 $field 不是合法的 base64');
    }
  }
}

/// 恢复结果报告：各类别是否恢复、因冲突跳过的类别。
class RestoreReport {
  final Map<String, int> restored = {};
  final List<String> skippedCategories = [];
}
