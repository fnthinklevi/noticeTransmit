import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/fnthink_inbox_message.dart';
import 'platform_channel.dart';

/// 把一条收件显示成系统通知（T48 的前置；实现在 `FnthinkInboxDisplay.kt`）。
///
/// 这台 App 此前没有"从 Dart 显示一条通知"的能力 —— 收货链路把消息取回来也落库了，
/// 但用户看不见，而"可以慢不能丢"要的是**用户看得见**。
///
/// ⚠ 这里只回 true/false，**不抛**：显示失败不是收货失败。调用方（收货循环）拿这个布尔值决定
/// ack 报 `displayed` 还是 `delivered` —— 把"没显示出去"报成"已显示"，服务端就会按契约删正文，
/// 而用户从头到尾没见过这条。
class FnthinkInboxDisplay {
  FnthinkInboxDisplay({MethodChannel? channel})
    : _channel = channel ?? AppChannels.notification;

  final MethodChannel _channel;

  /// 空 id 直接回 false：那是"没有这一条"，不是一次显示请求。
  /// 服务端删正文、本机标已读、通知栏撤回，全都要按 id 说话。
  Future<bool> show(FnthinkInboxMessage message) async {
    if (message.messageId.isEmpty) return false;
    try {
      final shown = await _channel.invokeMethod<bool>('showFnthinkInbox', {
        'messageId': message.messageId,
        'sender': message.sender,
        'title': message.title,
        'body': message.body,
      });
      return shown ?? false;
    } catch (e) {
      // 平台通道没接（纯 Dart 测试）、原生抛异常，都只意味着"这次没显示"。
      // 往上抛会让整轮收货失败，那条消息本来已经安全落库了。
      debugPrint('[fnthink] 收件通知显示调用失败（按未显示处理）: $e');
      return false;
    }
  }

  /// 取走「点通知要跳去的那一条」（T83）。返回 null = 没有待跳的那条。
  ///
  /// ⚠ **这一枚 id 的唯一出口就是这里**：原生侧 `FnthinkOpenTarget.take()` 取走即清，
  /// 所以冷启动那一路与热恢复那一路不可能各跳一次。别在这里加"读但不清"的第二种读法 ——
  /// 第二个读者一旦出现，"同一条通知跳两遍"就只是时间问题。
  ///
  /// 通道没接（纯 Dart 测试、原生异常）也回 null：那的含义是"没东西要跳"，
  /// 调用方据此什么都不做，而不是猜一条。
  Future<String?> takeOpenTarget() async {
    try {
      return await _channel.invokeMethod<String>('takeFnthinkOpenTarget');
    } catch (e) {
      debugPrint('[fnthink] 取「要点开的那条」失败（按没有待跳处理）: $e');
      return null;
    }
  }
}
