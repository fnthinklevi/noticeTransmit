import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'platform_channel.dart';

/// 备用模式这一格在屏幕上要说的那几句话需要的全部读数（都来自原生那一份真相）。
class BackupModeState {
  const BackupModeState({
    required this.engaged,
    this.releasedAt,
    this.releasedAuto = false,
    this.recoveryCount = 0,
  });

  /// 当前是否锁在"以备用为准"那一档
  final bool engaged;

  /// 最近一次切回主通道的时刻（epoch ms）。没切回过 → null。
  ///
  /// 下一次降级会把它抹掉（`BackupModeStore.engage`）：那句"已回到主通道"只描述
  /// 当前这一段故事，挂着上一段的话就是把过期结论画在屏幕上。
  final int? releasedAt;

  /// 那一次切回是自动判的（连续探测成功）还是用户手动点的
  final bool releasedAuto;

  /// 自动切回要攒够几次连续成功探测 —— **这个数住在原生判据那一处**
  /// （`ChannelRouting.RECOVERY_SUCCESS_COUNT`），这里只把它带过来念，不在 Dart 抄第二份。
  /// 0 = 原生没回（跨端键名漂移，由 `test/architecture/backup_switch_contract_test.dart` 拦）。
  final int recoveryCount;
}

/// 「备用模式」这一格的读写入口（T12 锁存，T135 自动切回与那枚开关）。
///
/// 锁存的状态只住在原生（`channel_send_fails` prefs）：降级发生在发送现场，
/// 而解除有两条路 —— 手动这一发，与路由按探测证据自己判的那一条。
/// 不放进 GetIt：它是无状态的静态转发，注册进容器只会多一条装配顺序要照顾的东西。
class BackupMode {
  BackupMode._();

  static const _channel = AppChannels.notification;

  /// 那枚「主通道不可用时自动切到备用通道」开关的 prefs 键。
  ///
  /// ⚠ 这个键是**跨语言的**：写在这里（Dart 是作者），读在原生
  /// （`BackupModeStore.KEY_AUTO_BACKUP` = `flutter.channel_auto_backup`）。
  /// 键名与**默认值**三处都得一致，由守卫比对（见上面那个文件的注释）。
  static const autoBackupPrefKey = 'channel_auto_backup';

  /// 读取失败按"未锁存"处理：这个值只影响一条提示与一个按钮，
  /// 报成"已切到备用"会把用户引去点一个没有作用的按钮。
  static Future<BackupModeState> read() async {
    try {
      final raw = await _channel.invokeMethod<dynamic>('getBackupMode');
      if (raw is! Map) return const BackupModeState(engaged: false);
      return BackupModeState(
        engaged: raw['engaged'] == true,
        releasedAt: (raw['releasedAt'] as num?)?.toInt(),
        releasedAuto: raw['releasedAuto'] == true,
        recoveryCount: (raw['recoveryCount'] as num?)?.toInt() ?? 0,
      );
    } catch (e) {
      debugPrint('BackupMode: 读取备用模式失败: $e');
      return const BackupModeState(engaged: false);
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

  /// 那枚开关的当前值。**缺键按开**（T135 拍板：今天的行为就是自动切备，
  /// 默认关等于把既有行为藏进一个用户不会去点的开关里）。
  ///
  /// 读不出 prefs（还没初始化等）也按开：这一格读不到时的正确观感是"照默认那样"，
  /// 而不是给用户画一个他并没有做过的决定。
  static Future<bool> autoBackupEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(autoBackupPrefKey) ?? true;
    } catch (e) {
      debugPrint('BackupMode: 读取自动切备开关失败（按默认值开处理）: $e');
      return true;
    }
  }

  static Future<void> setAutoBackupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(autoBackupPrefKey, enabled);
  }
}
