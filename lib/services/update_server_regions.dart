import 'package:shared_preferences/shared_preferences.dart';

/// 更新服务器的两档地区地址与「自动 / 手动」偏好（T95）。
///
/// 需求口径（维护者 2026-10-06）：检测更新的服务器也分国内外两台，用户可选；第一次进入
/// 按用户网络自动选；除后缀与 CDN 外其余链接完全一致。
///
/// ⚠ **两档之间只差主机名**：协议、路径、查询参数、安装包文件名逐字一致。
///   这条由 `test/services/update_server_regions_test.dart` 钉住，并且与官网那份
///   双域名映射（`server/public/index.html` 里的 `_isCom` / `_cdn`）交叉核对 ——
///   同一个事实现在有两份代码在用（站点按 hostname 自推，App 按用户选的档），
///   谁改了另一份不知道，正是本仓「域名口径纠正」那一次的形状。
///
/// ⚠ 为什么**不进** `protocol/fnthink-v1.json`：那份契约管幻念推送的收发链路，
///   两端协商；更新流走的是版本 API（`/api/version/check`），这台服务器由部署方自己维护，
///   「哪个域名对哪个 CDN」是一条部署事实而不是协议。写进契约就等于让契约替一份
///   部署配置背书，而改部署的人不会想起去改契约 —— 那份陈述会静默变成假话。
///   （`update_download_urls.dart` 里 `releaseTagFor` 为什么不进契约，同一个理由。）
enum UpdateServerRegion {
  /// 大陆这一档：入口 `notice.fnthink.com`，它下发的安装包地址落在 `cdn.fnthink.com`。
  mainland(apiHost: 'notice.fnthink.com', cdnHost: 'cdn.fnthink.com'),

  /// 国际这一档：入口 `notice.fnthink.top`，它下发的安装包地址落在 `cdn2.fnthink.top`。
  /// 这一档同时是 [defaultRegion]（= 本改动之前代码里唯一的那台）。
  international(apiHost: 'notice.fnthink.top', cdnHost: 'cdn2.fnthink.top');

  const UpdateServerRegion({required this.apiHost, required this.cdnHost});

  /// 版本 API 的**裸主机名**：scheme 一律由 [apiBase] 加，调用方不许自己拼 `https://`。
  final String apiHost;

  /// 这一档的安装包 CDN 主机名。**只用于展示**：下载地址由该服务器自己下发
  /// （`version.json` 的 `downloads`），客户端从不拼 CDN —— 拼出来的一份是
  /// 「客户端以为的 CDN」，它错的时候正好是 CDN 已经换了的那一天。
  final String cdnHost;

  String get apiBase => 'https://$apiHost';

  /// 界面上从上到下的顺序（大陆在前：多数用户是第一眼看到这一条的那批人）。
  static const List<UpdateServerRegion> ordered = [mainland, international];

  /// 两台都没测出结果时用的那一档 = **今天的行为**。
  ///
  /// 这一档不是"猜一个可用的"：它是唯一一台从本仓有更新流起就在跑的入口，
  /// 拿它兜底时界面必须写「没测出来，用的是默认那一台」（见 [UpdateServerSettings.autoUnprobed]），
  /// 不能把"没读到"演成"读到了好消息"。
  static const UpdateServerRegion defaultRegion = international;

  /// 偏好里存的字符串 → 档位。认不出来返回 null（**不猜**：猜成一档就等于
  /// 用户没选过却被当成选过，而另一档从此在界面上"看起来是他不要的"）。
  static UpdateServerRegion? parse(String? raw) {
    final value = raw?.trim().toLowerCase();
    if (value == null || value.isEmpty) return null;
    for (final region in ordered) {
      if (region.name == value) return region;
    }
    return null;
  }
}

/// 选择方式。
///
/// 「自动」的含义是**跟着最近一次实测走**，不是"每次检查都重猜"：
/// 手动档则是钉住，除非用户自己改，谁都不许动它（与幻念推送那条「禁止自动改已保存的
/// 偏好」同一个口径，见 `fnthink_settings.dart` 的 `ensureFirstRunHost`）。
enum UpdateServerMode { auto, manual }

