import 'package:get_it/get_it.dart';

import '../models/email_channel.dart';
import 'app_channel_service.dart';
import 'channel_health_store.dart';
import 'channel_display.dart';
import 'email_service.dart';
import 'webhook_service.dart';

/// 一条通道在首页/状态页的健康态。**三态**，不是二态：
/// 「没有新鲜的探测结果」既不能说正常（那是恒绿的谎），也不能说异常（那是假警报）。
enum ChannelHealthState { ok, error, unknown }

/// 一个**已启用**通道的条目：身份、显示名、用户命名、最近一次探测结果。
class ActiveChannel {
  const ActiveChannel({
    required this.family,
    required this.slug,
    required this.id,
    required this.displayName,
    required this.configName,
    this.health,
  });

  /// 'webhook' | 'app' | 'email'
  final String family;

  /// 规范 slug（`dingtalk` / `wecom_app` / `email`），与送达键、图标表同口径
  final String slug;

  /// 通道行 id（健康缓存按 `family:id` 存）
  final String id;

  /// 类型显示名（随语言，纯显示用，**不参与任何键**）
  final String displayName;

  /// 用户给这条通道起的名字
  final String configName;

  /// 最近一次探测结果（来自健康单点）。null = 从没探过。
  final ChannelHealth? health;

  String get deliveryKey => channelDeliveryKey(slug);

  /// 健康态：失败就一直是失败（有确凿证据），成功但记录过期算未知。
  ChannelHealthState get healthState {
    final h = health;
    if (h == null) return ChannelHealthState.unknown;
    if (!h.reachable) return ChannelHealthState.error;
    return ChannelHealthStore.needsProbe(h)
        ? ChannelHealthState.unknown
        : ChannelHealthState.ok;
  }

  /// 首页「当前推送通道」的状态标签（页面据此取 l10n 文案与点色）。
  String get statusLabel => switch (healthState) {
    ChannelHealthState.ok => 'ok',
    ChannelHealthState.error => 'error',
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
/// 两份都是「遍历三个 service 的 enabled」，同一件事两个实现 ——
/// 加一个通道族或改判 enabled 的口径时只改一处，就会出现
/// 「首页显示了三条而历史记录只按两条算」这类对不上的账。
///
/// 顺序沿用首页原有观感：应用通道 → webhook → 邮件。
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
        health: health?.of('email', c.id),
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

/// 服务未注册（早期启动阶段 / 测试环境）时按「该族无通道」处理，与两份旧实现一致。
List<Map<String, dynamic>> _rows(List<Map<String, dynamic>> Function() read) {
  try {
    return read();
  } catch (_) {
    return const [];
  }
}
