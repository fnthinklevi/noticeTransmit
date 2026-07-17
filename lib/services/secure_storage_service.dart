import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 安全存储服务：基于 flutter_secure_storage 的加密键值存储。
///
/// 用于存储 webhook URL（含钉钉/企微/飞书认证 key）、
/// TOTP 密钥、通知记录等敏感数据。
///
/// 与普通 SharedPreferences 的区别：
/// - Android: 使用 EncryptedSharedPreferences（AndroidKeyStore 加密）
/// - iOS: 使用 Keychain
class SecureStorageService {
  static final _instance = SecureStorageService._();
  factory SecureStorageService() => _instance;
  SecureStorageService._();

  final FlutterSecureStorage _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // ========== Webhook URLs ==========

  static const _keyWebhookUrls = 'secure_webhook_urls';
  static const _keyWebhookChannels = 'secure_webhook_channels';

  Future<void> saveWebhookUrls(List<String> urls) async {
    await _storage.write(key: _keyWebhookUrls, value: urls.join('|||'));
  }

  Future<List<String>> loadWebhookUrls() async {
    final value = await _storage.read(key: _keyWebhookUrls);
    if (value == null || value.isEmpty) return [];
    return value.split('|||');
  }

  Future<void> saveWebhookChannels(String jsonStr) async {
    await _storage.write(key: _keyWebhookChannels, value: jsonStr);
  }

  Future<String?> loadWebhookChannels() async {
    return await _storage.read(key: _keyWebhookChannels);
  }

  // ========== Generic ==========

  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  Future<String?> read(String key) async {
    return await _storage.read(key: key);
  }

  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }

  Future<void> clearAll() async {
    await _storage.deleteAll();
  }
}
