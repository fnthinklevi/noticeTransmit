import 'dart:convert';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_pair_items.dart';
import 'package:notice_transmit/services/fnthink_remote_action_labels.dart';

/// T134 片3：配对同意那一屏**能勾的那几项**是怎么从契约派生出来的。
///
/// 这一组用例钉的是三件事，每件都有一个"写歪了会怎样"：
///  ① 名单只能从契约那两张表来（在界面里抄一份的代价是：契约加一项而那份没加，
///     而那一格的缺席在屏上读起来和"用户没兴趣"一模一样）；
///  ② **要参数的那几项与 L3 那两枚 toggle 不许出现在这张表上** —— 授权表比的是整串，
///     而它们线上的 item 是 `<名>/<参数>`。把它们列出来就是让用户勾一项永远判不到的东西，
///     并在界面上留下"我已经给了"的记录；
///  ③ 派生结果必须逐项落在契约声明的取值域里（不一致时**抛**，而不是把一批服务端会回 400
///     的名字签出去 —— 那一发的表现是"点了同意，什么都没发生"）。
void main() {
  final contract = FnthinkContract.readFile();

  /// ⚠ **深拷贝**而不是 shallow：`raw` 里那几张子表是被顶层那份 `contract` 共用的，
  ///   改 `root['clientEvents']['pairConfirm']` 会把上面每一条用例读的原件一起改掉
  ///   —— 那种"跑完这一条后面都变了"的红，读起来像实现坏了，其实是夹具互相踩。
  FnthinkContract mutate(void Function(Map<String, Object?> root) edit) {
    final root = jsonDecode(jsonEncode(contract.raw)) as Map<String, Object?>;
    edit(root);
    return FnthinkContract(root);
  }

  group('候选集（pairItemCandidates）', () {
    test('就是「L2 名单减去要参数的」并上「L3 里不要目标值的那几项」', () {
      final got = pairItemCandidates(contract);
      final expected = <String>[
        ...contract.l2Actions.where(
          (a) => !contract.l2ActionsRequiringArgument.contains(a),
        ),
        ...contract.l3Settings.entries
            .where((e) => !e.value.isToggle)
            .map((e) => e.key),
      ];
      expect(got, expected);
      // 条数直接对着契约的两张表说：期望值由**契约**算，不由被量的那个函数算。
      expect(
        got.length,
        contract.l2Actions.length -
            contract.l2ActionsRequiringArgument.length +
            contract.l3Settings.values.where((s) => !s.isToggle).length,
      );
    });

    test('要填参数的与那两枚 toggle 一张都不画（勾了也永远对不上线上那个串）', () {
      final got = pairItemCandidates(contract).toSet();
      for (final excluded in [
        ...contract.l2ActionsRequiringArgument,
        ...contract.l3Settings.entries
            .where((e) => e.value.isToggle)
            .map((e) => e.key),
      ]) {
        expect(
          got,
          isNot(contains(excluded)),
          reason: '$excluded 在线上发的是 <名>/<参数>，名字进了表就等于画一项永远判不过的东西',
        );
      }
    });

    test('每一项都在契约声明的取值域里，且每一项都有人话标签', () {
      final vocabulary = pairItemVocabulary(contract).toSet();
      for (final item in pairItemCandidates(contract)) {
        expect(vocabulary, contains(item));
        expect(
          hasFnthinkRemoteActionLabel(item),
          isTrue,
          reason: '没配词条的项会被画成裸标识符（界面上一串英文冒号词），那是看得见的缺',
        );
      }
    });

    test('取值域指到别的表 ⇒ 抛（不把一批服务端会整发拒的名字签出去）', () {
      final broken = mutate((root) {
        ((root['clientEvents'] as Map)['pairConfirm']
            as Map)['itemsVocabularyFrom'] = [
          'capabilities.l3.settings',
        ];
      });
      expect(
        () => pairItemCandidates(broken),
        throwsStateError,
        reason: 'L2 那些项落进不了取值域 ⇒ 服务端 400，而这在屏上就是"点了同意没反应"',
      );
    });

    test('取值域路径指空 ⇒ 抛，不读成"没有任何一项能勾"', () {
      final broken = mutate((root) {
        ((root['clientEvents'] as Map)['pairConfirm']
            as Map)['itemsVocabularyFrom'] = [
          'capabilities.nowhere',
        ];
      });
      expect(() => pairItemVocabulary(broken), throwsStateError);
    });
  });

  group('这一档用不用得上清单（pairItemsApplyAtLevel）', () {
    test('从契约 itemRequiredFromLevel 那一档起才为真；L1 为假', () {
      expect(pairItemsApplyAtLevel(contract, 'L1'), isFalse);
      expect(
        pairItemsApplyAtLevel(contract, contract.itemRequiredFromLevel),
        isTrue,
      );
      expect(pairItemsApplyAtLevel(contract, 'L3'), isTrue);
    });

    test('档位词不在契约的档位表里 ⇒ 回 false（不给勾），不把未知当全给', () {
      expect(pairItemsApplyAtLevel(contract, 'L9'), isFalse);
      expect(pairItemsApplyAtLevel(contract, ''), isFalse);
    });
  });
}
