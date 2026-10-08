import 'package:get_it/get_it.dart';

import '../models/email_channel.dart';
import '../models/fnthink_channel.dart';
import 'app_channel_service.dart';
import 'channel_config_codec.dart';
import 'channel_health_store.dart';
import 'channel_display.dart';
import 'channel_probe_service.dart';
import 'email_service.dart';
import 'fnthink_channel_probe.dart';
import 'fnthink_channel_service.dart';
import 'fnthink_endpoint_dryrun.dart';
import 'webhook_service.dart';

/// 一条通道在首页/状态页的健康态。**四态**（T115 决定一把"过期"从 `unknown` 里拆出来了）：
/// `ok` 有新鲜的正常结论 · `error` 有确凿的失败证据 · `stale` 上次结论是正常但已过时效 ·
/// `unknown` 从没测过。
enum ChannelHealthState { ok, error, stale, unknown }

/// 四态判定的**唯一**实现（T04 抽出三态，T115 决定一改口径）：首页通道卡、通道状态页、
/// 各通道列表的徽标必须同一条规则，否则同一刻会出现"首页说正常、列表说失败"。
///
/// - `null`（从没测过）算 [ChannelHealthState.unknown]：说不出可用性就画成红色，
///   等于把"我不知道"伪装成"坏了"；
/// - 失败则一直是失败（有确凿证据），直到下一次测试覆盖它 ⇒ `error` **不**按时效拆；
/// - 成功但过了 [ChannelHealthStore.staleness] 是 [ChannelHealthState.stale]。
///   ⚠ 这一档在 2026-10-08 之前画成 `unknown`，当时的理由是"没有新鲜的探测结果，
///   既不能说正常也不能说异常"。维护者拍的**新**口径是：可以说正常，但必须把
///   "上次探测于 X 前"一起说出来 —— 只说正常、不带上次时间仍是那句禁令禁的谎。
///   所以这一态带着一条**显示契约**，由 [channelHealthStateForDisplay] 把关：
///   拿不出时间的过期结论（`probedAt == 0`，email 旧缓存搬进来的那种）宁可退回 `unknown`。
ChannelHealthState channelHealthState(ChannelHealth? h) {
  if (h == null) return ChannelHealthState.unknown;
  if (!h.reachable) return ChannelHealthState.error;
  return ChannelHealthStore.needsProbe(h)
      ? ChannelHealthState.stale
      : ChannelHealthState.ok;
}

/// **显示**用的那一条判定（T115 决定一的显示契约）：所有画徽标/状态词的地方读它，
/// 而调度（"这条过期了吗，要不要重探"）读 [channelHealthState]。
///
/// 为什么要有第二枚而不直接把时间塞进 [channelHealthState]：那条规则会读 `probedAt`
/// 之外的东西（时间能不能说出来），而调度侧关心的是"过没过时效"这一件事。
/// 分开的代价是"两处各读一枚"，所以守卫钉住：**显示点只许读这一枚**。
ChannelHealthState channelHealthStateForDisplay(ChannelHealth? h) {
  final state = channelHealthState(h);
  if (state == ChannelHealthState.stale && (h == null || h.probedAt <= 0)) {
    // 「上次是通的」这句要成立，得连带说得出"上次是什么时候"。说不出口就还是未知 ——
    // 这一支不是防御性代码：email 族的旧缓存 `email_test_results` 就没有时间戳（搬进来
    // 时 probedAt 记 0），而它确实能读出一条"通"的历史结论。
    return ChannelHealthState.unknown;
  }
  return state;
}

/// 通道**族**的同一份清单：显示分组的顺序、主备弹层要列的族、`updateChannelRole` 能写回的族，
/// 三处都从这里取（T113）。
///
/// 为什么收成一份：这三处今日是同一个集合，却在三个文件里各数各的 —— 一旦少数一族，
/// 表现是"这一族能配能显示，快捷入口里却没有它"（维护者报的 T113），或者反过来
/// "列表里有这一行、点下去没人写"（写路径 `default:` 回 false，界面只能说那句「这条通道已经不在了」，
/// 而那句话说的是**没找到**，不是**没人会写**）。守卫钉住"switch 的 case 集合 == 这一份"。
///
/// ⚠ 只有**主备**这一档是四族。启用/停用（`updateChannelEnabled` 与远程指令
/// `channel:toggle` 的 `isKnownChannelFamily`）仍是那三族 —— 幻念那一族的启停走
/// `FnthinkChannelService.save()`，那一发要连带重验目标，形状与"设一个布尔"不是一件事。
const List<String> channelFamilies = ['webhook', 'email', 'app', 'fnthink'];