/// 健康度单点（`ChannelHealthStore`）里这一族的名字。
///
/// ⚠ 更新服务器**不是通道**，它借的是同一个读写口（第 6 步「健康度缓存单点」说的是
///   一件事两份实现的那个问题，不是"只有通道才有健康度"）。幻念那台主机已经这么借过一次
///   （family=`fnthink`、id=主机名），所以 `of(family,id)` 的 family 位必须一直带上：
///   不带的话 `mainland` 这种 id 撞上某条通道的 id 时，徽标会串到别人身上。
const String kUpdateHealthFamily = 'update';

/// 一次「这台更新服务器今天能不能用」的结论（T95 片2）。
///
/// 同一个形状既是**检查更新那一发的副产物**，也是**服务器选择页主动探测的结果** ——
/// 两件事问的是同一个问题，分成两个类就会长出两套"可用"的判据。
/// `reachable` 判的是"按我们要用的那条路答了 200 且业务码可用"，不是"它回了个包"：
/// 被 CDN 拦成 403 的服务器对用户就是不可用。
class UpdateServerProbe {
  const UpdateServerProbe({
    required this.region,
    required this.reachable,
    required this.latencyMs,
    this.httpCode,
    this.latestVersion,
    this.latestBuild,
    this.downloadHost,
  });

  final UpdateServerRegion region;
  final bool reachable;
  final int latencyMs;

  /// 没发出去（超时、DNS 失败）时为 null —— 与"发了但回 500"不是一件事。
  final int? httpCode;

  /// 这一台报告的最新版（**读到才算**，探测失败时是 null）。
  ///
  /// 为什么要摆这个数：两台的 `version.json` 是各自部署的那一份，会漂。
  /// 漂了的时候界面上"这一台说最新版是 1.5.75"是用户唯一看得见的证据。
  final String? latestVersion;
  final int? latestBuild;

  /// 这一台实际下发的安装包主机名（实测，不是档位表里那份声明）。
  final String? downloadHost;
}

/// 检查更新/探测那一发之后把结论交出去（装配点注入，见 `lib/di/service_locator.dart`）。
///
/// ⚠ 为什么用回调而不是在这一层直接 import `ChannelHealthStore`：这一层在后台引擎里也会跑，
///   让服务自己去容器里捞另一个服务，测试与启动顺序就都变成第二件事 —— 幻念协调者
///   已经按这个形状接过一次（`fnthink_receive_wiring_test` 那条守卫防的就是"漏接"）。
typedef UpdateProbeReport =
    Future<void> Function({required UpdateServerProbe probe});

/// 偏好里存的字符串 → 方式。认不出来返回 null。
UpdateServerMode? parseUpdateServerMode(String? raw) {
  final value = raw?.trim().toLowerCase();
  if (value == null || value.isEmpty) return null;
  for (final mode in UpdateServerMode.values) {
    if (mode.name == value) return mode;
  }
  return null;
}

/// 本机记住的更新服务器偏好。
///
/// 三个键各管一件事，故意不合成一个：
/// ①方式（auto / manual）——用户要不要自己管这件事；
/// ②手动钉住的那一档；
/// ③自动档最近一次实测选中的那一档。
/// ②与③分开存，是因为「钉过哪台」不该混进自动判据，而切回自动时上一次实测的结果
/// 也不该被顺手抹掉（抹掉的后果：下一次冷启动之前，自动档会退回默认那一台）。
class UpdateServerSettings {
  UpdateServerSettings({
    required this.mode,
    this.manualRegion,
    this.autoRegion,
  });

  static const keyMode = 'update_server_mode';
  static const keyManualRegion = 'update_server_manual_region';
  static const keyAutoRegion = 'update_server_auto_region';

  final UpdateServerMode mode;
  final UpdateServerRegion? manualRegion;
  final UpdateServerRegion? autoRegion;

