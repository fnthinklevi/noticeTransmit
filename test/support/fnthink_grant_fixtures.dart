import 'package:fnthink_push/fnthink_push.dart';
import 'package:notice_transmit/services/fnthink_grant_items.dart';

/// 测试夹具用的那份「**名单这一格不参与**」授权（T134 片4 之后不再是"全勾"一句话）。
///
/// ## 为什么需要这一枚
/// 判定层（`rejectBySenderGrant`）从片4 起**只要名字在词表里就查清单**，而勾选项的 id 是
/// 整串 `<名>/<参数>` —— 参数值是各条用例自己挑的，夹具没法替它们全部猜中。
/// 于是"我要判的是渠道 / 凭据 / 词表 / 参数形状那一道，不想被名单挡住"这个意图，
/// 只能靠把**这一条要试的串**放进清单来表达。这一枚给的是那一族里
/// **不需要用例配合**的两类：无参数项（串就是名字）与 L3 那两枚 toggle（裸名 + 两个档）。
///
/// ⚠ 要参数的那几项（`channel:toggle`、count / keyword 那五种）**不在这里**：
///   它们的合法串带用例自己挑的参数值，谁测谁在自己的 `grants` 里逐条写出那一串。
///   少了这一句提醒的写法是"默认给全表"，而那张表永远缺一项，缺的那一条会红成
///   `not-granted` —— 读起来像名单判据坏了，其实是用例没交代。
///
/// ⚠ 两枚 toggle 的**裸名字不在**这份里，而它们两个档的整串在：
///   `RemoteCommandRecognizer.judge` 把 `grant.items` **同时**当成"L3 那几项的前置授权"
///   （`grantedKeys`）。带上裸名字，「缺前置授权 ⇒ 拒 missing-grant」那一条就假绿 ——
///   它要钉的那一格根本没被走到，而红点会跑到别的用例上。
///   裸名字是**老数据**的形状（片4 之后的同意屏画不出它）；要测它就自己写进 `grants`。
List<String> grantEverythingExceptArguments(FnthinkContract contract) => [
  for (final row in pairItemRows(contract))
    if (!row.needsArgument)
      row.base
    else if (row.kind == FnthinkGrantArgumentKind.toggle)
      for (final word in contract.l3ItemTargetWords)
        contract.grantItemWire(base: row.base, argument: word),
];
