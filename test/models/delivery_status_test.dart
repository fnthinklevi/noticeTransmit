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

    test('「已送达」是两个词：本机推成功 ＋ 对端取走了（T154 端到端）', () {
      expect(deliveredStatuses, [deliveredStatus, peerDeliveredStatus]);
      expect(peerDeliveredStatus, isNot(deliveredStatus));
      expect(
        notDeliveredStatuses,
        isNot(contains(peerDeliveredStatus)),
        reason: '对端取走了还与"没发出去"同档 ⇒ 用户会在失败那一档里看见成功的记录',
      );
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

    test('对端取走的 delivered 与本机推成功的 success 同属「已送达」', () {
      expect(
        matchDeliveryFilter(statusOf(['delivered']), deliveryFilterDelivered),
        isTrue,
        reason: '对端已经取走了还说"没送达"＝ 把最成功的那一档也扣在失败里',
      );
      expect(
        matchDeliveryFilter(
          statusOf(['success', 'delivered']),
          deliveryFilterDelivered,
        ),
        isTrue,
        reason: '一条通知同时走了别的通道与幻念：两边都到账才算这一条已送达',
      );
      expect(
        matchDeliveryFilter(
          statusOf(['delivered', 'queued']),
          deliveryFilterDelivered,
        ),
        isFalse,
        reason: '还有一份球在对面 ⇒ 不能因为幻念那一格到了就说整条已送达',
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

  group('桶值：T133 走 (c) 之后这一位是判据的唯一去处', () {
    // 这一族从"SQL 粗筛 + Dart 精筛"收成"算一次、存一列、等值筛"。
    // 于是桶值的**值域**与**与精筛的一致性**就是全部承诺：值域一破，SQL 那一层筛不到东西；
    // 一致性一破，同一句判据在两处给出不同答案，而没有任何一层会报错。
    final shapes = <String, Map<String, dynamic>>{
      '全成功': statusOf(['success', 'success']),
      '对端已取走': statusOf(['delivered']),
      '两路都已送达': statusOf(['success', 'delivered']),
      '有失败': statusOf(['success', 'failed']),
      '只有拦截': statusOf(['intercepted']),
      '暂停中': statusOf(['paused']),
      '还在途': statusOf(['sending']),
      '已交给服务端待取': statusOf(['queued']),
      '混合在途': statusOf(['success', 'sending']),
      '空记录': const {},
      '异形条目': <String, dynamic>{
        'chan:a': 'failed',
        'chan:b': {'message': '没有状态'},
      },
    };

    test('每一行恰好落进一个桶，且值域只有那三枚（没有第四枚）', () {
      const domain = {
        deliveryBucketDelivered,
        deliveryBucketNotDelivered,
        deliveryBucketNone,
      };
      for (final e in shapes.entries) {
        final b = deliveryBucketOf(e.value);
        expect(domain, contains(b), reason: '${e.key} 算出了值域外的桶值 $b');
        final hits = <String>[
          if (b == deliveryBucketDelivered) 'delivered',
          if (b == deliveryBucketNotDelivered) 'not_delivered',
          if (b == deliveryBucketNone) 'none',
        ];
        expect(hits.length, 1, reason: '${e.key} 落进零个或好几个桶 ⇒ SQL 那一层会重筛或漏筛');
      }
    });

    test('桶与那句精筛逐行同答案（下沉没换判据，这是这一片的核心承诺）', () {
      for (final e in shapes.entries) {
        for (final filter in [
          deliveryFilterDelivered,
          deliveryFilterNotDelivered,
        ]) {
          expect(
            matchDeliveryFilter(e.value, filter),
            deliveryBucketOf(e.value) == filter,
            reason:
                '${e.key} 在档「$filter」下：精筛与桶值给的答案不一样 ⇒ '
                'SQL 筛的与判据认的是两件事，两层筛又回来了',
          );
        }
        // 「不限定」那一档谁都不匹配（它由调用方当作"不加条件"，不是判据的一档）
        expect(matchDeliveryFilter(e.value, deliveryFilterAll), isFalse);
      }
    });

    test('档名与桶名是同一对常量（SQL 拿档名当值筛的前提）', () {
      // `buildSearchSql` 那一层不做映射：它把界面给的档名直接当 `delivery_bucket` 的值筛。
      // 这两句一旦分家，历史页那两档会同时筛不到任何行，而全场测试仍然绿 —— 所以钉在这里。
      expect(deliveryBucketDelivered, deliveryFilterDelivered);
      expect(deliveryBucketNotDelivered, deliveryFilterNotDelivered);
      expect(deliveryBucketNone, isNot(deliveryFilterAll));
    });

    test('既有成功又有失败的那一行算"没发出去的"，不算"已送达"', () {
      // 顺序是判据的一部分：用户在"已送达"那一档看到一条有失败的记录，就是替他撒了谎。
      expect(
        deliveryBucketOf(statusOf(['success', 'failed'])),
        deliveryBucketNotDelivered,
      );
      expect(
        deliveryBucketOf(statusOf(['success', 'intercepted'])),
        deliveryBucketNotDelivered,
      );
    });

    test('对端取走那一行落「已送达」；本机交出去还没被取走的两档都不落', () {
      expect(
        deliveryBucketOf(statusOf(['delivered'])),
        deliveryBucketDelivered,
        reason: 'T154 端到端回来之后，这个桶就是服务端回执的下场：到了就该显示已送达',
      );
      expect(
        deliveryBucketOf(statusOf(['queued'])),
        deliveryBucketNone,
        reason:
            '「已推送到服务器·待目标设备上线」既不是终点也不是失败（与 sending/pending 同档）—— '
            '把它塞进"没发出去的"会让失败那一档混进还在路上的记录',
      );
    });

    test('没状态可说的行落 none，而不是落空串（空串的含义是"没人算过"）', () {
      expect(deliveryBucketOf(const {}), deliveryBucketNone);
      expect(
        deliveryBucketOf(<String, dynamic>{'chan:a': 'failed'}),
        deliveryBucketNone,
      );
      // ⚠ `''` 是**列的默认值**，意思是"这一行没被算过"（迁移没跑或写入咽喉漏了一列）。
      //   判据永远不许返回它 —— 否则"没人算过"与"算过、两个档都不落"就分不开了。
      expect(deliveryBucketOf(const {}), isNot(''));
    });
  });
}
