import 'package:flutter/foundation.dart';

import 'platform_channel.dart';

/// 「备用模式已启用」这个锁存的读写入口（T12）。
///
/// 状态只住在原生（`channel_send_fails` prefs 的 `backup_engaged`）：降级发生在发送现场，
/// 而锁存刻意**不自动解除**（防主备抖动），所以这里只有"读"和"手动切回"两个动作。
/// 不放进 GetIt：它是无状态的静态转发，注册进容器只会多一条装配顺序要照顾的东西。
class BackupMode {
  BackupMode._();

  static const _channel = AppChannels.notification;

  /// 读取失败按"未锁存"处理：这个值只影响一条提示与一个按钮，
  /// 报成"已切到备用"会把用户引去点一个没有作用的按钮。
  static Future<bool> isEngaged() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('getBackupMode');
      if (raw is Map) return raw['engaged'] == true;
      return false;
    } catch (e) {
      debugPrint('BackupMode: 读取备用模式失败: $e');
      return false;
    }
  }

  /// 手动切回主通道。原生会连带清掉连续失败计数，否则一放开就又被判不可用。
  static Future<void> reset() async {
    try {
      await _channel.invokeMethod<dynamic>('resetBackupMode');
    } catch (e) {
      debugPrint('BackupMode: 切回主通道失败: $e');
    }
  }
}
