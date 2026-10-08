import 'package:get_it/get_it.dart';

import 'locale_service.dart';

/// 通道**身份**与**显示名**的唯一出处。
///
/// 分两层，互不派生：
/// - [channelKey] / [channelDeliveryKey]：稳定标识（`wechat_work`），用于存储键。
///   与软件语言、用户改名、厂商叫法都无关，跨版本不变。
/// - [channelTypeDisplayName]：给人看的名字（中文「企业微信」/ 英文「WeCom」）。
///
/// 为什么必须分开（v1.62 第 2 步修掉的缺陷）：显示名曾同时充当 `deliveryStatus`
/// 的存储键与 `webhook_delivery_log.tag`，于是
/// 1. 用户切换语言 → 新旧记录键名不同，同一通道的送达状态分裂成两套键；
/// 2. 改一次文案（如 `'自建应用:企微'` → `'应用:企业微信应用'`）即让写入侧与
///    读取侧的键永不相等，表现为某些通道**永远「发送中」**；
/// 3. 显示层拿键当文案渲染，`webhook:` / `应用:` 前缀就这样漏到了界面上。
///
/// 所有入口（DB 存储值、Kotlin 枚举名、历史遗留拼写、旧版本地化键）都经
/// [channelKey] 归一，因此读旧数据、导出文件、原生回传都不需要调用方各自兼容。

/// 送达状态键前缀：把 `deliveryStatus` / `tag` 的键与「将来可能出现的同名裸键」
/// 隔开。键形如 `chan:dingtalk`。
const String kDeliveryKeyPrefix = 'chan:';

/// 拦截伪通道的规范键（短信/通知被黑白名单或应用过滤拦截）。
/// FILTER 与 SMS 在原生侧是两种回传，语义相同（内容不投递），故归并为同一键。
const String kBlockedChannelKey = 'blocked';

/// 幻念推送的规范 slug（T60 approach B）。它同时是：
/// - 送达键 `chan:fnthink` 的那一段（经 [channelDeliveryKey] 拼，别处不手打）；
/// - [ChannelHealthStore] 里**那一族通道**的 family 名 —— id 必须是**通道 id**
///   （T104 片① 之前它还被拿去记服务器可达性，那一份现在搬去 [kFnthinkServerFamily]）。
/// 写成一处常量，是为了让"页面读健康度"与"协调者写健康度"用的是同一个串 —— 两边各打一份
/// 字面量时，改一个忘一个的表现是徽标永远"没测过"（读到的键与写入的键不等）。
const String kFnthinkChannelSlug = 'fnthink';

/// 幻念推送**服务器**（那台中转机）可达性的 family，id＝服务器 host。
///
/// 为什么不与 [kFnthinkChannelSlug] 共用一个族名（这就是 T104 拆的那"两种主语"）：
/// `(fnthink, 通道 id)` 说的是"这条通道最近一次**手动**测的结果"，而 `(fnthink, host)` 说的是
/// "这台服务器通不通"。两件事的下一步动作完全不同（前者去通道详情点「仅探测」，后者去
/// 「切换服务」那一格换档），挤在一个族名里时，首页那条通道行随时可能把服务器的结论显示成
/// 自己的结论 —— 而它俩的 id 形状碰巧不会撞上，所以这种错**不会崩，只会静默说错话**。
///
/// ⚠ 旧键（`channel_health_fnthink:<host>`）**不迁移**：读写两侧一起换到新族名，旧键就此没人读，
///   过了 [ChannelHealthStore.staleness] 连"上次成功"都不会再冒出来。代价是第一次进那一格时
///   徽标显示「从未探测」—— 那是真话（这一族的探针本来就只有"真发一条"那一种）。
const String kFnthinkServerFamily = 'fnthink-server';

/// 聚合伪通道的规范键（P2 merge 动作：窗口期内成员被合并推送）。
const String kMergedChannelKey = 'merge';

/// 伪通道的**送达键**（`chan:` 形态），供写入侧与迁移直接引用。
const String deliveryKeyBlocked = '$kDeliveryKeyPrefix$kBlockedChannelKey';
const String deliveryKeyMerged = '$kDeliveryKeyPrefix$kMergedChannelKey';

