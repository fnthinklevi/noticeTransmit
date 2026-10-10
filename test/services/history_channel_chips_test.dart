import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/history_channel_chips.dart';

/// T133 片2：那一串通道 chip 的排法与折法（唯一作者的纯函数真值表）。
///
/// 盯的是三件会被"顺手改回去"的事：
/// 1. 出问题的排在前（原先抄配置顺序 ⇒ 真失败那枚埋在中间）；
/// 2. 同档**稳定**（否则每次 rebuild 自己换序，那是噪音不是信息）；
/// 3. 折起来的是尾部的"没事"那几枚，而不是头部。
void main() {
  Map<String, dynamic> d(Map<String, String> byChannel) =>
      byChannel.map<String, dynamic>((k, v) => MapEntry(k, {'status': v}));

  group('注意力档位', () {
    test('要人动手的两档在最前，成功在最后', () {
      expect(
        deliveryAttention('failed'),
        lessThan(deliveryAttention('paused')),
      );
      expect(
        deliveryAttention('paused'),
        lessThan(deliveryAttention('intercepted')),
      );
      expect(
        deliveryAttention('intercepted'),
        lessThan(deliveryAttention('sending')),
      );
      expect(deliveryAttention('pending'), deliveryAttention('sending'));
      expect(
        deliveryAttention('success'),
        greaterThan(deliveryAttention('sending')),
      );
    });

    test('说不清的（空状态、陌生词）与"还在途"同一档，不许排到成功之后', () {
      expect(deliveryAttention(''), deliveryAttention('sending'));
      expect(deliveryAttention('whatever'), deliveryAttention('sending'));
    });

    test('注意力档**不等于**重推判据：intercepted 排在前面却不该被重推', () {
      // 这条钉的是"两件事不许再合成一个"：排序按通道级事实，重推池要排除用户自己拦的。
      expect(
        deliveryAttention('intercepted'),
        lessThan(deliveryAttention('success')),
      );
    });
  });

  group('排法：问题在前，同档保持记录里的原顺序', () {
    test('混合状态按注意力重排', () {
      final rows = ['chan:email', 'chan:dingtalk', 'chan:bark'];
      final status = d({
        'chan:email': 'success',
        'chan:dingtalk': 'failed',
        'chan:bark': 'intercepted',
      });
      expect(orderChannelsByAttention(rows, status), [
        'chan:dingtalk',
        'chan:bark',
        'chan:email',
      ]);
    });

    test('同档稳定：两枚失败保持记录顺序（不许按名字或哈希换序）', () {
      final rows = ['chan:slack', 'chan:ntfy', 'chan:gotify'];
      final status = d({
        'chan:slack': 'failed',
        'chan:ntfy': 'failed',
        'chan:gotify': 'failed',
      });
      expect(orderChannelsByAttention(rows, status), rows);
    });

    test('没有送达记录的通道按"说不清"那一档排，不许消失也不许置顶', () {
      final rows = ['chan:email', 'chan:bark'];
      expect(orderChannelsByAttention(rows, d({'chan:email': 'success'})), [
        'chan:bark',
        'chan:email',
      ]);
    });

    test('空列表进空列表出', () {
      expect(orderChannelsByAttention(const [], const {}), isEmpty);
    });
  });

  group('折法：只折尾部，展开态全露', () {
    // ⚠ 这一组的期望值**一律写死数字**，不引用 `visibleChannelChipCount` ——
    //   拿"被量的那个常量"去算期望值就是自证：上限改成 99，四条用例一条都不会红
    //   （2026-10-10 反证 Y1 实测到的假绿）。常量自己的读数只在下面那一条里钉一次。
    test('上限今天定在 4 枚（改这个数要连同一句理由一起改）', () {
      expect(visibleChannelChipCount, 4);
    });

    test('不超过上限时全露，折叠计数为 0', () {
      final three = ['a', 'b', 'c'];
      expect(visibleChannelChips(three), three);
      expect(foldedChannelChipCount(three), 0);
    });

    test('恰好到上限不折（边界：上限那一枚不能自己被折进去）', () {
      final four = ['a', 'b', 'c', 'd'];
      expect(visibleChannelChips(four), four);
      expect(foldedChannelChipCount(four), 0);
    });

    test('超出上限只露前 4 枚，折的是尾部（那些是"没事"的那几枚）', () {
      final six = ['a', 'b', 'c', 'd', 'e', 'f'];
      expect(visibleChannelChips(six), ['a', 'b', 'c', 'd']);
      expect(foldedChannelChipCount(six), 2);
    });

    test('展开态全露 —— 但折叠计数按全集算，「收起」才留在原位', () {
      final seven = ['a', 'b', 'c', 'd', 'e', 'f', 'g'];
      expect(visibleChannelChips(seven, expanded: true), seven);
      expect(foldedChannelChipCount(seven), 3);
    });
  });
}
