import 'dart:math';

import 'package:fnthink_push/fnthink_push.dart';

import 'fnthink_remote_execution.dart';
import 'remote_credentials.dart';
import 'secure_storage_service.dart';

/// 远程执行凭据的本机存法（片3b）。
///
/// ⚠ 落盘的东西**只有三样**，而且每一样都不能单独让别人控制这台设备：
/// - `keyHash`（`sha256(salt|key)`）—— 明文密钥落盘那一刻就等于把它交出去了；
/// - `salt`（安装盐，16 字节）—— 让自定义的低熵口令没有通用彩虹表可查；
/// - `totpSecret` —— **这一项是明文，且必须明文**：B 要校验 A 的 6 位码就得有种子
///   （RFC 6238 的输入就是它）。它进的是 **EncryptedSharedPreferences**，不进备份、
///   不进日志、不进回执。⚠ 契约把这条写成了 `auth.totpSecretOwner: "receiver"` ——
///   种子只存在于**接收端**，A 那侧是把它录进验证器 App 之后由验证器保管。
///
/// ⚠ 换句话说：**本类不存"延时秒数"与"总开关"**。那两件是决定不是秘密，
/// 走 `FnthinkRemoteSettings`（明文 prefs）—— 免得"关掉远程执行"要动一把 KeyStore 钥匙，
/// 而钥匙读不出来时用户会以为设置丢了。
class RemoteCredentialStore {
  RemoteCredentialStore({
    required this.contract,
    SecureStorageService? storage,
    Random? random,
    int Function()? clockMs,
  }) : _storage = storage ?? SecureStorageService(),
       _random = random ?? Random.secure(),
       _clockMs =
           clockMs ?? (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  final FnthinkContract contract;
  final SecureStorageService _storage;
  final Random _random;
  final int Function() _clockMs;

  static const keyHashKey = 'fnthink.remote.key_hash';
  static const saltKey = 'fnthink.remote.salt';
  static const totpSecretKey = 'fnthink.remote.totp_secret';

  /// 本机这一份凭据（**不含明文密钥**）。
  ///
  /// ⚠ 三件各自可空而组合起来才有意义：只有 salt 没有 hash = 用户还没设过密钥
  /// （正常状态，不是坏了）；只有 hash 没有 salt = **存量坏了**（盐丢了等于所有
  /// 已设的密钥当场作废，而且没法自愈）—— 这种情况抛而不是当"没设过"，
  /// 否则界面上会显示"还没设过密钥"，用户重新设一把之后**旧的还在别人手里**。
  Future<RemoteCredentialEntry?> read() async {
    final hash = await _storage.read(keyHashKey);
    final salt = await _storage.read(saltKey);
    final totp = await _storage.read(totpSecretKey);
    final hasKey = hash != null && hash.isNotEmpty;
    final hasSalt = salt != null && salt.isNotEmpty;
    final hasTotp = totp != null && totp.isNotEmpty;
    if (!hasKey && !hasTotp && !hasSalt) return null;
    if (hasKey && !hasSalt) {
      throw const RemoteCredentialCorrupted(
        '存着高级密钥的哈希，却没有那把安装盐 —— 盐丢了的话这把密钥永远算不出对错，'
        '而且没有任何办法自愈。请走「重置远程凭据」重新设一把。',
      );
    }
    return RemoteCredentialEntry(
      keyHash: hasKey ? hash : null,
      salt: hasSalt ? salt : null,
      totpSecret: hasTotp ? totp : null,
    );
  }

  /// 生成（或换掉）一把高级密钥。**明文只在这一发里出现**，调用方必须当场显示给用户抄走。
  ///
  /// ⚠ 为什么不给"每次进页面就生成一把"：`read()` 那一处明确不生成，
  /// 与地址码同一条纪律（`FnthinkCredentialStore.storedAddressCode` 的注释里写了原因）。
  Future<RemoteCredentialIssue> generateKey() async {
    final salt = await _ensureSalt();
    final key = generateRemoteKey(contract, _random);
    await _storage.write(keyHashKey, hashRemoteKey(key, salt));
    return RemoteCredentialIssue(key: key, salt: salt);
  }

  /// 用户自定义一把密钥。**长度不足契约的 `keyMinLength` 就抛，不悄悄截断也不悄悄补长**：
  /// 界面写"已设置"而实际生效的是另一串（补长）或更短的一串（截断），用户无从发现。
  Future<void> setCustomKey(String key) async {
    final min = contract.remoteExecutionKeyMinLength;
    final trimmed = key.trim();
    if (trimmed.length < min) {
      throw RemoteCredentialInvalid('高级密钥至少要 $min 个字符（现在 ${trimmed.length} 个）');
    }
    final salt = await _ensureSalt();
    await _storage.write(keyHashKey, hashRemoteKey(trimmed, salt));
  }

  /// 换一枚 TOTP 种子。**明文只在这一发里出现**（调用方据此显示链接与密钥串）。
  ///
  /// ⚠ 换种子 = 已录进验证器的那一枚当场作废（A 侧要重新录）—— 这一句必须由界面说出去，
  /// 不写在这里是因为它是对**另一个设备上的人**说的话。
  Future<RemoteTotpIssue> generateTotp({required String account}) async {
    final shape = contract.remoteExecutionTotpShape;
    final secretBytes = List<int>.generate(20, (_) => _random.nextInt(256));
    final secret = base32Encode(secretBytes);
    await _storage.write(totpSecretKey, secret);
    return RemoteTotpIssue(
      secret: secret,
      digits: shape.digits,
      periodSeconds: shape.periodSeconds,
      uri: otpAuthUri(
        secretBase32: secret,
        account: account,
        issuer: _issuer,
        digits: shape.digits,
        periodSeconds: shape.periodSeconds,
      ),
    );
  }

  /// 撤掉 TOTP 种子（"我不用验证码这一种了"）。
  Future<void> clearTotp() => _storage.delete(totpSecretKey);

  /// 撤掉高级密钥。
  Future<void> clearKey() => _storage.delete(keyHashKey);

  /// 全部撤掉（**含安装盐**：留着盐没有任何用处，而留着它等于"上次那把密钥的哈希还在算"）。
  Future<void> clearAll() async {
    await _storage.delete(keyHashKey);
    await _storage.delete(saltKey);
    await _storage.delete(totpSecretKey);
  }

  /// 校验一条指令带来的凭据 —— [RemoteExecutionCredentialProbe] 的**唯一实现**。
  ///
  /// ⚠ 计时：TOTP 校验里有 HMAC 与 sha256，走的是 [RemoteExecutionCredentialProbe] 的
  ///   `Future` 形状（片2 定的），所以这里的两次 await 都在同一个 isolate 上顺序跑；
  ///   而**密钥**那条走定长比较（`verifyRemoteKey`），不为 TOTP 那一路做对称的常数时间 ——
  ///   那要靠"两条路的耗时结构不同"来对齐，实测不可证，因此不假装做了。
  Future<bool> keyMatches(String presented) async {
    final entry = await read();
    final hash = entry?.keyHash;
    final salt = entry?.salt;
    if (hash == null || salt == null) return false;
    return verifyRemoteKey(presented: presented, salt: salt, storedHash: hash);
  }

  /// TOTP 6 位码是否有效。⚠ 种子缺失 ⇒ **一律 false**（fail-closed）：
  /// "本机没设过 TOTP"而对面发来一个码，判成 true 等于给没配过的设备开了这条路。
  Future<bool> totpValid(String code) async {
    final entry = await read();
    final secret = entry?.totpSecret;
    if (secret == null || secret.isEmpty) return false;
    final shape = contract.remoteExecutionTotpShape;
    return verifyTotpCode(
      secret,
      presented: code,
      atMs: _clockMs(),
      digits: shape.digits,
      periodSeconds: shape.periodSeconds,
    );
  }

  /// 一次性把两层（总开关、延时窗口）与凭据读齐给设置页用。
  ///
  /// ⚠ `credential == null` 与 `credential.problem != null` 是**两件必须分开说的事**：
  /// 前者是"还没设过"（用户该去设），后者是"存的东西坏了"（用户该去重置）。
  /// 合成一句"本机还没设过凭据"就会让第二种情形里的用户重新设一把，而**旧的还在别人手里**。
  Future<RemoteCredentialState> state({
    required bool enabled,
    required int delaySeconds,
  }) async {
    RemoteCredentialEntry? entry;
    String? problem;
    try {
      entry = await read();
    } on RemoteCredentialCorrupted catch (e) {
      problem = e.reason;
    }
    final shape = contract.remoteExecutionTotpShape;
    return RemoteCredentialState(
      enabled: enabled,
      delaySeconds: delaySeconds,
      entry: entry,
      problem: problem,
      totpDigits: shape.digits,
      totpPeriodSeconds: shape.periodSeconds,
    );
  }

  Future<String> _ensureSalt() async {
    final stored = await _storage.read(saltKey);
    if (stored != null && stored.isNotEmpty) return stored;
    final fresh = generateInstallSalt(_random);
    await _storage.write(saltKey, fresh);
    return fresh;
  }

  /// `otpauth://` 链接里的 issuer。
  ///
  /// ⚠ **为什么这里不能写死一个中文名**：验证器 App 会把这个字段显示给用户看，
  /// 而它进入的是另一台设备（多半是别人的手机）。写死一个"通知转发助手"之外的东西
  /// 都不是 bug，只是没必要 —— 契约里没有这一项，它就只在本页出现一次。
  static const _issuer = 'NoticeTransmit';
}

/// 本机存着的那一份（**没有明文密钥**）。
class RemoteCredentialEntry {
  const RemoteCredentialEntry({this.keyHash, this.salt, this.totpSecret});

