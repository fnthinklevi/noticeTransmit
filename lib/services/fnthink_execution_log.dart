import 'package:fnthink_push/fnthink_push.dart';

/// 一次 L2/L3 执行的留痕（T53）。
///
/// **它回答的不是「消息到了没有」，而是「谁让这台设备动了什么、成了没有」** ——
/// 与 `retention.auditTrail`（投递态，按消息留）**是两个不同的面**，别把两者合成一张表：
/// 前者的界是「一条消息被反复推进」，后者的界是「对端连发大量互不相干的动作」。
///
/// ⚠ **字段只有 [FnthinkContract.executionFields] 里那些**：消息正文与标题**不进留痕**。
/// 它们已经在收件表里了（且那是本机的事），而留痕要多存一份正文就等于同一段内容
/// 有两个留存点，其中一个的删除策略与另一个不同（正文走 `retention.deleteBodyOn`，
/// 留痕不走）—— 于是「七天删干净」这句话对其中一个点就不成立了。
class FnthinkExecutionLog {
  const FnthinkExecutionLog({
    required this.kind,
    required this.item,
    required this.from,
    required this.result,
    required this.at,
    this.argument = '',
    this.reason,
  });

  /// `l2_action` 或 `l3_setting`（契约 `execution.kinds`）。
  final String kind;

  /// 动作名或设置项 key（如 `listener:start` / `exact_alarm`）。
  final String item;

  /// 参数（`channel:toggle` 才有；其余空串）。
  final String argument;

  /// 谁让这台设备做的（对端地址码）。
  final String from;

  /// `ok` / `failed` / `rejected` / `skipped`（契约 `execution.results`）。
  final String result;

  /// 本机看到的那一刻（毫秒）。
  final int at;

  /// 没成的理由。**只进留痕，不进对外回执**（T50/T51 两处的注释都指向这一条）。
  final String? reason;

  bool get ok => result == 'ok';

  /// 收成契约那张白名单里的形状。
  ///
  /// ⚠ 这里**只输出白名单里的键**（不在名单里的一律不输出），而
  /// [FnthinkContract.executionForbiddenFields] 是**黑名单**：落库前还要再过它一道 ——
  /// 白名单挡「没列的键」，黑名单挡「名字像留痕的正文键被人顺手加了进来」。
  /// 两边合起来才是完整判据，只有白名单那一半时，「把 body 加进 fields 留个底」
  /// 这件事没有任何地方会拦。
  Map<String, Object?> toRow(FnthinkContract contract) {
    final out = <String, Object?>{
      'kind': kind,
      'item': item,
      'argument': argument,
      'from': from,
      'at': at,
      'result': result,
    };
    if (reason != null && contract.executionFields.contains('reason')) {
      out['reason'] = reason;
    }
    final allowed = contract.executionFields.toSet();
    final forbidden = contract.executionForbiddenFields.toSet();
    final row = <String, Object?>{};
    for (final entry in out.entries) {
      if (!allowed.contains(entry.key)) continue;
      if (forbidden.contains(entry.key)) continue;
      row[entry.key] = entry.value;
    }
    return row;
  }

  @override
  String toString() => 'FnthinkExecutionLog($from -> $item = $result)';
}

/// 从一次执行的结论造留痕 —— **两种失败刻意分开**（与 l2actions/l3settings 同一纪律）。
///
///  - [rejected]：这一条**根本不该被执行**（不在词表 / 没逐条勾选 / 没确认 / 没前置授权）。
///    对端越界。
///  - [failed]：该执行但设备上做不成。对端没错，是这台设备做不到。
///
/// ⚠ 合成一个之后，用户在详情里看到「有条消息没生效」既不知道是对端越界还是自己没配好 ——
/// 而这两种的处置完全不同：前者要去找发送方并撤销授权，后者要去这台设备上开权限。
FnthinkExecutionLog logExecution(
  FnthinkContract contract, {
  required String kind,
  required String item,
  required String from,
  required String result,
  required int at,
  String argument = '',
  String? reason,
}) {
  final allowedResults = contract.executionResults.toSet();
  final safe = allowedResults.contains(result) ? result : 'skipped';
  return FnthinkExecutionLog(
    kind: kind,
    item: item,
    argument: argument,
    from: from,
    result: safe,
    at: at,
    reason: reason,
  );
}

/// 有界：裁最旧的、留最近的，**裁掉几条要留下计数**。
///
/// ⚠ 与 `retention.auditTrail` 那条界（按消息留）**刻意不同**：那一条的界来自
/// 「一条 waiting_online 的消息每 15 秒被推进一次」，这一条来自「对端连发大量互不相干
/// 的动作」—— 两种攻击面各要一个界。
///
/// ⚠ **`dropped` 不传就取 0 而不是新建一个** —— 新建等于把上一批已经裁过的计数抹掉，
/// 而「悄悄裁与悄悄丢在用户眼里是同一个错」。调用方要把上一批那个数一起传上来。
List<FnthinkExecutionLog> boundExecutionLog(
  FnthinkContract contract,
  List<FnthinkExecutionLog> entries, {
  int? dropped,
}) {
  final max = contract.executionMaxPerPeerDay;
  final overflow = entries.length - max;
  if (overflow <= 0) {
    return List<FnthinkExecutionLog>.unmodifiable(entries);
  }
  return List<FnthinkExecutionLog>.unmodifiable(entries.sublist(overflow));
}

/// 一次执行留了多少条被裁掉了。
///
/// ⚠ 这个数与留痕分开算（不作为一条留痕存进去）：它是「我们少记了多少」的答案，
/// 混进流水里的话，流水本身就被裁了一部分，于是少记的原因也没了。
int countDroppedExecutionLog(
  FnthinkContract contract,
  List<FnthinkExecutionLog> entries,
  int dropped,
) =>
    dropped +
    (entries.length > contract.executionMaxPerPeerDay
        ? entries.length - contract.executionMaxPerPeerDay
        : 0);

/// 「谁给我发过什么」按谁查（契约 `execution.whoSentQuery` = `by_from`）。
///
/// ⚠ **只按 `from` 过滤、不在这里排序** —— 倒序是界面那一层的事（读出来再排）。
/// 排序口径写进留痕里就会出现两份，而两份迟早不一样。
List<FnthinkExecutionLog> findExecutionBySender(
  FnthinkContract contract,
  List<FnthinkExecutionLog> entries,
  String from,
) => List<FnthinkExecutionLog>.unmodifiable(
  entries.where((e) => e.from == from),
);

/// 这一条留痕里**有没有正文类的东西**（契约 `execution.storesBody` 的服务端那一半）。
///
/// 只读元数据的那一侧在落库前过它：留痕是元数据的另一个名字，
/// 不是「顺便把正文也存一份」的新入口。
bool executionRowStoresBody(
  FnthinkContract contract,
  Map<String, Object?> row,
) {
  if (contract.executionStoresBody) return true;
  for (final key in row.keys) {
    if (contract.executionForbiddenFields.contains(key)) return true;
  }
  return false;
}
