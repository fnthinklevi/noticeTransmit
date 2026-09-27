import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/active_channels.dart';
import 'package:notice_transmit/services/channel_config_codec.dart';
import 'package:notice_transmit/services/channel_role_guide.dart';

/// 升级后「主备通道」引导的判定（维护者 1.5.76 反馈 #2 的第二半）。
///
/// 只测判定，不测界面：什么时候该弹、什么时候**不该**弹，全是一张真值表；
/// 界面部分（AlertDialog + 记 prefs）钉在 channel_role_schema_test 的源守卫里。
///
/// 不该弹的三种情形各有各的坏处，缺一不可：
///  - 已经弹过还弹 ⇒ 每次启动拦一遍，用户学会闭眼点掉，引导就失效了；
///  - 只有一条通道就弹 ⇒ 没有"主备"可分，除了困惑什么都没换来；
///  - 一条主 + 零条未设置还弹 ⇒ 那已经是最正确的形状。
void main() {
  ActiveChannel ch(String role) => ActiveChannel(
    family: 'webhook',
    slug: 'wecom',
    id: 'id-$role-${DateTime.now().microsecondsSinceEpoch}',
    displayName: '企微',
    configName: '机器人',
    target: 'qyapi.weixin.qq.com',
    role: role,
    health: null,
  );

  group('shouldPrompt 真值表', () {
    bool p({
      String? seen = '1.5.77',
      String current = '1.5.77',
      required int primary,
      required int unset,
    }) => ChannelRoleGuide.shouldPrompt(
      seenVersion: seen,
      currentVersion: current,
      primaryCount: primary,
      unsetCount: unset,
    );

    test('本版本已经提示过 ⇒ 不再弹（点"以后再说"也算提示过）', () {
      expect(p(primary: 5, unset: 3), isFalse);
    });

    test('版本变了 ⇒ 可以再提醒一次', () {
      expect(
        p(seen: '1.5.76', current: '1.5.77', primary: 2, unset: 0),
        isTrue,
        reason: '记的是版本号而不是布尔，就是为了每次升级都能重新引导一遍',
      );
    });

    test('新装（一条通道都没有）⇒ 不弹', () {
      expect(p(seen: null, primary: 0, unset: 0), isFalse);
    });

    test('只有一条主、没人未设置 ⇒ 不弹（那已经是对的）', () {
      expect(p(seen: null, primary: 1, unset: 0), isFalse);
    });

    test('只有一条未设置 ⇒ 不弹（不到两条就没有主备可分）', () {
      expect(p(seen: null, primary: 0, unset: 1), isFalse);
    });

    test('两条都在主档 ⇒ 弹（同一条通知会重复推两次，这是要引导的那个形状）', () {
      expect(p(seen: null, primary: 2, unset: 0), isTrue);
    });

    test('一条主 + 一条未设置 ⇒ 弹（新建那条正等着被决定）', () {
      expect(p(seen: null, primary: 1, unset: 1), isTrue);
    });

    test('两条未设置 ⇒ 弹', () {
      expect(p(seen: null, primary: 0, unset: 2), isTrue);
    });
  });

  group('decide：从通道清单算数', () {
    test('点名条数 = 主 + 未设置；备与不参与都不算', () {
      final d = ChannelRoleGuide.decide(
        seenVersion: null,
        currentVersion: '1.5.77',
        channels: [
          ch(ChannelConfigCodec.rolePrimary),
          ch(ChannelConfigCodec.rolePrimary),
          ch(ChannelConfigCodec.roleUnset),
          ch(ChannelConfigCodec.roleBackup),
          ch(ChannelConfigCodec.roleNone),
        ],
      );
      expect(d.prompt, isTrue);
      expect(d.count, 3, reason: '弹窗正文要说"3 条需要确认"，备和不参与都已经是明确决定');
    });

    test('全是备用（没人设主）⇒ 不弹：发送层有兜底，不会因此静默不发', () {
      final d = ChannelRoleGuide.decide(
        seenVersion: null,
        currentVersion: '1.5.77',
        channels: [
          ch(ChannelConfigCodec.roleBackup),
          ch(ChannelConfigCodec.roleBackup),
        ],
      );
      expect(d.prompt, isFalse);
    });

    test('未设置那格用的是跨端契约值 unset，不是页面自造的字面量', () {
      expect(ChannelConfigCodec.roleUnset, 'unset');
      expect(ChannelConfigCodec.normalizeRole('unset'), 'unset');
      expect(ChannelConfigCodec.normalizeRole(' UNSET '), 'unset');
    });
  });
}
