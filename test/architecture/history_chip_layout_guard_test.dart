import 'package:flutter_test/flutter_test.dart';

import '../support/source_guards.dart';

/// T133 片2 的架构守卫：那一串通道 chip 的**排法、上限、档位表**各只有一个作者。
///
/// 挡的是"改回原样"那条路：页面重新拿 `record.channels` 的原始顺序直接 map 出 Wrap
/// （于是真失败那枚又被埋进中间），或另一处再抄一个"露几枚"的数字（于是两处口径漂开）。
void main() {
  final root = projectRoot();
  final libCode = libCodeByRel(root);

  List<String> filesMentioning(List<String> names) =>
      libCode.entries
          .where((e) => names.any((n) => e.value.contains(n)))
          .map((e) => e.key)
          .toList()
        ..sort();

  group('chip 的排法与折法只有一个作者', () {
    test('注意力档位表全库只此一份，页面不许自己查档', () {
      expect(
        filesMentioning(['deliveryAttention']),
        ['services/history_channel_chips.dart'],
        reason:
            '`deliveryAttention` 的读者变了。今天它只在作者文件内部用（页面要的是排好的序列，'
            '不是档位数字）；页面开始自己比档位，就等于把"先看谁"这件事又拆成两份判断。',
      );
    });

    test('一屏露几枚这个上限全库只有一处', () {
      expect(
        filesMentioning(['visibleChannelChipCount']),
        ['services/history_channel_chips.dart'],
        reason:
            '露出的枚数被抄到别处了。两处数字一旦漂开，就会出现"折了 3 枚却按 4 枚算收起"这类'
            '展开后收不回去的形状（同 `normalizeAlias` 那条纪律：钉的是只有一处口径）。',
      );
    });

    test('排法与折法的读者登记在册（新增读者要显式加进来）', () {
      expect(
        filesMentioning([
          'orderChannelsByAttention',
          'visibleChannelChips',
          'foldedChannelChipCount',
        ]),
        ['pages/history_page.dart', 'services/history_channel_chips.dart'],
        reason:
            'chip 排布的读者集合变了。今天只有历史页一处消费；'
            '要新增消费者请登记，别绕过作者自己排序自己数。',
      );
    });
  });
}
