import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:notice_transmit/update_manager.dart';
import 'package:notice_transmit/widgets/app_root.dart';
import 'package:notice_transmit/widgets/update_dialog_body.dart';

/// T169：发现新版本弹层的内容。
///
/// 首屏是**摘要**，不是整篇日志；展开与收起都必须真的换内容，而不是把全文塞在屏幕外
/// （那就等于没改：用户看到的仍是一堵字墙）。
void main() {
  VersionCheckResult result(String changelog) => VersionCheckResult(
    hasUpdate: true,
    latestVersion: '2.0.0',
    latestBuild: 200,
    forceUpdate: false,
    changelog: changelog,
    downloadUrl: 'https://example.com/app.apk',
    fileSize: 123456,
    minSupportedVersion: '1.0.0',
  );

  Future<void> pumpBody(
    WidgetTester tester, {
    required String changelog,
  }) async {
    await tester.pumpWidget(
      AppRoot(
        locale: const Locale('zh'),
        dark: false,
        home: CupertinoPageScaffold(
          child: SingleChildScrollView(
            child: UpdateDialogBody(
              result: result(changelog),
              currentVersion: '1.0.0',
              changelog: changelog,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('首屏只画前 4 行摘要，全文不出现', (tester) async {
    await pumpBody(tester, changelog: '第一行\n第二行\n第三行\n第四行\n第五行\n第六行');

    expect(
      find.byKey(const ValueKey('update-changelog-summary')),
      findsOneWidget,
    );
    expect(find.text('第一行'), findsOneWidget);
    expect(find.text('第四行'), findsOneWidget);
    expect(find.textContaining('第五行'), findsNothing);
    expect(find.byKey(const ValueKey('update-changelog-full')), findsNothing);
  });

  testWidgets('展开后显示全文，收起后回到摘要', (tester) async {
    await pumpBody(tester, changelog: '第一行\n第二行\n第三行\n第四行\n第五行\n第六行');

    await tester.tap(find.byKey(const ValueKey('update-changelog-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('update-changelog-full')), findsOneWidget);
    expect(find.textContaining('第六行'), findsOneWidget);
    expect(find.text('收起'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('update-changelog-summary')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('update-changelog-toggle')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('update-changelog-summary')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('update-changelog-full')), findsNothing);
  });

  testWidgets('四行以内不画展开入口（没有更多内容可看）', (tester) async {
    await pumpBody(tester, changelog: '第一行\n第二行');
    expect(find.byKey(const ValueKey('update-changelog-toggle')), findsNothing);
    expect(find.text('第一行'), findsOneWidget);
    expect(find.text('第二行'), findsOneWidget);
  });
}
