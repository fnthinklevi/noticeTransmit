import 'package:fnthink_push/fnthink_push.dart';

import 'secure_storage_service.dart';

/// 本机三件套里 Dart 这一侧的两件：**设备地址码**与**一次性配对口令**（T26 的设备侧存法）。
///
/// 为什么必须由设备自己生成、而不是让服务端代发：契约写了
/// `clientEvents.register.addressCodeSource=client-generated`，而 `identity.pairingCode
/// .derivedFromDeviceIdentity=false` 明确否掉"从公钥推出来"那条省事的路 ——
/// 推出来等于把一枚**可分享的公开标识**绑死在一把**不可换的身份密钥**上：
/// 想换密钥就得换身份，而旧地址码还留在别人的白名单里，那是一条永远对不上的引用。
///
/// 落盘走 `SecureStorageService`（Android 侧是 AndroidKeyStore 加密的 EncryptedSharedPreferences），
/// 不是 SharedPreferences：口令等价于密码，而 prefs 是明文 XML。
/// 本文件因此**不 import shared_preferences** —— 这条由测试当守卫钉住。
class FnthinkCredentialStore {
  FnthinkCredentialStore({
    required this.contract,
    SecureStorageService? storage,
  }) : _storage = storage ?? SecureStorageService();

  final FnthinkContract contract;
  final SecureStorageService _storage;

  static const addressCodeKey = 'fnthink.address_code';
  static const pairingCodeKey = 'fnthink.pairing_code';

  /// 口令是**什么时候挂上去的**（本机毫秒）。计时归服务端（契约把 ttl 的解释权放在服务端），
  /// 这一枚只用来在界面上显示"已挂出 X 秒"，不许拿本机时钟去判定口令还活着没有。
  static const pairingArmedAtKey = 'fnthink.pairing_armed_at';

  /// 首启自动生成，之后每次回同一个。**存量坏了就抛，不悄悄换一枚**：
  /// 换一枚是"我这个人不存在了"级别的事故 —— 别人白名单里那一条、以及用户抄给别人的
  /// 那一串，全部指向不再存在的一台设备，而且没有任何一处会报错。
  Future<FnthinkAddressCode> ensureAddressCode() async {
    final stored = await _storage.read(addressCodeKey);
    if (stored == null || stored.isEmpty) {
      final fresh = FnthinkAddressCode.generate(contract);
      await _storage.write(addressCodeKey, fresh.value);
      return fresh;
    }
    final parsed = FnthinkAddressCode.parse(contract, stored);
    if (parsed == null) {
      throw const FnthinkCredentialCorrupted(
        '存下来的地址码过不了契约的校验（位数或字母表对不上）：'
        '这里不许自动换一枚 —— 换码会让别人白名单里那一条指向一台不再存在的设备',
      );
    }
    return parsed;
  }

  /// 换一枚新地址码。⚠ 调用方必须先拿到用户的二次确认：这台设备在**所有对端**白名单里
  /// 那一串会当场作废，之前配好的关系全部失效，需要重新配对。
  Future<FnthinkAddressCode> resetAddressCode() async {
    final fresh = FnthinkAddressCode.generate(contract);
    await _storage.write(addressCodeKey, fresh.value);
    return fresh;
  }

  /// 挂一枚新的配对口令（契约 `singleUse=true`：配对成功即被服务端消耗）。
  /// 每次调用都换新的 —— 这就是"重置"那档的落点：界面上"重新生成"与"5 分钟到了"走的是同一扇门。
  Future<FnthinkArmedPairingCode> armPairingCode({int? nowMs}) async {
    final code = FnthinkPairingCode.generate(contract);
    final armedAt = nowMs ?? DateTime.now().toUtc().millisecondsSinceEpoch;
    await _storage.write(pairingCodeKey, code.value);
    await _storage.write(pairingArmedAtKey, '$armedAt');
    return FnthinkArmedPairingCode(
      code: code,
      armedAtMs: armedAt,
      ttlSeconds: code.ttlSeconds,
    );
  }

  /// 当前挂着的口令；没挂过 ⇒ null。**过期也照原样带回**：判定权在服务端
  /// （它按自己的 `serverTime` 与签发时刻算），本机时钟说了不算 —— 一台时钟漂了两天的
  /// 设备若自己判"已过期"而不再显示，用户会看到"永远挂不出口令"，那查起来最难。
  Future<FnthinkArmedPairingCode?> currentPairingCode() async {
    final stored = await _storage.read(pairingCodeKey);
    if (stored == null || stored.isEmpty) return null;
    final code = FnthinkPairingCode.parse(contract, stored);
    if (code == null) {
      throw const FnthinkCredentialCorrupted(
        '存下来的配对口令过不了契约的校验：请重新生成一枚（旧的本来也没人能用）',
      );
    }
    final rawAt = await _storage.read(pairingArmedAtKey);
    return FnthinkArmedPairingCode(
      code: code,
      armedAtMs: int.tryParse(rawAt ?? ''),
      ttlSeconds: code.ttlSeconds,
    );
  }

  /// 撤掉口令（不撤也行：服务端那边 5 分钟就过期，单次消耗后也不会复活）。
  /// 留着这扇门是因为**用户想要一个"现在就不能再有人配上来"的按钮**，而不是"等它自己烂掉"。
  Future<void> clearPairingCode() async {
    await _storage.delete(pairingCodeKey);
    await _storage.delete(pairingArmedAtKey);
  }

  /// 恢复出厂/换机时用。⚠ 地址码一清，之前所有配对关系就成了孤儿 —— 调用方负责说清这件事。
  Future<void> clearAll() async {
    await _storage.delete(addressCodeKey);
    await clearPairingCode();
  }
}

/// 挂出去的口令 + 它是什么时候挂出去的。
class FnthinkArmedPairingCode {
  const FnthinkArmedPairingCode({
    required this.code,
    required this.armedAtMs,
    required this.ttlSeconds,
  });

  final FnthinkPairingCode code;

  /// null = 存量的时间戳缺失或不是整数（老数据/被改坏），此时**不知道**挂了多久。
  final int? armedAtMs;
  final int? ttlSeconds;

  /// 已经挂了多久（毫秒）。不知道就 null —— 界面上该显示"未知"，不该显示 0 秒。
  int? ageMs(int nowMs) => armedAtMs == null ? null : nowMs - armedAtMs!;

  /// 显示用的"看起来过期了没有"。**这不是判定**：判定在服务端。
  bool? looksExpired(int nowMs) {
    final age = ageMs(nowMs);
    final ttl = ttlSeconds;
    if (age == null || ttl == null) return null;
    return age > ttl * 1000;
  }

  /// ⚠ 这句里**没有口令本体**：日志会离开这台机（`identity.identityKey.neverIn` 那条精神
  /// 对口令同样成立 —— 口令虽然 5 分钟就烂，但那 5 分钟里它能配上一台设备）。
  @override
  String toString() =>
      'FnthinkArmedPairingCode(****, armedAt=$armedAtMs, ttl=${ttlSeconds}s)';
}

/// 存量与契约对不上。这是一个**需要人来处理**的状态，不是可以自愈的状态。
class FnthinkCredentialCorrupted implements Exception {
  const FnthinkCredentialCorrupted(this.reason);

  final String reason;

  @override
  String toString() => '幻念推送的本机凭证不可用：$reason';
}
