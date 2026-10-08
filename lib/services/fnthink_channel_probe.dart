import 'dart:async';

import 'package:fnthink_push/fnthink_push.dart';

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
/// 返回 **null = 这次没有结论**（调用方据此**不写健康度**）；true / false = 服务端的结论。
///
/// 三条口径，每条防的都是具体的一种错：
///  ① **有结论就立刻收工**（哪怕结论是 `false`）：`ready:false` 是服务端查过之后的答复，
///     再试两次不会有第二个答案 —— 重试针对的是"没问到"，不是"问到了坏消息"；
///  ② **三次都没成 ⇒ `false`**（超时、连不上、服务端答了却没给结论）。这是维护者定的产品口径
///     （「超时显示失败」）。⚠ 它与另外三族那条「探测调用本身抛异常时不写不可达」**刻意不同**：
///     那三族的探针在原生侧，探测本身失败多半是本机的事；这一族的绿灯说的是"对面那条链立得住"，
///     把"连问三次都没问到"画成绿是假安心；
///  ③ 每次一发**各自**计时（不共用一份总预算）：一台 3 秒、串行三次最多 9 秒 ——
///     总预算制会让"第一发卡满"吃掉后面两发，而那正是最需要重试的情形。
Future<bool?> probeFnthinkWithRetries(
  FnthinkProbeCall call, {
  required String peer,
  Duration budget = kFnthinkProbeBudget,
  int attempts = kFnthinkProbeAttempts,
}) async {
  for (var i = 0; i < attempts; i++) {
    try {
      final result = await call(peer: peer).timeout(budget);
      if (result.ready != null) return result.ready;
    } catch (_) {
      // 超时 / 传输异常：这一发不算，下一发见。
    }
  }
  return false;
}
