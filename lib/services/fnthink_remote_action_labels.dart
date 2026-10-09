import '../l10n/app_localizations.dart';

/// 契约里那些动作与设置项，**给人看的那一句**只有一个作者 = 这个文件。
///
/// ## 为什么名单不在这里
/// 词表的唯一出处仍是契约（`capabilities.l2.actions` 与 `capabilities.l3.settings`）。
/// 这里只回答"这个动作对面上的人话说成什么"，**不回答"有没有这个动作"**：
/// 那份名单在这里再抄一遍的下场，就是本仓反复在治的第二份实现 ——
/// 契约加一项而这里没加，界面上那一格就永远不出现，而对面已经能收了。
/// 所以 `test/architecture/fnthink_remote_action_labels_test.dart` 判的是**双向差集**：
/// 少一项红、多一项也红。
///
/// ## 为什么不写 ARB 键名再去反查
/// 下面这张表存的是**取值函数**，不是字符串键名。于是"词条配了没有"这件事由编译器判：
/// 少一条 ARB 词条就编译不过，而不必等一条运行时用例去撞。
final Map<String, String Function(AppLocalizations)>
kFnthinkRemoteActionLabels = {
  'listener:start': (l) => l.remoteActionListenerStart,
  'listener:stop': (l) => l.remoteActionListenerStop,
  'channel:toggle': (l) => l.remoteActionChannelToggle,
  'device_state:push': (l) => l.remoteActionDeviceStatePush,
  'notifications:report': (l) => l.remoteActionNotificationsReport,
  'alert:ring': (l) => l.remoteActionAlertRing,
  'sms:search': (l) => l.remoteActionSmsSearch,
  'notification': (l) => l.remoteSettingNotification,
  'exact_alarm': (l) => l.remoteSettingExactAlarm,
  'battery_optimization': (l) => l.remoteSettingBatteryOptimization,
  'autostart': (l) => l.remoteSettingAutostart,
  'monitoring': (l) => l.remoteSettingMonitoring,
  'collect_inbox': (l) => l.remoteSettingCollectInbox,
};

/// 这一项的人话说法。契约里有而这里没配 ⇒ 原样回那个动作名（**看得见**的缺，
/// 不是编一句假话把它盖住），同时 [hasFnthinkRemoteActionLabel] 回 false 让守卫红。
String fnthinkRemoteActionLabel(AppLocalizations l10n, String action) {
  final label = kFnthinkRemoteActionLabels[action];
  return label == null ? action : label(l10n);
}

/// 这一项配了人话词条没有（守卫用它，页面不用它）。
bool hasFnthinkRemoteActionLabel(String action) =>
    kFnthinkRemoteActionLabels.containsKey(action);
