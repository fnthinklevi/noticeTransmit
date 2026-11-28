import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T221：全站界面文案由口语转书面，一页一批推进。
///
/// 这本台账是「哪些页已经复核过」的唯一清单：
/// - 48 页缺一行、页文件不存在、状态写错，测试就红；
/// - 标成 `reviewed` 的页必须在 `test/fixtures/t221_reviewed_copy.json`
///   留下逐 key 的中英期望值，实际 ARB 与清单不一致也红。
///
/// 新增页面不在 T221 范围内；以后真的新增页面时，要同时补台账并说明。
/// 词条数单独钉住：本任务只改值，不新增/删除 key。
void main() {
  final root = projectRoot();
  final zh = jsonDecode(
    File('$root/lib/l10n/arb/app_zh.arb').readAsStringSync(),
  ) as Map<String, dynamic>;
  final en = jsonDecode(
    File('$root/lib/l10n/arb/app_en.arb').readAsStringSync(),
  ) as Map<String, dynamic>;
  final reviewed = jsonDecode(
    File('$root/test/fixtures/t221_reviewed_copy.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  Set<String> keys(Map<String, dynamic> arb) =>
      arb.keys.where((k) => !k.startsWith('@')).toSet();

  const coverage = <String, String>{
    'lib/pages/history_page.dart': 'pending',
    'lib/pages/fnthink_send_page.dart': 'reviewed',
    'lib/pages/rule_edit_page.dart': 'pending',
    'lib/pages/fnthink_peers_page.dart': 'reviewed',
    'lib/pages/remote_credential_settings_page.dart': 'reviewed',
    'lib/pages/battery_page.dart': 'pending',
    'lib/pages/permission_settings_page.dart': 'pending',
    'lib/pages/temperature_page.dart': 'pending',
    'lib/pages/rule_tester_page.dart': 'pending',
    'lib/pages/device_snapshot_page.dart': 'pending',
    'lib/pages/channel_status_page.dart': 'reviewed',
    'lib/pages/fnthink_endpoint_page.dart': 'reviewed',
    'lib/pages/rule_list_page.dart': 'pending',
    'lib/pages/app_channel_settings_page.dart': 'reviewed',
    'lib/pages/device_state_page.dart': 'pending',
    'lib/pages/fnthink_channel_settings_page.dart': 'reviewed',
    'lib/pages/fnthink_read_caps_page.dart': 'reviewed',
    'lib/pages/app_filter_page.dart': 'pending',
    'lib/pages/fnthink_channel_list_page.dart': 'reviewed',
    'lib/pages/fnthink_settings_page.dart': 'reviewed',
    'lib/pages/more_page.dart': 'pending',
    'lib/pages/remote_trigger_filter_page.dart': 'pending',
    'lib/pages/email_settings_page.dart': 'reviewed',
    'lib/pages/main_page.dart': 'pending',
    'lib/pages/notification_engine_page.dart': 'pending',
    'lib/pages/app_channel_list_page.dart': 'pending',
    'lib/pages/fnthink_shortcuts_page.dart': 'reviewed',
    'lib/pages/notification_page.dart': 'pending',
    'lib/pages/remote_history_page.dart': 'pending',
    'lib/pages/rule_edit_widgets.dart': 'pending',
    'lib/pages/webhook_channel_list_page.dart': 'pending',
    'lib/pages/main_page_dialogs.dart': 'reviewed',
    'lib/pages/privacy_policy_page.dart': 'reviewed',
    'lib/pages/sms_monitor_settings_page.dart': 'pending',
    'lib/pages/fnthink_receive_page.dart': 'reviewed',
    'lib/pages/fnthink_remote_page.dart': 'pending',
    'lib/pages/keywords_page.dart': 'pending',
    'lib/pages/webhook_settings_item.dart': 'pending',
    'lib/pages/widget_guide_page.dart': 'reviewed',
    'lib/pages/fnthink_peer_detail_page.dart': 'reviewed',
    'lib/pages/update_server_page.dart': 'pending',
    'lib/pages/backup_restore_page.dart': 'pending',
    'lib/pages/main_page_actions.dart': 'pending',
    'lib/pages/main_page_update.dart': 'pending',
    'lib/pages/stats_page.dart': 'pending',
    'lib/pages/fnthink_consent_gate.dart': 'reviewed',
    'lib/pages/splash_page.dart': 'reviewed',
    'lib/pages/webhook_settings_page.dart': 'pending',
  };

  test('T221 覆盖台账 48 页齐全，状态与复核清单互相对得上', () {
    expect(coverage.length, 48);
    expect(coverage.keys.toSet().length, 48, reason: '台账里同一页只许出现一次');
    for (final entry in coverage.entries) {
      expect(
        File('$root/${entry.key}').existsSync(),
        isTrue,
        reason: '台账里的页面不存在：${entry.key}',
      );
      expect(
        const ['pending', 'reviewed'].contains(entry.value),
        isTrue,
        reason: '状态只许是 pending / reviewed：${entry.key}',
      );
    }

    final reviewedPages = reviewed.keys.toSet();
    for (final page in reviewedPages) {
      expect(coverage[page], 'reviewed', reason: '有复核清单却没在台账里标 reviewed：$page');
    }
    for (final entry in coverage.entries) {
      if (entry.value != 'reviewed') continue;
      expect(
        reviewedPages.contains(entry.key),
        isTrue,
        reason: '台账标了 reviewed，却没有逐 key 复核清单：${entry.key}',
      );
    }
  });

  test('T221 已复核页的每条中英文都与复核清单一致', () {
    for (final page in reviewed.keys) {
      final entries = reviewed[page] as Map<String, dynamic>;
      expect(entries, isNotEmpty, reason: '已复核页的清单不能为空：$page');
      for (final entry in entries.entries) {
        final key = entry.key;
        final expected = entry.value as Map<String, dynamic>;
        expect(zh[key], expected['zh'], reason: '中文值被改回口语或与清单不一致：$key');
        expect(en[key], expected['en'], reason: '英文值被改回口语或与清单不一致：$key');
      }
    }
  });

  test('T221 期间词条数不变，中英键集仍相等', () {
    expect(keys(zh).length, 1776, reason: '本任务只改值，不新增/删除词条');
    expect(keys(en).length, 1776);
    expect(keys(zh).difference(keys(en)), isEmpty);
    expect(keys(en).difference(keys(zh)), isEmpty);
  });
}