/// slug →（中文名, 英文名）。新增通道只需在此加一行 + 在 [_slugAliases] 补历史拼写。
const Map<String, (String, String)> _channelNames = {
  'wechat_work': ('企业微信', 'WeCom'),
  'dingtalk': ('钉钉', 'DingTalk'),
  'feishu': ('飞书', 'Feishu'),
  'telegram': ('Telegram', 'Telegram'),
  'bark': ('Bark', 'Bark'),
  'server_chan': ('Server酱', 'ServerChan'),
  'push_plus': ('PushPlus', 'PushPlus'),
  'ntfy': ('ntfy', 'ntfy'),
  'gotify': ('Gotify', 'Gotify'),
  'slack': ('Slack', 'Slack'),
  'discord': ('Discord', 'Discord'),
  'generic': ('通用 Webhook', 'Generic Webhook'),
  'wecom_app': ('企业微信应用', 'WeCom App'),
  'feishu_app': ('飞书应用', 'Feishu App'),
  'email': ('邮件', 'Email'),
  // T60 发送侧通道化（approach B）：幻念推送在 Dart 侧占一个送达键 `chan:fnthink`，
  // 复用健康度/送达数据；它不进原生 ChannelRegistry 的封闭三族（那是 approach A）。
  'fnthink': ('幻念推送', 'Fnthink Push'),
  'blocked': ('过滤拦截', 'Blocked'),
  'merge': ('合并推送', 'Merged'),
};

/// 裸类型拼写 → slug。键一律小写（[channelKey] 会先 lowercase）。
/// 覆盖：DB `channel_type`/`app_type` 值、Kotlin 枚举名、驼峰历史值、
/// 早期按枚举序号存储的数字、已废弃的显示串。
const Map<String, String> _slugAliases = {
  // 早期把 webhook 类型按枚举序号存成数字（与 ConfigManager.parseWebhookType 同表；
  // 注意该序号**不等于** Dart 侧下拉列表的下标）
  '0': 'wechat_work',
  '1': 'dingtalk',
  '2': 'feishu',
  '3': 'generic',
  '4': 'telegram',
  '5': 'bark',
  '6': 'server_chan',
  '7': 'push_plus',
  '8': 'ntfy',
  '9': 'gotify',
  '10': 'slack',
  '11': 'discord',
  // snake_case（DB 现值）/ 驼峰（早期 Dart 与 Kotlin 传值）
  'wechat_work': 'wechat_work',
  'wechatwork': 'wechat_work',
  'dingtalk': 'dingtalk',
  'feishu': 'feishu',
  'telegram': 'telegram',
  'bark': 'bark',
  'server_chan': 'server_chan',
  'serverchan': 'server_chan',
  'push_plus': 'push_plus',
  'pushplus': 'push_plus',
  'ntfy': 'ntfy',
  'gotify': 'gotify',
  'slack': 'slack',
  'discord': 'discord',
  'generic': 'generic',
  'wecom_app': 'wecom_app',
  'wecomapp': 'wecom_app',
  'feishu_app': 'feishu_app',
  'feishuapp': 'feishu_app',
  'email': 'email',
  // 幻念推送（T60 approach B）：规范 slug 自身，大小写/去前缀后都归到它
  'fnthink': 'fnthink',
  // 拦截/聚合伪通道（原生回传枚举名 SMS/FILTER/MERGE 与旧本地化键）
  'sms': 'blocked',
  'filter': 'blocked',
  'blocked': 'blocked',
  'merge': 'merge',
  'merged': 'merge',
  // 已废弃写法：早期首页给自建应用写过 '自建应用:企微'（剥前缀后剩 '企微'）
  '企微': 'wecom_app',
};

/// 显示名反查表：`_channelNames` 的中英文值 → slug。
/// 由表自动派生，避免"加通道忘了加别名"导致旧记录读成通用。
final Map<String, String> _slugByDisplayName = {
  for (final e in _channelNames.entries) e.value.$1.toLowerCase(): e.key,
  for (final e in _channelNames.entries) e.value.$2.toLowerCase(): e.key,
};

/// 任意来源的通道标识 → 规范 slug。未知值回退 `generic`（与旧显示兜底同口径）。
///
/// 输入可为：`chan:` 键（幂等）、Kotlin 枚举名（`WECHAT_WORK`）、DB 值
/// （`wechat_work`）、驼峰（`wechatWork`）、早期数字（`'0'`）、
/// 旧版本地化显示串（`webhook:企业微信` / `App:WeCom App`）、裸显示名（`企业微信`）。
String channelKey(String rawType) {
  var v = rawType.trim();
  // 剥掉前缀：chan:（自身幂等）与历史把显示名当前缀的写法（webhook:/应用:/App:/自建应用:）
  final colon = v.indexOf(':');
  if (colon > 0) v = v.substring(colon + 1);
  v = v.toLowerCase();
  return _slugAliases[v] ?? _slugByDisplayName[v] ?? 'generic';
}

