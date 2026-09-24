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
import 'channel_config_codec.dart';
import 'channel_url_policy.dart';
import 'locale_service.dart';
import 'sms_service.dart';
import 'theme_service.dart';
import 'app_channel_service.dart';
import 'webhook_service.dart';

/// P1 配置备份与恢复。
///
/// 容器格式（.nbackup，JSON 文本）：文件头携带版本号与 KDF 参数（盐/迭代次数），
/// 密文为 AES-256-GCM（口令经 PBKDF2-HMAC-SHA256 派生，210000 次迭代）。
/// 备份内容（v1.59 起 **12 类**，对齐 base.md §10.2「升级设置保留要求」）：
/// Webhook/邮件通道（含凭据）、通知规则、短信监听设置、应用过滤与黑白名单关键词、
/// 电池规则与电量通知开关、主题/语言、设备名、**自建应用通道（含凭据，v1.59 新增）**；
/// 不含通知历史与送达日志。
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
    // v1.59：自建应用通道（含凭据）同样纳入备份
    final appChannel = GetIt.instance<AppChannelService>();
    if (appChannel.channels.isEmpty) await appChannel.loadChannels();
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
      'appChannels': appChannel.channels,
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

  /// 字段级校验 + **形状归一化**：返回 (可安全恢复的 payload, 被跳过的非法 webhook 数)。
  ///
  /// 备份文件是这条链路上唯一的**外部输入**：跨版本（v1 容器里没有电池/设备名/偏好）、
  /// 可能被手改、可能来自别的导出工具。而下游是硬类型的：`NotificationRule.fromMap`
  /// 用 `as int?`/`as bool?`，`List<String>.from` 遇到非字符串元素就抛。
  /// 所以形状必须在**这里**修好，让模型层保持严格、恢复逻辑不必处处兜底。
  ///
  /// URL 规则复用 [ChannelUrlPolicy]（第 6 步）。这里原来**只认 https**，而原生两处
  /// （`AppChannelTokenHelper.normalizeBase` / `ChannelHealthProbe.isProbeableUrl`）
  /// 都认 http+https ⇒ 自建 http 的 ntfy / Gotify 通道在恢复备份时会被当非法条目跳过：
  /// 备份显示成功、通道列表静默少几条。
  ///
  /// ⚠ 缺键的类别**不补空列表**：补了就会被 [restorePayload] 当成「备份里该类为空」，
  /// 覆盖模式下等于删掉用户本机的全部该类配置。只对「存在但形状不对」的键做收拾。
  (Map<String, dynamic>, int) validatePayload(Map<String, dynamic> payload) {
    var skipped = 0;
    final fixed = Map<String, dynamic>.from(payload);

    final rawWebhooks = payload['webhookChannels'];
    if (rawWebhooks is! List) {
      // 键存在但不是列表（'garbage'）→ 清空；键不存在 → 保持不存在
      if (payload.containsKey('webhookChannels')) {
        fixed['webhookChannels'] = <Map<String, dynamic>>[];
      }
    } else {
      final webhooks = <Map<String, dynamic>>[];
      for (final item in rawWebhooks.whereType<Map>()) {
        final row = Map<String, dynamic>.from(item);
        final url = row['url']?.toString().trim() ?? '';
        if (!ChannelUrlPolicy.isHttpUrl(url)) {
          skipped++;
          continue;
        }
        // 归一化写回：下游 webhookToDb 读 `ui['url'] ?? ''`，非字符串会原样落库
        row['url'] = url;
        webhooks.add(row);
      }
      fixed['webhookChannels'] = webhooks;
    }

    // 规则表**不在这里重塑形状**：NotificationRule/Condition/RuleAction 的 fromMap
    // 自己容忍宽松取值（备份恢复与规则模板导入共用这两个模型，兜底只能做在模型里）。
    // 这里只保住一条语义：键存在但不是列表 ⇒ 原样留着，让 restorePayload 整类跳过，
    // 而不是当成"备份里没有规则"删掉本机规则。

    final appFilter = payload['appFilter'];
    if (appFilter is Map) {
      fixed['appFilter'] = {
        ...Map<String, dynamic>.from(appFilter),
        'mode': _text(appFilter['mode'], 'allow'),
        // packages 不是列表就当没有名单：saveAppFilter 需要 List<String>，
        // 而「allow + 空列表」在原生侧是"全部放行"（FilterEngine：非空才拦截），
        // 与"这份备份没写名单"的语义一致。
        'packages': _textList(appFilter['packages']),
      };
    }

    for (final key in ['blacklistKeywords', 'whitelistKeywords']) {
      if (payload[key] is List) {
        fixed[key] = _textList(payload[key]);
      }
    }

    final sms = payload['smsSettings'];
    if (sms is Map) {
      fixed['smsSettings'] = {
        ...Map<String, dynamic>.from(sms),
        'sms_monitor_enabled': _bool(sms['sms_monitor_enabled'], true),
        'sms_code_monitor_enabled': _bool(
          sms['sms_code_monitor_enabled'],
          true,
        ),
        'sms_sim_filter': _text(sms['sms_sim_filter'], 'all'),
      };
    }

    final battery = payload['battery'];
    if (battery is Map) {
      final notify = battery['notify_enabled'];
      fixed['battery'] = {
        ...Map<String, dynamic>.from(battery),
        'notify_enabled': notify == null ? null : _bool(notify, true),
        // 非列表 → null（BatteryService.restoreSettings 把 null 解释为"保持当前规则"）；
        // 归一化成 [] 会删掉本机全部电量规则。
        'rules': battery['rules'] is List ? _mapList(battery['rules']) : null,
      };
    }

    return (fixed, skipped);
  }

  // ── 形状兜底（只服务于"文件里的值类型不受控"这一件事）───────────────

  static String _text(Object? value, String fallback) =>
      ChannelConfigCodec.nullableText(value) ?? fallback;

  /// JSON 侧是真 bool，DB 导出侧是 0/1，字符串 "true" 也可能出现在手改的文件里
  static bool _bool(Object? value, bool fallback) {
    if (value == null) return fallback;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().toLowerCase();
    if (text == 'true' || text == '1') return true;
    if (text == 'false' || text == '0') return false;
    return fallback;
  }

  static List<String> _textList(Object? value) {
    if (value is! List) return const [];
    return value
        .map((e) => ChannelConfigCodec.nullableText(e) ?? '')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static List<Map<String, dynamic>> _mapList(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  // ── 冲突检测 / 恢复 ──────────────────────────────────────────────────

  /// 各类别当前是否已有配置（恢复冲突策略的判定依据）。
  Future<Map<String, bool>> detectExisting() async {
    final webhook = GetIt.instance<WebhookService>();
    if (webhook.channels.isEmpty) await webhook.loadChannels();
    final appChannel = GetIt.instance<AppChannelService>();
    if (appChannel.channels.isEmpty) await appChannel.loadChannels();
    final email = GetIt.instance<EmailService>();
    final emailChannels = await email.loadChannels();
    final sms = GetIt.instance<SmsService>();
    await sms.loadSettings();
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
      'appChannels': appChannel.channels.isNotEmpty,
      'emailChannels': emailChannels.isNotEmpty,
      'notificationRules': filter.notificationRules.isNotEmpty,
      'smsSettings':
          sms.smsMonitorEnabled ||
          sms.codeMonitorEnabled ||
          sms.simFilter != 'all',
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
      // 逐类别落盘 ⇒ 中途抛异常会留下「一半备份、一半本机」的配置，
      // 而界面只会显示一句"恢复失败"。所以单类失败记进报告后继续，
      // 由 UI 明确列出哪些类没恢复成功。
      try {
        report.restored[category] = await doRestore() ? 1 : 0;
      } catch (e) {
        report.failedCategories[category] = e.toString();
      }
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

    final appChannelsRaw = payload['appChannels'];
    if (appChannelsRaw is List) {
      await restore('appChannels', () async {
        await GetIt.instance<AppChannelService>().saveChannels(
          appChannelsRaw
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList(),
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

/// 恢复结果报告：各类别是否恢复、因冲突跳过的类别、失败的类别（category → 原因）。
class RestoreReport {
  final Map<String, int> restored = {};
  final List<String> skippedCategories = [];
  final Map<String, String> failedCategories = {};
}
