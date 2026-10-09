import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/notification_record.dart';
import 'package:notice_transmit/services/fnthink_notification_report.dart';

/// 回传正文的组装（T124 片B，`notifications:report`）。
///
/// 钉四件（每一件都对应一种"对面会误读"的形状）：
///  ① 空表回**一句**而不是空串（空串在执行链那边是失败，两者不许同形）；
///  ② 单条超长**明写**省略号（不静默截断）；
///  ③ 整段超预算**明写**"另有 N 条未包含"；
///  ④ 只带时间/应用/标题/正文四件 —— 设备名、包名、送达状态一个都不许进。
void main() {
  NotificationRecord rec({
    String title = '标题',
    String content = '正文',
    String appName = '微信',
    String time = '07-12 09:31',
    int postTime = 0,
    String packageName = 'com.tencent.mm',
    String deviceName = '我的手机',
  }) => NotificationRecord(
    id: 'n1',
    title: title,
    content: content,
    subText: '',
    packageName: packageName,
    appName: appName,
    type: 'normal',
    postTime: postTime,
    time: time,
    deviceName: deviceName,
    priority: 2,
    channels: const ['chan:x'],
    deliveryStatus: const {
      'chan:x': {'status': 'failed', 'message': 'boom'},
    },
  );

  test('一条都没有 ⇒ 回一句明说，绝不是空串', () {
    final text = formatFnthinkNotificationReport(const []);
    expect(text, kFnthinkReportEmptyText);
    expect(text, isNotEmpty, reason: '空串在执行链那边是"没做成"，两者不许同形');
  });

  test('一条 ⇒ 「时间 应用 标题：正文」', () {
    expect(formatFnthinkNotificationReport([rec()]), '07-12 09:31 微信 标题：正文');
  });

  test('标题或正文为空 ⇒ 少哪段少哪段，不补占位符', () {
    expect(
      formatFnthinkNotificationReport([rec(title: '')]),
      '07-12 09:31 微信 正文',
    );
    expect(
      formatFnthinkNotificationReport([rec(content: '')]),
      '07-12 09:31 微信 标题',
    );
  });

  test('应用名缺 ⇒ 退包名（那是它唯一还认得出自己的名字）', () {
    expect(
      formatFnthinkNotificationReport([
        rec(appName: '', packageName: 'com.tencent.mm'),
      ]),
      '07-12 09:31 com.tencent.mm 标题：正文',
    );
  });

  test('time 空着 ⇒ 按 postTime 现算（本机时区），不为空', () {
    final millis = DateTime(2026, 7, 12, 9, 31).millisecondsSinceEpoch;
    expect(
      formatFnthinkNotificationReport([rec(time: '', postTime: millis)]),
      '07-12 09:31 微信 标题：正文',
    );
  });

  test('单条超长 ⇒ 明写省略号（截在哪看得见）', () {
    final long = 'x' * 300;
    final text = formatFnthinkNotificationReport([rec(content: long)]);
    expect(text, contains('…'), reason: '静默截断正是这一族最不该有的形状');
    expect(text, contains('x' * kFnthinkReportContentCap));
    expect(text, isNot(contains('x' * (kFnthinkReportContentCap + 1))));
  });

  test('超预算 ⇒ 明写「另有 N 条未包含」，且第一条无论如何在里面', () {
    final rows = List.generate(40, (i) => rec(content: 'y' * 120));
    final lines = formatFnthinkNotificationReport(rows).split('\n');
    expect(lines.first, contains('y'), reason: '第一条被预算挤掉 = "这台空的"');
    expect(
      lines.last,
      matches(RegExp(r'^（另有 \d+ 条因体积上限未包含）$')),
      reason: '少的那些必须明写条数（不静默丢）',
    );
    final dropped = int.parse(
      RegExp(r'另有 (\d+) 条').firstMatch(lines.last)!.group(1)!,
    );
    expect(dropped, greaterThan(0));
    expect(lines.length - 1 + dropped, 40, reason: '在里面的 + 明写未包含的，正好是全部');
  });

  test('只带四件：设备名／包名／送达状态一个字都不进', () {
    final text = formatFnthinkNotificationReport([rec()]);
    expect(text, isNot(contains('我的手机')));
    expect(text, isNot(contains('com.tencent.mm')));
    expect(text, isNot(contains('failed')));
    expect(text, isNot(contains('chan:')));
  });
}
