import 'dart:async';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:get_it/get_it.dart';

import '../models/fnthink_channel.dart';
import 'channel_display.dart';
import 'channel_health_store.dart';
import 'fnthink_channel_service.dart';
import 'fnthink_contract_loader.dart';
import 'fnthink_receive_coordinator.dart';
import 'fnthink_settings.dart';

/// 幻念通道的**非浸入**健康探测（T106）。它与另外三族的差别只有一句：
/// 另外三族的探针不打扰任何人，而这一族的"测一次"曾经只能真发一条通知
/// （对面会收到）—— 有了 `/probe` 这一发，才轮得到它进自动重探。
///
/// 这一层只做三件事：**该不该探**（启用 + 过期 + 在飞护栏）、**这一条该由谁来问**
/// （设备档＝签名探针，端点档＝干跑，两种都没有的那条就跳过）、**节流与重试**
/// （[probeFnthinkAttempts] 是唯一一份判据）。线上形状不在这里：签名与载荷在
/// `FnthinkReceiveKernel.probe`，干跑在 `postFnthinkEndpointDryRun`，路径与口令放法在契约，
/// 写健康度在调用方。

/// 单发预算：3 秒。**与 `measureEndpointLatency` 那个单台预算同值**，但不共用常量 ——
/// 那一个量的是"就近选服务器"，这一个量的是"这条路答不答"，两件事；合并成一个常量，
/// 改其中一个的动机会带着另一个一起变。
const Duration kFnthinkProbeBudget = Duration(seconds: 3);

/// 串行最多试几次（维护者 2026-10-08：「自动重试 3 次」）。
const int kFnthinkProbeAttempts = 3;

/// 一发探针的调用口（生产装配是 `FnthinkReceiveCoordinator.probePeer`）。
typedef FnthinkProbeCall =
    Future<FnthinkProbeResult> Function({required String peer});

/// 端点档那一发的调用口（T106 片①b 格2；生产就是 `postFnthinkEndpointDryRun` 那一发，
/// 由 `probeChannelsAcrossFamilies` 直接挂上来）。
///
/// 三个参数都在**签名之外**：这一发没有签名 —— 它靠一把长期口令出示身份，
/// 而口令从 `Authorization: Bearer` 走（契约 `endpoint.probe.secretPlacement` 钉着）。
typedef FnthinkEndpointProbeCall =
    Future<FnthinkProbeResult> Function({
      required FnthinkContract contract,
      required Uri probeUrl,
      required String secret,
    });

/// 这一轮能不能问端点档那一发：随包契约 + 这台设备**当前正在用的那一台**服务器。
///
/// ⚠ 只放行"当前那一台"而不是"契约声明的两台"：端点记录住在它被创建的那台上，
///   往另一台问一个不存在的人只会得到一次**假红** —— 而这一族的红灯承诺过是确凿的。
///   这也顺手关掉了另一件事：口令只可能发给这台设备本来就在通信的那一个地址。
typedef FnthinkEndpointContext =
    Future<({FnthinkContract contract, String host})?> Function();

/// 探一次：3 秒预算、最多 [attempts] 发，**每发各自计时**。
///
/// 这一条是两族（设备档 / 端点档）**共用**的那一份判据 —— 重试的语义只有一种，
/// 写两份就会分叉（一份改"有结论就收工"，另一份还在那儿傻等三次）。
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
Future<bool> probeFnthinkAttempts(
  Future<FnthinkProbeResult> Function() one, {
  Duration budget = kFnthinkProbeBudget,
  int attempts = kFnthinkProbeAttempts,
}) async {
  for (var i = 0; i < attempts; i++) {
    try {
      final result = await one().timeout(budget);
      if (result.ready != null) return result.ready!;
    } catch (_) {
      // 超时 / 传输异常：这一发不算，下一发见。
    }
  }
  return false;
}

/// 探**设备档**那一条路（[probeFnthinkAttempts] 的一个适配器，判据不重复写第二遍）。
Future<bool> probeFnthinkWithRetries(
  FnthinkProbeCall call, {
  required String peer,
  Duration budget = kFnthinkProbeBudget,
  int attempts = kFnthinkProbeAttempts,
}) => probeFnthinkAttempts(
  () => call(peer: peer),
  budget: budget,
  attempts: attempts,
);

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

