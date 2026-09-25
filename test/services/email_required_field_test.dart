import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/pages/email_settings_page.dart';

import '../support/source_guards.dart';

/// T03（邮件侧）：必填判定与"点名"的契约。
///
/// 弹窗里的表单不适合起一个 widget 测试台架（要 DB + 服务 +  secure storage），
/// 所以把**规则**抽成纯函数 [missingEmailRequiredFields] 直接测；再补一条源码级
/// 守卫钉住"每个必填键都有本地化标签"—— 漏一个标签，提示里就会露出
/// `to`/`username` 这种裸键名，正是 T03 要消灭的东西。
void main() {
  Map<String, String> filled() => const {
    'name': '主邮箱',
    'host': 'smtp.example.com',
    'port': '465',
    'username': 'u@example.com',
    'password': 'auth-code',
    'from': 'u@example.com',
    'to': 'to@example.com',
  };

  group('missingEmailRequiredFields', () {
    test('全空 → 按表单顺序点名全部必填项', () {
      expect(missingEmailRequiredFields({}), kEmailRequiredKeys);
    });

    test('填满则无缺失；纯空白串仍算缺失', () {
      expect(missingEmailRequiredFields(filled()), isEmpty);
      expect(
        missingEmailRequiredFields({...filled(), 'host': '   '}),
        ['host'],
        reason: '只敲了空格 = 没填（存进去会让原生把它当无配置跳过，用户以为配好了）',
      );
    });

    test('端口必须是正整数（空 / 0 / 负数 / 非数字都算没填）', () {
      for (final bad in ['', '0', '-1', 'abc', '465.0']) {
        expect(
          missingEmailRequiredFields({...filled(), 'port': bad}),
          contains('port'),
          reason: '端口 "$bad" 不该被当成有效值',
        );
      }
      expect(
        missingEmailRequiredFields({...filled(), 'port': ' 465 '}),
        isEmpty,
        reason: '两侧空白要 trim 掉再判（粘贴常见）',
      );
    });

    test('授权码"留空 = 沿用旧值"这条规则本身要能测（编辑场景不回显明文）', () {
      expect(
        effectiveEmailPassword(typed: '', existingPassword: 'old-code'),
        'old-code',
        reason: '留空必须解成旧值，否则保存会把已有授权码洗掉',
      );
      expect(
        effectiveEmailPassword(typed: 'new', existingPassword: 'old-code'),
        'new',
      );
      expect(
        effectiveEmailPassword(typed: '   ', existingPassword: null),
        isEmpty,
        reason: '新建场景没有旧值可沿用 ⇒ 空就是缺失',
      );
      expect(
        missingEmailRequiredFields({
          ...filled(),
          'password': effectiveEmailPassword(
            typed: '',
            existingPassword: 'old-code',
          ),
        }),
        isEmpty,
      );
      expect(
        missingEmailRequiredFields({...filled(), 'password': ''}),
        contains('password'),
      );
    });
  });

  group('点名用的标签必须齐全', () {
    final src = stripComments(
      File(
        '${projectRoot()}/lib/pages/email_settings_page.dart',
      ).readAsStringSync(),
    );

    test('每个必填键都有本地化标签分支', () {
      for (final key in kEmailRequiredKeys) {
        expect(
          src,
          contains("'$key' => l10n."),
          reason: '必填键 $key 没有标签分支 ⇒ 保存失败的提示里会露出裸键名「$key」',
        );
      }
    });

    test('标签分支不得超出必填清单（加了标签却忘了加校验）', () {
      final labeled = RegExp(
        r"'([a-z]+)' => l10n\.",
      ).allMatches(src).map((m) => m.group(1)!).toSet();
      final stray = labeled.difference(kEmailRequiredKeys.toSet()).toList()
        ..sort();
      expect(stray, isEmpty, reason: '这些键有标签但不在必填清单里（校验永远不会报它）：$stray');
    });

    test('保存失败的提示必须用点名版（不许退回"请填写所有必填项"）', () {
      expect(
        src,
        contains('l10n.fillRequiredFieldsNamed('),
        reason: '不点名就等于让用户在 7 个输入框里自己找漏了哪个',
      );
      expect(
        src,
        isNot(contains('Text(l10n.fillRequiredFields)')),
        reason: '点名版已经存在，再留一条不点名的文案就有两条路可走（迟早有人用回旧的）',
      );
    });
  });
}
