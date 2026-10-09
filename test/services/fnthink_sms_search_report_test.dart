import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_sms_search_report.dart';

/// 短信搜索结果那段正文的组装（T124 片B 的 `sms:search`）。
///
/// 四条口径与通知回传那一份同源（空表回一句、不静默截断、预算明写、只带该带的），
/// 外加这一族独有的两条：**空表那句要带关键词**（对面要能分辨"搜了没有"与"没搜"）、
/// **只带时间／号码／正文三件**（`_id`、线程、槽位都不进）。
void main() {
  Map<String, Object?> row({
    String address = '10086',
    String body = '验证码 123456',
    int dateMillis = 0,
  }) => {'address': address, 'body': body, 'dateMillis': dateMillis};

  test('一条都没命中 ⇒ 回一句**带关键词**的明说，绝不是空串', () {
    final text = formatFnthinkSmsSearchReport('验证码', const []);
    expect(text, contains('验证码'), reason: '不带词的"没有"，对面分不清是搜过还是没搜');
    expect(text, isNotEmpty);
  });

  test('一条 ⇒ 「时间 号码 正文」', () {
    final millis = DateTime(2026, 7, 12, 9, 31).millisecondsSinceEpoch;
    expect(
      formatFnthinkSmsSearchReport('验证码', [row(dateMillis: millis)]),
      '07-12 09:31 10086 验证码 123456',
    );
  });

  test('缺时间或号码 ⇒ 少哪段少哪段，不补占位符', () {
    expect(formatFnthinkSmsSearchReport('x', [row(address: '')]), '验证码 123456');
  });

  test('正文超长 ⇒ 明写省略号（截在哪看得见）', () {
    final long = 'y' * 300;
    final text = formatFnthinkSmsSearchReport('y', [row(body: long)]);
    expect(text, contains('…'));
    expect(text, contains('y' * kFnthinkSmsReportContentCap));
    expect(text, isNot(contains('y' * (kFnthinkSmsReportContentCap + 1))));
  });

  test('超预算 ⇒ 明写「另有 N 条未包含」，第一条无论如何在里面', () {
    final rows = List.generate(40, (_) => row(body: 'z' * 120));
    final lines = formatFnthinkSmsSearchReport('z', rows).split('\n');
    expect(lines.first, contains('z'));
    expect(lines.last, matches(RegExp(r'^（另有 \d+ 条因体积上限未包含）$')));
    final dropped = int.parse(
      RegExp(r'另有 (\d+) 条').firstMatch(lines.last)!.group(1)!,
    );
    expect(lines.length - 1 + dropped, 40);
  });

  test('只带三件：命中的行里别的字段一个字都不进', () {
    final text = formatFnthinkSmsSearchReport('x', [
      {
        'address': '10086',
        'body': '验证码 123456',
        'dateMillis': 0,
        'thread_id': '42',
        'subscription_id': '1',
      },
    ]);
    expect(text, '10086 验证码 123456', reason: '多带一个字段（线程 id／槽位）都是一次新的对外披露面');
  });
}
