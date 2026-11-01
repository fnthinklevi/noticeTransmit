/// T220 片2c：一键全链路自检。
///
/// 回答的是维护者那句「确保转发链路通畅」里最难回答的一半：**四条族各自现在通不通**。
/// 单通道有「测试这条通道」，幻念有「测 latency」，但没有一处能一次把四族都问一遍。
///
/// 三条硬边界（写在这里，因为这是所有调用点共享的那一份口径）：
///  ① **只打最小载荷**：webhook / 自建应用 / 邮件走各自的既有测试原语（一条测试消息），
///     幻念走非侵入探针（`/probe`，一条都不投）—— 不占幻念额度；
///  ② **不写历史、不动主备锁存**：这几个原语本来就不经投递链，这里只做编排，不新增写口；
///  ③ **每族只挑一条**：优先主通道，其次该族第一条。四处并发打会让「结论一致」这条
///     验收失真（用户连点两次时，第二次的结果取决于第一次的发完没发完）。
library;

import 'dart:async';

import 'package:get_it/get_it.dart';

import 'active_channels.dart';
import 'app_channel_service.dart';
import 'channel_config_codec.dart';
import 'channel_health_store.dart';
import 'email_service.dart';
import 'fnthink_channel_probe.dart';
import 'fnthink_endpoint_dryrun.dart';
import 'platform_channel.dart';
import 'webhook_service.dart';

/// 一次自检里某一族的结论。
enum ChainCheckState {
  /// 打出去并回来了成功。
  ok,

  /// 打出去了、对面说不行或超时。
  failed,

  /// 这一族没有已启用的通道 —— 不是失败，是"没得测"。
  noChannel,
}

/// 一族的自检结论。`channelName` 为 null 只在 [ChainCheckState.noChannel] 出现。
class ChainCheckEntry {
  const ChainCheckEntry({
    required this.family,
    required this.state,
    this.channelName,
    this.message = '',
  });

  final String family;
  final ChainCheckState state;
  final String? channelName;

  /// 对面/原生给的原话（成功时通常是"OK"，失败时是错的理由）。不译：那是事实不是文案。
  final String message;
}

/// 某一发的发送口。生产是 [defaultChainCheckSend]；用例注入替身以免真发消息。
typedef ChainCheckSend = Future<({bool ok, String message})> Function(
  ActiveChannel channel,
);

/// 每族那发的预算。**比单通道「测试这条通道」的 90 秒略宽**：这里等的是同一发，
/// 但用户是在等"四族一起"的结论，多给几秒好过把一条其实还在发的通道判成失败。
const Duration kChainCheckBudget = Duration(seconds: 95);

/// 挑出每族要测的那一条：优先主通道，其次该族第一条。
///
/// 顺序跟着 [channelFamilies] 走（与状态页分组、主备弹层同一份清单）。
List<ActiveChannel> chainCheckTargets(List<ActiveChannel> channels) {
  final out = <ActiveChannel>[];
  for (final family in channelFamilies) {
    final inFamily = channels.where((c) => c.family == family).toList();
    if (inFamily.isEmpty) continue;
    final primary = inFamily.where(
      (c) => c.role == ChannelConfigCodec.rolePrimary,
    );
    out.add(primary.isNotEmpty ? primary.first : inFamily.first);
  }
  return out;
}

/// 跑一轮自检：四族各一条结论（没配置的族也给一行 [ChainCheckState.noChannel]，
/// 让"四族"这件事在结果里始终是四行，而不是少几行让人以为漏测）。
///
/// 串行而不是并发：见文件头第 ③ 条。单族失败不拦后面的族 —— 一次自检的价值就在"四份结论"。
Future<List<ChainCheckEntry>> runChainSelfCheck({
  required List<ActiveChannel> channels,
  required ChainCheckSend send,
}) async {
  final targets = chainCheckTargets(channels);
  final byFamily = {for (final c in targets) c.family: c};
  final out = <ChainCheckEntry>[];
  for (final family in channelFamilies) {
    final target = byFamily[family];
    if (target == null) {
      out.add(
        ChainCheckEntry(family: family, state: ChainCheckState.noChannel),
      );
      continue;
    }
    try {
      final result = await send(target).timeout(kChainCheckBudget);
      out.add(
        ChainCheckEntry(
          family: family,
          state: result.ok ? ChainCheckState.ok : ChainCheckState.failed,
          channelName: target.configName.isNotEmpty
              ? target.configName
              : target.displayName,
          message: result.message,
        ),
      );
    } on TimeoutException {
      out.add(
        ChainCheckEntry(
          family: family,
          state: ChainCheckState.failed,
          channelName: target.configName.isNotEmpty
              ? target.configName
              : target.displayName,
          // 与「测试这条通道」同一句话：超时不等于"对面说不行"，但这一格必须给出结论。
          message: 'timeout',
        ),
      );
    } catch (e) {
      out.add(
        ChainCheckEntry(
          family: family,
          state: ChainCheckState.failed,
          channelName: target.configName.isNotEmpty
              ? target.configName
              : target.displayName,
          message: e.toString(),
        ),
      );
    }
  }
  return out;
}

