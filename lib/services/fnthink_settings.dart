import 'package:fnthink_push/fnthink_push.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 幻念推送的设备侧设置（T44 的数据层 —— 页面还没做，先把"总开关 + 服务地址"这两件事定下来）。
///
/// 这一层存在的理由不是"存两个值"，而是**默认方向**：
/// ① 接收总开关**默认关**。这台设备从没同意过"通知内容经服务器中转"（T56 的隐私三分要求
///    用幻念 ⇒ 需一次性同意），默认开着等于替用户点了同意 —— 而"升级/新功能不许悄悄做让用户
///    意外的事"是路线图顶部四条不变量之一。
/// ② 服务地址默认取契约 `transport.endpoints.default`（国际那台），大陆切换由 T44 那条
///    "检测到大陆网络时提示"来做 —— 提示可以自动，**改设置不行**。
class FnthinkSettings {
  FnthinkSettings({required this.contract});

  final FnthinkContract contract;

  static const keyReceiveEnabled = 'fnthink.receive_enabled';
  static const keyHost = 'fnthink.host';

  /// 本机记住的「已同意中转」版本号（契约 `privacy.relayConsentVersion` 的那一档）。
  /// **null = 从没同意过** —— 这是默认值，也是"升级不许悄悄替用户点同意"那条不变量的落点。
  static const keyConsentVersion = 'fnthink.consent_version';

  /// 契约要求同意的那一档版本。
  ///
  /// 取不到就抛：没有这个数，"要不要重新问"就没了判据，而缺省成"当同意过了"正是
  /// 替用户点同意的那一种（另一种是当没同意过，代价是所有经服务器的功能对谁都不可用）。
  int get requiredConsentVersion {
    final value = contract.intOf(const ['privacy', 'relayConsentVersion']);
    if (value == null || value <= 0) {
      throw StateError('契约缺 privacy.relayConsentVersion（正整数）');
    }
    return value;
  }

  /// 这台同意过「通知内容经服务器中转」没有（版本够新就算）。
  Future<bool> hasRelayConsent() async {
    final prefs = await SharedPreferences.getInstance();
    final granted = prefs.getInt(keyConsentVersion);
    return granted != null && granted >= requiredConsentVersion;
  }

  /// 本机同意过的版本号（null = 从没同意）。给界面上"你同意的是第几版"那一行用。
  Future<int?> grantedConsentVersion() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(keyConsentVersion);
  }

  /// 记下这一次同意。**只写契约当前那一档**（页面上那行文案就是按它写的），
  /// 不接受调用方传一个别的版本进来 —— 那样"同意的文案"与"记下的版本"会分家。
  Future<void> grantRelayConsent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyConsentVersion, requiredConsentVersion);
  }

  Future<bool> get receiveEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(keyReceiveEnabled) ?? false;
  }

  Future<void> setReceiveEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyReceiveEnabled, value);
  }

  /// 连哪一台（裸主机名，可带端口）。默认是契约声明的那台。
  ///
  /// ⚠ 读的时候**也校验**：写入这条路校验过不代表值一定合法 —— 备份恢复会把 prefs 里的值
  /// 原样灌回来（本仓在通道配置上栽过同一次），那时候这里不校验，后果是拼出一个
  /// `https://a/ b?x=` 这种 authority 然后一路 400，而没人会怀疑到设置上。
  Future<String> get host async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(keyHost);
    if (stored == null || stored.isEmpty) return defaultHost;
    return validateHost(stored);
  }

  /// 存进去之前归一成小写：DNS 大小写不敏感，而 `A.COM` 与 `a.com` 存成两份就会被认成两台服务
  /// （表现是换过一次输入方式之后"原来的端点都不见了"—— 键是按主机名分的）。
  Future<void> setHost(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyHost, validateHost(value));
  }

  /// 契约里默认那一台。取不到就抛：默认地址没有"兜底值"这一说，
  /// 兜底值等于把一个没被协议评审过的域名写进代码。
  String get defaultHost {
    final value = validateHost(
      contract.str(const ['transport', 'endpoints', 'default']) ?? '',
    );
    return value;
  }

  /// scheme 不是自由项：契约 `transport.httpsOnly=true` ⇒ 只能是 https。
  /// 收货服务在装配期还会再判一次，这里是第一次、也是离用户输入最近的那一次。
  Future<Uri> get baseUrl async {
    final h = await host;
    if (contract.boolOf(const ['transport', 'httpsOnly']) != true) {
      // 契约哪天改成允许明文（自部署在内网跑），这里才可能出非 https —— 不在代码里开后门。
      return Uri.parse('http://$h');
    }
    return Uri.https(h, '');
  }

  /// 服务地址的唯一校验点（公开：备份恢复那条路也要走它，不许拷第二份）。
  static String validateHost(String raw) {
    final host = raw.trim().toLowerCase();
    if (host.isEmpty) {
      throw const FnthinkSettingsInvalid('服务地址是空的');
    }
    // 「先判 scheme、再判斜杠」：`https://x` 里确实有 `/`，但用户实际犯的是**多写了 scheme**。
    // 报错了方向要指向他真犯的那个 —— 否则会去主机名里找一个并不存在的斜杠。
    if (host.contains('://')) {
      throw FnthinkSettingsInvalid(
        '服务地址不要写 scheme（$raw）：scheme 由契约 transport.httpsOnly 决定，不是用户输入的一部分',
      );
    }
    for (final bad in const ['/', '\\', '?', '#', '@', ' ']) {
      if (host.contains(bad)) {
        throw FnthinkSettingsInvalid('服务地址只能是裸主机名（可带端口），里面出现了「$bad」：$raw');
      }
    }
    // 端口允许（自部署常见 https://host:8443），但冒号后面必须真的是数字。
    final colon = host.indexOf(':');
    if (colon >= 0) {
      final port = host.substring(colon + 1);
      if (port.isEmpty || int.tryParse(port) == null) {
        throw FnthinkSettingsInvalid('服务地址的端口不是数字：$raw');
      }
    }
    return host;
  }
}

/// 设置里的值不可用（输入错、或备份恢复灌回来一个坏值）。
/// 说清是**哪一项**：这条会被 coordinator 原样转成"为什么没起来"给用户看。
class FnthinkSettingsInvalid implements Exception {
  const FnthinkSettingsInvalid(this.reason);

  final String reason;

  @override
  String toString() => '幻念推送的设置不可用：$reason';
}
