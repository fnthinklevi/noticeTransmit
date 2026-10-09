import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_call_log_report.dart';

/// 「按关键词搜通话记录」那段正文的组装（T124 片C 的 `calls:search`）。
///
/// 钉四件（与短信那一份同源：同一条消息预算、同一条不静默丢的纪律）：
///  ① 一条都没命中也要回一句（带那个词）—— 空表不是失败；
///  ② 命中行只带四件：时间／方向／对方／时长；
///  ③ 未接（时长 0）不冒出 `(0s)`；认不出的类型**不猜方向**；
///  ④ 单条超长打省略号、整段放不下**明写**「另有 N 条未包含」。
void main() {
  Map<String, Object?> row({
    String? name,
    String? number,
    int type = 1,
    int dateMillis = 0,
    int durationMillis = 0,
  }) => {
    'name': name,
    'number': number,
    'type': type,
    'dateMillis': dateMillis,
    'durationMillis': durationMillis,
  };

  const stamp = 1752205200000; // 2025-07-11 09:00（本机时区）附近，只钉"有值"不钉具体钟点

  group('通话记录回传正文', () {
    test('一条都没命中 ⇒ 回一句带那个词的（不是空串，也不是失败）', () {
      final text = formatFnthinkCallLogReport('10086', const []);
      expect(text, contains('10086'));
      expect(text, contains('没有'));
    });

    test('命中 ⇒ 时间/方向/对方/时长都在；来电那一条是 ↙', () {
      final text = formatFnthinkCallLogReport('10086', [
        row(
          name: '老妈',
          number: '10086',
          type: 1,
          dateMillis: stamp,
          durationMillis: 65000,
        ),
      ]);
      expect(text, contains('↙'));
      expect(text, contains('老妈'));
      expect(text, contains('10086'));
      expect(text, contains('(1m05s)'));
    });

    test('去电 ↗、未接 ✗；未接那一条**不冒出** (0s)', () {
      final text = formatFnthinkCallLogReport('x', [
        row(number: '10086', type: 2, dateMillis: stamp, durationMillis: 12000),
        row(number: '10010', type: 3, dateMillis: stamp),
      ]);
      final lines = text.split('\n');
      expect(lines[0], contains('↗'));
      expect(lines[0], contains('(12s)'));
      expect(lines[1], contains('✗'));
      expect(lines[1], isNot(contains('(0s)')));
    });

    test('认不出的类型不猜方向（那一格空着，而不是随手画一个）', () {
      final text = formatFnthinkCallLogReport('x', [
        row(number: '10086', type: 99, dateMillis: stamp),
      ]);
      expect(text, contains('10086'));
      for (final glyph in ['↙', '↗', '✗', '⊗']) {
        expect(text, isNot(contains(glyph)));
      }
    });

    test('单条超长打省略号；整段放不下 ⇒ 明写「另有 N 条」', () {
      final longName = 'x' * (kFnthinkCallLogPartyCap + 10);
      final one = formatFnthinkCallLogReport('x', [
        row(name: longName, number: '10086', dateMillis: stamp),
      ]);
      expect(one, contains('…'));
      final many = formatFnthinkCallLogReport('x', [
        for (var i = 0; i < 400; i++)
          row(
            name: '很长的名字很长的名字很长的名字很长的名字${'y' * 20}',
            number: '1380000$i',
            dateMillis: stamp,
          ),
      ]);
      expect(many, contains('另有'));
      expect(many, contains('条因体积上限未包含'));
    });
  });
}
