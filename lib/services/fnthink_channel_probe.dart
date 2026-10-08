import 'dart:async';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:get_it/get_it.dart';

import '../models/fnthink_channel.dart';
import 'channel_display.dart';
import 'channel_health_store.dart';
import 'fnthink_channel_service.dart';
import 'fnthink_receive_coordinator.dart';

/// 幻念通道的**非浸入**健康探测（T106）。它与另外三族的差别只有一句：
/// 另外三族的探针不打扰任何人，而这一族的"测一次"曾经只能真发一条通知
/// （对面会收到）—— 有了 `/probe` 这一发，才轮得到它进自动重探。
///
/// 这一层只做**节流与重试**，不做任何协议判断：探针本身在
/// `FnthinkReceiveKernel.probe`（签名、载荷、三态结论），写健康度在调用方。

/// 单发预算：3 秒。**与 `measureEndpointLatency` 那个单台预算同值**，但不共用常量 ——
/// 那一个量的是"就近选服务器"，这一个量的是"这条路答不答"，两件事；合并成一个常量，
/// 改其中一个的动机会带着另一个一起变。
const Duration kFnthinkProbeBudget = Duration(seconds: 3);

/// 串行最多试几次（维护者 2026-10-08：「自动重试 3 次」）。
const int kFnthinkProbeAttempts = 3;

/// 一发探针的调用口（生产装配是 `FnthinkReceiveCoordinator.probePeer`）。
typedef FnthinkProbeCall =
    Future<FnthinkProbeResult> Function({required String peer});

/// 探一条路：3 秒一发、串行最多 3 次。
///
/// 返回 true / false = 这次的结论（服务端说的，或"三次都没问到"折算的那一次失败）。
/// **没有"没结论"这一档**：见下面第 ② 条 —— 问到上限还没问到，按维护者定的口径就是失败。
///
/// 三条口径，每条防的都是具体的一种错：
///  ① **有结论就立刻收工**（哪怕结论是 `false`）：`ready:false` 是服务端查过之后的答复，
///     再试两次不会有第二个答案 —— 重试针对的是"没问到"，不是"问到了坏消息"；
///  ② **三次都没成 ⇒ `false`**（超时、连不上、服务端答了却没给结论）。这是维护者 2026-10-08
///     定的产品口径（「超时显示失败」）。⚠ 它与另外三族那条「探测调用本身抛异常时不写不可达」
///     **刻意不同**，差别在承诺：那三族的绿灯不承诺对外做过什么事；这一族的绿灯承诺的是
///     "对面那条链立得住" —— 把"连问三次都没问到"画成绿是假安心。同理，本机那几种发不出去
///     （没契约／没同意中转／签不出来）也落成红：那几种状态下这条通道**确实**送不出去；
///  ③ 每次一发**各自**计时（不共用一份总预算）：一台 3 秒、串行三次最多 9 秒 ——
///     总预算制会让"第一发卡满"吃掉后面两发，而那正是最需要重试的情形。
Future<bool> probeFnthinkWithRetries(
  FnthinkProbeCall call, {
  required String peer,
  Duration budget = kFnthinkProbeBudget,
  int attempts = kFnthinkProbeAttempts,
}) async {
  for (var i = 0; i < attempts; i++) {
    try {
      final result = await call(peer: peer).timeout(budget);
      if (result.ready != null) return result.ready!;
    } catch (_) {
      // 超时 / 传输异常：这一发不算，下一发见。
    }
  }
  return false;
}

/// 生产装配点：探针那一发走协调者（前置判定与 service 生命周期都在它那里）。
/// 取不到（这一族还没装配）⇒ null，调用方当"无事可做"。
FnthinkProbeCall? fnthinkProbeFromLocator() {
  try {
    final coordinator = GetIt.instance<FnthinkReceiveCoordinator>();
    return ({required peer}) => coordinator.probePeer(peer: peer);
  } catch (_) {
    return null;
  }
}

/// 此刻正在探的通道 id（T115 护栏①：一轮内同一通道只测一次）。
///
/// 原生那三族有 `ChannelProbeService._running` 那把锁挡着并发轮次（后到的那一发直接返回 0）；
/// 这一族走自己这条路，**没有**那份保护 ⇒ 主动节奏那一轮 + 状态页进页那一轮 + 首页下拉那一轮
/// 叠起来时，同一条通道会被连发两次签名探针。两边各自有锁不等于"同一轮同一通道只测一次"，
/// 所以这里补自己那一份。
/// ⚠ 按**通道 id** 挡而不是按整族挡：按族挡会把没在探的别的通道一起挡掉（那是"点了没反应"）。
/// 只在进程内记 —— 这一族没有需要长期记住的状态，跨重启的那一发本来就过期该重探。
final Set<String> _probing = {};

/// 探**一整族**幻念通道（自动重探的那一条路）。
///
/// ⚠ 这一族此前**不许进自动重探**（T104 立的安全判据）：它当时没有非侵入探针，
/// 「顺手重探一次」＝替用户往对面那台设备发一条真通知（对面会收到）。T106 补上了 `/probe`
/// （服务端只查关系与档位、一条都不投），那条判据随之**改理由**而不是被悄悄放宽 ——
/// 判据本身没错，错的是它当初依赖的那个事实：非侵入探针已经有了。
///
/// 三条与另外三族同一口径：**只探启用的**、进页那一路**只探过期的**（[force] 只属于下拉刷新）、
/// 结论照实写进健康单点（写的是 `(kFnthinkChannelSlug, 通道 id)`，不是 host）。
/// ⚠ **webhook 目标那条今天探不了**：它的干跑要另立一条出示长期口令的路（T106 片①b），
/// 这里**跳过**它 —— 不是忘了，是没有那条路可走；它的徽标仍只会被人手动测那两枚写。
Future<int> probeFnthinkChannels({
  required bool force,
  FnthinkProbeCall? call,
  void Function()? onUpdated,
}) async {
  if (call == null) return 0;
  final FnthinkChannelService channels;
  final ChannelHealthStore health;
  try {
    channels = GetIt.instance<FnthinkChannelService>();
    health = GetIt.instance<ChannelHealthStore>();
  } catch (_) {
    // 探测链路没装配（早期启动 / 测试环境）⇒ 当"无事可做"，与另三族同一条兜底。
    return 0;
  }
  final now = DateTime.now();
  var probed = 0;
  for (final channel in channels.cachedChannels) {
    if (!channel.enabled || channel.id.isEmpty) continue;
    if (channel.targetKind != FnthinkChannelTarget.device) continue;
    // T115 护栏①：另一轮（进页 / 回前台 / 下拉）正在探这一条 ⇒ 这一轮跳过它。
    // 结论由那一发写回同一个键，界面靠它自己的 onUpdated 重画 —— 这里再发一次只是把
    // 同一条路问两遍（而这一族的"问一遍"是一次签名事件，不是免费的）。
    if (_probing.add(channel.id)) {
      try {
        if (!force &&
            !ChannelHealthStore.needsProbe(
              health.of(kFnthinkChannelSlug, channel.id),
              now: now,
            )) {
          continue;
        }
        final watch = Stopwatch()..start();
        final ready = await probeFnthinkWithRetries(call, peer: channel.target);
        watch.stop();
        await health.record(
          kFnthinkChannelSlug,
          channel.id,
          reachable: ready,
          latencyMs: watch.elapsedMilliseconds,
        );
        probed++;
        onUpdated?.call();
      } finally {
        _probing.remove(channel.id);
      }
    }
  }
  return probed;
}
