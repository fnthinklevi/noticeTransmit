import 'package:flutter/services.dart';
import 'package:get_it/get_it.dart';

import 'channel_health_store.dart';
import 'platform_channel.dart';

/// 一条待探测的通道：探测方法名与载荷由各族给出（三种通道的凭据形状本就不同），
/// **该不该探、探完写到哪、探测本身出错算什么**这三件事由 [ChannelProbeService] 统一管。
class ChannelProbeTarget {
  const ChannelProbeTarget({
    required this.id,
    required this.enabled,
    required this.method,
    required this.args,
  });

  final String id;
  final bool enabled;

  /// 原生侧的非侵入探测方法（`probeChannelHealth` / `probeAppChannelToken` / `verifySmtp`）
  final String method;
  final Map<String, Object?> args;
}

/// 6e：三族通道「非侵入健康探测」的调度单点。
///
/// 为什么收在一处：进页刷新这件事 webhook 已经做了（超 6h 的启用通道后台逐个探测），
/// 而应用通道与邮件通道**没有**——因为它们当时只有"会真发消息/真寄信"的测试手段，
/// 自动跑等于每 6 小时骚扰一次。原生补上只换 token / 只握手两个探测方法后，
/// 三族共用同一套判据与写回路径，才不会又长出第二份 staleness 与第二份错误口径。
///
/// ⚠ 三条不变量（各有对应守卫）：
/// 1. **只探启用的**：停用通道不该产生对外请求（也不该被徽标算成异常）；
/// 2. **只探过期的**（[ChannelHealthStore.needsProbe]）：不是进页就发一轮请求；
/// 3. **探测调用本身抛异常时不写"不可达"**：那会把徽标钉成红，比"这次没探到"更误导。
class ChannelProbeService {
  ChannelProbeService({
    ChannelHealthStore? health,
    MethodChannel? channel,
    DateTime Function()? clock,
  }) : _health = health ?? GetIt.instance<ChannelHealthStore>(),
       _channel = channel ?? AppChannels.notification,
       _clock = clock ?? DateTime.now;

  final ChannelHealthStore _health;
  final MethodChannel _channel;
  final DateTime Function() _clock;
  bool _running = false;

  /// 逐个探测过期通道并把结论写回健康单点；[onUpdated] 每写回一条回调一次（页面 setState）。
  /// 返回本次实际探测的通道数。
  Future<int> probeStale(
    String family,
    List<ChannelProbeTarget> targets, {
    void Function()? onUpdated,
  }) async {
    if (_running) return 0;
    final now = _clock();
    final stale = targets
        .where(
          (t) =>
              t.enabled &&
              t.id.isNotEmpty &&
              ChannelHealthStore.needsProbe(_health.of(family, t.id), now: now),
        )
        .toList();
    if (stale.isEmpty) return 0;
    _running = true;
    var probed = 0;
    try {
      for (final t in stale) {
        final watch = Stopwatch()..start();
        try {
          final r = await _channel.invokeMethod<Object?>(t.method, t.args);
          if (r is! Map) {
            // 原生没给 Map（缺桩/版本错配）：与"调用抛异常"同处理，不写不可达
            continue;
          }
          await _health.record(
            family,
            t.id,
            reachable: r['reachable'] == true,
            latencyMs:
                (r['latencyMs'] as num?)?.toInt() ?? watch.elapsedMilliseconds,
            httpCode: (r['httpCode'] as num?)?.toInt(),
          );
          probed++;
          onUpdated?.call();
        } catch (_) {
          // 见不变量 3
        }
      }
    } finally {
      _running = false;
    }
    return probed;
  }
}
