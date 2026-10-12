/// 历史一屏读多少行 —— 三个档共用一枚数（T148 差异⑦ 把口径归一）。
///
/// 为什么只能有一枚：转发档翻页时每页 200，幻念那两档写死 100，远程执行那一档吃读口的
/// 缺省值 200。同一个「历史」页面上的三档，往下滚能看到的深度各不相同 —— 而用户读到
/// 「怎么这里翻到底了、那里还有」时，那是三处各写一次的数字，不是一句实话。
const int kHistoryPageSize = 200;

/// 把「一页一页的读口」续到取尽 —— T133 已拍「历史不设上限」的载体（那边是转发档的
/// 分页取数循环，这一件是另外两档的：它们此前**根本没有翻页**，超过写死的那一条就直接看不见，
/// 而界面不说少）。
///
/// ⚠ 适用口径：[readPage] 回来的**就是最终要画的那些行**（筛选已经在 SQL 的 `WHERE` 里做完）。
/// 转发那本账不归这件管：它读回来还要在 Dart 侧再筛一道，「这一页 0 条」不等于「后面没有了」，
/// 所以那边自带三元组 `(记录, hasMore, 本页粗筛行数)`（见 `history_page.dart` 的
/// `ForwardedPageLoader`）。把两截口径合成一件，等于把「空页不许冒充取尽」那条判据洗掉。
///
/// 终止条件只有一个：某一批回来**不满一页** ⇒ 读口到了尾。满页就一直续。
/// 游标按**已经拿到手的行数**走（`all.length`），不按「页号 × 每页」推 —— 后者在读口某一批
/// 少给一行时会让下一批往回拨，表现是同一行出现两次而后面永远读不到。
Future<List<T>> drainAllPages<T>(
  Future<List<T>> Function(int limit, int offset) readPage, {
  int pageSize = kHistoryPageSize,
}) async {
  final all = <T>[];
  var lastPageWasFull = true;
  while (lastPageWasFull) {
    final page = await readPage(pageSize, all.length);
    all.addAll(page);
    lastPageWasFull = page.length == pageSize;
  }
  return all;
}
