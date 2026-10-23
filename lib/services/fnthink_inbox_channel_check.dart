import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'platform_channel.dart';

/// 收件通知渠道的可读状态（T173）。
class FnthinkInboxChannelState {
  const FnthinkInboxChannelState({
    required this.channelId,
    required this.channelExists,
    required this.notificationsEnabled,
    required this.highImportance,
    required this.sound,
    required this.vibration,
    required this.lockscreenVisibility,
    required this.showBadge,
  });

  final String channelId;
  final bool channelExists;
  final bool notificationsEnabled;
  final bool highImportance;
  final String sound;
  final bool vibration;
  final int lockscreenVisibility;
  final bool showBadge;

  /// 系统 `Notification.VISIBILITY_PUBLIC`。
  static const int visibilityPublic = 1;

  static FnthinkInboxChannelState? fromMap(Object? raw) {
    if (raw is! Map) return null;
    return FnthinkInboxChannelState(
      channelId: '${raw['channelId'] ?? ''}',
      channelExists: raw['channelExists'] == true,
      notificationsEnabled: raw['notificationsEnabled'] == true,
      highImportance: raw['highImportance'] == true,
      sound: '${raw['sound'] ?? ''}',
      vibration: raw['vibration'] == true,
      lockscreenVisibility:
          (raw['lockscreenVisibility'] as num?)?.toInt() ?? -1,
      showBadge: raw['showBadge'] == true,
    );
  }
}

/// 自检发现的那几档问题。**每一档各自一句**，不合并成"配置有问题"。
enum FnthinkInboxChannelIssue {
  notificationsDisabled,
  channelMissing,
  notHighImportance,
  noSound,
  noVibration,
  lockscreenNotPublic,
}

/// 纯函数：把一个状态翻成问题清单（顺序固定，界面直接按这个顺序画）。
List<FnthinkInboxChannelIssue> fnthinkInboxChannelIssues(
  FnthinkInboxChannelState state,
) {
  if (!state.notificationsEnabled) {
    return const [FnthinkInboxChannelIssue.notificationsDisabled];
  }
  if (!state.channelExists) {
    return const [FnthinkInboxChannelIssue.channelMissing];
  }
  return [
    if (!state.highImportance) FnthinkInboxChannelIssue.notHighImportance,
    if (state.sound.isEmpty) FnthinkInboxChannelIssue.noSound,
    if (!state.vibration) FnthinkInboxChannelIssue.noVibration,
    if (state.lockscreenVisibility != FnthinkInboxChannelState.visibilityPublic)
      FnthinkInboxChannelIssue.lockscreenNotPublic,
  ];
}

/// 自检的三个动作。全部走**原生同一个类**的状态与方法：Dart 不自己猜渠道配置。
class FnthinkInboxChannelCheck {
  FnthinkInboxChannelCheck({MethodChannel? channel})
    : _channel = channel ?? AppChannels.notification;

  final MethodChannel _channel;

  Future<FnthinkInboxChannelState?> state() async {
    try {
      final raw = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'fnthinkInboxChannelState',
      );
      return FnthinkInboxChannelState.fromMap(raw);
    } catch (e) {
      debugPrint('[fnthink] 读收件渠道状态失败：$e');
      return null;
    }
  }

  /// 重建一条新的高优先级渠道，返回新 id（null = 这一发没成功）。
  Future<String?> rebuild() async {
    try {
      return await _channel.invokeMethod<String>('fnthinkInboxChannelRebuild');
    } catch (e) {
      debugPrint('[fnthink] 重建收件渠道失败：$e');
      return null;
    }
  }

  Future<bool> showTest() async {
    try {
      return await _channel.invokeMethod<bool>('fnthinkInboxShowTest') ?? false;
    } catch (e) {
      debugPrint('[fnthink] 发测试通知失败：$e');
      return false;
    }
  }

  Future<void> openSystemSettings() async {
    try {
      await _channel.invokeMethod<void>('openInboxChannelSettings');
    } catch (e) {
      debugPrint('[fnthink] 打开收件渠道设置失败：$e');
    }
  }
}