/// 一个**已启用**通道的条目：身份、显示名、用户命名、最近一次探测结果。
class ActiveChannel {
  const ActiveChannel({
    required this.family,
    required this.slug,
    required this.id,
    required this.displayName,
    required this.configName,
    required this.target,
    required this.role,
    this.health,
  });

  /// 'webhook' | 'app' | 'email' | 'fnthink'
  final String family;

  /// 规范 slug（`dingtalk` / `wecom_app` / `email`），与送达键、图标表同口径
  final String slug;

  /// 通道行 id（健康缓存按 `family:id` 存）
  final String id;

  /// 类型显示名（随语言，纯显示用，**不参与任何键**）
  final String displayName;

  /// 用户给这条通道起的名字
  final String configName;

  /// 关键链接（通道状态页用）：**只有 host[:port]**，见 [channelTargetLabel]。
  /// 邮件族没有 URL，放 `smtpHost:port`。
  final String target;

  /// 主备角色（T11）：`ChannelConfigCodec.rolePrimary` / `roleBackup` / `roleNone`。
  /// 与 `enabled` 是两件事：enabled=false 根本不进这份清单，role=none 是"启用但
  /// 不参与推送"（保留配置以便随时归队）。
  final String role;

  /// 最近一次探测结果（来自健康单点）。null = 从没探过。
  final ChannelHealth? health;

  String get deliveryKey => channelDeliveryKey(slug);

  /// 健康态：见 [channelHealthStateForDisplay]（显示侧的单点，各页共用同一条规则）。
  /// 这一枚是**给界面读的** —— 首页与状态页拿它取文案与点色，所以它带那条"过期必须
  /// 说得出时间"的显示契约（T115）。调度侧问"过没过期"走 `ChannelHealthStore.needsProbe`。
  ChannelHealthState get healthState => channelHealthStateForDisplay(health);

  /// 首页「当前推送通道」的状态标签（页面据此取 l10n 文案与点色）。
  String get statusLabel => switch (healthState) {
    ChannelHealthState.ok => 'ok',
    ChannelHealthState.error => 'error',
    ChannelHealthState.stale => 'stale',
    ChannelHealthState.unknown => 'unknown',
  };

  /// 统一显示格式 `类型：（子类型/）通道名`（邮件族无子类型）。
  /// 名字为空时不留空尾巴 —— 只到子类型为止。
  String get displayLine {
    final familyName = channelFamilyName(family);
    final name = configName.trim();
    final subtype = family == 'email' ? '' : displayName.trim();
    final tail = [
      if (subtype.isNotEmpty && subtype != familyName) subtype,
      if (name.isNotEmpty) name,
    ].join('/');
    return tail.isEmpty
        ? familyName
        : '$familyName${channelLabelSeparator()}$tail';
  }
}

