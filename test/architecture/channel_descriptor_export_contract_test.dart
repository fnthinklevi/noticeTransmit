import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/webhook_channel.dart';
import 'package:notice_transmit/services/channel_descriptor_service.dart';
import 'package:notice_transmit/services/channel_display.dart';
import 'package:notice_transmit/services/template_variables.dart';
import 'package:notice_transmit/widgets/channel_form_renderer.dart';
import 'package:notice_transmit/widgets/channel_visuals.dart';

import '../support/channel_descriptor_fixtures.dart';
import '../support/source_guards.dart';

/// 第 5 步的跨语言边界：原生描述符 ⇄ Dart 表单/文案表。
///
/// UI 改成按描述符渲染之后，「原生表」与「Dart 显示层」之间只剩三类衔接点，
/// 每一类出错都**不报错、只是显示得不一样**：
/// 1. slug 口径（`chan:<slug>` 的 slug == 描述符 `key` == 图标表 key）；
/// 2. ARB 资源名（描述符发的是资源名，Dart 查不到就当字符串显示出去）；
/// 3. URL 自动识别的 host 表（Dart `_platformRules` 与原生 `hosts` 必须是同一份事实，
///    否则界面显示的通道类型与原生实际使用的类型分叉）。
/// 本文件把这三件事变成断言。
void main() {
  final root = projectRoot();
  final descriptors = exportedDescriptors();
  final l10n = lookupAppLocalizations(const Locale('zh'));

  Map<String, dynamic> arbOf(String file) =>
      (jsonDecode(File('$root/$file').readAsStringSync())
            as Map<String, dynamic>)
        ..removeWhere((k, _) => k.startsWith('@'));

  group('导出快照自身', () {
    test('15 条：12 webhook + 2 应用通道 + 1 邮件', () {
      expect(descriptors, hasLength(15));
      final families = <String, int>{};
      for (final d in descriptors) {
        final f = d['family'] as String;
        families[f] = (families[f] ?? 0) + 1;
      }
      expect(families, {'webhook': 12, 'app': 2, 'email': 1});
    });

    test('key 唯一且是 slug 口径', () {
      final keys = descriptors.map((d) => d['key'] as String).toList();
      expect(keys.toSet().length, keys.length, reason: '描述符 key 重复');
      for (final k in keys) {
        expect(
          RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(k),
          isTrue,
          reason: '$k 不是 slug 口径',
        );
      }
    });
  });

  group('slug 口径贯穿三端', () {
    test('每条描述符都能被 Dart 身份表原样解析（否则送达键退成 generic）', () {
      for (final d in descriptors) {
        final key = d['key'] as String;
        expect(
          channelKey(key),
          key,
          reason:
              'channel_display.dart 的别名/名称表缺 $key：新增通道时送达键、'
              '历史徽标与统计都会把它归到「通用 Webhook」',
        );
      }
    });

    test('每条描述符在 Dart 图标表里有自己的条目（不套别人的图标与名字）', () {
      for (final d in descriptors) {
        final key = d['key'] as String;
        expect(
          hasChannelVisual(key),
          isTrue,
          reason: 'channel_visuals.dart 缺 $key：界面会用通用样式显示它',
        );
      }
    });
  });

  group('ARB 资源名两端一致', () {
    test('描述符的 labelKey 在 ARB 里真实存在，且 Dart 侧查得到译文', () {
      final arb = arbOf('lib/l10n/arb/app_zh.arb');
      for (final d in descriptors) {
        final labelKey = d['labelKey'] as String;
        expect(arb.containsKey(labelKey), isTrue, reason: 'ARB 缺词条 $labelKey');
        expect(
          channelLabelFor(l10n, labelKey),
          isNot(labelKey),
          reason: 'channelLabelFor 没有 $labelKey 的 case（界面会显示资源名原文）',
        );
      }
    });

    test('channelLabelFor 的 case 与文案表引用的词条一一对应，且都在 ARB 里', () {
      final src = stripComments(
        File('$root/lib/widgets/channel_visuals.dart').readAsStringSync(),
      );
      final arbZh = arbOf('lib/l10n/arb/app_zh.arb');
      final arbEn = arbOf('lib/l10n/arb/app_en.arb');

      final cases = RegExp(
        r"case '([A-Za-z0-9_]+)':",
      ).allMatches(src).map((m) => m.group(1)!).toSet();
      // 文件里出现的、名字确实在 ARB 中的字符串字面量 = 本表引用到的词条
      final referenced = RegExp(r"'([A-Za-z][A-Za-z0-9]+)'")
          .allMatches(src)
          .map((m) => m.group(1)!)
          .where((s) => arbZh.containsKey(s))
          .toSet();

      expect(
        cases,
        isNotEmpty,
        reason: '一枚 case 都没解析到 ⇒ 上面两条双向核对与下面那条 ARB 遍历全部空跑（假绿）',
      );
      expect(
        referenced,
        isNotEmpty,
        reason: '没解析到任何"表内引用的词条" ⇒ referenced/cases 的比较退化成空对空',
      );
      expect(
        referenced.difference(cases),
        isEmpty,
        reason: '这些词条被文案表引用却没有 channelLabelFor 的 case',
      );
      expect(
        cases.difference(referenced),
        isEmpty,
        reason: 'channelLabelFor 里留着表内已不引用的死 case',
      );
      for (final key in cases) {
        expect(arbZh.containsKey(key), isTrue, reason: 'ARB(zh) 缺 $key');
        expect(arbEn.containsKey(key), isTrue, reason: 'ARB(en) 缺 $key');
      }
    });

    test('应用通道字段 labelKey 由 ARB 提供（原生不再自带中英双份文案）', () {
      final arb = arbOf('lib/l10n/arb/app_zh.arb');
      for (final d in descriptors.where((d) => d['family'] == 'app')) {
        final fields = (d['fields'] as List<Object?>)
            .cast<Map<Object?, Object?>>();
        expect(fields, isNotEmpty, reason: '${d["key"]} 没有导出字段 schema');
        for (final f in fields) {
          final labelKey = f['labelKey'] as String;
          expect(
            arb.containsKey(labelKey),
            isTrue,
            reason: '${d["key"]}.${f["key"]} 的 $labelKey 不在 ARB',
          );
          // 表单标签真的渲染得出来：漏 case 的表现是输入框显示资源名原文
          expect(
            channelLabelFor(l10n, labelKey),
            isNot(labelKey),
            reason:
                'channelLabelFor 缺 $labelKey 的 case：${d["key"]}.${f["key"]} '
                '输入框会显示「$labelKey」而不是中文标签',
          );
        }
      }
    });
  });

  group('提示文案不得互相借用（roadmap E8）', () {
    test('12 个 webhook 通道各有一句自己的说明，且两两不同', () {
      final slugs = descriptors
          .where((d) => d['family'] == 'webhook')
          .map((d) => d['key'] as String)
          .toList();
      expect(slugs, hasLength(12));

      final seen = <String, String>{};
      for (final slug in slugs) {
        final visual = channelVisual(slug);
        final descKey = visual.descKey;
        expect(descKey, isNotNull, reason: '$slug 没有自己的提示词条（会退回通用占位文案）');
        expect(
          channelLabelFor(l10n, descKey!),
          isNot(descKey),
          reason: '$slug 的 $descKey 在 channelLabelFor 里没有 case',
        );
        final owner = seen[descKey];
        expect(
          owner,
          isNull,
          reason:
              '$slug 借用了 $owner 的说明文字（$descKey）：这正是 E8 那类缺陷 —— '
              '复制别家文案的表现是用户对着自己的平台读到不相干的能力说明',
        );
        seen[descKey] = slug;
      }
    });
  });

  group('URL 自动识别的 host 表两端同一份事实', () {
    test('Dart _platformRules 与描述符 hosts 完全一致', () {
      final dartRules = <String, Set<String>>{
        for (final (type, hosts) in WebhookChannel.platformRules)
          type.value: hosts.toSet(),
      };
      final nativeRules = <String, Set<String>>{
        for (final d in descriptors.where((d) => d['family'] == 'webhook'))
          d['key'] as String: ((d['hosts'] as List<Object?>?) ?? const [])
              .map((e) => e.toString())
              .toSet(),
      };
      // 自建 ntfy / Gotify / generic 的 host 不可枚举 ⇒ 原生侧就是空集，Dart 侧不该有它
      expect(
        dartRules.keys.toSet(),
        nativeRules.entries
            .where((e) => e.value.isNotEmpty)
            .map((e) => e.key)
            .toSet(),
        reason: '可自动识别的平台集合不一致：Dart 少或多出条目',
      );
      for (final entry in dartRules.entries) {
        expect(
          nativeRules[entry.key],
          entry.value,
          reason: '${entry.key} 的 host 规则不一致（显示类型与实发类型会分叉）',
        );
      }
    });
  });

  group('能力位驱动显隐（页面不得再按平台分支）', () {
    test('webhook 两页都没有平台枚举分支与凭据黑名单', () {
      final page = stripComments(
        File('$root/lib/pages/webhook_settings_page.dart').readAsStringSync(),
      );
      final item = stripComments(
        File('$root/lib/pages/webhook_settings_item.dart').readAsStringSync(),
      );
      final list = stripComments(
        File(
          '$root/lib/pages/webhook_channel_list_page.dart',
        ).readAsStringSync(),
      );
      for (final src in [page, item, list]) {
        expect(
          src,
          isNot(contains('case WebhookChannelType.')),
          reason: '又写回 12 臂平台 switch：新增通道时这里会漏',
        );
        expect(
          src,
          isNot(contains('!= WebhookChannelType.')),
          reason: '又写回「排除某几个平台」的黑名单：判据应在原生能力位里',
        );
      }
      expect(
        page,
        contains('_descriptor?.usesSecretField'),
        reason: 'secret 输入框显隐必须走描述符（单通道形态下没有 index，判据仍是同一个）',
      );
      expect(
        page,
        contains('_descriptor?.supportsCustomTemplate'),
        reason: '格式/模板入口显隐必须走描述符',
      );
      // 正面锚点：被禁的那个符号必须**还活着**。整个枚举一旦消失，上面两条
      // 「页面里不许出现 WebhookChannelType 分支」会因为找不到主语而永远为真 ——
      // 那时这条守卫已经谁也不拦了（A 类失效：判据为真 ≠ 有保护）。
      final model = stripComments(
        File('$root/lib/models/webhook_channel.dart').readAsStringSync(),
      );
      expect(
        model,
        contains('enum WebhookChannelType'),
        reason:
            '枚举已不在 lib/models/webhook_channel.dart：请把上面两条禁令一起改掉，'
            '别留一条空转的守卫',
      );
    });

    test('应用通道设置页不得再手抄字段清单', () {
      final page = stripComments(
        File(
          '$root/lib/pages/app_channel_settings_page.dart',
        ).readAsStringSync(),
      );
      for (final key in [
        'corpid',
        'agentid',
        'touser',
        'app_id',
        'receive_id_type',
        'receive_id',
      ]) {
        expect(
          page,
          isNot(contains("'$key'")),
          reason: '字段 key 又硬编码回页面（$key）：表单字段只在原生描述符声明一次',
        );
      }
      expect(
        page,
        contains('ChannelFormRenderer.ensureControllers'),
        reason: '控制器必须由 schema 创建，不是人手抄一遍 key',
      );
    });
  });

  group('消息格式档位只有原生一份（T08-B）', () {
    test('快照里的档位 == TemplateEngine.formatOptions（改了原生不重跑快照就红）', () {
      final kt = stripComments(
        File(
          '$root/android/app/src/main/kotlin/com/fnthink/notice/TemplateEngine.kt',
        ).readAsStringSync(),
      );
      final decl = RegExp(
        r'val formatOptions[^=]*=\s*listOf\(([^)]*)\)',
      ).firstMatch(kt);
      expect(
        decl,
        isNotNull,
        reason: 'TemplateEngine 里找不到 formatOptions 名单：定义被挪走，导出与守卫都会静默失真',
      );
      final native = decl!
          .group(1)!
          .split(',')
          .map((e) => e.trim().replaceAll('"', ''))
          .where((e) => e.isNotEmpty)
          .toList();
      expect(
        exportedMessageFormats(),
        native,
        reason:
            '导出快照与原生名单分叉：Dart widget 测试会对着旧档位跑绿'
            '（重跑 ChannelDescriptorExportTest 生成快照）',
      );
      expect(native, contains('default'), reason: 'default 是"不覆写平台包装"的哨兵档位');
    });

    test('Dart 侧不得再抄一份档位名单，选择器读的是导出值', () {
      final page = stripComments(
        File('$root/lib/pages/webhook_settings_page.dart').readAsStringSync(),
      );
      expect(
        page,
        contains('_descriptors.messageFormats'),
        reason: '档位必须来自描述符服务（第二份名单 = 加档位时漏改的那类缺陷）',
      );
      for (final rel in [
        'lib/pages/webhook_settings_page.dart',
        'lib/pages/webhook_settings_item.dart',
        'lib/models/webhook_channel.dart',
        'lib/services/channel_descriptor_service.dart',
      ]) {
        final src = stripComments(File('$root/$rel').readAsStringSync());
        expect(
          RegExp(r"'default'\s*,\s*'text'").hasMatch(src),
          isFalse,
          reason: '$rel 里出现了手抄的档位名单（Dart 只按导出渲染，标签映射不算）',
        );
        expect(
          src,
          isNot(contains('enum WebhookMessageFormat')),
          reason: '$rel 又把档位做成了 Dart 枚举',
        );
      }
    });
  });

  group('邮件族表单文本两端一致（T08-C）', () {
    final email = descriptors.firstWhere((d) => d['family'] == 'email');
    final emailFields = (email['fields'] as List<Object?>)
        .cast<Map<Object?, Object?>>();

    /// 快照引用到的全部词条资源名（通道名 + 字段标签 + 提示 + 档位名 + 档位正文）
    Set<String> referencedKeys() {
      final keys = <String>{email['labelKey'] as String};
      for (final f in emailFields) {
        keys.add(f['labelKey'] as String);
        final hint = f['hintKey'];
        if (hint != null) keys.add(hint.toString());
        for (final p
            in (f['presets'] as List<Object?>).cast<Map<Object?, Object?>>()) {
          keys.add(p['labelKey'] as String);
          final value = p['valueKey'];
          if (value != null) keys.add(value.toString());
        }
      }
      return keys;
    }

    test('每个资源名都在两份 ARB 里，且解析得出来（不是原样吐回 key）', () {
      final arbZh = arbOf('lib/l10n/arb/app_zh.arb');
      final arbEn = arbOf('lib/l10n/arb/app_en.arb');
      final zh = lookupAppLocalizations(const Locale('zh'));
      final en = lookupAppLocalizations(const Locale('en'));
      final keys = referencedKeys();
      expect(keys, isNotEmpty);
      for (final k in keys) {
        expect(arbZh.containsKey(k), isTrue, reason: 'ARB(zh) 缺词条 $k');
        expect(arbEn.containsKey(k), isTrue, reason: 'ARB(en) 缺词条 $k');
        expect(
          channelFormText(zh, k),
          isNot(k),
          reason:
              '$k 没有登记进 channelFormText / channelLabelFor：'
              '表现是输入框或档位按钮直接显示资源名原文',
        );
        expect(
          channelFormText(en, k),
          isNot(k),
          reason: '$k 在英文环境下解析不出来（英文界面会看到中文键名）',
        );
      }
    });

    test('预置正文只许用邮件模板名单里的变量', () {
      final arbZh = arbOf('lib/l10n/arb/app_zh.arb');
      final arbEn = arbOf('lib/l10n/arb/app_en.arb');
      final allowed = emailTemplateVars.map((v) => v.token).toSet();
      var checked = 0;
      for (final f in emailFields) {
        for (final p
            in (f['presets'] as List<Object?>).cast<Map<Object?, Object?>>()) {
          final valueKey = p['valueKey'];
          // valueKey == null 是显式语义「清空」（交回运行时默认），不是漏登记
          if (valueKey == null) continue;
          checked++;
          for (final arb in {arbZh, arbEn}) {
            final text = arb[valueKey].toString();
            for (final v in RegExp(r'%(\w+)%').allMatches(text)) {
              expect(
                allowed,
                contains(v.group(1)),
                reason:
                    '$valueKey 用了原生不替换的变量 %${v.group(1)}%'
                    '（用户会收到原样留在正文里的占位符）',
              );
            }
          }
        }
      }
      expect(checked, greaterThan(0), reason: '快照里一个预置正文都没有：守卫变空转');
    });

    test('主题档位的「默认」与原生运行时默认同源', () {
      // 芯片写进用户配置的正文，必须等于用户什么都不填时 `EmailSender` 实际发出去的
      // 那一行。两处各写一份的漂移表现是"预览与实发不一致"，而且没人会红。
      final arb = arbOf('lib/l10n/arb/app_zh.arb');
      final sender = stripComments(
        File(
          '$root/android/app/src/main/kotlin/com/fnthink/notice/EmailSender.kt',
        ).readAsStringSync(),
      );
      final native = RegExp(
        r'val DEFAULT_SUBJECT = "([^"]*)"',
      ).firstMatch(sender);
      expect(native, isNotNull, reason: 'EmailSender 里找不到 DEFAULT_SUBJECT');
      final subject = emailFields.firstWhere(
        (f) => f['key'] == 'subjectTemplate',
      );
      final presets = (subject['presets'] as List<Object?>)
          .cast<Map<Object?, Object?>>();
      final defaultPreset = presets.firstWhere(
        (p) => p['labelKey'] == 'presetDefault',
      );
      expect(
        arb[defaultPreset['valueKey']],
        native!.group(1),
        reason:
            '预置档位「默认」的正文与原生运行时默认分叉：'
            '点它和留空会得到两封不一样的邮件',
      );
    });

    test('快照里出现的 kind 都必须有渲染分支', () {
      final kinds = emailFields.map((f) => f['kind'] as String).toSet();
      expect(kinds, containsAll(['number', 'switch', 'secret', 'multiline']));
      for (final k in kinds) {
        expect(
          ChannelFieldSpec.knownKinds,
          contains(k),
          reason:
              'kind=$k 没有渲染分支：会静默降级成普通文本框'
              '（凭据明文显示 / 开关画成输入框 就是这一类）',
        );
      }
    });
  });
}
