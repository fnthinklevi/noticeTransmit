import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/l10n/app_localizations.dart';
import 'package:notice_transmit/pages/notification_page.dart';
import 'package:notice_transmit/theme/app_colors.dart';

/// T01：首页「当前推送通道」这张卡的渲染契约。
///
/// 判据本身在 `test/services/active_channels_health_test.dart`（三族同判据、时效、格式）。
/// 这里只管页面拿得到三态、且不会因为新格式而画坏：
/// 1. `unknown` 有第三种颜色与文案 —— 二态时代它会掉进"异常"的红，等于假警报；
/// 2. 「类型：子类型/通道名」比旧格式长，窄屏必须截断而不是 RenderFlex 溢出；
/// 3. 没配通道时仍是原来的空态文案（这条是回归网，别让它被格式化改出新行为）。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget page(
    List<Map<String, String>> channels, {
    bool running = true,
    VoidCallback? onOpenChannelStatus,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('zh'),
      home: NotificationPage(
        notificationPermissionGranted: true,
        foregroundServiceRunning: running,
        notificationCount: 3,
        activeChannels: channels,
        onStartService: () {},
        onStopService: () {},
        onRefresh: () async {},
        onOpenHistory: () {},
        onOpenPermissionSettings: () {},
        onOpenChannelStatus: onOpenChannelStatus ?? () {},
        onToggleSmsMonitor: (_) {},
        onOpenSmsMonitorSettings: () {},
      ),
    );
  }

  /// 只取通道行那三枚 8×8 状态点：页面上还有别的圆形 Container（180×180 的服务
  /// 启停按钮），不按尺寸筛就会错位一位 —— 把绿点读成第一条通道的状态。
  Color dotColor(WidgetTester t, int index) {
    final dots = t
        .widgetList<Container>(
          find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.constraints?.maxWidth == 8 &&
                w.constraints?.maxHeight == 8 &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).shape == BoxShape.circle,
          ),
        )
        .toList();
    final box = dots[index].decoration as BoxDecoration;
    return box.color!;
  }

  testWidgets('三态各自成色：正常绿、异常红、未知灰（未知不是假警报）', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      page(const [
        {'label': 'Webhook：钉钉/告警群', 'status': 'ok'},
        {'label': '自建应用：企业微信应用/办公', 'status': 'error'},
        {'label': '邮件：主邮箱', 'status': 'unknown'},
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('状态正常'), findsOneWidget);
    expect(find.text('状态异常'), findsOneWidget);
    expect(find.text('状态未知'), findsOneWidget, reason: '没有新鲜探测结果时既不能报正常也不能报异常');
    expect(dotColor(tester, 0), AppColors.green);
    expect(dotColor(tester, 1), AppColors.red);
    expect(dotColor(tester, 2), isNot(AppColors.green));
    expect(dotColor(tester, 2), isNot(AppColors.red));
  });

  testWidgets('窄屏长标签只截断不溢出（RenderFlex 溢出在 debug 里就是异常）', (tester) async {
    tester.view.physicalSize = const Size(360, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      page(const [
        {'label': 'Webhook：通用 Webhook/一个非常非常长的通道名称用来把这一行撑爆', 'status': 'ok'},
      ]),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final label = tester.widget<Text>(find.textContaining('一个非常非常长的通道名称'));
    expect(label.overflow, TextOverflow.ellipsis);
  });

  testWidgets('没配通道时仍是空态文案', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(page(const []));
    await tester.pumpAndSettle();

    expect(find.text('未配置推送通道'), findsOneWidget);
    expect(find.text('状态未知'), findsNothing);
  });

  testWidgets('通道卡常驻且可点 → 通道状态页（T10 的入口）', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var opened = 0;

    // 故意用 running: false —— 这张卡以前只在监听运行时渲染，闸门 5.9 因此忽红忽绿：
    // 第 1 节刚把服务关掉，入口就不在树上了。常驻是这次的有意改动，必须钉住。
    await tester.pumpWidget(
      page(
        const [
          {'label': 'Webhook：钉钉/告警群', 'status': 'ok'},
        ],
        running: false,
        onOpenChannelStatus: () => opened++,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('当前推送通道'), findsOneWidget, reason: '服务停着时通道卡应当仍在');
    await tester.tap(find.text('当前推送通道'));
    await tester.pumpAndSettle();
    expect(opened, 1, reason: '首页那张卡点不进状态页 = T10 的入口没了');
  });
}
