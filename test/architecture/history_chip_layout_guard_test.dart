import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T133 片2 的架构守卫：通道那一族的**排法、统计、档位表**各只有一个作者。
///
/// 挡的是"改回原样"那条路：页面重新拿 `record.channels` 的原始顺序直接 map 出 Wrap
/// （于是真失败那枚又被埋进中间），或另一处再抄一遍"几条成几条败"的算法（于是两处口径漂开）。
///
/// ⚠ T154 片2：**"一屏露几枚"那条随折法整族退休**（行内不再摊 chip ⇒ 上限没有意义）。
///   删掉它而不是改写成别的东西：那一族的能力本身不在了。
///   新顶上来的是 [tallyDelivery] 的成员判定来源（"这条到底成没成"接替了"露几枚"）。
void main() {
  final root = projectRoot();
  final libCode = libCodeByRel(root);

  List<String> filesMentioning(List<String> names) =>
      libCode.entries
          .where((e) => names.any((n) => e.value.contains(n)))
          .map((e) => e.key)
          .toList()
        ..sort();

  group('通道那一族的排法与统计只有一个作者', () {
    test('注意力档位表全库只此一份，页面不许自己查档', () {
      expect(
        filesMentioning(['deliveryAttention']),
        ['services/history_channel_chips.dart'],
        reason:
            '`deliveryAttention` 的读者变了。今天它只在作者文件内部用（页面要的是排好的序列，'
            '不是档位数字）；页面开始自己比档位，就等于把"先看谁"这件事又拆成两份判断。',
      );
    });

    test('排法与统计的读者登记在册（新增读者要显式加进来）', () {
      expect(
        filesMentioning(['orderChannelsByAttention', 'tallyDelivery']),
        ['pages/history_page.dart', 'services/history_channel_chips.dart'],
        reason:
            '通道那一族的读者集合变了。今天只有历史页一处消费（行内统计 + 子页）；'
            '要新增消费者请登记，别绕过作者自己排序、自己数成败。'
            '⚠ 折法三件套（`visibleChannelChips` / `foldedChannelChipCount` / '
            '`visibleChannelChipCount`）在 T154 片2 退休，这条守卫不再提它们 —— '
            '提一个不存在的名字会让守卫恒红。',
      );
    });

    test('统计函数体里不许出现状态词字面量：成了/没成只有那一位作者', () {
      // ⚠ 两条口径都容易站错地方，各记一次：
      //   ① **必须剥注释**（否则"解释为什么复用那两位"的那段注释自己就让下面的
      //      字符串断言通过 —— 假绿）；
      //   ② **必须限定在 `tallyDelivery` 的函数体里**（第一版扫了整个文件，
      //      而 `deliveryAttention` 的档位表本来就带状态词字面量 ⇒ 守到正确代码上，
      //      当场红过一次。尺要量的是"统计有没有自己列词表"，不是"这个文件里出现过状态词"）。
      final src = stripComments(
        librarySource(root, 'lib/services/history_channel_chips.dart'),
      );
      final start = src.indexOf('DeliveryTally tallyDelivery(');
      expect(
        start,
        greaterThan(-1),
        reason: '找不到统计函数本体 ⇒ 下面的断言全是空断言（整段被删也会通过）',
      );
      final bodyEnd = src.indexOf('\n}', start);
      expect(bodyEnd, greaterThan(start));
      final body = src.substring(start, bodyEnd);
      for (final literal in [
        "'success'",
        "'failed'",
        "'pending'",
        "'queued'",
      ]) {
        expect(
          body.contains(literal),
          isFalse,
          reason:
              '统计里出现了状态词字面量 $literal ⇒ 有人在这里又列了一遍词表。'
              '"成了"是 `deliveredStatus`、"没成"是 `notDeliveredStatuses`'
              '（`lib/models/delivery_status.dart`）—— 历史页筛选与 `delivery_bucket` '
              '算的都是那一位，抄第二遍就是第二个作者',
        );
      }
      // 反向自证：函数体里确实在按那两位判（否则上面那串"都不在"可以靠"整段删空"通过）。
      expect(
        body.contains('deliveredStatus') &&
            body.contains('notDeliveredStatuses'),
        isTrue,
        reason: '统计没在读那两位 ⇒ 上下两条断言合起来就是空断言',
      );
    });
  });
}
