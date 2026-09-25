import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T05 共用组件的接入契约（源码级）。
///
/// 组件自身行为见 `test/widgets/card_action_sheet_test.dart`；这里守的是**接入面**：
/// 六个入口是否都还挂着长按菜单、每一处"复制"是否都换新 id、组件有没有被写成第二份真值。
void main() {
  final root = projectRoot();

  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  group('卡片长按菜单的接入面（T05）', () {
    const entries = {
      'lib/pages/app_channel_list_page.dart': '自建应用通道卡（T07 起在列表页）',
      // webhook 的菜单在库文件里，卡片只是挂上长按手势（part 文件）
      'lib/pages/webhook_settings_page.dart': 'webhook 通道行',
      'lib/pages/email_settings_page.dart': '邮件通道卡',
      'lib/pages/battery_page.dart': '电量规则卡',
      'lib/pages/temperature_page.dart': '温度规则卡',
      'lib/pages/history_page.dart': '历史记录卡',
    };

    test('六个入口都还经共用的 CardActionSheet', () {
      for (final entry in entries.entries) {
        expect(
          read(entry.key),
          contains('CardActionSheet.show('),
          reason: '${entry.value} 不再挂长按菜单 ⇒ 该入口静默退出 T05 的覆盖面',
        );
      }
      // 手势挂在卡片上（在 part 文件里），菜单本体在库文件里：两边都得在
      expect(
        read('lib/pages/webhook_settings_item.dart'),
        contains('onLongPress: () => _showRowActions(index)'),
        reason: 'webhook 行上没有长按手势了 ⇒ 菜单成了永远打不开的代码',
      );
    });

    test('每一处「复制」都不带原条目的历史归属', () {
      const copiers = [
        'lib/pages/app_channel_list_page.dart',
        'lib/pages/webhook_settings_page.dart',
        'lib/pages/email_settings_page.dart',
        'lib/pages/battery_page.dart',
        'lib/pages/temperature_page.dart',
      ];
      final offenders = <String>[];
      for (final rel in copiers) {
        final src = read(rel);
        // 锚在**声明**上（`void` / `Future<void>` 前缀），不是光秃秃的函数名：
        // 长按菜单里的 `onTap: () => _duplicateChannel(index)` 出现在声明之前，
        // 用函数名当锚会截到调用点那一块，守卫就变成"看运气"。
        final decl = RegExp(
          '(?:Future<void>|void)\\s+_duplicate\\w*\\(',
        ).firstMatch(src);
        if (decl == null) {
          offenders.add('$rel（找不到 _duplicate* 声明）');
          continue;
        }
        // 两种合法写法：当场 mint 新 id；或**留空**让保存路径发号
        // （webhook 是并行列表，id 由 `_saveAndBack` 生成）
        if (!_givesFreshIdentity(blockAfter(src, decl.group(0)!))) {
          offenders.add(rel);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            '复制出来的那条必须"没有过去"：当场换新 id，或不带 id 交给保存路径发号。'
            '沿用原 id 会让两条互相顶掉健康徽标与送达归属，'
            '规则页的 updateRule/deleteRule 还会一次改中两条：$offenders',
      );
    });

    test('组件保持纯 UI：不碰 MethodChannel、不写死中文', () {
      final code = read('lib/widgets/card_action_sheet.dart');
      expect(code, isNot(contains('invokeMethod')));
      expect(
        RegExp(r"'[^']*[\u4e00-\u9fff][^']*'").hasMatch(code),
        isFalse,
        reason: '弹层里的文字一律由调用方传 l10n —— 组件自己写中文就没有英文可言',
      );
    });
  });
}

/// 复制出来的那条必须"没有过去"：要么当场换新 id，要么根本不带 id（保存时再发号）。
bool _givesFreshIdentity(String block) =>
    block.contains('DateTime.now().millisecondsSinceEpoch') ||
    block.contains('add(null)');