  final String? keyHash;
  final String? salt;

  /// ⚠ 明文（RFC 6238 的输入）。**调用方不许把它写进任何日志或回执**。
  final String? totpSecret;

  bool get hasKey => keyHash != null;
  bool get hasTotp => totpSecret != null && totpSecret!.isNotEmpty;

  @override
  String toString() =>
      'RemoteCredentialEntry(key: ${hasKey ? '已设' : '未设'}, totp: ${hasTotp ? '已设' : '未设'})';
}

/// 「生成一把」的结论 —— **明文只活在这个对象里**。
class RemoteCredentialIssue {
  const RemoteCredentialIssue({required this.key, required this.salt});

  final String key;
  final String salt;
}

class RemoteTotpIssue {
  const RemoteTotpIssue({
    required this.secret,
    required this.digits,
    required this.periodSeconds,
    required this.uri,
  });

  final String secret;
  final int digits;
  final int periodSeconds;

  /// `otpauth://totp/…`，验证器 App 的标准录入格式。
  final String uri;
}

/// 设置页那一格要显示的全部内容（**一次读齐**，理由同 `FnthinkPollSetting`）。
class RemoteCredentialState {
  const RemoteCredentialState({
    required this.enabled,
    required this.delaySeconds,
    required this.totpDigits,
    required this.totpPeriodSeconds,
    this.entry,
    this.problem,
  });

