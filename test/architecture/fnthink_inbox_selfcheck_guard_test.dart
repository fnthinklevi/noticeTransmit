import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// T173：收件通知自检的接线。
///
/// 三件事都能静默失效：
///  ① 重建渠道**必须换新 id**（原 id 上的 importance 程序改不动）；
///  ② 显示那一发必须用**当前** id，不能还取常量；
///  ③ 页面四个动作各接各的原生方法，不能只画按钮。
void main() {
  String read(String rel) => File(rel).readAsStringSync();

  test('重建渠道换新 id，并让显示走当前 id', () {
    final native = read(
      'android/app/src/main/kotlin/com/fnthink/notice/FnthinkInboxDisplay.kt',
    );
    expect(native, contains('fnthink_inbox_v\${System.currentTimeMillis()}'));
    expect(native, contains('currentChannelId(context)'));
    expect(native, contains('createHighChannel(manager, id)'));
    final handler = read(
      'android/app/src/main/kotlin/com/fnthink/notice/channels/FnthinkChannelHandler.kt',
    );
    expect(handler, contains('FnthinkInboxDisplay.currentChannelId(context)'));
    for (final method in const [
      'fnthinkInboxChannelState',
      'fnthinkInboxChannelRebuild',
      'fnthinkInboxShowTest',
    ]) {
      expect(handler, contains(method), reason: '$method 没接上');
    }
  });

  test('页面四个动作与状态行都在', () {
    final page = read('lib/pages/fnthink_receive_page.dart');
    for (final key in const [
      "'fnthink-inbox-selfcheck-state'",
      "'fnthink-inbox-selfcheck-refresh'",
      "'fnthink-inbox-selfcheck-settings'",
      "'fnthink-inbox-selfcheck-rebuild'",
      "'fnthink-inbox-selfcheck-test'",
    ]) {
      expect(page, contains(key), reason: '$key 那一格不见了');
    }
    expect(page, contains('fnthinkInboxChannelIssues('));
  });
}
