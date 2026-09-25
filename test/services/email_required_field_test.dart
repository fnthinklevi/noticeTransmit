import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/email_channel.dart';
import 'package:notice_transmit/pages/email_settings_page.dart';
import 'package:notice_transmit/services/channel_descriptor_service.dart';
import 'package:notice_transmit/widgets/channel_form_renderer.dart';

import '../support/channel_descriptor_fixtures.dart';
import '../support/source_guards.dart';

/// T03（邮件侧）的必填契约 + T08-C2 之后的**判据来源**契约。
///
/// 规则本体仍是纯函数（弹窗台架要 DB + 服务 + secure storage，不值得为校验起一套），
/// 但清单、类型、默认值、"留空算不算缺失"现在都由**导出快照里的那条 email 描述符**决定：
/// 测试读的就是原生发的那份，所以"原生改了表、Dart 判定还停在旧清单"这种分叉会立刻红。
void main() {
  final descriptor = ChannelDescriptor.fromMap(
    exportedDescriptors().firstWhere((d) => d['family'] == 'email'),
  );
  final l10n = lookupAppLocalizations(const Locale('zh'));

  List<String> requiredKeys() =>
      descriptor.fields.where((f) => f.required).map((f) => f.key).toList();

  Map<String, bool> switches({bool useSsl = true}) => {
    for (final f in descriptor.fields)
      if (f.isSwitch) f.key: useSsl,
  };

  Map<String, String> effective(
    Map<String, String> typed, {
    String? existingPassword,
    ChannelDescriptor? descriptorOverride,
  }) => emailEffectiveValues(
    descriptor: descriptorOverride ?? descriptor,
    typed: typed,
    switches: switches(),
    existingPassword: existingPassword,
  );

  Map<String, String> fullForm() => {
    'smtpHost': 'smtp.example.com',
    'smtpPort': '465',
    'username': 'u@example.com',
    'password': 'auth-code',
    'fromEmail': 'u@example.com',
    'toEmail': 'to@example.com',
    'subjectTemplate': '',
    'bodyTemplate': '',
  };

  List<String> missing(
    Map<String, String> values, {
    bool nameMissing = false,
    ChannelDescriptor? descriptorOverride,
  }) => missingEmailRequiredFields(
    descriptor: descriptorOverride ?? descriptor,
    effective: values,
    nameMissing: nameMissing,
  );

  group('必填清单来自描述符', () {
    test('六个连接必填项 + 顺序 = 表单顺序（点名顺序与输入顺序一致）', () {
      expect(requiredKeys(), [
        'smtpHost',
        'smtpPort',
        'username',
        'password',
        'fromEmail',
        'toEmail',
      ]);
      // 端口不在其中：它有 defaultValue ⇒ 空值的意思是"采用默认"，不是"没填"
      expect(
        missing(effective({})),
        requiredKeys().where((k) => k != 'smtpPort').toList(),
        reason: '全空 ⇒ 按表单顺序逐项点名，不是一句"请填写所有必填项"',
      );
      expect(
        requiredKeys(),
        contains('smtpPort'),
        reason: '端口在表里确实是必填项，只是"必填 + 有默认值"的组合下空值不算缺失',
      );
    });

    test('name 是本页自有字段，缺失时排在最前（表单第一项就是它）', () {
      expect(missing(effective(fullForm()), nameMissing: true), ['name']);
    });

    test('填满则无缺失；只敲空格算没填', () {
      expect(missing(effective(fullForm())), isEmpty);
      expect(
        missing(effective({...fullForm(), 'smtpHost': '   '})),
        ['smtpHost'],
        reason: '存进空 host 会让原生当这条没配好而跳过，用户以为配完了',
      );
    });

    test('模板类字段非必填（留空 = 用运行时默认主题/正文）', () {
      expect(
        requiredKeys(),
        isNot(contains('subjectTemplate')),
        reason: '主题/正文留空是常态，不是错误',
      );
      expect(requiredKeys(), isNot(contains('bodyTemplate')));
    });
  });

  group('kind 决定的规则', () {
    test('端口：非正整数点名（0 / 负数 / 非数字 / 小数）', () {
      for (final bad in ['0', '-1', 'abc', '465.0']) {
        expect(
          missing(effective({...fullForm(), 'smtpPort': bad})),
          contains('smtpPort'),
          reason: '端口 "$bad" 不该被当成有效值',
        );
      }
    });

    test('端口：两侧空白 trim 后再判', () {
      expect(
        missing(effective({...fullForm(), 'smtpPort': ' 465 '})),
        isEmpty,
        reason: '粘贴带空格是常态',
      );
    });

    test('端口：留空落描述符的默认值 ⇒ 不算缺失（T08-C2 的语义变化）', () {
      // 旧版把空端口直接判成"没填"；现在默认值在表里（smtpPort.defaultValue），
      // 空 = 采用默认，与表单预填一致。少这一句说明，下次有人会以为这是漏做。
      final values = effective({...fullForm(), 'smtpPort': ''});
      expect(values['smtpPort'], '465');
      expect(missing(values), isEmpty);
    });

    test('开关字段的生效值来自开关，不是输入框文本', () {
      final values = emailEffectiveValues(
        descriptor: descriptor,
        typed: fullForm(),
        switches: {'useSSL': false},
      );
      expect(values['useSSL'], 'false');
      expect(
        descriptor.fields.firstWhere((f) => f.key == 'useSSL').isSwitch,
        isTrue,
      );
    });
  });

  group('授权码：留空 = 沿用旧值，但只有能力位这么说才这样', () {
    test('有 secretKeepsPrevious ⇒ 空输入解成旧值', () {
      expect(
        effective({
          ...fullForm(),
          'password': '  ',
        }, existingPassword: 'old-code')['password'],
        'old-code',
      );
      expect(
        missing(
          effective({
            ...fullForm(),
            'password': '',
          }, existingPassword: 'old-code'),
        ),
        isEmpty,
        reason: '编辑时不回显明文，留空必须解成旧值，否则保存把已有授权码洗掉',
      );
    });

    test('有该能力位但新建（没有旧值）⇒ 仍然算缺失', () {
      expect(
        missing(effective({...fullForm(), 'password': ''})),
        contains('password'),
      );
    });

    test('能力位摘掉 ⇒ 空输入就是空（不许页面按族自己决定"留空算不改"）', () {
      final withoutKeeps = ChannelDescriptor(
        family: descriptor.family,
        key: descriptor.key,
        labelKey: descriptor.labelKey,
        iconKey: descriptor.iconKey,
        capabilities: descriptor.capabilities.difference({
          'secretKeepsPrevious',
        }).toSet(),
        fields: descriptor.fields,
        hosts: descriptor.hosts,
        textLimitChars: descriptor.textLimitChars,
        officialBase: descriptor.officialBase,
      );
      expect(
        withoutKeeps.secretKeepsPrevious,
        isFalse,
        reason: '前提：这份"反例描述符"确实没有该能力位',
      );
      expect(
        effective(
          {...fullForm(), 'password': ''},
          existingPassword: 'old-code',
          descriptorOverride: withoutKeeps,
        )['password'],
        isEmpty,
      );
    });
  });

  group('点名要叫得出名字', () {
    test('每个必填键都有译文（既不是裸键名，也不是 ARB 资源名原文）', () {
      for (final f in descriptor.fields) {
        final label = channelFormText(l10n, f.labelKey);
        expect(label, isNot(f.labelKey), reason: '${f.labelKey} 没登记，提示里会露资源名');
        expect(label, isNot(f.key), reason: '${f.key} 的标签解析成了裸键名');
        if (f.hintKey != null) {
          expect(
            channelFormText(l10n, f.hintKey!),
            isNot(f.hintKey!),
            reason: '${f.key} 的提示词条没登记',
          );
        }
      }
    });

    test('模型兜底默认值必须等于描述符默认值（否则界面显示 A、发信用 B）', () {
      expect(
        EmailChannel.defaultSmtpPort.toString(),
        descriptor.fields.firstWhere((f) => f.key == 'smtpPort').defaultValue,
      );
      expect(
        EmailChannel.defaultUseSsl.toString(),
        descriptor.fields.firstWhere((f) => f.key == 'useSSL').defaultValue,
      );
    });
  });

  group('页面不得再抄一份表单事实', () {
    final src = stripComments(
      File(
        '${projectRoot()}/lib/pages/email_settings_page.dart',
      ).readAsStringSync(),
    );

    test('必填清单与键→标签映射已从页面消失（事实只在描述符里）', () {
      expect(
        src,
        isNot(contains('kEmailRequiredKeys')),
        reason: '又抄了一份必填清单：新增字段时会漏改其中一处',
      );
      expect(src, isNot(contains('String labelOf(')), reason: '又抄了一份键→标签映射');
      expect(
        src,
        isNot(contains("'smtp.qq.com'")),
        reason: '提示用的示例主机名回归 ARB（hintKey）',
      );
      expect(
        src,
        isNot(contains("'your@email.com'")),
        reason: '同上：示例地址是文案，不是页面常量',
      );
    });

    test('字段控件由描述符驱动', () {
      expect(src, contains('descriptor.fields'), reason: '表单不再遍历描述符');
      expect(src, contains('channelFormText('), reason: '标签/提示不再硬编码');
      expect(
        src,
        contains('l10n.fillRequiredFieldsNamed('),
        reason: '不许退回"请填写所有必填项"',
      );
      expect(
        src,
        isNot(contains('Text(l10n.fillRequiredFields)')),
        reason: '不点名的文案已被点名版取代，留着就有第二条路可走',
      );
    });

    test('弹层的 controller 必须释放（T06 收口时漏了这一页）', () {
      expect(
        src,
        contains('c.dispose()'),
        reason: '每次开合弹窗泄漏 9 个 TextEditingController',
      );
    });
  });
}
