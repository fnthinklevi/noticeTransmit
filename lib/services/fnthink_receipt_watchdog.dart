import 'dart:async';

import 'package:flutter/foundation.dart';

/// 「发件回执看守」（T194 A 档）。
///
/// 它解决的是一条**没人跑就没有读者**的链：发送端锁屏、接收开关关着、或收货循环没跑时，
/// 没有任何人发 `/poll` ⇒ 服务端那边的 `receipts` 永远不被消费，发送端历史停在
/// 「发送中」，而目标设备其实早已收下。
///
/// 它**不是第二个轮询**：没有自己的节奏，只在三个时刻被踢一脚 —— 发送后（[kick]，
/// 短窗口合并）、回前台 / 冷启动（[runNow]，等它结束再把清扫排在其后）。每次只先问
/// 「本机还有没有在等回执的发件」：没有就一个字节都不发；有就只取回执（`/receipts`），
/// 不取货、不刷新在场。等远程执行回执的那一路复用**既有收货循环**的「立即收取」，
/// 不开第二条轮询。全部终态之后下一次踢进来自然什么都不做 —— 这就是「短生命周期」的
/// 全部实现，不留常驻定时器。
class FnthinkReceiptWatchdog {
  FnthinkReceiptWatchdog({
    required this.hasWaiting,
    required this.sync,
    this.remoteWaiting,
    this.receiveRound,
    this.debounce = const Duration(seconds: 2),
    this.onSyncResult,
  });

  /// 本机还有没有「在路上」的幻念发件（通知历史里那一格仍 pending/queued）。
  final Future<bool> Function() hasWaiting;

  /// 只取回执那一发。返回取到几条（0 也是一次成功的同步）。
  final Future<int> Function() sync;

  /// 本机还有没有在等对面回执的**远程执行**发件（`direction=out` 未终态）。
  final Future<bool> Function()? remoteWaiting;

  /// 等远程回执要走一次正常收货轮（回执是一条消息，不在 `/receipts` 里）——
  /// 复用既有循环的入口，**不开第二条轮询**。
  final Future<void> Function()? receiveRound;

  /// [kick] 的合并窗口：转发一批通知不该发 N 发 `/receipts`。
  final Duration debounce;

  /// 每次同步取到几条（测试与诊断用；生产不接）。
  final void Function(int applied)? onSyncResult;

  Timer? _debounceTimer;
  Future<void>? _inFlight;
  bool _disposed = false;

  /// 发送之后踢一脚：短窗口内多次发送合并成一次。
  void kick() {
    if (_disposed || _debounceTimer != null) return;
    _debounceTimer = Timer(debounce, () {
      _debounceTimer = null;
      unawaited(runNow());
    });
  }

  /// 回前台 / 冷启动 / 唤醒：立刻跑一次，并等它结束（清扫排在它之后）。
  Future<void> runNow() {
    if (_disposed) return Future<void>.value();
    final running = _inFlight;
    if (running != null) return running;
    final future = _run();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
  }

  Future<void> _run() async {
    try {
      if (await hasWaiting()) {
        final applied = await sync();
        onSyncResult?.call(applied);
        return;
      }
      if ((await remoteWaiting?.call()) != true) return;
      final round = receiveRound;
      if (round == null) return;
      // 回前台那条链还要接着跑清扫；远程回执这一发是收货循环的事，不挡它。
      unawaited(
        round().catchError((Object e) {
          debugPrint('[fnthink] 发件看守补一轮收货失败：$e');
        }),
      );
    } catch (e) {
      // 看守失败不改任何一格：本机的「在等」仍是真话，下一脚再来。
      debugPrint('[fnthink] 发件看守这一轮失败：$e');
    }
  }

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
}
