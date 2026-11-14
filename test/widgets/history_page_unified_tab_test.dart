import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:notice_transmit/services/fnthink_settings.dart';
import 'package:notice_transmit/pages/fnthink_consent_gate.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/models/fnthink_inbox_message.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/widgets/app_root.dart';

import '../test_setup.dart';

/// HistoryPage 三个 tab 统一选择/搜索/删除功能 widget 测试。
///
/// 钉四件事：
/// ① 幻念收件/发件档都能关键词搜索（内存过滤，不碰数据库）；
/// ② 三个 tab 都能长按进入选择模式（之前发件档不可选）；
/// ③ 批量删除能正确写入各自的数据源（替身记账 + 列表刷新）；
/// ④ 反选/全选/清空在三个 tab 上行为一致。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  stubNativeChannels();

  setUp(() async {
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<NotificationService>(
      NotificationService(),
    );
    SharedPreferences.setMockInitialValues(<String, Object>{
      'fnthink.consent_version': 1,
    });
    debugFnthinkConsentSettingsOverride = FnthinkSettings(
      contract: FnthinkContract.readFile(),
    );
  });
  tearDown(() => debugFnthinkConsentSettingsOverride = null);
  tearDown(() async => GetIt.instance.reset());
  tearDownAll(clearNativeChannelStubs);

  FnthinkInboxMessage inboxRow(
    String mid, {
    String sender = 'endpoint:ep_7',
    String direction = kFnthinkDirectionIn,
    String title = '默认标题',
    String body = '默认正文',
    bool read = false,
    int sentAt = 0,
    int ackedAt = 0,
  }) => FnthinkInboxMessage(
    messageId: mid,
    sender: sender,
    type: 'notice',
    item: '',
    title: title,
    body: body,
    receivedAt: 1780000000000,
    sentAt: sentAt,
    read: read,
    ackResult: ackedAt > 0
        ? 'delivered'
        : (direction == kFnthinkDirectionOut ? '' : 'displayed'),
    ackedAt: ackedAt,
    direction: direction,
  );

  NotificationRecord forwardedRow(
    String rid, {
    String packageName = 'com.test',
    String appName = 'Test',
    String title = '标题',
    String content = '内容',
  }) => NotificationRecord(
    id: rid,
    title: title,
    content: content,
    subText: '',
    packageName: packageName,
    appName: appName,
    type: 'notice',
    postTime: 1780000000000,
    time: '2026-11-14 12:00',
    deviceName: '',
    priority: 1,
    channels: const [],
    deliveryStatus: const {},
  );

  late List<FnthinkInboxMessage> inboxTable;
  late List<FnthinkInboxMessage> sentTable;
  late List<String> deletedInboxIds;
  late List<NotificationRecord> forwardedTable;

  Future<void> pump(
    WidgetTester tester, {
    String initialDirection = 'forwarded',
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: HistoryPage(
          initialDirection: initialDirection,
          reportContract: FnthinkContract.readFile(),
          forwardedLoader: fakeForwardedLoader(forwardedTable),
          forwardedCountLoader: () async => forwardedTable.length,
          onClear: () async {
            forwardedTable.clear();
          },
          onExport: () async => <String, dynamic>{},
          onClearToday: () async => 0,
          onClearLastN: (_) async => 0,
          inboxLoader: () async => List.of(inboxTable),
          sentLoader: () async => List.of(sentTable),
          inboxMarkRead: (id) async {
            final at = inboxTable.indexWhere((m) => m.messageId == id);
            if (at < 0) return false;
            // FnthinkInboxMessage 是 const，没有 copyWith，重新构造一条
            final orig = inboxTable[at];
            inboxTable[at] = FnthinkInboxMessage(
              messageId: orig.messageId,
              sender: orig.sender,
              type: orig.type,
              item: orig.item,
              title: orig.title,
              body: orig.body,
              receivedAt: orig.receivedAt,
              sentAt: orig.sentAt,
              read: true,
              ackResult: orig.ackResult,
              ackedAt: orig.ackedAt,
              direction: orig.direction,
              viaBackup: orig.viaBackup,
              appName: orig.appName,
            );
            return true;
          },
          inboxDeleteMany: (ids) async {
            deletedInboxIds.addAll(ids);
            inboxTable.removeWhere((m) => ids.contains(m.messageId));
            sentTable.removeWhere((m) => ids.contains(m.messageId));
            return ids.length;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(HistoryPage)));

  Future<void> enterSearch(WidgetTester tester, String query) async {
    final field = find.byType(TextField);
    await tester.enterText(field, query);
    // 等防抖 300ms 跑完 + 一帧
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  setUp(() {
    inboxTable = [
      inboxRow('m_in_1', title: '机箱温度 50度'),
      inboxRow('m_in_2', title: 'CPU 使用率'),
      inboxRow('m_in_3', title: '机箱温度 45度'),
    ];
    sentTable = [
      inboxRow('m_out_1',
          direction: kFnthinkDirectionOut,
          title: '远程摄像头',
          body: '拍一张办公室照片'),
      inboxRow('m_out_2',
          direction: kFnthinkDirectionOut,
          title: '关机指令',
          body: '下班后自动关机'),
    ];
    forwardedTable = [
      forwardedRow('f1', title: '微信消息', content: '张三：在吗'),
      forwardedRow('f2', title: '系统更新', content: 'Android 15 推送'),
    ];
    deletedInboxIds = [];
  });

  // ────────────── 搜索功能测试 ──────────────

  group('幻念收件档：关键词搜索（内存过滤）', () {
    testWidgets('输入「温度」⇒ 只剩标题含温度的两条', (tester) async {
      await pump(tester, initialDirection: 'received');
      expect(find.text('机箱温度 50度'), findsOneWidget);
      expect(find.text('CPU 使用率'), findsOneWidget);

      final field = find.byType(TextField);
      debugPrint('BEFORE enterText: ${field.evaluate().length} TextField');
      await tester.enterText(field.first, '温度');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      debugPrint('AFTER enterText: CPU=${find.text('CPU 使用率').evaluate().length}');

      expect(find.text('机箱温度 50度'), findsOneWidget);
      expect(
        find.text('CPU 使用率'),
        findsNothing,
        reason: '不含「温度」的那条应该被过滤掉',
      );
      expect(find.text('机箱温度 45度'), findsOneWidget);
    });

    testWidgets('输入空串 ⇒ 恢复全部（不过滤）', (tester) async {
      await pump(tester, initialDirection: 'received');
      await enterSearch(tester, '温度');
      await enterSearch(tester, '');

      expect(find.text('机箱温度 50度'), findsOneWidget);
      expect(find.text('CPU 使用率'), findsOneWidget);
      expect(find.text('机箱温度 45度'), findsOneWidget);
    });

    testWidgets('输入「CPU」⇒ 只剩那一条（不区分大小写）', (tester) async {
      await pump(tester, initialDirection: 'received');
      await enterSearch(tester, 'cpu');

      expect(find.text('CPU 使用率'), findsOneWidget);
      expect(find.text('机箱温度 50度'), findsNothing);
    });

    testWidgets('搜不到任何匹配 ⇒ 显示空态文案', (tester) async {
      await pump(tester, initialDirection: 'received');
      await enterSearch(tester, '完全不会匹配的词xyz');

      expect(
        find.text(l10n(tester).noMatchRecords),
        findsOneWidget,
      );
    });

    testWidgets('正文也能搜到：搜「拍一张」能命中那条（虽然标题不含）', (
      tester,
    ) async {
      inboxTable = [
        inboxRow('m_body', title: '通知', body: '拍一张办公室照片'),
        inboxRow('m_title', title: '别的', body: '无关正文'),
      ];
      await pump(tester, initialDirection: 'received');
      await enterSearch(tester, '拍一张');

      expect(find.text('通知'), findsOneWidget);
      expect(find.text('别的'), findsNothing);
    });
  });

  group('幻念发件档：关键词搜索（内存过滤）', () {
    testWidgets('输入「摄像头」⇒ 只剩那条含摄像头的', (tester) async {
      await pump(tester, initialDirection: 'sent');
      await enterSearch(tester, '摄像头');

      expect(find.text('远程摄像头'), findsOneWidget);
      expect(find.text('关机指令'), findsNothing);
    });

    testWidgets('发件档空搜索 ⇒ 恢复全部', (tester) async {
      await pump(tester, initialDirection: 'sent');
      await enterSearch(tester, '摄像头');
      await enterSearch(tester, '');

      expect(find.text('远程摄像头'), findsOneWidget);
      expect(find.text('关机指令'), findsOneWidget);
    });

    testWidgets('发件档正文搜索也生效', (tester) async {
      await pump(tester, initialDirection: 'sent');
      await enterSearch(tester, '下班后');

      expect(find.text('关机指令'), findsOneWidget);
      expect(find.text('远程摄像头'), findsNothing);
    });
  });

  // ────────────── 统一选择模式 ──────────────

  group('统一选择模式：长按进入', () {
    testWidgets('幻念发件档长按某条 ⇒ 进入选择模式（之前发件档根本不可选）', (
      tester,
    ) async {
      await pump(tester, initialDirection: 'sent');

      await tester.longPress(
        find.byKey(const ValueKey('fnthink-inbox-row-m_out_1')),
      );
      await tester.pumpAndSettle();

      // AppBar 标题变成「已选 1」
      expect(
        find.text(l10n(tester).batchSelectedCount(1)),
        findsOneWidget,
        reason: '发件档长按也能进入选择模式（之前是空白）',
      );

      // 底部操作栏有取消 + 删除 + 重发（发件档 _canResend=true）
      expect(find.text(l10n(tester).cancel), findsOneWidget);
      expect(find.text(l10n(tester).clearRecords), findsOneWidget);
    });

    testWidgets('幻念收件档长按某条 ⇒ 进入选择模式（回归）', (tester) async {
      await pump(tester, initialDirection: 'received');
      await tester.longPress(
        find.byKey(const ValueKey('fnthink-inbox-row-m_in_1')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(l10n(tester).batchSelectedCount(1)),
        findsOneWidget,
      );
      // 收件档有标已读 + 删除
      expect(find.text(l10n(tester).inboxMarkReadAction), findsOneWidget);
      expect(find.text(l10n(tester).clearRecords), findsOneWidget);
    });
  });

  group('全选 / 反选 在幻念档都工作', () {
    testWidgets('收件档长按后全选 ⇒ 三条都勾上', (tester) async {
      await pump(tester, initialDirection: 'received');
      await tester.longPress(
        find.byKey(const ValueKey('fnthink-inbox-row-m_in_1')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pumpAndSettle();

      expect(
        find.text(l10n(tester).batchSelectedCount(3)),
        findsOneWidget,
      );
    });

    testWidgets('发件档反选 ⇒ 勾上刚才没选的那条', (tester) async {
      await pump(tester, initialDirection: 'sent');
      await tester.longPress(
        find.byKey(const ValueKey('fnthink-inbox-row-m_out_1')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.check_box_outline_blank));
      await tester.pumpAndSettle();

      // 现在应该只勾中 m_out_2（反选了原来的 m_out_1）
      expect(
        find.text(l10n(tester).batchSelectedCount(1)),
        findsOneWidget,
      );
    });
  });

  // ────────────── 批量删除（幻念收件档） ──────────────

  group('批量删除（幻念收件档）', () {
    testWidgets('长按勾选 → 底部删除 → 确认 → 那条消失 + 写口收到 ids', (
      tester,
    ) async {
      await pump(tester, initialDirection: 'received');

      await tester.longPress(
        find.byKey(const ValueKey('fnthink-inbox-row-m_in_1')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n(tester).clearRecords));
      await tester.pumpAndSettle();

      // 确认框
      await tester.tap(find.text(l10n(tester).confirm));
      await tester.pumpAndSettle();

      expect(deletedInboxIds, ['m_in_1']);

      expect(
        find.byKey(const ValueKey('fnthink-inbox-row-m_in_1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('fnthink-inbox-row-m_in_2')),
        findsOneWidget,
      );
    });

    testWidgets('选中多条删除 ⇒ 写口带上全部 ids', (tester) async {
      await pump(tester, initialDirection: 'received');

      await tester.longPress(
        find.byKey(const ValueKey('fnthink-inbox-row-m_in_1')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('fnthink-inbox-row-m_in_2')),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(l10n(tester).batchSelectedCount(2)),
        findsOneWidget,
      );

      await tester.tap(find.text(l10n(tester).clearRecords));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n(tester).confirm));
      await tester.pumpAndSettle();

      expect(
        deletedInboxIds..sort(),
        equals(['m_in_1', 'm_in_2']..sort()),
      );

      // 两条消失，第三条还在
      expect(
        find.byKey(const ValueKey('fnthink-inbox-row-m_in_1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('fnthink-inbox-row-m_in_2')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('fnthink-inbox-row-m_in_3')),
        findsOneWidget,
      );
    });
  });

  // ────────────── 批量删除（幻念发件档） ──────────────

  group('批量删除（幻念发件档）', () {
    testWidgets('发件档长按 + 删除（之前发件档是空白的功能）', (tester) async {
      await pump(tester, initialDirection: 'sent');

      await tester.longPress(
        find.byKey(const ValueKey('fnthink-inbox-row-m_out_1')),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n(tester).clearRecords), findsOneWidget);

      await tester.tap(find.text(l10n(tester).clearRecords));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n(tester).confirm));
      await tester.pumpAndSettle();

      expect(deletedInboxIds, ['m_out_1']);

      expect(
        find.byKey(const ValueKey('fnthink-inbox-row-m_out_1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('fnthink-inbox-row-m_out_2')),
        findsOneWidget,
      );
    });
  });

  // ────────────── 搜索 + 删除组合 ──────────────

  group('搜索与选择/删除联动', () {
    testWidgets('幻念收件档：搜索过滤后全选 → 只删搜索结果里的那些', (tester) async {
      await pump(tester, initialDirection: 'received');

      // 先搜「温度」，只剩两条
      await enterSearch(tester, '温度');
      expect(find.text('机箱温度 50度'), findsOneWidget);
      expect(find.text('CPU 使用率'), findsNothing);

      // 长按一条进入选择模式
      await tester.longPress(find.text('机箱温度 50度'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.select_all));
      await tester.pumpAndSettle();

      // 应该只选了搜索结果里的 2 条（不是全部 3 条）
      expect(
        find.text(l10n(tester).batchSelectedCount(2)),
        findsOneWidget,
      );

      await tester.tap(find.text(l10n(tester).clearRecords));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n(tester).confirm));
      await tester.pumpAndSettle();

      expect(
        deletedInboxIds..sort(),
        equals(['m_in_1', 'm_in_3']..sort()),
      );

      // 搜索词还保留着，所以 CPU 那条虽然还在 inbox 里但被过滤了
      // 清掉搜索再看
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();

      expect(
        find.text('CPU 使用率'),
        findsOneWidget,
        reason: '没在搜索结果里的那条不该被全选一起删掉',
      );
    });
  });

  // ────────────── 选择模式取消 ──────────────

  group('取消选择模式', () {
    testWidgets('点底部「取消」按钮 ⇒ 退出选择模式，底部操作栏消失', (tester) async {
      await pump(tester, initialDirection: 'sent');

      await tester.longPress(
        find.byKey(const ValueKey('fnthink-inbox-row-m_out_1')),
      );
      await tester.pumpAndSettle();

      expect(find.text(l10n(tester).batchSelectedCount(1)), findsOneWidget);

      await tester.tap(find.text(l10n(tester).cancel));
      await tester.pumpAndSettle();

      // 退出后 AppBar 标题不再显示「已选 N」
      expect(
        find.text(l10n(tester).batchSelectedCount(1)),
        findsNothing,
      );
      // 选择模式底部栏应该消失
      expect(find.text(l10n(tester).clearRecords), findsNothing);
    });

    testWidgets('点 AppBar 左上关闭图标 ⇒ 同样退出选择模式', (tester) async {
      await pump(tester, initialDirection: 'received');

      await tester.longPress(
        find.byKey(const ValueKey('fnthink-inbox-row-m_in_1')),
      );
      await tester.pumpAndSettle();

      // 左上应该有个 close 图标
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(
        find.text(l10n(tester).batchSelectedCount(1)),
        findsNothing,
      );
    });
  });
}