/// 存储键：`deliveryStatus` 的键、`webhook_delivery_log.tag` 都用它。幂等。
String channelDeliveryKey(String rawType) =>
    '$kDeliveryKeyPrefix${channelKey(rawType)}';

/// 通道**族**显示名（T01：首页与通道状态页的「类型：」前缀）。
///
/// 与 [_channelNames] 分两张表是有意的：族只有四五个、不随原生描述符表增删（钉钉/飞书应用/…
/// 那些子类型会变），而"这一族能不能被某条写路径改"是另一件事。混成一张表会让"族"这一层
/// 跟着通道数漂移。
///
/// ⚠ 这一张是**显示**用的四族。"可写的族"今天分成**两档**，别再混着说：
/// **主备**（`updateChannelRole`）四族都有 —— T113 起幻念那一族走只改角色的
/// `FnthinkChannelService.setRole`（不重验目标），弹层与页面分组都读 `channelFamilies` 那一份；
/// **启停**（`updateChannelEnabled` / 远程指令 `channel:toggle` 的 `isKnownChannelFamily`）
/// 仍是那三族 —— 那一族的启停只有 `save()`，会连带重验目标，形状与"设一个布尔"不是一件事。
/// 两张表不一致时的表现是「这一族能配能显示，就是快捷改不了」，所以守卫钉在
/// `channel_single_points_test.dart`（清单 = switch 的 case 集合 = 弹层遍历的那一份）。
const Map<String, (String, String)> _familyNames = {
  'webhook': ('Webhook', 'Webhook'),
  'app': ('自建应用', 'App Channel'),
  'email': ('邮件', 'Email'),
  // T104 片③：第四族进首页与通道状态页。不登记这一行的话 `channelFamilyName` 会**原样返回
  // 'fnthink'**（那是有意的：不猜成 webhook），表现就是首页那行写着英文 token。
  'fnthink': ('幻念推送', 'Fnthink Push'),
};

/// 族显示名（语言感知）。未登记的族原样返回，不猜成 webhook。
String channelFamilyName(String family) {
  final names = _familyNames[family];
  if (names == null) return family;
  return _isEnglishLocale() ? names.$2 : names.$1;
}

/// 「类型：子类型/通道名」里的那个冒号（英文用半角 + 空格，中文用全角）。
String channelLabelSeparator() => _isEnglishLocale() ? ': ' : '：';

/// 送达状态映射的键归一（幂等）。同 slug 冲突时保留后写入者——
/// 旧数据里 `webhook:通用` 与 `webhook:Generic` 本就是同一通道的两套语言写法。
Map<String, dynamic> normalizeDeliveryKeys(Map<String, dynamic> status) {
  if (status.keys.every((k) => k.startsWith(kDeliveryKeyPrefix))) {
    return status;
  }
  final result = <String, dynamic>{};
  for (final entry in status.entries) {
    result[channelDeliveryKey(entry.key)] = entry.value;
  }
  return result;
}

/// 通道「关键链接」的可显示部分：**只有 host[:port]，path 与 query 一律丢掉**。
///
/// 为什么不显示 path：webhook 的凭据常常就在 path 里 —— Server酱是
/// `https://sctapi.ftqq.com/<SENDKEY>.send`、飞书是 `/open-apis/bot/v2/hook/<token>`，
/// query 里更是标配（`?access_token=` / `?key=`）。这个字段要显示在通道状态页上，
/// 任何一条都等于把凭据抄进界面（截图即泄露）。
/// 解析不出来（缺 scheme 的旧值等）返回空串，由调用方省略这一行。
String channelTargetLabel(String raw) {
  final uri = Uri.tryParse(raw.trim());
  if (uri == null || uri.host.isEmpty) return '';
  return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
}

/// 通道显示名（语言感知）。输入同 [channelKey]，因此把键直接喂进来也能得到名字。
String channelTypeDisplayName(String rawType) {
  final names = _channelNames[channelKey(rawType)]!;
  return _isEnglishLocale() ? names.$2 : names.$1;
}

bool _isEnglishLocale() {
  String? localeCode;
  try {
    // GetIt 未初始化（极早期调用）时回退中文
    localeCode = GetIt.instance<LocaleService>().currentLocale.languageCode;
  } catch (_) {
    localeCode = null;
  }
  return localeCode == 'en';
}
