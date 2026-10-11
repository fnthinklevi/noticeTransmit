import 'dart:convert';

import 'package:fnthink_push/fnthink_push.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/services/fnthink_grant_items.dart';
import 'package:notice_transmit/services/fnthink_pair_items.dart';
import 'package:notice_transmit/services/fnthink_remote_action_labels.dart';

/// T134 片3 的那两枚**档位/取值域**读口（片4 之后"画哪几行"搬去 `fnthink_grant_items.dart`）。
///
/// 这一组钉的是三件事，每件都有一个"写歪了会怎样"：
///  ① 名单只能从契约那两张表来（在界面里抄一份的代价是：契约加一项而那份没加，
///     而那一格的缺席在屏上读起来和"用户没兴趣"一模一样）；
///  ② L1 那一档**不看清单**（给它画一张"勾了才生效"的表，用户读到的是"多勾一项＝多给一项权限"，
///     而那一读法在这一档不成立）；
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

  group('取值域（pairItemVocabulary）', () {
    test('两张表都解得出来：名单取值、键控表取**键名**', () {
      final vocabulary = pairItemVocabulary(contract);
      expect(vocabulary, containsAll(contract.l2Actions));
      expect(vocabulary, containsAll(contract.l3Settings.keys));
      // 键控表若被读成"一张空表"（只认名单的那份写法），L3 那六项会永远算词表外 ——
      // 而界面上那看起来就是"用户没勾"。所以这里要的是**键名进了名单**。
      expect(
        vocabulary.length,
        contract.l2Actions.length + contract.l3Settings.length,
      );
    });

    test('每一项都有人话标签（没配词条的项会被画成裸标识符）', () {
      for (final item in pairItemVocabulary(contract)) {
        expect(
          hasFnthinkRemoteActionLabel(item),
          isTrue,
          reason: '$item 在屏上会是英文冒号串，那是看得见的缺',
        );
      }
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

  group('派生层与取值域对不上 ⇒ 抛（片3 立的那条自证，读者换到 pairItemRows）', () {
    test('取值域指到别的表 ⇒ 抛，不把一批服务端会整发拒的名字签出去', () {
      final broken = mutate((root) {
        ((root['clientEvents'] as Map)['pairConfirm']
            as Map)['itemsVocabularyFrom'] = [
          'capabilities.l3.settings',
        ];
      });
      expect(
        () => pairItemRows(broken),
        throwsStateError,
        reason: 'L2 那些项落进不了取值域 ⇒ 服务端 400，而这在屏上就是"点了同意没反应"',
      );
    });
  });
}
