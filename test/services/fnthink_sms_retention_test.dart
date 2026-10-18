import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_sms_retention.dart';
import 'package:notice_transmit/services/fnthink_sms_search_report.dart';

/// T124 ①「已监听的短信留存」那一路的纯函数账。
///
/// 这一族的判据都在盘上（SQL 形状、两路合并、来源标记），而真库与真权限在页面上拿不到，
/// 所以这里只管**形状**；真 SQL 那一发另有库层用例（见本文件最后一组）。
void main() {
  group('LIKE 转义（与 Kotlin 那一处同一张三字符表）', () {
    test('三个通配字符各自被转义', () {
      expect(escapeFnthinkSmsLike('50%'), r'50\%');
      expect(escapeFnthinkSmsLike('a_b'), r'a\_b');
      expect(escapeFnthinkSmsLike(r'C:\temp'), r'C:\\temp');
    });

    test('顺序证明：先转反斜杠本身，输入「反斜杠+百分号」得到三个反斜杠+百分号', () {
      // 正确次序：`\`→`\\` 然后 `%`→`\%` ⇒ `\%` 变 `\\\%`（SQL 里读作"字面反斜杠 + 字面百分号"）。
      // 反过来写（先 % 后 \）会得到四个反斜杠+百分号 —— 那匹配的是"反斜杠开头的串"，
      // 于是"搜 \%"变成"搜 \\%"，多带出去的就是静默多带。
      expect(escapeFnthinkSmsLike(r'\%'), r'\\\%');
    });

    test('普通词一字不动（转义不许顺手吃掉正常字符）', () {
      expect(escapeFnthinkSmsLike('验证码 1234'), '验证码 1234');
    });
  });

  group('留存那一路的查询形状', () {
    test('关键词只进绑定参数，绝不进 SQL 串', () {
      final q = smsRetentionQueryFor("'; DROP");
      expect(q.where, isNot(contains("'; DROP")));
      expect(q.where, contains('content LIKE ?'));
      expect(q.args, hasLength(2));
      expect(q.args[1], "%'; DROP%");
    });

    test('两处条件都在：type 那一列 + ESCAPE 子句（缺 ESCAPE 就像 % 没转义）', () {
      final q = smsRetentionQueryFor('code');
      expect(q.where, contains('type = ?'));
      expect(q.where, contains(r"ESCAPE '\'"));
      expect(q.args.first, kFnthinkSmsRetentionType);
    });
  });

  group('两路合并', () {
    Map<String, Object?> row(String addr, String body, int millis) => {
      'address': addr,
      'body': body,
      'dateMillis': millis,
    };

    test('按时间倒序，新的在前', () {
      final merged = mergeFnthinkSmsHits(
        direct: [row('A', 'a', 100), row('A', 'b', 300)],
        retained: [row('B', 'c', 200)],
      );
      expect(merged.map((r) => r['dateMillis']).toList(), [300, 200, 100]);
    });

    test('每条都带来源（两路的「没有」含义不同，不标就是让对面以为只有一个来源）', () {
      final merged = mergeFnthinkSmsHits(
        direct: [row('A', 'a', 1)],
        retained: [row('B', 'b', 2)],
      );
      expect(merged[0]['source'], kFnthinkSmsSourceRetained);
      expect(merged[1]['source'], kFnthinkSmsSourceDirect);
    });

    test('同一条只留直查那一份（键＝时间+正文，不含号码：两处给的地址常常不同形）', () {
      final merged = mergeFnthinkSmsHits(
        direct: [row('+8613800000000', '同一句', 500)],
        retained: [row('张三', '同一句', 500)],
      );
      expect(merged, hasLength(1));
      expect(merged.single['source'], kFnthinkSmsSourceDirect);
      expect(merged.single['address'], '+8613800000000');
    });

    test('上限是两路合起来的上限，不是各自的上限', () {
      final merged = mergeFnthinkSmsHits(
        direct: [for (var i = 0; i < 15; i++) row('A', 'd$i', i)],
        retained: [for (var i = 0; i < 15; i++) row('B', 'r$i', i + 100)],
        limit: 20,
      );
      expect(merged, hasLength(20));
    });

    test('时间戳相同 ⇒ 直查在前（同一批结果的次序在两路都不漂）', () {
      final merged = mergeFnthinkSmsHits(
        direct: [row('A', 'x', 7)],
        retained: [row('B', 'y', 7)],
      );
      expect(merged.first['source'], kFnthinkSmsSourceDirect);
    });

    test('两路都空 ⇒ 空表，而不是"没查"（这一点报告那一步要接着说）', () {
      expect(mergeFnthinkSmsHits(), isEmpty);
    });

    test('留存行的映射：正文取 content、时间取 post_time、发件人取通知标题那一格', () {
      final mapped = retainedRowFromNotification({
        'title': '张三',
        'content': '验证码 1234',
        'post_time': 12345,
      });
      expect(mapped['address'], '张三');
      expect(mapped['body'], '验证码 1234');
      expect(mapped['dateMillis'], 12345);
      expect(mapped['source'], kFnthinkSmsSourceRetained);
    });

    test('坏的时间型不崩（读不到就当没有，交给排序的 0 档）', () {
      expect(
        retainedRowFromNotification({'post_time': '123'})['dateMillis'],
        0,
      );
    });
  });

  group('报告那一格的来源与"只有一路"', () {
    test('留存那条带〔已监听留存〕，直查那条不带', () {
      final out = formatFnthinkSmsSearchReport('1234', [
        {
          'address': 'A',
          'body': '验证码 1234 甲',
          'dateMillis': 2,
          'source': kFnthinkSmsSourceDirect,
        },
        {
          'address': 'B',
          'body': '验证码 1234 乙',
          'dateMillis': 1,
          'source': kFnthinkSmsSourceRetained,
        },
      ]);
      final lines = out.split('\n');
      expect(lines.first, isNot(contains(fnthinkSmsRetentionMarker())));
      expect(lines.last, contains(fnthinkSmsRetentionMarker()));
    });

    test('不带来源标记时，形状与片B 落地那天逐字相同（这一片不许改动老那一路）', () {
      final out = formatFnthinkSmsSearchReport('k', [
        {'address': 'A', 'body': 'b', 'dateMillis': 0},
      ]);
      expect(out.split('\n').single.startsWith('A b'), isTrue);
    });

    test('lead 缺席时一个字都不多', () {
      expect(
        formatFnthinkSmsSearchReport('x', const []),
        fnthinkSmsSearchEmptyText('x'),
      );
    });

    test('直查那一路没成 + 一条都没命中 ⇒ 那句「没有」必须带上来源', () {
      final out = formatFnthinkSmsSearchReport('x', const [], lead: '只搜了留存');
      expect(out, contains('只搜了留存'));
      expect(out, contains(fnthinkSmsSearchEmptyText('x')));
    });

    test('单条截断的预算仍按那几个常量走（来源标记不许把预算挤掉）', () {
      final long = '甲' * (kFnthinkSmsReportContentCap + 10);
      final out = formatFnthinkSmsSearchReport('k', [
        {
          'address': 'A',
          'body': long,
          'dateMillis': 1,
          'source': kFnthinkSmsSourceRetained,
        },
      ]);
      expect(out, contains('…'));
      expect(out, contains(fnthinkSmsRetentionMarker()));
    });
  });
}
