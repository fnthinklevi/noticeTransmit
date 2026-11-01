import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 安全存储不可用（T222）。
///
/// 现场是 AndroidKeyStore 里那把主密钥已经解不开 prefs 里的密文：
/// `SecurityException: Could not decrypt key` / `bad base-64`。插件那边是一个
/// **可能永不回答**的 Future —— 过去它一路冒到启动链，界面停在「初始化完成」。
/// 这一族把"读不出来"变成**有类型的失败**，并且**有界**（不会再无限等待）。
class SecureStorageUnavailable implements Exception {
  const SecureStorageUnavailable(this.reason, [this.cause]);

  /// 哪一步、为什么：`timeout:read:db_encryption_key` / `failed:read:...`。
  final String reason;
  final Object? cause;

  @override
  String toString() =>
      'SecureStorageUnavailable($reason${cause == null ? '' : ': $cause'})';
}

/// 安全存储服务：基于 flutter_secure_storage 的加密键值存储。
///
/// 用于存储 webhook URL（含钉钉/企微/飞书认证 key）、
/// TOTP 密钥、通知记录等敏感数据。
///
/// 与普通 SharedPreferences 的区别：
/// - Android: 自定义 AES-GCM 数据加密 + RSA-OAEP 密钥包裹（AndroidKeyStore）
/// - iOS: 使用 Keychain
///
/// v10 起 `encryptedSharedPreferences` 已废弃：旧 EncryptedSharedPreferences
/// 数据在首次访问时自动迁移到自定义 cipher；直跳 v11 会丢失迁移路径，
/// 所以本仓先停在 10.x，等迁移在设备上验证过再抬 11。
///
/// ⚠ T222：每一次读写都**有界**（[opTimeout]），失败一律抛
/// [SecureStorageUnavailable] —— 插件在密钥失效时可能永远不 complete，
/// 而没有上界的那一条就是"App 卡在启动屏"的直接来路。
class SecureStorageService {
  static final _instance = SecureStorageService._();
  factory SecureStorageService() => _instance;
  SecureStorageService._();

  /// 单次安全存储操作的上界。**故意短**：这些调用都在启动链/页面装配里，
  /// 等它 5 秒还没有答案时，用户需要的是"看见一句能照做的错误"，不是继续等。
  static const Duration opTimeout = Duration(seconds: 5);

  /// 仅测试：关掉单次上界。
  ///
  /// widget 测试里安全存储的平台通道 await 本来就不返回（见 `test/test_setup.dart` 的注释），
  /// 开着上界会在用例结束、树已销毁时留下 pending Timer（`!timersPending` 断言）。
  /// **产品路径不许关它**——上界本身就是 T222 那一条的修法。
  @visibleForTesting
  static bool boundedOps = true;

  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(migrateOnAlgorithmChange: true),
  );

  // ========== Webhook URLs ==========

  static const _keyWebhookUrls = 'secure_webhook_urls';
  static const _keyWebhookChannels = 'secure_webhook_channels';

  Future<void> saveWebhookUrls(List<String> urls) =>
      write(_keyWebhookUrls, urls.join('|||'));

  Future<List<String>> loadWebhookUrls() async {
    final value = await read(_keyWebhookUrls);
    if (value == null || value.isEmpty) return [];
    return value.split('|||');
  }

  Future<void> saveWebhookChannels(String jsonStr) =>
      write(_keyWebhookChannels, jsonStr);

  Future<String?> loadWebhookChannels() => read(_keyWebhookChannels);

  // ========== Generic ==========

  Future<void> write(String key, String value) =>
      _guard('write:$key', () => _storage.write(key: key, value: value));

  Future<String?> read(String key) =>
      _guard('read:$key', () => _storage.read(key: key));

  Future<void> delete(String key) =>
      _guard('delete:$key', () => _storage.delete(key: key));

  Future<void> clearAll() => _guard('clearAll', () => _storage.deleteAll());

  /// 唯一的失败分类点：超时与异常都变成 [SecureStorageUnavailable]。
  ///
  /// ⚠ 这里**不吞异常**（也不返回 null）：读不出来与"这里本来没有值"是两件事，
  /// 把后者当前者会让"密钥丢了"看起来像"还没设过"，用户重新设一把之后旧的还在别人手里。
  Future<T> _guard<T>(String op, Future<T> Function() run) async {
    try {
      final future = run();
      return boundedOps ? await future.timeout(opTimeout) : await future;
    } on TimeoutException catch (e) {
      debugPrint('[secure-storage] $op 超过 ${opTimeout.inSeconds}s 没有回答：$e');
      throw SecureStorageUnavailable('timeout:$op', e);
    } catch (e) {
      debugPrint('[secure-storage] $op 失败：$e');
      throw SecureStorageUnavailable('failed:$op', e);
    }
  }
}
