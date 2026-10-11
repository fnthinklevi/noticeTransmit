import 'package:fnthink_push/fnthink_push.dart';

import 'fnthink_l2_actions.dart';
import 'fnthink_pair_items.dart';

// 勾选项那一串的**语法**（T134 片4，粒度＝参数级）。
//
// 这里只回答两件事：「这一行要收哪一种参数」与「这一串能不能进授权表」。
// **不判权限** —— 判的还是 `grant.items` 里整串相等那一条（`rejectBySenderGrant`），
// 与服务端 `grant.items.includes(item)` 同一口径。串法本身（拼 / 切）在契约那三枚方法上
// （`grantItemWire` / `grantItemBase` / `grantItemArgument`），这里不重复一份。
//
// ## 为什么"能不能被勾"要看参数
// 维护者 2026-10-11 拍：勾选项的 id 就是**线上的整串形状**。契约点名要参数的那六项 L2
// 与两枚 L3 toggle，在线上的 item 长成 `<名>/<参数>`（发送侧的作者是 [buildChannelArgument]
// 与 [buildL3Item]）。而片3 那张表把这些项**整排减掉**了，于是那一族只由档位天花板 +
// 整机那一枚读能力开关管 —— 其中 `app:launch` 最扎手：要么整条不给，要么等于允许对面
// 启动任意应用。
//
// 反面形状（动作级）也不成立：把**名字**勾进表里，它永远对不上线上那一串
// （向量 `c-action-item-not-granted` 那条 note 的原话是"items 里没有通配"），
// 表现是界面写着"已授权"、对面发来还是一句 `item:<整串>` 的 403。
//
// ## 裸名字从此不是合法的勾选项
// 要参数就得先给参数，那一格才表达得了它勾选的东西。裸名字被拒的那一句**从契约读**
// （`clientEvents.pairConfirm.itemGrammar.bareNameRejected`），服务端与本机才回得了同一句话。
//
// ## 名单仍然不在这里抄
// 取值域仍是契约那两张表（[pairItemVocabulary]）；本文件只**按契约声明的参数形状给每一项定 kind**。
// 参数形状也不在这儿另立一本账：L2 的 kind 与上下界在 `capabilities.l2.reports`、
// 通道目标三段在 `capabilities.l2.channelTargetShape`、toggle 那两个词在 `capabilities.l3.itemTargetWords`。

/// 那一行要收哪一种参数（决定界面画什么控件，也决定这一串合不合法）。
enum FnthinkGrantArgumentKind {
  /// 没有参数：勾上就是那个名字（`listener:start`、`location:get`、四枚 `grant` 型设置）。
  none,

  /// 「要几条」那一种（`notifications:report`）。
  count,

  /// 「搜什么词 / 打开哪一条」那一种（`sms:search`、`app:launch`、`calls:search`、`contacts:search`）。
  keyword,

  /// 三段拼出来的通道目标（`channel:toggle`）。
  channelTarget,

  /// L3 那一族里"设成哪一档"这一种参数（契约 `l3.itemMayCarryTarget` 的两枚 toggle）。
  toggle,
}

/// 同意屏那一行：契约里的名字 + 它要的参数种类。
class FnthinkGrantItemRow {
  const FnthinkGrantItemRow({required this.base, required this.kind});

  /// 契约词表里的那个名字（L2 动作名或 L3 设置键）。
  final String base;

  final FnthinkGrantArgumentKind kind;

  bool get needsArgument => kind != FnthinkGrantArgumentKind.none;

  @override
  String toString() => 'FnthinkGrantItemRow($base,$kind)';
}