/// 端点档那一问的上下文装配。契约或"这台在用哪台服务器"取不到 ⇒ null（⇒ 端点档整档跳过）。
Future<({FnthinkContract contract, String host})?>
fnthinkEndpointContextFromLocator() async {
  try {
    final contract = await GetIt.instance<FnthinkContractLoader>().load();
    final host = await GetIt.instance<FnthinkSettings>().host;
    return (contract: contract, host: host);
  } catch (_) {
    // 没注册（早期启动 / 测试环境）或契约不可用：与"这一族没装配"同一处置。
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
///
/// 两种目标各有各的那一发（[call] 设备档 / [endpointCall]＋[endpointContext] 端点档）：
///  - **设备档**＝一次签名事件（`POST /probe`），问的是「这台到那台的关系与档位立不立得住」；
///  - **端点档**＝一次干跑（`POST /p/<id>/probe` + Bearer 长期口令，T106 片①b），问的是
///    「这把口令还对吗、这个来源被允许吗、这条端点还活着且绑着设备吗」。
/// ⚠ 端点档**只有幻念自己的端点**能问，而且只问这台设备**当前在用的那一台**服务器：
///   第三方 webhook（NAS 自己的口、Slack 那种）协议里没有这一发，硬探＝真推一条；
///   往另一台服务器问，得到的是一次**假红**（那边本来就没有这条端点）。
///   所以这两条路的 skip 分支都**不是失败**：宁可徽标读"从未探测"，也不写一个编出来的结论。
Future<int> probeFnthinkChannels({
  required bool force,
  FnthinkProbeCall? call,
  FnthinkEndpointProbeCall? endpointCall,
  FnthinkEndpointContext? endpointContext,
  void Function()? onUpdated,
}) async {
  if (call == null && endpointCall == null) return 0;
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
  // 端点档那一问要契约与"当前哪台服务器"，两者都得问一次装配 —— 但**只在真有端点档通道时**
  // 问（一轮里全是设备档就去读 prefs 是白活），且整轮只问一次。
  ({FnthinkContract contract, String host})? endpointCtx;
  var probed = 0;
  for (final channel in channels.cachedChannels) {
    if (!channel.enabled || channel.id.isEmpty) continue;
    // 进页/回前台那一路只看过期（判据在 ChannelHealthStore 那一层，两档共用）。
    if (!force &&
        !ChannelHealthStore.needsProbe(
          health.of(kFnthinkChannelSlug, channel.id),
          now: now,
        )) {
      continue;
    }
    Future<FnthinkProbeResult> Function()? attempt;
    if (channel.targetKind == FnthinkChannelTarget.device) {
      if (call != null) {
        final peer = channel.target;
        attempt = () => call(peer: peer);
      }
    } else {
      if (endpointCall != null && endpointContext != null) {
        endpointCtx ??= await endpointContext();
        final c = endpointCtx;
        if (c != null) {
          final plan = fnthinkEndpointDryRunFor(
            contract: c.contract,
            target: channel.target,
            allowedHost: c.host,
          );
          if (plan != null) {
            // ⚠ 口令从 plan 里来、只交给 endpointCall 放请求头：这里没有任何一条路径把
            //   它拼进 URL、写进 body 或落进日志（`FnthinkChannel.toString()` 那句截断也是同一件事）。
            attempt = () => endpointCall(
              contract: c.contract,
              probeUrl: plan.probeUrl,
              secret: plan.secret,
            );
          }
        }
      }
    }
    if (attempt == null) continue;
    // T115 护栏①：另一轮（进页 / 回前台 / 下拉）正在探这一条 ⇒ 这一轮跳过它。
    // 结论由那一发写回同一个键，界面靠它自己的 onUpdated 重画 —— 这里再发一次只是把
    // 同一条路问两遍（而这一族的"问一遍"不免费：一次是签名事件，一次是出示口令）。
    if (_probing.add(channel.id)) {
      try {
        final watch = Stopwatch()..start();
        final ready = await probeFnthinkAttempts(attempt);
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