/// 当前启用的通道清单（**唯一实现**，第 6 步）。
///
/// 此前有两份：`main_page` 返回 `Map{type,name,status}` 给首页显示，
/// `notification_service` 返回送达键列表给入库快照与初始送达状态。
/// 两份都是「遍历各 service 的 enabled」，同一件事两个实现 ——
/// 加一个通道族或改判 enabled 的口径时只改一处，就会出现
/// 「首页显示了三条而历史记录只按两条算」这类对不上的账。
///
/// 顺序沿用首页原有观感：应用通道 → webhook → 邮件 → 幻念推送
/// （第四族是 T104 片③ 才进来的；它此前一直缺席，而一条启用中的幻念通道**照在转发**，
/// 界面上看不见就等于让用户猜。它排在最后是刻意的：这一族的徽标只能靠人手动测（见下面
/// 那段 ⚠），把它排在前面会让首页顶上第一行就是「未知」）。
/// 服务侧只取 [deliveryKeysOfActiveChannels]（去重后与顺序无关）。
List<ActiveChannel> collectActiveChannels() {
  final result = <ActiveChannel>[];

  // ⚠ 两个 GetIt 解析必须分开兜底：合成一个 try 时「健康单点没注册」会连带把
  //   email 通道整族丢掉 —— 表现是历史记录的送达快照里再也不会出现 chan:email。
  ChannelHealthStore? health;
  try {
    health = GetIt.instance<ChannelHealthStore>();
  } catch (_) {
    health = null;
  }

  for (final c in _rows(() => GetIt.instance<AppChannelService>().channels)) {
    if (c['enabled'] != true) continue;
    final appType = c['appType']?.toString() ?? '';
    final id = c['id']?.toString() ?? '';
    // 未登记的 appType 也要出现在清单里（它可能就是原生新增而 Dart 未跟上的通道）：
    // 跳过会让「历史记录按几条算」与首页显示不一致，且推送照发不误。
    result.add(
      ActiveChannel(
        family: 'app',
        slug: appType,
        id: id,
        displayName: channelTypeDisplayName(appType),
        configName: c['name']?.toString() ?? '',
        target: channelTargetLabel(c['baseUrl']?.toString() ?? ''),
        role: ChannelConfigCodec.normalizeRole(c['role']),
        // T01：三族一律读健康单点。此前只有 email 带状态，webhook / 应用通道恒判 ok，
        // 首页于是对着一堆从没探过的通道显示"状态正常"。
        health: health?.of('app', id),
      ),
    );
  }

  for (final c in _rows(() => GetIt.instance<WebhookService>().channels)) {
    if (c['enabled'] != true) continue;
    final type = c['type']?.toString() ?? 'generic';
    final id = c['id']?.toString() ?? '';
    result.add(
      ActiveChannel(
        family: 'webhook',
        slug: type,
        id: id,
        displayName: channelTypeDisplayName(type),
        configName: c['name']?.toString() ?? '',
        target: channelTargetLabel(c['url']?.toString() ?? ''),
        role: ChannelConfigCodec.normalizeRole(c['role']),
        health: health?.of('webhook', id),
      ),
    );
  }

  List<EmailChannel> emails;
  try {
    emails = GetIt.instance<EmailService>().cachedChannels;
  } catch (_) {
    emails = const [];
  }
  for (final c in emails.where((c) => c.enabled)) {
    result.add(
      ActiveChannel(
        family: 'email',
        slug: 'email',
        id: c.id,
        displayName: channelTypeDisplayName('EMAIL'),
        configName: c.name,
        // 邮件族没有 URL：smtp 主机+端口就是它的"关键链接"（不含口令）
        target: '${c.smtpHost}:${c.smtpPort}',
        role: ChannelConfigCodec.normalizeRole(c.role),
        health: health?.of('email', c.id),
      ),
    );
  }

  // 第四族：幻念推送的通道（T104 片③）。它此前一直不在这份清单里，而一条启用中的幻念通道
  // **照在转发**（原生 fanout 读的是通道表，不看这份列表）—— 界面上看不见，用户就只能猜。
  //
  // ⚠ 它的健康度现在**能自动重探了**（T106 片③：非侵入探针 `/probe` 落了地，见下面
  //   `probeChannelsAcrossFamilies` 里那一段）；在那之前这里写的是"绝不进自动重探"。
  //   两种目标各有各的那一发（片①b）：设备档＝一次签名探针，端点档＝一次干跑（一条都不投）。
  List<FnthinkChannel> fnthinkChannels;
  try {
    fnthinkChannels = GetIt.instance<FnthinkChannelService>().cachedChannels;
  } catch (_) {
    fnthinkChannels = const [];
  }
  for (final c in fnthinkChannels.where((c) => c.enabled)) {
    result.add(
      ActiveChannel(
        family: 'fnthink',
        slug: kFnthinkChannelSlug,
        id: c.id,
        displayName: channelTypeDisplayName(kFnthinkChannelSlug),
        configName: c.name,
        // 设备目标的关键链接就是那台地址码（18 位，不含任何凭据）；webhook 目标才取 host[:port]。
        target: c.targetKind == FnthinkChannelTarget.device
            ? c.target
            : channelTargetLabel(c.target),
        role: ChannelConfigCodec.normalizeRole(c.role),
        health: health?.of(kFnthinkChannelSlug, c.id),
      ),
    );
  }

  return result;
}

/// 入库快照与初始送达状态用的**送达键**列表。
///
/// 去重是必要的：送达键按类型（`chan:<slug>`，第 2 步的决策），两个企微群机器人
/// 共用一个键，不去重就会在同一记录里存两个相同键（历史页也会画两枚一样的 chip）。
List<String> deliveryKeysOfActiveChannels() => collectActiveChannels()
    .map((c) => c.deliveryKey)
    .toSet()
    .toList(growable: false);

