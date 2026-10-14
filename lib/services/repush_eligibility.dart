/// 「这一通道能不能再发一次」的判据（T133 片1，**唯一作者**）。
///
/// 这里回答的是一个问题，而它常被和另一个问题混起来 —— 混起来就是那条缺陷：
///
/// | 问题 | 谁回答 | 含 `intercepted` 吗 |
/// |---|---|---|
/// | 这条**送达了吗**（筛选、状态词、计数） | `lib/models/delivery_status.dart`：词表 + 精筛，SQL 粗筛的 LIKE 参数由那张表生成 | **含** —— 被拦截的确实没送达 |
/// | 这条**可以再发一次吗**（批量池、勾选框、单条「现在推送」） | 本文件 | **不含** —— 那是用户自己定的过滤规则，替他推翻它不是"重推" |
///
/// 改之前两件事共用一个 `hasFailedChannel`（只认 `failed`），于是"筛选筛得出 intercepted、
/// 批量却选不中"这一类自相矛盾出现在界面上（维护者 2026-10-10 第 7 条点名的形状之一）。
///
/// ⚠ 另外三条**不进批量池**，各有一句理由（片9 起它们仍进**单条**那一档，见 [RepushIntent] ——
/// 批量是"给一批补缺"，单条是"用户当场对着这一条做一次决定"，两格语义本来就不同）：
/// - `success`：再发一遍 = 同一条通知推两次。收件端那条消息不会因为"重推"而消失。
/// - `pending`：还在途。重推就是拿"再发一次"去和"这一次可能正在发"抢，at-least-once 之上再叠一层。
/// - 空 / 异形：这一条从来没有送达记录 —— 典型是"仅记录不推送"与规则 `Record` 那一档，
///   那是用户明说"这条别发"。把"没有记录"读成"失败了"会静默扩张推送范围（批量池因此不收它；
///   单条那一枚要发它，得由用户自己按下去）。
library;

/// 一个通道条目该不该被再发一次。[info] 是送达 map 里那一格（正常是 `Map`，也可能是异形值）。
bool channelNeedsRepush(Object? info) {
  if (info is! Map) return false;
  final status = info['status']?.toString() ?? '';
  return status == 'failed' || status == 'paused';
}

/// 一条记录要不要进重推池（= 至少一个通道该再发一次）。
bool recordNeedsRepush(Map<String, dynamic> deliveryStatus) {
  return deliveryStatus.values.any(channelNeedsRepush);
}

/// 这一条里该再发的那几把（保持记录里的原顺序，界面按它列明细）。
List<String> repushableChannels(Map<String, dynamic> deliveryStatus) {
  return deliveryStatus.entries
      .where((e) => channelNeedsRepush(e.value))
      .map((e) => e.key)
      .toList();
}

/// 历史页那一枚行内出口的**口径**（T133 片9，走 (b)：每一条转发行都给出口）。
///
/// 为什么必须分成三档、又为什么两档共用一句文案：这一枚按钮要回答的是
/// **「按哪些通道把这一条发出去」**，而那条问题的答案有三种真不同的事实：
///
/// | 档 | 这条此刻的状态 | 范围 | 界面说的话 |
/// |---|---|---|---|
/// | [RepushIntent.missing] | 有通道 `failed`／`paused` | 只有那几族（其余原样保留） | 「现在推送」 |
/// | [RepushIntent.unsent] | 整条**没有**送达记录 | 当前启用的全部通道（缺省＝不限定） | 「现在推送」 |
/// | [RepushIntent.again] | 每一族都有了终态或还在途 | 这条快照里的全部通道键 | 「再发一次」 |
///
/// ⚠ 前两档共用「现在推送」不是偷懒：它们在用户眼里是同一句话 —— **这一条还没（完全）发出去，
/// 现在把它发出去**。第三档说的是另一件事：它已经发出去了，**点它就是主动要收件端再多收一条**。
/// 把这句也用「现在推送」写，等于让界面在同一枚钮下藏两种后果 —— 那正是片1 之前「同一枚
/// monitoring 两套人话」那一族的形状。**一枚钮两种口径必须靠文案分开**，靠图标分开不够。
///
/// ⚠ [RepushIntent.again] 含被规则拦下的（`intercepted`）那几条：这一档说的是"这条有送达记录、
/// 现在要再发一遍"，而用户当场点这一枚就是**显式推翻**那条过滤 —— 与 [RepushIntent.unsent]
/// （"仅记录不推送"那一档）同理。**批量池不吃这一档**（那里仍是「补缺」，见 [recordNeedsRepush]），
/// 所以"这条被拦下的能选进批量吗"答案是不不能，而"这一行有没有出口"答案是有的：两格语义不同，
/// 不是自相矛盾。
enum RepushIntent { missing, unsent, again }

/// 这一条落进哪一档（**唯一作者**；文案与范围都从这里取，两边不可能分家）。
RepushIntent repushIntentOf(Map<String, dynamic> deliveryStatus) {
  if (recordNeedsRepush(deliveryStatus)) return RepushIntent.missing;
  // 空 map = 这条从没推过（"仅记录不推送"、规则 `Record` 那一档）。
  // 判序有意：先认"还有没发出去的"，再分"整条没记录"与"有记录但都落了终态"。
  if (deliveryStatus.isEmpty) return RepushIntent.unsent;
  return RepushIntent.again;
}

/// 这一发要覆盖的送达键。返回 `null` = **不限定**（交 service 按当前启用通道整表重建），
/// 与"空集合 = 谁都不发"是两件事 —— 那一句的判据在 [pushRecordNow] 与原生 `RepushScope` 两侧同源。
List<String>? repushScopeKeys(Map<String, dynamic> deliveryStatus) {
  return switch (repushIntentOf(deliveryStatus)) {
    RepushIntent.missing => repushableChannels(deliveryStatus),
    RepushIntent.unsent => null,
    RepushIntent.again => deliveryStatus.keys.toList(),
  };
}
