import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_location_report.dart';

/// 「读最近一次定位」那段正文的组装（T124 片C-2 的 `location:get`）。
///
/// 钉四件：
///  ① 六位小数 + 精度 + 来源 + 时间都在（六个小数位是这一份的口径，不靠读的人四舍五入）；
///  ② **方位中立**：不带中文（这段正文组装在被查那台上、读的人在另一台 —— 与通话记录的
///     ↙／↗ 同一理由）；
///  ③ 缺失不编：精度缺/来源缺/时间缺，各格各自空着（不写"刚刚"这类猜出来的话）；
///  ④ 连坐标都没有 ⇒ 回空串（调用方读成"没成"，不拿空话冒充读数）。
void main() {
  group('定位回传正文', () {
    test('六位小数 + 精度 + 来源 + 时间都在', () {
      final text = formatFnthinkLocationReport({
        'lat': 31.2304161,
        'lon': 121.4737014,
        'accuracyMeters': 25.0,
        'provider': 'gps',
        'timeMillis': 1752205200000,
      });
      expect(text, startsWith('31.230416,121.473701'));
      expect(text, contains('±25m'));
      expect(text, contains('gps'));
      // 时间那一格：MM-DD HH:mm（与另两份报告同形）
      expect(RegExp(r'\d{2}-\d{2} \d{2}:\d{2}').hasMatch(text), isTrue);
    });

    test('六位小数是**四舍五入后写死的**（读的人不用自己再舍一次）', () {
      final text = formatFnthinkLocationReport({'lat': 1.23456789, 'lon': 2.0});
      expect(text, '1.234568,2.000000');
    });

    test('方位中立：这段正文里一个汉字都不带', () {
      final text = formatFnthinkLocationReport({
        'lat': 1.0,
        'lon': 2.0,
        'accuracyMeters': 3.0,
        'provider': 'network',
        'timeMillis': 1752205200000,
      });
      expect(RegExp(r'[\u4e00-\u9fff]').hasMatch(text), isFalse);
    });

    test('缺失不编：精度/来源/时间缺了就各自空着', () {
      final text = formatFnthinkLocationReport({'lat': 1.5, 'lon': 2.5});
      expect(text, '1.500000,2.500000');
    });

    test('连坐标都没有 ⇒ 空串（调用方读成没成，不许拿空话冒充）', () {
      expect(formatFnthinkLocationReport(const {}), '');
      expect(formatFnthinkLocationReport(const {'accuracyMeters': 5.0}), '');
      // 只有一半更糟：报了半个坐标比"没有"更容易被读成一条真读数
      expect(formatFnthinkLocationReport(const {'lat': 1.0}), '');
      expect(formatFnthinkLocationReport(const {'lon': 2.0}), '');
    });

    test('精度非正/来源超长：前者不带那格，后者截断', () {
      final text = formatFnthinkLocationReport({
        'lat': 1.0,
        'lon': 2.0,
        'accuracyMeters': 0.0,
        'provider': 'a' * 40,
      });
      expect(text, isNot(contains('±')));
      expect(text, contains('${'a' * 16}…'));
    });
  });
}
