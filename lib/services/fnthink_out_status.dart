/// 幻念「发出」那一档该显示哪个状态词的**唯一作者**（P2-7）。
///
/// 数据只有两列：`ack_result`（服务端带回的对端回执原话）与 `acked_at`（对端收下
/// 的时刻）。此前后者只在详情页里以「对端接收时间」出现，列表行的 `statusMessage`
/// 对 outgoing 恒为 null ⇒ 手动发出去的一条在历史里永远看不出"到了没有"。
///
/// 映射到的是**既有送达词表**（`queued` / `delivered` / `displayed` / `failed`）：
/// 词表与人话的唯一作者在 `delivery_display.dart`，这里不另造一套措辞。
///
/// 为什么 `ack_result` 为空也算 `queued` 而不是"未知"：`_recordSentOut` 只在服务端
/// `accepted` 之后才写这一行（被拒的没有可记的事实），所以"这一行存在"本身就等于
/// "服务端已经替我们排上了" —— `queued` 是那一刻唯一为真的描述。
String fnthinkOutgoingStatusWord({
  required String ackResult,
  required int ackedAt,
}) {
  final word = ackResult.trim().toLowerCase();
  switch (word) {
    case 'delivered':
    case 'displayed':
      return word;
    case 'expired':
    case 'dropped':
      // 两个都是"服务端那边结束了、但对端没拿走"：对发送者而言与 failed 同一档，
      // 原始词仍留在详情页的 ack_result 里，排障时不会被这条映射抹掉。
      return 'failed';
  }
  if (word.isEmpty) {
    // 旧服务端/旧记录只落了时刻、没有回执词：有收下时刻就能确定"对面拿到了"。
    return ackedAt > 0 ? 'delivered' : 'queued';
  }
  // 认不出的词不硬翻译成某一档：原话交给 `delivery_display.dart` 说「未知状态」，
  // 与那一处 `default:` 的纪律一致（不替本机编一个"到了"或"失败"）。
  return word;
}
