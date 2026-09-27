import 'active_channels.dart';
import 'channel_config_codec.dart';

/// 升级后的「主备通道」引导（维护者 1.5.76 反馈 #2 的第二半）。
///
/// 这里只放**判定**，不放界面：弹不弹、什么形状才值得弹、同一个版本只弹一次 ——
/// 这三件事都能在纯函数里测完；界面部分留在调用方（主页），因为它需要 l10n 与 context。
///
/// 为什么需要它：新建通道的起点已从「主」改成「未设置」（见 [ChannelConfigCodec.roleUnset]），
/// 但**存量**用户升级上来时所有通道都还在「主」档 —— 同一条通知会照着通道数重复推送多次。
/// 那一版说明文字里写过的"老通道默认为主"对用户不构成可操作的指引，所以补一次弹窗引导。
class ChannelRoleGuide {
  /// 已提示过的**应用版本号**（不是布尔）：每个新版本都可以再提醒一次，
  /// 而不是"这辈子只提醒一次"。键名沿用 `<feature>_seen*` 的既有写法。
  static const seenVersionKey = 'channel_role_guide_seen_version';

  /// 该不该弹。三条判据各自对应一种"不该打扰"：
  ///  - 本版本已经提示过（点「以后再说」也算提示过）；
  ///  - 一共不到两条通道 —— 没有"主备"可分，弹了只会让人困惑；
  ///  - 恰好一条主、没人未设置 —— 那已经是正确的最简形状。
  static bool shouldPrompt({
    required String? seenVersion,
    required String currentVersion,
    required int primaryCount,
    required int unsetCount,
  }) {
    if (seenVersion == currentVersion) return false;
    if (primaryCount + unsetCount < 2) return false;
    return unsetCount > 0 || primaryCount >= 2;
  }

  /// 从通道清单算出该不该弹，并给出弹窗要点名的条数（=需要确认角色的那些）。
  static ({bool prompt, int count}) decide({
    required String? seenVersion,
    required String currentVersion,
    required List<ActiveChannel> channels,
  }) {
    final primary = channels
        .where((c) => c.role == ChannelConfigCodec.rolePrimary)
        .length;
    final unset = channels
        .where((c) => c.role == ChannelConfigCodec.roleUnset)
        .length;
    return (
      prompt: shouldPrompt(
        seenVersion: seenVersion,
        currentVersion: currentVersion,
        primaryCount: primary,
        unsetCount: unset,
      ),
      count: primary + unset,
    );
  }
}
