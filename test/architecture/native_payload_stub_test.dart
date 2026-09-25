import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/native_payload_stubs.dart';
import '../support/channel_descriptor_fixtures.dart';

/// 集成测试的原生载荷桩 ⇄ 导出快照（roadmap T09-B1）。
///
/// 集成测试跑在设备上，读不到仓库里的 `channel_descriptors.json`，只能自带一份桩。
/// 这份桩过去在 `smoke_test.dart` 与 `release_walkthrough_test.dart` 里各抄一遍，
/// 两次都撞出同一类事故：**桩与原生表分叉时不会有人红** ——
/// T08-B 改载荷形状 ⇒ 设备侧 splash 静默判"描述符未就绪"而 681 例单测全绿；
/// T08-C2 邮件页改成按描述符渲染 ⇒ 桩里没有 email 族，闸门直接点不开编辑器。
///
/// 本守卫做的是**数据级深比对**（把桩的 map 与快照的 map 逐键比），不是正则扫源码：
/// 解析式守卫一旦锚点漂移就会静默放行，那正是本仓库反复撞到的失效模式。
void main() {
  final snapshot = <String, Map<Object?, Object?>>{
    for (final d in exportedDescriptors()) d['key'] as String: d,
  };

  /// 闸门实际点得到的类型（各文件只给自己用得上的那几条）。
  /// 新增一族/一类被闸门用到时，在这里加一行 —— 漏加就等于那类的桩没人核对过。
  final stubbed = <String, Map<String, Object?>>{
    'dingtalk': stubDingtalk(),
    'wechat_work': stubWechatWork(),
    'wecom_app': stubWecomApp(),
    'email': stubEmail(),
  };

  group('集成桩与导出快照逐字段一致', () {
    test('桩非空且每条都在原生表里（表没了就该删桩）', () {
      expect(stubbed, isNotEmpty, reason: '一条桩都没有 = 守卫空转');
      for (final key in stubbed.keys) {
        expect(
          snapshot.containsKey(key),
          isTrue,
          reason:
              '桩里还有 $key，但原生描述符表已经没有它了 —— '
              '留着只会让闸门在一条不存在的通道上练点击',
        );
      }
    });

    test('每条桩与其快照行**完全同形**（键集合与值都要一致）', () {
      for (final entry in stubbed.entries) {
        final real = snapshot[entry.key]!;
        final stub = entry.value;
        // 先比键集合：少一个键（如 webhook 的 textLimitChars）在 Dart 侧的表现是
        // "那个字段永远读不到"，而页面只是少了点东西，不会崩 —— 最容易漏。
        expect(
          stub.keys.toSet(),
          real.keys.toSet(),
          reason: '${entry.key} 的桩与快照键集合不同（左=桩，右=快照）',
        );
        for (final k in real.keys) {
          expect(
            stub[k],
            equals(real[k]),
            reason:
                '${entry.key}.$k 与导出快照不一致：桩=${stub[k]} 快照=${real[k]}。'
                '改原生表之后要同步这里，否则闸门测的是一份不存在的元数据。',
          );
        }
      }
    });

    test('消息格式档位与原生名单一致', () {
      expect(
        stubMessageFormats,
        equals(exportedMessageFormats()),
        reason: '桩里的档位与原生 TemplateEngine.formatOptions 分叉（T08-B 那类第二份真值）',
      );
    });

    test('桩组装出的载荷形状与生产相同（对象 + 两个键）', () {
      final payload = channelDescriptorsStub([stubDingtalk()]);
      expect(
        payload.keys.toSet(),
        {'descriptors', 'messageFormats'},
        reason:
            '形状变了要同时改 `ChannelDescriptorService.load()` 与两处集成桩 —— '
            '服务认不下载荷时是**保留旧缓存**的（静默降级），不会有人红',
      );
    });
  });
}
