import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/services/channel_descriptor_service.dart';
import 'package:notice_transmit/widgets/channel_form_renderer.dart';
import 'package:notice_transmit/widgets/channel_visuals.dart';

import '../support/channel_descriptor_fixtures.dart';

/// 表单渲染器与文案表的纯逻辑测试（widget 树下的行为见设置页测试）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final descriptors = exportedDescriptors();
  List<ChannelDescriptor> parsed() =>
      descriptors.map((m) => ChannelDescriptor.fromMap(m)).toList();

  ChannelDescriptor wecom() => parsed().firstWhere((d) => d.key == 'wecom_app');

  Map<String, dynamic> existing() => {
    'corpid': 'corp-x',
    'agentid': 1000002,
    'touser': '@all',
    // 描述符里没有的键：真实场景是用户从旧版本备份回来的扩展参数
    'future_key': 'keep-me',
  };

  group('ensureControllers', () {
    test('为 schema 里每个字段各建一个控制器，并按 config 回填', () {
      final controllers = <String, TextEditingController>{};
      ChannelFormRenderer.ensureControllers(
        wecom(),
        controllers,
        existingConfig: existing(),
        keyPrefix: 'c1.',
      );
      expect(controllers.keys.toSet(), {
        'c1.corpid',
        'c1.agentid',
        'c1.touser',
      });
      expect(controllers['c1.corpid']!.text, 'corp-x');
      expect(controllers['c1.agentid']!.text, '1000002');
    });

    test('幂等：再次调用不覆盖用户已输入的文本', () {
      final controllers = <String, TextEditingController>{};
      ChannelFormRenderer.ensureControllers(
        wecom(),
        controllers,
        existingConfig: existing(),
        keyPrefix: '',
      );
      controllers['corpid']!.text = 'typed-by-user';
      ChannelFormRenderer.ensureControllers(
        wecom(),
        controllers,
        existingConfig: existing(),
        keyPrefix: '',
      );
      expect(controllers['corpid']!.text, 'typed-by-user');
    });
  });

  group('collect', () {
    test('保留未知键、覆盖 schema 字段、number 落 int', () {
      final controllers = <String, TextEditingController>{};
      ChannelFormRenderer.ensureControllers(
        wecom(),
        controllers,
        existingConfig: existing(),
        keyPrefix: '',
      );
      controllers['touser']!.text = 'user1|user2';
      final config = ChannelFormRenderer.collect(
        wecom(),
        controllers,
        existing(),
      );
      expect(config['touser'], 'user1|user2');
      expect(config['agentid'], 1000002);
      expect(config['future_key'], 'keep-me', reason: '未知键不得被丢弃');
    });

    test('留空时落到 schema 的默认值（而不是空串）', () {
      final controllers = <String, TextEditingController>{};
      ChannelFormRenderer.ensureControllers(
        wecom(),
        controllers,
        existingConfig: const {},
        keyPrefix: '',
      );
      final config = ChannelFormRenderer.collect(
        wecom(),
        controllers,
        const {},
      );
      expect(config['touser'], '@all');
      expect(config['agentid'], 0);
      expect(config['corpid'], '');
    });

    test('非数字文本原样保留（由原生校验报错，不在这里静默清零）', () {
      final controllers = <String, TextEditingController>{
        'agentid': TextEditingController(text: 'abc'),
      };
      final config = ChannelFormRenderer.collect(
        wecom(),
        controllers,
        const {},
      );
      expect(config['agentid'], 'abc');
    });
  });

  group('missingRequired', () {
    test('只报必填且无默认值的空字段', () {
      final controllers = <String, TextEditingController>{
        'corpid': TextEditingController(text: ''),
        'agentid': TextEditingController(text: ''),
        'touser': TextEditingController(text: ''),
      };
      expect(
        ChannelFormRenderer.missingRequired(wecom(), controllers),
        ['corpid'],
        reason: 'agentid 有默认值 0、touser 非必填，都不该拦下保存',
      );
    });

    test('控制器缺失也算未填', () {
      expect(
        ChannelFormRenderer.missingRequired(
          wecom(),
          <String, TextEditingController>{},
        ),
        ['corpid'],
      );
    });

    test('keyPrefix 生效', () {
      final controllers = <String, TextEditingController>{
        'c1.corpid': TextEditingController(text: 'ok'),
      };
      expect(
        ChannelFormRenderer.missingRequired(
          wecom(),
          controllers,
          keyPrefix: 'c1.',
        ),
        isEmpty,
      );
    });
  });

  group('描述符视图', () {
    test('byKey / families / 能力位读取', () {
      final serviceDescriptors = parsed();
      expect(serviceDescriptors, hasLength(15));
      final byKey = {for (final d in serviceDescriptors) d.key: d};
      expect(byKey['wecom_app']!.family, 'app');
      expect(byKey['dingtalk']!.family, 'webhook');
      expect(byKey['slack']!.capabilities, isEmpty);
      expect(byKey['ntfy']!.can('bearerToken'), isTrue);
    });
  });

  group('文案表', () {
    test('未知 slug 不套别人的名字（原样显示），图标走通用兜底', () {
      final l10n = lookupAppLocalizations(const Locale('zh'));
      expect(channelDisplayNameFor(l10n, 'matrix'), 'matrix');
      expect(channelVisual('matrix').icon, channelVisual('generic').icon);
      expect(channelVisual('matrix').color, channelVisual('generic').color);
      expect(hasChannelVisual('matrix'), isFalse);
    });

    test('channelNameOf 三级回退：labelKey → slug 表 → slug 本身', () {
      final l10n = lookupAppLocalizations(const Locale('zh'));
      final known = wecom();
      expect(channelNameOf(l10n, known), '企业微信自建应用');

      const unregisteredLabel = ChannelDescriptor(
        family: 'webhook',
        key: 'matrix',
        labelKey: 'channelTypeMatrix',
        iconKey: 'matrix',
        capabilities: {},
        fields: [],
      );
      expect(
        channelNameOf(l10n, unregisteredLabel),
        'matrix',
        reason: 'ARB 里没有这个词条时退回 slug，不能把资源名显示给用户',
      );
    });

    test('每个已知通道的提示文案与密钥提示都取得到', () {
      final l10n = lookupAppLocalizations(const Locale('zh'));
      for (final d in parsed()) {
        final visual = channelVisual(d.key);
        expect(
          channelLabelFor(l10n, visual.labelKey),
          isNot(visual.labelKey),
          reason: '${d.key} 的名称词条没有 case',
        );
        final desc = channelDescFor(l10n, visual);
        expect(desc, isNotEmpty, reason: '${d.key} 的提示文案为空');
        if (visual.descKey != null) {
          expect(desc, isNot(visual.descKey), reason: '${d.key} 的提示取到了资源名原文');
        }
        final signingHint = channelSigningHintFor(l10n, visual);
        expect(signingHint, isNotEmpty);
        if (visual.signingHintKey != null) {
          expect(
            signingHint,
            isNot(visual.signingHintKey),
            reason: '${d.key} 的密钥提示取到了资源名原文',
          );
        }
      }
    });
  });
}