/// 改一条通道的主备角色（T11）。写回**该族自己的服务**，因此走的就是既有的
/// "归一化 → DB → 同步原生"链路，不另开一条写路径。
///
/// 返回 false = 没找到这条通道（并发删除、或 family/id 传错），调用方据此提示而不是静默。
Future<bool> updateChannelRole(String family, String id, String role) async {
  final normalized = ChannelConfigCodec.normalizeRole(role);
  switch (family) {
    case 'webhook':
      final service = GetIt.instance<WebhookService>();
      final rows = service.channels
          .map<Map<String, dynamic>>(
            (c) => c['id']?.toString() == id ? {...c, 'role': normalized} : c,
          )
          .toList();
      if (!rows.any((c) => c['id']?.toString() == id)) return false;
      await service.saveChannels(rows);
      return true;
    case 'app':
      final service = GetIt.instance<AppChannelService>();
      final rows = service.channels
          .map<Map<String, dynamic>>(
            (c) => c['id']?.toString() == id ? {...c, 'role': normalized} : c,
          )
          .toList();
      if (!rows.any((c) => c['id']?.toString() == id)) return false;
      await service.saveChannels(rows);
      return true;
    case 'email':
      final service = GetIt.instance<EmailService>();
      if (!service.cachedChannels.any((c) => c.id == id)) return false;
      await service.saveChannels([
        for (final c in service.cachedChannels)
          if (c.id == id) c.copyWith(role: normalized) else c,
      ]);
      return true;
    case 'fnthink':
      // 走**只改角色**那一条写口（[FnthinkChannelService.setRole]），不走 `save()`：
      // `save()` 会连带重验目标（那台设备被取消勾选就抛），而用户此刻做的是"改主备"，
      // 不是"改目标"。用 save() 的话这一发有三种失败，而弹层只有一句话说得出，
      // 说错的那一句比少一个快捷入口坏得多（T113 的病灶就是这个"没法说清所以干脆不列"）。
      return GetIt.instance<FnthinkChannelService>().setRole(id, normalized);
    default:
      return false;
  }
}

/// 改一条通道的启用/停用（远程执行 `channel:toggle` 的落点）。
///
/// ⚠ 与 [updateChannelRole] **刻意同形**（family + id 二元组 → switch 三族 → 写回该族
/// 自己的服务）：本机寻址一条通道的方式只有这一种，两条写路径各写一套 switch，
/// 表现是「改了主备不生效」或「启停了不生效」—— 而两处都得对着另两族的模型形状改一遍。
///
/// ⚠ [enabled] 是**目标值而不是"翻"**：这条是远程指令，重投是常态（契约
/// `delivery._retryWhy`：ack 没送到就再投一次），而"翻"不可重现 ——
/// 翻一次开、翻两次回原状，于是对面看到的是"这条指令好像没生效"。
/// 幂等地设成某一档，重投多少次都是同一个结果。
Future<bool> updateChannelEnabled(
  String family,
  String id,
  bool enabled,
) async {
  switch (family) {
    case 'webhook':
      final service = GetIt.instance<WebhookService>();
      final rows = service.channels
          .map<Map<String, dynamic>>(
            (c) => c['id']?.toString() == id ? {...c, 'enabled': enabled} : c,
          )
          .toList();
      if (!rows.any((c) => c['id']?.toString() == id)) return false;
      await service.saveChannels(rows);
      return true;
    case 'app':
      final service = GetIt.instance<AppChannelService>();
      final rows = service.channels
          .map<Map<String, dynamic>>(
            (c) => c['id']?.toString() == id ? {...c, 'enabled': enabled} : c,
          )
          .toList();
      if (!rows.any((c) => c['id']?.toString() == id)) return false;
      await service.saveChannels(rows);
      return true;
    case 'email':
      final service = GetIt.instance<EmailService>();
      if (!service.cachedChannels.any((c) => c.id == id)) return false;
      await service.saveChannels([
        for (final c in service.cachedChannels)
          if (c.id == id) c.copyWith(enabled: enabled) else c,
      ]);
      return true;
    default:
      return false;
  }
}

/// 服务未注册（早期启动阶段 / 测试环境）时按「该族无通道」处理，与两份旧实现一致。
List<Map<String, dynamic>> _rows(List<Map<String, dynamic>> Function() read) {
  try {
    return read();
  } catch (_) {
    return const [];
  }
}