/// 生产那一发：按族走既有原语，**不新造第二套发送路径**。
///
/// ⚠ 这几枚原语（`testWebhook` / `testAppChannel` / `testEmail` / 幻念探针）各自已经
/// 是那一族的"测一次"唯一入口；这里再写一份 HTTP/SMTP 客户端就是第四条链，而四条链
/// 的判定迟早对不上。
Future<({bool ok, String message})> defaultChainCheckSend(
  ActiveChannel channel,
) async {
  switch (channel.family) {
    case 'webhook':
      return _checkWebhook(channel);
    case 'app':
      return _checkAppChannel(channel);
    case 'email':
      return _checkEmail(channel);
    case 'fnthink':
      return _checkFnthink(channel);
    default:
      return (ok: false, message: 'unknown-family:${channel.family}');
  }
}

Future<({bool ok, String message})> _checkWebhook(ActiveChannel channel) async {
  final service = GetIt.instance<WebhookService>();
  final row = service.channels.firstWhere(
    (c) => ChannelConfigCodec.nullableText(c['id']) == channel.id,
    orElse: () => <String, dynamic>{},
  );
  if (row.isEmpty) {
    return (ok: false, message: 'channel-missing');
  }
  final secret = ChannelConfigCodec.nullableText(row['secret']);
  final result = await AppChannels.notification.invokeMethod('testWebhook', {
    'url': row['url']?.toString() ?? '',
    if (secret != null && secret.isNotEmpty) 'secret': secret,
    'channelType':
        row['channelType']?.toString() ?? row['type']?.toString() ?? 'auto',
    // 与真发同一裁决：测试那一发也必须按通道上存着的那个方法打。
    'httpMethod':
        row['http_method']?.toString() ??
        row['httpMethod']?.toString() ??
        'POST',
  });
  return _outcomeOf(result);
}

Future<({bool ok, String message})> _checkAppChannel(
  ActiveChannel channel,
) async {
  final service = GetIt.instance<AppChannelService>();
  final row = service.channels.firstWhere(
    (c) => ChannelConfigCodec.nullableText(c['id']) == channel.id,
    orElse: () => <String, dynamic>{},
  );
  if (row.isEmpty) {
    return (ok: false, message: 'channel-missing');
  }
  final result = await AppChannels.notification.invokeMethod(
    'testAppChannel',
    ChannelConfigCodec.appProbePayload(row),
  );
  return _outcomeOf(result);
}

Future<({bool ok, String message})> _checkEmail(ActiveChannel channel) async {
  final service = GetIt.instance<EmailService>();
  final cached = service.cachedChannels;
  final model = cached.where((c) => c.id == channel.id).firstOrNull;
  if (model == null) {
    return (ok: false, message: 'channel-missing');
  }
  final result = await service.testEmail(model);
  final ok = result?['success'] as bool? ?? false;
  return (ok: ok, message: result?['message']?.toString() ?? '');
}

/// 幻念那一格只认**这一轮写下的**结论：探针没问成时健康单点里可能还留着上一次的值，
/// 把那个旧"通"读回来就是一眼假绿。窗口给 1 分钟（探针自身 3 秒预算 × 3 发）。
const Duration _kFnthinkFreshWindow = Duration(minutes: 1);

/// 幻念：只打非侵入探针，**不占额度、不投递**；结论从健康单点读回（探针自己会写）。
Future<({bool ok, String message})> _checkFnthink(ActiveChannel channel) async {
  await probeFnthinkChannels(
    force: true,
    call: fnthinkProbeFromLocator(),
    endpointCall: postFnthinkEndpointDryRun,
    endpointContext: fnthinkEndpointContextFromLocator,
  );
  ChannelHealth? health;
  try {
    health = GetIt.instance<ChannelHealthStore>().of('fnthink', channel.id);
  } catch (_) {
    health = null;
  }
  final fresh =
      health != null &&
      DateTime.now().millisecondsSinceEpoch - health.probedAt <=
          _kFnthinkFreshWindow.inMilliseconds;
  if (health == null || !fresh) {
    // 探针这一轮没写这条（未启用/未装配/两档都没有）：如实说"没问到"，不编绿灯。
    return (ok: false, message: 'no-probe-result');
  }
  return (ok: health.reachable, message: health.latencyMs.toString());
}

({bool ok, String message}) _outcomeOf(Object? raw) {
  if (raw is! Map) return (ok: false, message: 'no-answer');
  final ok = raw['success'] as bool? ?? false;
  return (ok: ok, message: raw['message']?.toString() ?? '');
}
