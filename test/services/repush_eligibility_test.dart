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
}