/// 同意屏要画的行：契约那两张表的**全量**，每项按契约声明的参数形状定 kind。
///
/// ⚠ 这里做的仍是"派生"而不是"名单"：契约加一项 L2 动作，这一栏自动多一行。
/// 派生不出来时必须**抛**而不是静默少画一项：那要么让一格必然被服务端 400 的勾出现在屏上，
/// 要么让一项谁都不认识的勾静默消失 —— 两种表现读起来都同"用户没勾"。
List<FnthinkGrantItemRow> pairItemRows(FnthinkContract contract) {
  final needsArgument = contract.l2ActionsRequiringArgument.toSet();
  final rows = <FnthinkGrantItemRow>[];
  for (final action in contract.l2Actions) {
    // 参数形状的作者只有 `l2.reports` 那一格（kind 与上下界都写在那儿）。
    final declared = switch (contract.l2ReportKind(action)) {
      null => FnthinkGrantArgumentKind.none,
      'none' => FnthinkGrantArgumentKind.none,
      'count' => FnthinkGrantArgumentKind.count,
      'keyword' => FnthinkGrantArgumentKind.keyword,
      'channelTarget' => FnthinkGrantArgumentKind.channelTarget,
      final other => throw StateError(
        '契约 l2.reports 给 $action 声明了本机看不懂的 argumentKind「$other」：'
        '只剩「照着猜一种拼法」可走，而猜出来的串服务端整发拒',
      ),
    };
    // 两处对同一项的说法必须一致。`validate()` 钉的是"argumentKind 非 none 的项要列进
    // requiresArgumentFrom"与"none 的不许列"；这里钉的是另一头：**列了 requiresArgumentFrom
    // 却没有 argumentKind**（读出来是 none）—— 那种项的整串没有作者。
    final saysNeedsArgument = needsArgument.contains(action);
    if (saysNeedsArgument != (declared != FnthinkGrantArgumentKind.none)) {
      throw StateError(
        '$action 在两处说法不一致：requiresArgumentFrom ${saysNeedsArgument ? '列了' : '没列'}，'
        'l2.reports 的 argumentKind 却是 ${declared.name} —— '
        '同意屏与逐条判据会各按一种读法拼串',
      );
    }
    rows.add(FnthinkGrantItemRow(base: action, kind: declared));
  }
  for (final entry in contract.l3Settings.entries) {
    rows.add(
      FnthinkGrantItemRow(
        // L3 那一族的"参数"只有目标档一种（`grant` 型那四项是"请用户去系统里开"，没有档可选）。
        base: entry.key,
        kind: entry.value.isToggle
            ? FnthinkGrantArgumentKind.toggle
            : FnthinkGrantArgumentKind.none,
      ),
    );
  }
  final vocabulary = pairItemVocabulary(contract);
  final outside =
      rows.map((r) => r.base).where((b) => !vocabulary.contains(b)).toList()
        ..sort();
  if (outside.isNotEmpty) {
    throw StateError(
      '本机派生出的勾逐项不在契约声明的取值域里：$outside（取值域路径 = '
      '${contract.pairConfirmItemsVocabulary.join('/')}）—— '
      '服务端会整发拒（状态码由 unknownItemStatus 定），而用户在屏上刚勾完',
    );
  }
  return rows;
}

/// 词表里那些名字（逐条判据用它决定"这一串该不该由清单管"）。
Set<String> grantItemBases(FnthinkContract contract) =>
    pairItemRows(contract).map((r) => r.base).toSet();

/// 这一串能不能写进授权表。回 null = 能；回一句 = 理由（形状与服务端那一份同一）。
///
/// 四类理由**不许合并**（与 `parseL2Item` / `parseL3Item` 同一条纪律）：
///  - `unknown-item:<名>`   名字不在取值域里（服务端 400，状态码从 `unknownItemStatus` 读）
///  - 契约那句 `item-argument-required:<名>`  要参数的项给了裸名字（片4 收窄的那一维）
///  - `unexpected-argument:<名>`  不要参数的项带了参数（带了就是带了件没人认的东西）
///  - 各形状自己的理由      参数不成形（[reportArgumentProblem] / [rejectChannelTarget]）
/// 后两类不该被同意屏画出来（那些控件只产出成形的值），留着是因为这一枚判据同时服务
/// "答复发出去之前本机先看一眼"：那一步若撞上界面 bug，要能说出是哪一种。
String? grantItemProblem(FnthinkContract contract, String item) {
  final base = contract.grantItemBase(item);
  final argument = contract.grantItemArgument(item);
  final rows = pairItemRows(contract);
  final matching = rows.where((r) => r.base == base).toList();
  if (matching.isEmpty) return 'unknown-item:$base';
  final row = matching.first;
  // ⚠ 这里判的是"**有没有**那枚分隔符"，不是"参数段空不空"：`listener:start/` 的参数段
  // 是空串，按空串判就成了"没带参数"⇒ 那一串会被签出去，而线上从来发不出带尾斜杠的串，
  // 于是屏幕上"已授权"那一格里躺着一个永远判不过的东西（fail-closed，但没人看得出来）。
  final carriesArgument = item.contains(contract.grantItemSeparator);
  if (!row.needsArgument) {
    return carriesArgument ? 'unexpected-argument:$base' : null;
  }
  // 要参数的项：裸名字（以及带了个空参数的 `名/`）不再是合法的勾选项 —— 写进表里也永远
  // 判不过，见文件顶那一段。这一句从契约读：服务端拒收与本机留痕才回得了同一句话。
  if (argument.isEmpty) return contract.grantItemBareNameRejectedFor(base);
  return switch (row.kind) {
    FnthinkGrantArgumentKind.count || FnthinkGrantArgumentKind.keyword =>
      reportArgumentProblem(contract, base, argument),
    FnthinkGrantArgumentKind.channelTarget => rejectChannelTarget(
      contract,
      argument,
    ),
    FnthinkGrantArgumentKind.toggle =>
      contract.l3ItemTargetWords.contains(argument)
          ? null
          : 'unknown-target-word:$argument',
    FnthinkGrantArgumentKind.none => null,
  };
}
