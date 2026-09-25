import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T06：**删除一律二次确认**，而且确认必须写在"执行删除的那个函数"里。
///
/// 为什么不写在调用点：调用点会增加。这一批就是活例子 —— 长按菜单是 T05 新加的，
/// 它复用了卡片上那个"点一下就删"的入口；如果确认写在卡片按钮的 onTap 里，菜单这条
/// 新路径必然静默绕过。咽喉放在执行处，新增入口就只是多一个调用者。
///
/// 同一批还收掉了确认框本身的抄本：`IosDialogActions.confirm` 只给 actions，
/// 于是标题/圆角/按钮顺序在八处各写一遍，措辞还会分叉（电量页两份确认框，一份点名
/// 规则、一份只说"这条规则"）。删除类一律走 [IosDialogActions] 的 `askConfirm`。
void main() {
  final root = projectRoot();

  String read(String rel) =>
      stripComments(File('$root/$rel').readAsStringSync());

  const chokes = {
    'lib/pages/webhook_settings_page.dart': 'Future<void> _removeWebhookField(',
    'lib/pages/app_channel_settings_page.dart': 'Future<void> _removeChannel(',
    'lib/pages/email_settings_page.dart': 'Future<void> _deleteChannel(',
    'lib/pages/battery_page.dart': 'Future<void> _confirmDeleteRule(',
    'lib/pages/temperature_page.dart': 'Future<void> _confirmDeleteRule(',
    'lib/pages/rule_list_page.dart': 'Future<void> _deleteRule(',
    'lib/pages/keywords_page.dart': 'Future<void> _removeKeyword(',
  };

  group('删除的二次确认只有一个咽喉（T06）', () {
    test('每条删除路径的执行处都 askConfirm', () {
      for (final entry in chokes.entries) {
        final body = blockAfter(read(entry.key), entry.value);
        expect(
          body,
          contains('askConfirm('),
          reason: '${entry.key} :: ${entry.value} 不再确认 ⇒ 手滑即丢凭据/规则',
        );
      }
    });

    test('每个页面恰好一个咽喉，且不再手搭确认框', () {
      for (final rel in chokes.keys) {
        final src = read(rel);
        expect(
          'askConfirm('.allMatches(src).length,
          1,
          reason: '$rel 的 askConfirm 数量变了 ⇒ 要么漏了一条路径，要么又开了一份抄本',
        );
        expect(
          'showDialog<bool>'.allMatches(src).length,
          0,
          reason: '$rel 又自己搭确认框了（形状抄第二份，措辞就会开始分叉）',
        );
      }
    });

    test('真正改掉数据的那一句只出现在咽喉里', () {
      const mutators = {
        'lib/pages/webhook_settings_page.dart': '_webhookControllers.removeAt(',
        'lib/pages/app_channel_settings_page.dart': '_channels.removeAt(',
        'lib/pages/email_settings_page.dart': '_channels.removeAt(',
        'lib/pages/battery_page.dart': '_service.deleteRule(',
        'lib/pages/temperature_page.dart': '_service.deleteRule(',
        'lib/pages/rule_list_page.dart': '_rules.removeWhere(',
        'lib/pages/keywords_page.dart': '_blacklist.remove(',
      };
      for (final entry in mutators.entries) {
        expect(
          entry.value.allMatches(read(entry.key)).length,
          1,
          reason: '${entry.key} 里 `${entry.value}` 出现多次 ⇒ 有第二条绕过确认的删除路径',
        );
      }
    });

    test('自建应用删通道时释放它自己的控制器', () {
      final src = read('lib/pages/app_channel_settings_page.dart');
      final body = blockAfter(src, 'Future<void> _removeChannel(');
      expect(
        body,
        contains('_releaseControllers('),
        reason: '只删 _channels 那一条会让整批控制器留在 map 里（页面关闭前不回收）',
      );
      expect(
        blockAfter(src, 'void _releaseControllers('),
        contains('.dispose()'),
        reason: '释放必须真的 dispose，只是从 map 里移除等于换地方漏',
      );
    });

    test('删通道连带清健康记录（徽标不能靠 id 复用复活）', () {
      for (final entry in {
        'lib/pages/webhook_settings_page.dart': 'webhook',
        'lib/pages/app_channel_settings_page.dart': 'app',
        'lib/pages/email_settings_page.dart': 'email',
      }.entries) {
        final body = blockAfter(read(entry.key), chokes[entry.key]!);
        expect(
          body,
          contains("_health.remove('${entry.value}'"),
          reason: '${entry.key} 的删除没清健康缓存：id 复用（从旧备份恢复）时徽标会复活',
        );
      }
    });
  });
}
