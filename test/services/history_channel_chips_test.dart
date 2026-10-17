import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/history_channel_chips.dart';

/// T133 片2 立、T154 片2 改口径：通道那一族的**排法与统计**（唯一作者的纯函数真值表）。
///
/// 盯的是两件会被"顺手改回去"的事：
/// 1. 出问题的排在前（原先抄配置顺序 ⇒ 真失败那枚埋在中间）；
/// 2. 同档**稳定**（否则每次 rebuild 自己换序，那是噪音不是信息）。
///
/// ⚠ 折法那一组（`visibleChannelChips` / `foldedChannelChipCount` / `visibleChannelChipCount`）
/// 在 T154 片2 **整组删除**：行内不再摊 chip（改为一统计行 + 子页），"露几枚"没有意义了。
/// 删除时**没有**把那些用例改成别的东西凑数 —— 那一族的能力本身退休了。
/// 新的一组钉 [tallyDelivery]，它接替的是同一个位置上的另一个问题：
/// 不是"露几枚"，而是"这条到底成没成"。
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

  group('统计：这条到底成没成（T154 片2）', () {
    test('全成功：三档计数各自对得上', () {
      final t = tallyDelivery(
        d({'chan:a': 'success', 'chan:b': 'success', 'chan:c': 'success'}),
      );
      expect(t.total, 3);
      expect(t.done, 3);
      expect(t.failed, 0);
      expect(t.inFlight, 0);
    });

    test('混合：成了的与没成的分开数（这是维护者要的那一行）', () {
      final t = tallyDelivery(
        d({'chan:a': 'success', 'chan:b': 'success', 'chan:c': 'failed'}),
      );
      expect(t.total, 3);
      expect(t.done, 2);
      expect(t.failed, 1);
      expect(t.inFlight, 0);
    });

    test('没成的那三档都算 failed：发失败、被拦、暂停（同 `notDeliveredStatuses`）', () {
      for (final s in const ['failed', 'intercepted', 'paused']) {
        final t = tallyDelivery(d({'chan:x': s}));
        expect(t.failed, 1, reason: '$s 应算"没成"');
        expect(t.done, 0);
        expect(t.inFlight, 0);
      }
    });

    test('在途那几档都算 inFlight：pending 与 queued 各是各的"没到对端"', () {
      for (final s in const ['pending', 'queued', 'sending', '']) {
        final t = tallyDelivery(d({'chan:x': s}));
        expect(t.inFlight, 1, reason: '$s 应算"还在路上"');
        expect(t.failed, 0, reason: '$s 不是失败 —— 把它数成失败就是把本机的等待说成事故');
        expect(t.done, 0);
      }
    });

    test('认不出的词不猜：算在途，不算成功也不算失败', () {
      final t = tallyDelivery(d({'chan:x': 'weird-word'}));
      expect(t.inFlight, 1);
      expect(t.done, 0);
      expect(t.failed, 0);
      expect(
        t.inFlight + t.done + t.failed,
        t.total,
        reason: '三档必须覆盖全部：漏一档就会出现"共 3 条 · 2 成功"这种对不上的账',
      );
    });

    test('空 map ⇒ 全 0（界面据此不画这一行）', () {
      final t = tallyDelivery(const {});
      expect(t.total, 0);
      expect(t.isEmpty, isTrue);
    });

    test('三档之和恒等于 total（混合样本 + 陌生词一起数）', () {
      final t = tallyDelivery(
        d({
          'chan:a': 'success',
          'chan:b': 'failed',
          'chan:c': 'queued',
          'chan:d': 'weird',
        }),
      );
      expect(t.total, 4);
      expect(t.inFlight + t.done + t.failed, 4);
    });
  });
}