/// 把**全族通道**各探一遍（#174 / #182）。
///
/// 为什么需要它：别处（三个族页的进页刷新）只在"用户走到那一页"时才检查过期，而用户看
/// 状态的地方是首页那张卡与通道状态页 —— 过了时效的"上次成功"在界面上是 [ChannelHealthState.stale]
/// （T115 之前是 `unknown`），**无论画哪一档都得有人去重探**，否则那一档就一直挂着。
/// 这两处入口（通道状态页进页、App 回前台）走这一发把它补上。
///
/// ⚠ 读的是三个服务的**内存列表**（启动链 `main_page` 已装载），这里不做装载 IO：
/// 回前台要快，而且 `loadChannels()` 会连带写原生（secure storage），不该被一次"顺手检查"触发。
/// ⚠ 仍然是 **stale-only**：真正发请求的只有超过 [ChannelHealthStore.staleness] 的那几条 ——
/// 进页/回前台不是"必发一轮请求"的借口。三条不变量（只探启用 / 只探过期 / 调用异常不写不可达）
/// 全在 [ChannelProbeService] 里。
///
/// ⚠ **幻念族走自己那一条**（T106 片③）：它的探针是一次签名事件（`POST /probe`），
/// 不是原生那三枚方法，所以不进上面那张按「原生方法名 + 参数」组织的表。
/// 这一族**曾经**被明确挡在门外（T104 的安全判据）：那时它没有非侵入探针，"顺手重探一次"
/// 就是替用户往对面那台设备发一条真通知（对面会收到）。T106 补上了非浸入探针 ⇒ 那条判据
/// **改理由**而不是被悄悄放宽（判据本身没错，错的是它当初依赖的那个事实）。
/// 判据仍在守卫里：`channel_health_reprobe_guard_test` 那一组钉住"探它的**只有**这一条路、
/// 原生那张表里仍旧没有它"。
Future<int> probeChannelsAcrossFamilies({
  void Function()? onUpdated,
  bool force = false,
  FnthinkProbeCall? fnthinkProbe,
  FnthinkEndpointProbeCall? fnthinkEndpointProbe,
  FnthinkEndpointContext? fnthinkEndpointContext,
}) async {
  // 原生那三族的调度链路没装配（早期启动阶段 / 测试环境）⇒ 它们当"无事可做"；
  // ⚠ **不能顺手把第四族一起返回 0**：它不经过原生那套方法（见下面 `probeFnthinkChannels`），
  // 缺的是 `ChannelProbeService` 而它自己那条路是好的 —— 早退一次就等于"幻念这一族
  // 在别处测试环境里永远探不了"，而那正是这条判据要防的那种静默。
  ChannelProbeService? prober;
  try {
    prober = GetIt.instance<ChannelProbeService>();
  } catch (_) {
    prober = null;
  }

  var probed = 0;
  if (prober != null) {
    final byFamily = <String, List<ChannelProbeTarget>>{};
    void add(String family, List<ChannelProbeTarget> Function() build) {
      try {
        byFamily[family] = build();
      } catch (_) {
        // 这一族没注册 ⇒ 跳过这一族，别的两族照探
      }
    }

    add('webhook', () => GetIt.instance<WebhookService>().probeTargets);
    add('app', () => GetIt.instance<AppChannelService>().probeTargets);
    add('email', () => GetIt.instance<EmailService>().probeTargets);
    for (final entry in byFamily.entries) {
      probed += await (force
          ? prober.probeNow(entry.key, entry.value, onUpdated: onUpdated)
          : prober.probeStale(entry.key, entry.value, onUpdated: onUpdated));
    }
  }
  // 第四族（T106 片③）：走自己那一条 —— 判据「只探启用 / 只探过期 / 只写通道 id」都在
  // `probeFnthinkChannels` 里，与上面那三族同一套口径（不是"凑上去"的第二份实现）。
  // 两个 [fnthinkProbe]/[fnthinkEndpointProbe] 都只为测试注入：
  //  - 设备档生产走协调者（取不到 = 这一族还没装配 ⇒ 无事可做）；
  //  - 端点档生产直接挂 `postFnthinkEndpointDryRun`（T106 片①b 格2：一次干跑，一条都不投），
  //    而"能不能问"仍要问装配（随包契约 + 这台当前在用的那台服务器）⇒ 见 [endpointContext]。
  probed += await probeFnthinkChannels(
    force: force,
    call: fnthinkProbe ?? fnthinkProbeFromLocator(),
    endpointCall: fnthinkEndpointProbe ?? postFnthinkEndpointDryRun,
    endpointContext:
        fnthinkEndpointContext ?? fnthinkEndpointContextFromLocator,
    onUpdated: onUpdated,
  );
  return probed;
}
