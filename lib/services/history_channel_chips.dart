/// 历史记录里那一串通道 chip 的**排法与折法**（T133 片2，唯一作者）。
///
/// 现状缺陷（维护者 2026-10-10 第 8 条）：一条记录有几个通道就画几枚 chip，
/// 顺序抄 `record.channels`（配置顺序，与"哪条出问题了"无关）、无上限、无折叠
/// ⇒ 通道一多就是 N 枚 chip 换行堆叠、行高不定，而**真失败的那枚被埋在中间**。
///
/// 这一页排的是"先看谁"，不是"送达了吗"也不是"可以再发一次吗" ——
/// 那两问各有一位作者（`NotificationService.matchDeliveryFilter` 与
/// `repush_eligibility.dart`），本文件不回答它们，只决定**出现的顺序与露出的枚数**。
/// 之所以三者不能合成一个：注意力序要把 `intercepted` 排在前面（那是通道级事实），
/// 而重推池必须把它排在外面（那是用户自己定的规则）。
library;

/// 一屏内一行放得下的枚数。⚠ 按 393dp（MEIZU 21 走查那台）的行宽粗估：
/// 一行两枚稳、三枚看名字长度，四枚之后必然换行 —— 它钉的是"只有一处口径"，
/// 不是"这个数正好"；换机型要重看（同 `normalizeAlias` 那条纪律）。
const int visibleChannelChipCount = 4;

/// 注意力档位（小的在前）。
///
/// - `failed`／`paused` = 要人动手的那两档（与重推池同集合，但**这不是巧合也不是定义** ——
///   把两者绑成一个判据就又长回"一个名字答两个问题"）；
/// - `intercepted` = 被用户自己的规则拦下，看得见就够了，不需要动手；
/// - `sending`／`pending`／**说不清的（含空状态）** = 还没个结论，等一下或本就是"仅记录"；
/// - `success` = 没事，排最后。
int deliveryAttention(String status) {
  const attention = <String, int>{
    'failed': 0,
    'paused': 1,
    'intercepted': 2,
    'sending': 3,
    'pending': 3,
    'success': 4,
  };
  return attention[status] ?? 3;
}

String _statusOf(Map<String, dynamic> deliveryStatus, String channel) {
  final info = deliveryStatus[channel];
  return info is Map ? (info['status']?.toString() ?? '') : '';
}

/// 按注意力排好序的通道名。
///
/// ⚠ **稳定**排序：同档保持记录里的原顺序。否则每次 rebuild 都可能换序，
/// 同一行在两次泵帧之间自己跳 —— 那不是信息，是噪音。
List<String> orderChannelsByAttention(
  List<String> rows,
  Map<String, dynamic> deliveryStatus,
) {
  final indexed = rows.asMap().entries.toList();
  indexed.sort((a, b) {
    final byAttention = deliveryAttention(
      _statusOf(deliveryStatus, a.value),
    ).compareTo(deliveryAttention(_statusOf(deliveryStatus, b.value)));
    return byAttention != 0 ? byAttention : a.key.compareTo(b.key);
  });
  return indexed.map((e) => e.value).toList();
}

/// 露出来的那几枚：折叠态只露前 [visibleChannelChipCount] 枚，展开态全露。
List<String> visibleChannelChips(
  List<String> ordered, {
  bool expanded = false,
}) {
  if (expanded || ordered.length <= visibleChannelChipCount) return ordered;
  return ordered.sublist(0, visibleChannelChipCount);
}

/// 被折起来的枚数（0 = 没有"还有几枚"那一枚，界面据此决定画不画）。
int foldedChannelChipCount(List<String> ordered) {
  final hidden = ordered.length - visibleChannelChipCount;
  return hidden > 0 ? hidden : 0;
}
