import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/notification_rule.dart';
import 'package:notice_transmit/services/rule_template_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 规则模板库单元测试（P2）。
///
/// 覆盖：预设模板合法性、用户模板持久化（同名覆盖/删除）、导入实例化（新 id/默认启用）、
/// 导出导入往返（明文 + 口令加密两种格式）、异常路径（无效文件/口令错误/缺口令）。
/// 加密口令一律使用测试假口令字面量。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late RuleTemplateService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    // MethodChannel 不应被模板库触发；挂空 handler 防意外出网
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.fnthink.notice/notification'),
          (call) async {
            return null;
          },
        );
    service = RuleTemplateService();
  });

  NotificationRule sampleRule({String name = '我的规则', int priority = 60}) {
    return NotificationRule(
      id: 'rule_src_1',
      name: name,
      description: '测试用规则描述',
      enabled: true,
      priority: priority,
      conditions: [
        Condition(id: 'c1', type: ConditionType.titleContains, value: '告警'),
        Condition(
          id: 'c2',
          type: ConditionType.contentContains,
          value: '磁盘',
          logic: LogicOperator.or,
        ),
      ],
      actions: [
        RuleAction(
          id: 'a1',
          type: ActionType.merge,
          params: {'delaySeconds': 30, 'maxItems': 3},
        ),
      ],
    );
  }

  group('RuleTemplateService – 预设模板', () {
    test('内置 5 套预设，条件/动作/优先级齐备且 id 不重复', () {
      final presets = RuleTemplateService.presetTemplates();
      expect(presets.length, 5);
      expect(presets.map((t) => t.id).toSet().length, 5);
      for (final t in presets) {
        expect(t.name, isNotEmpty);
        expect(t.conditions, isNotEmpty, reason: '${t.name} 应有条件');
        expect(t.actions, isNotEmpty, reason: '${t.name} 应有动作');
      }
    });

    test('社交消息聚合模板携带 merge 参数（60 秒窗口 + 满 5 条提前）', () {
      final merge = RuleTemplateService.presetTemplates().firstWhere(
        (t) => t.actions.any((a) => a.type == ActionType.merge),
      );
      final params = merge.actions.first.params;
      expect(params['delaySeconds'], 60);
      expect(params['maxItems'], 5);
    });

    test('夜间免打扰模板为 time_range 条件 + silent 动作', () {
      final dnd = RuleTemplateService.presetTemplates().firstWhere(
        (t) => t.conditions.any((c) => c.type == ConditionType.timeRange),
      );
      expect(dnd.conditions.single.value, '22:00-07:00');
      expect(dnd.actions.single.type, ActionType.silent);
    });
  });

  group('RuleTemplateService – 用户模板持久化', () {
    test('存为模板后可读回，字段逐项一致', () async {
      await service.saveUserTemplate(sampleRule());
      final templates = await service.getUserTemplates();
      expect(templates.length, 1);
      expect(templates.first.name, '我的规则');
      expect(templates.first.priority, 60);
      expect(templates.first.conditions.length, 2);
      expect(templates.first.actions.first.type, ActionType.merge);
    });

    test('同名存为模板覆盖旧版本（不重复堆积）', () async {
      await service.saveUserTemplate(sampleRule(priority: 10));
      await service.saveUserTemplate(sampleRule(priority: 99));
      final templates = await service.getUserTemplates();
      expect(templates.length, 1);
      expect(templates.first.priority, 99);
    });

    test('deleteUserTemplate 移除指定模板', () async {
      await service.saveUserTemplate(sampleRule());
      final saved = (await service.getUserTemplates()).single;
      await service.deleteUserTemplate(saved.id);
      expect(await service.getUserTemplates(), isEmpty);
    });
  });

  group('RuleTemplateService – 导入实例化', () {
    test('instantiate 生成全新 id、默认启用，条件/动作完整拷贝', () {
      final template = sampleRule();
      final instances = service.instantiate([template, template]);

      expect(instances.length, 2);
      // 两条实例 id 互不相同、也不与模板 id 相同
      expect(instances[0].id != instances[1].id, isTrue);
      expect(instances[0].id, isNot(template.id));
      for (final inst in instances) {
        expect(inst.enabled, isTrue, reason: '导入的模板应默认启用');
        expect(inst.conditions.length, template.conditions.length);
        expect(inst.actions.length, template.actions.length);
      }
    });
  });

  group('RuleTemplateService – 导出导入往返', () {
    test('明文导出 → 导入：模板逐字段一致', () async {
      await service.saveUserTemplate(sampleRule());
      final templates = await service.getUserTemplates();
      final content = await service.buildExportContent(templates, null);

      final data = jsonDecode(content) as Map<String, dynamic>;
      expect(data['format'], RuleTemplateService.formatPlain);

      final imported = await service.parseImportContent(content, null);
      expect(imported.length, 1);
      expect(imported.first.name, '我的规则');
      expect(imported.first.conditions.length, 2);
      expect(imported.first.actions.first.type, ActionType.merge);
    });

    test('口令加密导出 → 正确口令导入往返一致', () async {
      await service.saveUserTemplate(sampleRule());
      final templates = await service.getUserTemplates();
      final content = await service.buildExportContent(
        templates,
        'test-pass-123',
      );

      final data = jsonDecode(content) as Map<String, dynamic>;
      expect(data['format'], RuleTemplateService.formatEncrypted);
      expect(data['ciphertext'], isNotNull);

      final imported = await service.parseImportContent(
        content,
        'test-pass-123',
      );
      expect(imported.single.name, '我的规则');
    });

    test('加密文件缺口令 → 抛 TemplatePasswordRequired', () async {
      await service.saveUserTemplate(sampleRule());
      final content = await service.buildExportContent(
        await service.getUserTemplates(),
        'test-pass-123',
      );
      expect(
        () => service.parseImportContent(content, null),
        throwsA(isA<TemplatePasswordRequired>()),
      );
    });

    test('错误口令 → 抛 TemplateDecryptException（不泄露内容）', () async {
      await service.saveUserTemplate(sampleRule());
      final content = await service.buildExportContent(
        await service.getUserTemplates(),
        'test-pass-123',
      );
      expect(
        () => service.parseImportContent(content, 'wrong-password'),
        throwsA(isA<TemplateDecryptException>()),
      );
    });

    test('无效文件 / 未知格式 → 抛 FormatException', () async {
      expect(
        () => service.parseImportContent('not json at all', null),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => service.parseImportContent('{"format":"other"}', null),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => service.parseImportContent('[]', null),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
