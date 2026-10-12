import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/active_channels.dart';
import 'package:notice_transmit/services/channel_config_codec.dart';

/// T151（维护者 2026-10-12 第 7 条：「首页当前推送通道改为仅显示主通道，其余不在首页显示」）。
///
/// 判 role 这一刀只有 `splitHomeChannels` 一个作者，所以它自己要有用例 ——
/// 判错一档的代价是**首页安静地少一行/多一行，而界面不报任何错**：
/// `role=none` 是"启用但不参与推送"、`role=unset` 是"刚建好还没归队"，
/// 页面若自己现编口径（最常见的写法是 `role != backup`）就会把那两档算进首页，
/// 于是首页出现一条**根本不会推送**的通道，用户以为它在。
void main() {
  ActiveChannel byRole(String role, String name) => ActiveChannel(
    family: 'webhook',
    slug: 'dingtalk',
    id: name,
    displayName: '钉钉',
    configName: name,
    target: 'oapi.dingtalk.com',
    role: role,
  );

  List<String> homeNames(List<ActiveChannel> all) =>
      splitHomeChannels(all).homeRows.map((c) => c.configName).toList();

  group('只留主档', () {
    test('主 + 备 + 不参与 + 未设置 ⇒ homeRows 只有那一条主档', () {
      final all = [
        byRole(ChannelConfigCodec.rolePrimary, '主群'),
        byRole(ChannelConfigCodec.roleBackup, '备群'),
        byRole(ChannelConfigCodec.roleNone, '不参与'),
        byRole(ChannelConfigCodec.roleUnset, '刚建好'),
      ];
      expect(
        splitHomeChannels(all).homeRows.map((c) => c.configName).toList(),
        ['主群'],
        reason:
            '多画一条 = 首页声称一条**从不会推送**的通道在推（`none` 那档就是这个意思），'
            '而界面不报任何错；页面现编口径最顺手的 `role != backup` 恰好会踩中',
      );
    });

    test('被藏的条数单独一条：hiddenOthers 恰好等于非主档那几条', () {
      final all = [
        byRole(ChannelConfigCodec.rolePrimary, '主群'),
        byRole(ChannelConfigCodec.roleBackup, '备群'),
        byRole(ChannelConfigCodec.roleNone, '不参与'),
        byRole(ChannelConfigCodec.roleUnset, '刚建好'),
      ];
      expect(
        splitHomeChannels(all).hiddenOthers,
        3,
        reason:
            '这个数是首页那句「另有 N 条」的唯一读数：算错就是当着用户的面少报/多报几条通道，'
            '而那几条其实照在推送',
      );
    });

    test('不许"没有主就退让给备"：全是非主 ⇒ homeRows 为空、hiddenOthers 仍是全量', () {
      final all = [
        byRole(ChannelConfigCodec.roleBackup, '备群'),
        byRole(ChannelConfigCodec.roleNone, '不参与'),
      ];
      final split = splitHomeChannels(all);
      expect(
        split.homeRows,
        isEmpty,
        reason:
            '退让会让首页显示一条**用户没设为主**的通道，而页面那句"当前推送通道"就变成谎；'
            '空表中让页面说出「未设主通道」，那才是真话',
      );
      expect(split.hiddenOthers, 2);
    });

    test('两条主并存（旧数据/并排设过）⇒ 都画出来，不许只取第一条', () {
      final all = [
        byRole(ChannelConfigCodec.rolePrimary, '主一'),
        byRole(ChannelConfigCodec.roleBackup, '备'),
        byRole(ChannelConfigCodec.rolePrimary, '主二'),
      ];
      expect(homeNames(all), ['主一', '主二']);
      expect(splitHomeChannels(all).hiddenOthers, 1);
    });

    test('顺序沿用进来的那一遍，不重排', () {
      final all = [
        byRole(ChannelConfigCodec.rolePrimary, '应用'),
        byRole(ChannelConfigCodec.roleBackup, '藏'),
        byRole(ChannelConfigCodec.rolePrimary, '幻念'),
        byRole(ChannelConfigCodec.rolePrimary, '邮件'),
      ];
      expect(homeNames(all), ['应用', '幻念', '邮件']);
    });

    test('一条都没启用 ⇒ 空 + 0（页面据此走原来那句"还没有配置通道"）', () {
      final split = splitHomeChannels(const []);
      expect(split.homeRows, isEmpty);
      expect(
        split.hiddenOthers,
        0,
        reason: 'hiddenOthers>0 与 ==0 是页面上两句不同的话，这里必须分得开',
      );
    });

    test('脏 role 值不进首页（Codec 把认不出的归到主，所以这一条盯的是"未归一化的原值"）', () {
      final split = splitHomeChannels([byRole('', '空值'), byRole('主', '中文')]);
      expect(
        split.homeRows,
        isEmpty,
        reason:
            '这里喂的是**没经 ChannelConfigCodec 归一化**的原值：存储层会把认不出的归成 primary，'
            '而 `splitHomeChannels` 只认字面值 —— 谁绕过 Codec 直接喂脏值，这里就得让它看不见'
            '（宁可首页少一行，也不要首页凭空多一条）',
      );
      expect(split.hiddenOthers, 2);
    });
  });
}
