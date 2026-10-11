import 'package:fnthink_push/fnthink_push.dart';

/// 配对同意那一屏的**档位维度**与**取值域**（T134 片3）。
///
/// 「这一屏画哪几行、每行收哪种参数、那一串能不能进授权表」在 `fnthink_grant_items.dart`
/// （片4 起粒度＝参数级）。这一份只回答另外两件事，因为它们的服务对象不是那张表：
/// - [pairItemsApplyAtLevel]：**这一档到底看不看清单**。
/// - [pairItemVocabulary]：契约声明的取值域**本身**（派生层拿它自证没抄名单）。
///
/// ⚠ 片3 那份"把要参数的项整排减掉"的写法已经删掉了。它当时的理由（"名字勾了对不上线上
/// 那一串"）到今天仍然成立 —— 成立的是**结论的方向**而不是那次减法：对的做法是让勾选项
/// 自己也长成线上那一串（`<名>/<参数>`），而不是把那一族留在清单之外只由档位天花板管
/// （`app:launch` 那一格因此要么整条不给、要么等于允许对面启动任意应用）。

/// 这一档**会不会**去看逐条清单（从契约 `capabilities.itemRequiredFromLevel` 那一档起）。
///
/// 档位顺序的出处仍是契约 `capabilities.levels` 的位置（与服务端 `levelRank` 同一把尺，
/// 这里不另写一张 rank 表）。L1 那一条压根不查清单：给它画一张"勾了也不参与判据"的表，
/// 用户读到的是"多勾一项＝多给一项权限"，而那在这一档不成立。
/// 词表里没有的那个档位词回 `false`（不给勾）—— 页面另一条 `unknown-level` 的说明已经在说它了。
bool pairItemsApplyAtLevel(FnthinkContract contract, String level) {
  final levels = contract.capabilityLevels;
  final from = levels.indexOf(contract.itemRequiredFromLevel);
  final at = levels.indexOf(level);
  if (from < 0 || at < 0) return false;
  return at >= from;
}

/// 契约声明的取值域**本身**（把 `itemsVocabularyFrom` 那两个路径解成一份名单）。
///
/// 两种形状都认，且必须两种都认：`capabilities.l2.actions` 是名单（值就是 item），
/// `capabilities.l3.settings` 是键控表（**键名**才是 item，值里装的是怎么执行）。
/// 只解名单的那份写法会把 L3 整张读成"空"，表现不是报错，是那几项永远算词表外。
List<String> pairItemVocabulary(FnthinkContract contract) {
  final out = <String>[];
  for (final path in contract.pairConfirmItemsVocabulary) {
    final node = contract.at(path.split('.'));
    final entries = node is List
        ? node.map((e) => '$e').toList()
        : node is Map
        ? node.keys.map((k) => '$k').toList()
        : null;
    if (entries == null || entries.isEmpty) {
      throw StateError(
        '契约 clientEvents.pairConfirm.itemsVocabularyFrom 指向的 $path '
        '既不是非空名单也不是非空键控表（与服务端那一侧同一判据）',
      );
    }
    out.addAll(entries.where((e) => e.trim().isNotEmpty).map((e) => e.trim()));
  }
  return out.toSet().toList()..sort();
}