  final bool enabled;
  final int delaySeconds;

  /// null = 还没设过任何凭据；非 null = 设过（哪几样看 [RemoteCredentialEntry]）。
  final RemoteCredentialEntry? entry;

  /// 非 null = 存量坏了，**不是"还没设过"**。
  final String? problem;

  final int totpDigits;
  final int totpPeriodSeconds;

  bool get hasKey => entry?.hasKey ?? false;
  bool get hasTotp => entry?.hasTotp ?? false;

  /// 开了但一把凭据都没有 ⇒ **L3 一条都进不来**（契约 `l3Requires:true`）。
  /// 界面必须把这句说出去，而不是让用户开完开关去发一条然后不知道为什么被拒。
  bool get l3Unreachable => enabled && !hasKey && !hasTotp && problem == null;
}

/// 存量坏了。这是**要人来处理**的状态，不是可自愈的状态。
class RemoteCredentialCorrupted implements Exception {
  const RemoteCredentialCorrupted(this.reason);

  final String reason;

  @override
  String toString() => '远程执行的凭据不可用：$reason';
}

/// 用户给的值不合法（自定义密钥太短）。
class RemoteCredentialInvalid implements Exception {
  const RemoteCredentialInvalid(this.reason);

  final String reason;

  @override
  String toString() => '远程执行的凭据不可用：$reason';
}

/// 把本类接到片2 的凭据校验上（页面与收货链路都走它，不自己 new 一份）。
RemoteExecutionCredentialProbe remoteCredentialProbe(
  RemoteCredentialStore store,
) => _StoreProbe(store);

class _StoreProbe extends RemoteExecutionCredentialProbe {
  _StoreProbe(this.store);

  final RemoteCredentialStore store;

  @override
  Future<bool> keyMatches(String presentedKey) =>
      store.keyMatches(presentedKey);

  @override
  Future<bool> totpValid(String code) => store.totpValid(code);
}
