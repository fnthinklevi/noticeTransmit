import 'package:fnthink_push/fnthink_push.dart';

/// 配对同意那一屏**能勾的那几项**（T134 片3）。
///
/// ## 为什么不是整张契约词表
/// 授权表里的比对是**整串相等**（`grant.items` 那个 `contains`，向量
/// `c-action-item-not-granted` 的原话是"items 里没有通配"）。而这一台将来真发出去的那个
/// `item`，对契约点名要参数的六个 L2 动作长成 `<名>/<参数>`、对 L3 那两枚 toggle 长成
/// `<名>/on|off`（见 `fnthink_send_page.dart` 的 `_wireItem`）。
/// ⇒ 把那些**名字**勾进表里，它们永远对不上线上的串：界面上写着"已授权"，对面发过来还是一句
/// `item:<整串>` 的 403。所以这里只给"勾了就真能对上"的那几项 —— 宁可窄。
///
/// 粒度到底收到"动作级"还是"参数级"是要拍的一条产品与安全取舍（按名字匹配＝勾 `app:launch`
/// 等于允许对面启动任意应用），登记在 roadmap 的 T134 行；**拍下来之前这张表不许放宽**。
///
/// ## 名单不在这里抄
/// 取值域仍是契约那两张表（`clientEvents.pairConfirm.itemsVocabularyFrom` 指过去的两处），
/// 本文件只做减法。末尾那道"派生结果必须逐项落在契约声明的取值域里"钉的就是这件事：
/// 哪天 `itemsVocabularyFrom` 改指别的表，这里**抛**，而不是把一批服务端会整发拒（400）的
/// 名字签出去 —— 后者在屏幕上的表现是"点了同意，什么都没发生"。
List<String> pairItemCandidates(FnthinkContract contract) {
  final needsArgument = contract.l2ActionsRequiringArgument.toSet();
  final out = <String>[
    ...contract.l2Actions.where((a) => !needsArgument.contains(a)),
    ...contract.l3Settings.entries
        .where((e) => !e.value.isToggle)
        .map((e) => e.key),
  ];
  final vocabulary = pairItemVocabulary(contract);
  final outside = out.where((i) => !vocabulary.contains(i)).toList();
  if (outside.isNotEmpty) {
    throw StateError(
      '本机派生出的勾逐项不在契约声明的取值域里：$outside（取值域路径 = '
      '${contract.pairConfirmItemsVocabulary.join('/')}）—— '
      '服务端会整发拒（状态码由 unknownItemStatus 定），而用户在屏上刚勾完',
    );
  }
  return out;
}

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
