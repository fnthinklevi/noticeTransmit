import 'platform_channel.dart';

/// 远程执行的**状态栏通知**那一半（片3c-5；契约 `delay.cancelChannels` 的 `statusBar`）。
///
/// ## 它为什么不在 Dart 里自己发通知
/// 带一枚**动作按钮**的系统通知需要一个 `PendingIntent` 指向一个 `BroadcastReceiver`，
/// 而那条广播要让引擎知道 —— 原生侧收下之后只能落盘（`RemoteExecutionCancelStore`），
/// 再由 Dart 到点动手前问一句。整条链没有一处能"从 Dart 直接发"。
///
/// ## 撤销的**权威在原生**
/// 用户按下去的时候 Dart 可能已经不在跑（后台轮次随时会被系统回收），
/// 而那正是这一格存在的理由 —— 用户不在这个 App 里。
/// 所以 [takeCancelled] 那一问是执行链**到点动手前**必须做的一步，
/// 漏掉它，表现是"我明明按了撤销，它还是执行了"。
///
/// ⚠ 每一次都是 **MethodChannel 往返**。它只发生在两条路径上
/// （窗口开始时发一条、到点时问一句），一分钟最多几次。
class RemoteExecutionNotifier {
  const RemoteExecutionNotifier();

  /// 复用那一条通知通道（与收件显示同一个 channel id —— 原生侧按方法名分派，
  /// 不同方法落在不同域的 handler 里，不靠 channel 区分）。
  static const _channel = AppChannels.notification;

  /// 发一条「N 秒后自动执行」的通知，带一枚撤销按钮。
  ///
  /// 回 false = **没发出去**（通知权限被关 / 渠道被禁用 / `execId` 空）。
  /// 调用方据此知道"撤销入口只有界面那一处"，并可以把这件事如实说给用户 ——
  /// 静默当成功的话，用户以为状态栏有入口而它根本没有。
  Future<bool> show({
    required String execId,
    required String item,
    required int seconds,
  }) async {
    if (execId.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>('fnthinkRemoteExecShow', {
            'execId': execId,
            'item': item,
            'seconds': seconds,
          }) ??
          false;
    } catch (e) {
      return false;
    }
  }

  /// 收掉那一枚（到了终点：做了 / 没成 / 撤了）。
  Future<void> clear(String execId) async {
    if (execId.isEmpty) return;
    try {
      await _channel.invokeMethod<bool>('fnthinkRemoteExecClear', {
        'execId': execId,
      });
    } catch (e) {
      // 清理失败不留痕：通知会在用户下一次把它划掉时消失，
      // 而为"清理没成"再写一行日志只会多一个要查的地方。
    }
  }

  /// 问一次：这一条在界面之外被撤了吗？**问完即清**（见原生那一格的同一条理由）。
  Future<bool> takeCancelled(String execId) async {
    if (execId.isEmpty) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'fnthinkRemoteExecTakeCancelled',
            {'execId': execId},
          ) ??
          false;
    } catch (e) {
      // 读不到就当"没被撤"：那是**执行**的方向（多执行一次）而不是**静默丢弃**的方向 ——
      // 宁可按协议的超时语义执行，也不要因为一次通道故障让对面的指令凭空消失。
      return false;
    }
  }

  /// 收尾时清掉原生那一份（一次都没被问过的那种）。
  Future<void> forget(String execId) async {
    if (execId.isEmpty) return;
    try {
      await _channel.invokeMethod<bool>('fnthinkRemoteExecForget', {
        'execId': execId,
      });
    } catch (e) {
      // 同上：原生那份有 TTL（两倍窗口上限），扫不到就让它自己过期。
    }
  }
}
