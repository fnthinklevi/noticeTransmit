import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/pages/history_page.dart';
import 'package:notice_transmit/services/notification_service.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/primary_action_button.dart';

/// T148 片7：筛选面板那一双「一实一虚」的形状证据（页面级）。
///
/// 钉的是"那两枚 key 挂在公共件上、标签还是那两枚词条"，不钉配色与圆角
/// （那些归件自己管 —— 归页面管的那一份就是这一族迟早与页脚那一对不一样的来路）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<NotificationService>(
      NotificationService(),
    );
  });
  tearDown(() async => GetIt.instance.reset());

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    Future<(List<NotificationRecord>, bool, int)> loader({
      String? keyword,
      int? startTime,
      int? endTime,
      String? appName,
      String? packageName,
      String? deliveryFilter,
      required int limit,
      required int offset,
    }) async {
      return (const <NotificationRecord>[], false, 0);
    }

    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: HistoryPage(
          forwardedLoader: loader,
          forwardedCountLoader: () async => 0,
          onClear: () async {},
          onExport: () async => <String, dynamic>{},
          onClearToday: () async => 0,
          onClearLastN: (_) async => 0,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('筛选面板那一双走页脚那一对同一形状（实心＋描边）', (tester) async {
    await pumpPage(tester);
    // ⚠ 先在这一页上解一次 l10n：弹层起来之后 HistoryPage 成了 offstage，
    //   `find.byType` 默认不看 offstage ⇒ 在这儿取会抛 No element（不是页面坏了）。
    final l10n = AppLocalizations.of(tester.element(find.byType(HistoryPage)));
    await tester.tap(find.byTooltip(l10n.filterTitle));
    await tester.pumpAndSettle();

    // ⚠ 那两枚件的 key 住的地方不一样：`PrimaryActionButton` 收 `super.key`（挂在件自己身上），
    //   而 `SecondaryActionButton` 收 `keyName` 参数、它把那枚 ValueKey 摆在**内部的 CupertinoButton**
    //   上（为的是"按 key 点"直接命中可点那一层）。⇒ 描边那枚判"键在件里面"，实心那枚判"键就是件"。
    expect(
      find.descendant(
        of: find.byType(SecondaryActionButton),
        matching: find.byKey(const ValueKey('history-filter-reset')),
      ),
      findsOneWidget,
      reason: '「重置」那枚可点位置不在描边件里面 ⇒ 这一对虚的那枚又回到页面自搭',
    );
    final secondary = tester.widgetList<SecondaryActionButton>(
      find.byType(SecondaryActionButton),
    );
    expect(secondary, hasLength(1));
    expect(secondary.single.label, l10n.filterReset);
    expect(
      tester
          .widget<PrimaryActionButton>(
            find.byKey(const ValueKey('history-filter-apply')),
          )
          .label,
      l10n.filterApply,
      reason: '「应用」不在实心那一枚件上 ⇒ 圆角/内边距/禁用态长出第二份写法',
    );
    expect(
      find.bySubtype<ElevatedButton>(),
      findsNothing,
      reason: '那一格里还留着 Material 的 ElevatedButton ⇒ 公共件没换上',
    );
  });
}
