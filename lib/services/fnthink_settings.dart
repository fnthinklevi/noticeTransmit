import 'package:fnthink_push/fnthink_push.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fnthink_endpoint_probe.dart';

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

  /// 「多久问一次货」用户选的那一档（秒）。没这个键 = 从没选过 ⇒ 用契约的 default（T88）。
  /// 存"用户选没选过"而不是存"当前生效的那个数"：后者会把协议给的与用户选的抹成同一份，
  /// 契约哪天调档时这台就跟不上。
  static const keyPollSeconds = 'fnthink.poll_interval_seconds';

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

  /// 撤销「通知内容经服务器中转」的同意（T119）。**只清这一枚键，别的什么都不碰**。
  ///
  /// 为什么只清一枚：撤销的是"我允许你把内容中转"这一个许可，不是"把这些记录都抹掉"——
  /// 名单、接入端点、幻念通道配置、收发历史都留着。把它们一起删的后果是用户想收回一个许可，
  /// 换来的是把自己配好的东西全丢一遍（而那会让他不敢点这个按钮）。
  ///
  /// ⚠ 与备份那条不变量同形：那条是**恢复时不替他点同意**（fail-closed），这一条是
  ///   **撤销时不替他删数据**。两边都不许顺手。
  /// ⚠ 撤销**不硬切正在飞的那一发**：收货循环下一轮在 `_resolveSpec` 那里 early-return
  ///   `not-consented`，已经收到的东西留在库里。
  Future<void> revokeRelayConsent() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyConsentVersion);
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

  /// T76 ⓑ 首启选路：**只在"从没选过"时**按实测时延选一次，选完立刻落盘。
  ///
  /// ⚠ 与「禁止自动切换」（T76 §6 ⑤）的分工写在这里，别把它们混成一句：
  /// ⑤ 管的是**已保存的偏好**被自动改掉；这一条只在偏好为空时动一次，
  /// 且结果**写进偏好** ⇒ 之后无论探测结果怎么变、用户按没按过，都不再自动选。
  /// 换句话说：它跑完这一次之后，己就是"用户的偏好"。
  ///
  /// [latencyProbe] 可注入（测试与"不想要探测"的那条路都用它）；null ⇒ 用真的
  /// [measureEndpointLatency]。**探测失败或两台都测不到 ⇒ 落契约的 default**
  /// 并同样写进偏好：宁可给一个确定的默认，也不要每次冷启动都重猜一次。
  Future<String> ensureFirstRunHost({
    EndpointLatencyProbe? latencyProbe,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(keyHost);
    if (stored != null && stored.isNotEmpty) {
      // 有偏好 ⇒ 一个字节都不许自动改（哪怕探测说另一台更快）。
      return validateHost(stored);
    }
    final hosts = declaredHosts.map((h) => h.host).toList();
    final probe = latencyProbe ?? measureEndpointLatency;
    final picked =
        nearestHost(await probe(hosts), preferredOrder: hosts) ?? defaultHost;
    await setHost(picked);
    return picked;
  }

  /// T76 双地域：契约声明的那**两台**（`transport.endpoints.international` /
  /// `mainland`），按声明顺序返回，供页面摆一个"选哪台"。
  ///
  /// ⚠ **候选恒是这两台，`.com` 没部署好也照样列出来**（T76 §6 定的口径）：探测不通就在
  /// 界面上说"不可用"，而不是把它从候选里拿掉 —— 拿掉的那一刻用户就没有回去的路，
  /// 而这一版能不能用是**运维侧**的事，不是客户端该替它做的判断。
  /// ⚠ 从契约读而不是在这里写死域名：本仓已经吃过一次「域名口径纠正」的亏
  /// （代码里那份与契约那份漂移，客户端连到了没部署的那台）。
  List<({String key, String host})> get declaredHosts {
    const keys = ['international', 'mainland'];
    final out = <({String key, String host})>[];
    for (final k in keys) {
      final raw = contract.str(['transport', 'endpoints', k]) ?? '';
      if (raw.isEmpty) continue; // 契约校验已保证非空；这里跳过而不是抛，页面另有错误位
      out.add((key: k, host: validateHost(raw)));
    }
    return out;
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

  /// 「多久问一次货」这一档（T88）。范围与判据的唯一作者仍是契约
  /// （`presence.pollIntervalSeconds` 的 min/max/default），这一层只是设备侧设置的门面 ——
  /// 与 `host` / `baseUrl` 对 `transport` 段的关系一模一样。
  ///
  /// 三件事分开做，是因为它们各自的失败方式不同：
  ///  - [pollSecondsRange]：界面上那格可点的范围。取不到就抛（没有范围就没有可校验的依据，
  ///    缺省成"随便填"等于把用户送到会被服务端持续 429 的那一档）。
  ///  - [pollSeconds]：**读的时候也校验**（同 `host` 那次教训 —— 备份恢复会把 prefs 里的值
  ///    原样灌回来，不校验的那一条路才是漏的那一条）。
  ///  - [setPollSeconds]：写之前校验，越界**抛**而不是夹 —— 悄悄夹掉的表现是"界面写 60、
  ///    实际按 30 跑"，而用户唯一的线索就是屏幕上那个数字。
  ({int min, int max}) get pollSecondsRange {
    try {
      return contract.pollIntervalRange;
    } on StateError catch (e) {
      throw FnthinkSettingsInvalid(e.message);
    }
  }

  /// 本机选的那一档（null = 从没选过 ⇒ 用契约的 default）。
  Future<int?> get pollSeconds async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getInt(keyPollSeconds);
    if (stored == null) return null;
    return _checked(stored);
  }

  Future<void> setPollSeconds(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyPollSeconds, _checked(seconds));
  }

  /// 抹掉这一档 = 回到"从没选过"，于是契约的 default 重新生效。
  /// 做成一件独立的事是因为界面上要能"恢复默认"，而写回 default 那个数会把"用户选的"
  /// 与"协议给的"这两种来源抹平（下次契约调档时，写死数值的那台就再也跟不上）。
  Future<void> clearPollSeconds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyPollSeconds);
  }

  /// 现在真正该用的那一档秒数（用户选的那一档，没选过就是契约的 default）。
  /// 读数处只有这一句 + 契约那一份数，闹钟与收货循环都从这里取值。
  Future<int> effectivePollSeconds() async =>
      contract.effectivePollIntervalSeconds(await pollSeconds);

  /// 一次读齐"收取间隔那一格要显示什么"（T88）。
  ///
  /// 做成一发而不是三个 getter 让页面自己拼：分三次读就有"某一次抛了、界面只显示半格"那种
  /// 形状 —— 而这一格里"用户选的"与"协议默认"与"坏值没生效"是三件必须同时说清的事。
  Future<FnthinkPollSetting> pollSetting() async {
    final range = pollSecondsRange;
    String? problem;
    int? chosen;
    try {
      chosen = await pollSeconds;
    } on FnthinkSettingsInvalid catch (e) {
      // prefs 里那一档协议不允许（备份恢复灌回来的那一种）：如实报出来，
      // 并按"没选过"处理 —— 让这一格还能被改，而不是整格消失。
      problem = e.reason;
    }
    return FnthinkPollSetting(
      range: range,
      chosen: chosen,
      effective: contract.effectivePollIntervalSeconds(chosen),
      problem: problem,
    );
  }

  int _checked(int seconds) {
    try {
      return contract.checkedPollIntervalSeconds(seconds);
    } on StateError catch (e) {
      throw FnthinkSettingsInvalid(e.message);
    }
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

/// 设置里那一格「收取间隔」的完整读数（T88）。
class FnthinkPollSetting {
  const FnthinkPollSetting({
    required this.range,
    required this.chosen,
    required this.effective,
    this.problem,
  });

  /// 协议允许的范围（界面上滑杆的两端，来自契约，不是本机写的）。
  final ({int min, int max}) range;

  /// 用户真选过的那一档；null = 从没选过（≠ "选了默认值"，这两件事界面上要分开说）。
  final int? chosen;

  /// 现在真正生效的那一档秒数。
  final int effective;

  /// 非 null = prefs 里存着的那一档协议不允许（备份恢复灌回来的那一种），
  /// 此时 [chosen] 按"没选过"处理 —— 报错要说出来，但那一格仍然要能被改回来。
  final String? problem;
}

/// 设置里的值不可用（输入错、或备份恢复灌回来一个坏值）。
/// 说清是**哪一项**：这条会被 coordinator 原样转成"为什么没起来"给用户看。
class FnthinkSettingsInvalid implements Exception {
  const FnthinkSettingsInvalid(this.reason);

  final String reason;

  @override
  String toString() => '幻念推送的设置不可用：$reason';
}
