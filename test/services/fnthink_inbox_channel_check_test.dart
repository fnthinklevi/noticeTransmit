import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_inbox_channel_check.dart';

/// T173：收件渠道状态 → 问题清单。
///
/// 每一档各说各的：把"通知权限关着"与"渠道被降级"并成一句，用户的下一步动作就没了。
void main() {
  FnthinkInboxChannelState state({
    bool notificationsEnabled = true,
    bool channelExists = true,
    bool highImportance = true,
    String sound = 'content://settings/system/notification_sound',
    bool vibration = true,
    int lockscreenVisibility = FnthinkInboxChannelState.visibilityPublic,
    bool showBadge = true,
  }) => FnthinkInboxChannelState(
    channelId: 'fnthink_inbox_v2',
    channelExists: channelExists,
    notificationsEnabled: notificationsEnabled,
    highImportance: highImportance,
    sound: sound,
    vibration: vibration,
    lockscreenVisibility: lockscreenVisibility,
    showBadge: showBadge,
  );

  test('正常状态没有问题', () {
    expect(fnthinkInboxChannelIssues(state()), isEmpty);
  });

  test('通知权限关着时只报那一档（其余读数此刻没有意义）', () {
    expect(
      fnthinkInboxChannelIssues(
        state(notificationsEnabled: false, highImportance: false),
      ),
      [FnthinkInboxChannelIssue.notificationsDisabled],
    );
  });

  test('渠道没建 ≠ 配置坏了：只报「还没建」', () {
    expect(
      fnthinkInboxChannelIssues(
        state(channelExists: false, highImportance: false),
      ),
      [FnthinkInboxChannelIssue.channelMissing],
    );
  });

  test('降级 / 没声音 / 没震动 / 锁屏不显示各报各的，顺序固定', () {
    expect(
      fnthinkInboxChannelIssues(
        state(
          highImportance: false,
          sound: '',
          vibration: false,
          lockscreenVisibility: 0,
        ),
      ),
      [
        FnthinkInboxChannelIssue.notHighImportance,
        FnthinkInboxChannelIssue.noSound,
        FnthinkInboxChannelIssue.noVibration,
        FnthinkInboxChannelIssue.lockscreenNotPublic,
      ],
    );
  });
}
