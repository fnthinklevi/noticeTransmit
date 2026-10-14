import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/delivery_status.dart';
import 'package:notice_transmit/services/repush_eligibility.dart';

/// T133 片1：把两个问题拆成两个具名作者，并把两份答案**同屏**钉住。
///
/// 原先两件事共用 `NotificationRecord.hasFailedChannel`（只认 `failed`）：
/// - 「这条送达了吗」—— 筛选、状态词；
/// - 「这条可以再发一次吗」—— 批量池、勾选框、单条「现在推送」。
///
/// 于是界面上出现「筛得出、选不中」与「选得中、筛不出」两种自相矛盾。
/// 本文件同时锁住这两问各自的答案，以及它们**故意不同**的那一格。
void main() {
  Map<String, dynamic> delivery(Map<String, Object?> byChannel) {
    return byChannel.map<String, dynamic>((k, v) => MapEntry(k, v));
  }

  group('可以再发一次吗：单通道真值表', () {
    test('failed 与 paused 进池 —— 这两档都没发出去', () {
      expect(channelNeedsRepush({'status': 'failed'}), isTrue);
      expect(channelNeedsRepush({'status': 'paused'}), isTrue);
    });

    test('success / sending / intercepted 都不进池，各有一句理由', () {
      // success：再发一遍 = 同一条通知推两次，收件端不会因"重推"而收回上一条
      expect(channelNeedsRepush({'status': 'success'}), isFalse);
      // sending：还在途，重推就是拿"再发一次"去和"这一次可能正在发"抢
      expect(channelNeedsRepush({'status': 'sending'}), isFalse);
      // intercepted：那是用户自己定的过滤规则，替他推翻它不叫"重推"
      expect(channelNeedsRepush({'status': 'intercepted'}), isFalse);
    });

    test('条目不是 Map / 缺 status / status 为 null ⇒ 保守判不可再发，不抛异常', () {
      expect(channelNeedsRepush('failed'), isFalse); // 历史脏数据形态
      expect(channelNeedsRepush(123), isFalse);
      expect(channelNeedsRepush(null), isFalse);
      expect(channelNeedsRepush(const {}), isFalse);
      expect(channelNeedsRepush({'message': 'HTTP 502'}), isFalse);
      expect(channelNeedsRepush({'status': null}), isFalse);
    });

    test('status 是数字/布尔一类异形值也不被读成"可再发"', () {
      expect(channelNeedsRepush({'status': 1}), isFalse);
      expect(channelNeedsRepush({'status': true}), isFalse);
    });
  });

  group('重推池：一条记录要不要进、进的是哪几把', () {
    test('混合状态：任一路没发出去就进池，明细只列没发出去的那几把', () {
      final d = delivery({
        'chan:wecom': {'status': 'success'},
        'chan:email': {'status': 'failed', 'message': 'HTTP 502'},
      });
      expect(recordNeedsRepush(d), isTrue);
      expect(repushableChannels(d), ['chan:email']);
    });

    test('多条可再发的通道全部列出，并保持记录里的原顺序', () {
      final d = delivery({
        'chan:wecom': {'status': 'failed'},
        'chan:bark': {'status': 'success'},
        'chan:email': {'status': 'paused'},
      });
      expect(repushableChannels(d), ['chan:wecom', 'chan:email']);
    });

    test('空送达记录不进池 —— 「没有记录」不等于「失败了」', () {
      // 典型是「仅记录不推送」与规则 `Record` 那一档：用户明说这条别发。
      // 把它读成失败会静默扩张推送范围。
      expect(recordNeedsRepush(delivery({})), isFalse);
      expect(repushableChannels(delivery({})), isEmpty);
    });

    test('全部成功的记录不进池', () {
      final d = delivery({
        'chan:wecom': {'status': 'success'},
        'chan:email': {'status': 'success'},
      });
      expect(recordNeedsRepush(d), isFalse);
      expect(repushableChannels(d), isEmpty);
    });

    test('异形条目整条保守判为不可再发', () {
      final d = delivery({
        'chan:wecom': 'failed',
        'chan:email': 123,
        'chan:sms': null,
      });
      expect(recordNeedsRepush(d), isFalse);
      expect(repushableChannels(d), isEmpty);
    });
  });

  group('两问两答：同一条记录，两份答案可以不同', () {
    test('只有拦截通道：筛选认它未送达，重推池不收它 —— 这就是那一个差集', () {
      final d = delivery({
        'chan:sms': {'status': 'intercepted', 'message': '黑名单'},
      });
      expect(matchDeliveryFilter(d, deliveryFilterNotDelivered), isTrue);
      expect(recordNeedsRepush(d), isFalse);
    });

    test('只有失败通道：两问同答（未送达 + 可再发）', () {
      final d = delivery({
        'chan:email': {'status': 'failed', 'message': 'SMTP 拒绝'},
      });
      expect(matchDeliveryFilter(d, deliveryFilterNotDelivered), isTrue);
      expect(recordNeedsRepush(d), isTrue);
    });

    test('只有暂停通道：两问也都答"是"（片3 把这一档补进了筛选）', () {
      // 改之前「仅失败」那一档不认 paused ⇒ 一条暂停没发的记录**两档都找不到**，
      // 却能被重推。片3 把这一档定成「没发出去的」（词表见 delivery_status.dart），
      // 两问的差集只剩 intercepted 一格 —— 那一格是刻意的，上面两条用例钉着它。
      final d = delivery({
        'chan:email': {'status': 'paused', 'message': '转发已暂停'},
      });
      expect(recordNeedsRepush(d), isTrue);
      expect(matchDeliveryFilter(d, deliveryFilterNotDelivered), isTrue);
      expect(matchDeliveryFilter(d, deliveryFilterDelivered), isFalse);
    });

    test('还在途的通道：既不算没送达，也不进重推池', () {
      final d = delivery({
        'chan:email': {'status': 'sending', 'message': ''},
      });
      expect(matchDeliveryFilter(d, deliveryFilterNotDelivered), isFalse);
      expect(recordNeedsRepush(d), isFalse);
    });
  });

  // ── T133 片9（走 (b)：每一条转发行都有出口）─────────────────────────
  //
  // 这一族钉的是**口径**：行内那一枚现在每行都画，于是「这一发到底动哪几族」整个落在
  // 文案与范围这一对上。两者都由 repushIntentOf / repushScopeKeys 给 —— 用例把三档
  // 各自的（文案档，范围）成对钉住，任何一档漂开都会红在这里。
  group('单条出口的三档口径（T133 片9 走 (b)）', () {
    test('有没发出去的那几族 ⇒ missing 档，范围就是那几把（成功的不进）', () {
      final d = delivery({
        'chan:wecom': {'status': 'success'},
        'chan:email': {'status': 'failed', 'message': 'HTTP 502'},
        'chan:dingtalk': {'status': 'paused', 'message': '转发已暂停'},
      });
      expect(repushIntentOf(d), RepushIntent.missing);
      expect(repushScopeKeys(d), ['chan:email', 'chan:dingtalk']);
    });

    test('整条没有送达记录 ⇒ unsent 档，范围＝不限定（null，不是空集）', () {
      expect(repushIntentOf(const {}), RepushIntent.unsent);
      expect(
        repushScopeKeys(const {}),
        isNull,
        reason:
            '这一档欠的是「当前启用通道各一发」。表达成空集合，service 那一头读成「谁都不发」，'
            '按下去什么都不会发生；表达成「全部键」又无从取 —— 这条没有键。',
      );
    });

    test('全成功 ⇒ again 档，范围＝这条快照里的全部键（含已成功的）', () {
      final d = delivery({
        'chan:wecom': {'status': 'success'},
        'chan:email': {'status': 'success'},
      });
      expect(repushIntentOf(d), RepushIntent.again);
      expect(repushScopeKeys(d), ['chan:wecom', 'chan:email']);
    });

    test('还在途的也算 again 档：点它就是主动再发一次，界面说的话得与之相配', () {
      final d = delivery({
        'chan:email': {'status': 'sending', 'message': ''},
      });
      expect(repushIntentOf(d), RepushIntent.again);
      expect(repushScopeKeys(d), ['chan:email']);
    });

    test('只有被规则拦下的那条也算 again 档：用户当场按下去＝显式推翻那条过滤', () {
      final d = delivery({
        'chan:sms': {'status': 'intercepted', 'message': '黑名单'},
      });
      expect(
        repushIntentOf(d),
        RepushIntent.again,
        reason: '批量池不收它（那是「给一批补缺」），单条这一枚收 —— 两格语义本来就不同，不是自相矛盾',
      );
      expect(repushScopeKeys(d), ['chan:sms']);
    });

    test('异形条目不当成「有没发出去的」，也不抛异常', () {
      final dirty = delivery({
        'chan:a': 'failed', // 老脏数据：值不是 Map
        'chan:b': {'status': 'success'},
      });
      expect(repushIntentOf(dirty), RepushIntent.again);
      expect(repushScopeKeys(dirty), ['chan:a', 'chan:b']);
    });

    test('值域封闭 + missing 永远优先（先补缺，再谈重发）', () {
      expect(
        RepushIntent.values.toSet(),
        {RepushIntent.missing, RepushIntent.unsent, RepushIntent.again},
        reason: '多加一档就必须同时给界面一句文案与一个范围，否则它会落到 switch 的默认分支上',
      );
      final mixed = delivery({
        'chan:wecom': {'status': 'success'},
        'chan:email': {'status': 'failed'},
      });
      expect(repushIntentOf(mixed), RepushIntent.missing);
    });

    test('这一问不改写「这条送达了吗」：again 档那条仍然算已送达', () {
      // 片9 让每行都有出口，正是这两问最容易被人重新混成一格的时刻。
      final d = delivery({
        'chan:wecom': {'status': 'success'},
      });
      expect(repushIntentOf(d), RepushIntent.again);
      expect(matchDeliveryFilter(d, deliveryFilterDelivered), isTrue);
      expect(matchDeliveryFilter(d, deliveryFilterNotDelivered), isFalse);
    });
  });
}