  /// 读偏好。认不出来的值一律当成"没这个键"（回到自动 + 没测过）：
  /// 一台设备的偏好被备份恢复灌回来一份别的版本的字符串时，这里崩溃或猜档都不是
  /// 好结局 —— 猜档尤其坏，因为它会替用户做出他没有做过的那个选择。
  factory UpdateServerSettings.fromPrefs(SharedPreferences prefs) {
    return UpdateServerSettings(
      mode:
          parseUpdateServerMode(prefs.getString(keyMode)) ??
          UpdateServerMode.auto,
      manualRegion: UpdateServerRegion.parse(prefs.getString(keyManualRegion)),
      autoRegion: UpdateServerRegion.parse(prefs.getString(keyAutoRegion)),
    );
  }

  static Future<UpdateServerSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    return UpdateServerSettings.fromPrefs(prefs);
  }

  bool get isAuto => mode == UpdateServerMode.auto;

  /// 自动档**一次都没测出来过**。界面必须把这一件事说出来：
  /// 此时 [region] 回的是默认那一台，看起来与"测过、结论是用这台"一模一样。
  bool get autoUnprobed => isAuto && autoRegion == null;

  /// 当前该用哪一台。
  UpdateServerRegion get region => resolveUpdateRegion(
    mode: mode,
    manualRegion: manualRegion,
    autoRegion: autoRegion,
  );

  /// 记下这一次自动实测的结果。**不改方式**：用户停在自动时才由它决定用哪台，
  /// 停在手动时这条只是一份"上次实测是谁"的记录（切回自动时立刻能用）。
  Future<void> recordAutoProbe(UpdateServerRegion region) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyAutoRegion, region.name);
  }

  /// 交回自动。钉住的那一档留着不清：清了之后用户来回切一次，
  /// 自动档会退回默认那一台，而他刚刚明明看着它选对了。
  Future<void> setAuto() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyMode, UpdateServerMode.auto.name);
  }

  /// 钉住某一档。
  Future<void> setManual(UpdateServerRegion region) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyMode, UpdateServerMode.manual.name);
    await prefs.setString(keyManualRegion, region.name);
  }
}

/// 纯函数：给定方式与记住的两档，该用哪一台。
///
/// 手动但钉不住（偏好缺键 / 存了个认不出来的值）时回 [fallback] 而不是回自动档：
/// 用户说过"我要这台"却没能落到这一台，那是配置坏了，界面要把 fallback 这一事实
/// 显式讲出来（[UpdateServerSettings.autoUnprobed] 是同一类话的另一半）。
UpdateServerRegion resolveUpdateRegion({
  required UpdateServerMode mode,
  UpdateServerRegion? manualRegion,
  UpdateServerRegion? autoRegion,
  UpdateServerRegion fallback = UpdateServerRegion.defaultRegion,
}) {
  if (mode == UpdateServerMode.manual) return manualRegion ?? fallback;
  return autoRegion ?? fallback;
}

/// 自动档的选法：两台都探过，取**可用里面更快**的那一台。
///
/// ⚠ 前提是"两台都被测过"：拿一台的结果替另一台说话，等于用一次测量做了一个比较。
/// ⚠ 都没探通 ⇒ 回 null，**不是**默认那一台。"没测出来"与"测出来就是它"是两句话，
///   混成一句会让一个凭空来的结论在界面上看起来像实测结果
///   （[UpdateServerSettings.autoUnprobed] 就是为了把这两句分开说）。
/// ⚠ 平手按 [preferredOrder]（大陆在前）：时延相同说明这一次测量分不出先后，
///   随机挑会让同一台设备两次开机走到不同档，而徽标与"最新版"数字看着都像服务器换了。
UpdateServerRegion? pickAutoRegion(
  Map<UpdateServerRegion, UpdateServerProbe> probes, {
  List<UpdateServerRegion> preferredOrder = UpdateServerRegion.ordered,
}) {
  ({UpdateServerRegion region, int latencyMs})? best;
  for (final region in preferredOrder) {
    final probe = probes[region];
    if (probe == null || !probe.reachable) continue;
    if (best == null || probe.latencyMs < best.latencyMs) {
      best = (region: region, latencyMs: probe.latencyMs);
    }
  }
  return best?.region;
}
