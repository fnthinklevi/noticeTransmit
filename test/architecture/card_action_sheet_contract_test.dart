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
      'lib/pages/webhook_channel_list_page.dart': 'webhook 通道行（T07-B 起也在列表页）',
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
      // 菜单本体在一页，手势必须真的挂在行上 —— 两族通道页都是列表行的 onLongPress
      for (final rel in const [
        'lib/pages/app_channel_list_page.dart',
        'lib/pages/webhook_channel_list_page.dart',
      ]) {
        expect(
          read(rel),
          contains('onLongPress: () => _showChannelActions(index)'),
          reason: '$rel 的行上没有长按手势了 ⇒ 菜单成了永远打不开的代码',
        );
      }
    });

    test('每一处「复制」都不带原条目的历史归属', () {
      const copiers = [
        'lib/pages/app_channel_list_page.dart',
        'lib/pages/webhook_channel_list_page.dart',
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
        if (!_givesFreshIdentity(blockAfter(src, decl.group(0)!))) {
          offenders.add(rel);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            '复制出来的那条必须"没有过去"：当场换新 id。'
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

    test('动作只能在弹层下场后执行，不得在弹层自己的 onTap 里调', () {
      // T07-B 的形状决定：ListTile 只把选中的 CardAction 作为 pop 结果带出去，
      // 由 show() await 到路由 popped 之后再调用。理由见组件里的注释（两层模态交叉退场
      // 会在真机上留下吞手势的屏障）。这条守卫钉的就是"别再改回原地调"。
      final code = read('lib/widgets/card_action_sheet.dart');
      expect(
        code,
        contains('Navigator.pop(context, action)'),
        reason: '弹层项必须把动作作为路由结果带出去，而不是自己执行',
      );
      expect(
        code,
        contains('picked?.onTap?.call()'),
        reason: '执行点必须收在 show() 里（await 到 popped 之后）',
      );
      expect(
        code,
        isNot(contains('action.onTap!()')),
        reason: '又在弹层内部原地执行动作 = 恢复成与确认框交叉退场的那个形状',
      );
    });
  });
}

/// 复制出来的那条必须"没有过去"：当场换新 id。
/// （T07-B 之前还有第二种合法写法"不带 id 交给保存路径发号"，那是 webhook 并行列表的
/// 产物；页面不再握整表快照之后，那种写法等于"复制出来的那条没有 id"，直接写不进库。）
bool _givesFreshIdentity(String block) =>
    block.contains('DateTime.now().millisecondsSinceEpoch');
