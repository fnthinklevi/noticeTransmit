import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/models/delivery_status.dart';

/// T133 片3：「这条**送达了吗**」的词表与精筛判定（唯一作者）。
///
/// 这一档原先叫「仅失败」却认两种状态，而"暂停期间没发出去"的记录**两档都找不到**
/// —— 名字与口径不符，于是"筛得出、选不中"这类自相矛盾只能靠人记住口径。
/// 本文件钉的是：档名就是说的那句话、词表三个状态一个不多一个不少、
/// 认不出的档名 fail-closed。
void main() {
  Map<String, dynamic> statusOf(List<String> states) {
    final out = <String, dynamic>{};
    for (var i = 0; i < states.length; i++) {
      out['chan:c$i'] = {'status': states[i]};
    }
    return out;
  }

  group('词表本身', () {
    test('「没发出去的」是三个状态词，一个不多一个不少', () {
      expect(notDeliveredStatuses, ['failed', 'intercepted', 'paused']);
      expect(deliveredStatus, 'success');
    });

    test('三个档名彼此不同且都不等于词表里的状态词（档名不是状态）', () {
      expect(
        {
          deliveryFilterAll,
          deliveryFilterDelivered,
          deliveryFilterNotDelivered,
        }.length,
        3,
      );
      expect(notDeliveredStatuses, isNot(contains(deliveryFilterNotDelivered)));
    });
  });

  group('精筛：没发出去的那一档', () {
    test('failed / intercepted / paused 任一路都算，混合也算', () {
      expect(
        matchDeliveryFilter(statusOf(['failed']), deliveryFilterNotDelivered),
        isTrue,
      );
      expect(
        matchDeliveryFilter(
          statusOf(['intercepted']),
          deliveryFilterNotDelivered,
        ),
        isTrue,
      );
      expect(
        matchDeliveryFilter(statusOf(['paused']), deliveryFilterNotDelivered),
        isTrue,
      );
      expect(
        matchDeliveryFilter(
          statusOf(['success', 'failed']),
          deliveryFilterNotDelivered,
        ),
        isTrue,
      );
    });

    test('全部成功 / 全部在途 都不在这一档', () {
      expect(
        matchDeliveryFilter(statusOf(['success']), deliveryFilterNotDelivered),
        isFalse,
      );
      expect(
        matchDeliveryFilter(
          statusOf(['sending', 'pending']),
          deliveryFilterNotDelivered,
        ),
        isFalse,
      );
    });
  });

  group('精筛：已送达那一档', () {
    test('要求**全部**通道都成功，混合状态不算', () {
      expect(
        matchDeliveryFilter(statusOf(['success']), deliveryFilterDelivered),
        isTrue,
      );
      expect(
        matchDeliveryFilter(
          statusOf(['success', 'sending']),
          deliveryFilterDelivered,
        ),
        isFalse,
      );
    });
  });

  group('边界：不许把"看不见"读成"符合条件"', () {
    test('空送达记录两档都不进（"仅记录不推送"没有送达这件事）', () {
      expect(
        matchDeliveryFilter(const {}, deliveryFilterNotDelivered),
        isFalse,
      );
      expect(matchDeliveryFilter(const {}, deliveryFilterDelivered), isFalse);
    });

    test('异形条目（非 Map / 缺 status）不进任何档，也不抛异常', () {
      final dirty = <String, dynamic>{
        'chan:a': 'failed',
        'chan:b': 123,
        'chan:c': null,
        'chan:d': {'message': '没有状态'},
      };
      expect(matchDeliveryFilter(dirty, deliveryFilterNotDelivered), isFalse);
      expect(matchDeliveryFilter(dirty, deliveryFilterDelivered), isFalse);
    });

    test('认不出的档名一律不匹配（fail-closed，宁可看不见）', () {
      final d = statusOf(['failed']);
      expect(matchDeliveryFilter(d, deliveryFilterAll), isFalse);
      expect(matchDeliveryFilter(d, 'success'), isFalse); // 旧档名已作废
      expect(matchDeliveryFilter(d, 'failed'), isFalse);
      expect(matchDeliveryFilter(d, ''), isFalse);
    });
  });
}
