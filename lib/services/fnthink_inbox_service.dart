import '../database/database_helper.dart';
import '../models/fnthink_inbox_message.dart';

/// 收件（别人推给本机的消息）的读写咽喉（T48 的数据层半边）。
///
/// 为什么要单独一层，而不是让页面直接摸 `DatabaseHelper`：
/// **未读数、排序口径、"标已读到底命中没有"这三件事只能有一处算法**。首页入口卡、
/// 幻念推送页、历史页的收件档都要读同一个数；三处各写一句 `WHERE read = 0`，
/// 早晚有一处写成 `read = 1` 或者忘了被 prune 裁掉的那批 —— 而那正是本仓反复出过的
/// "同一个事实抄几份，抄漏的那份不报错，只是某些入口行为不同"。
///
/// 这层**只转发、不加判断**：幂等入库、prune 的两条计数、`read` 只能 0/1 这些语义都留在
/// `DatabaseHelper` 与 `FnthinkInboxMessage` 那边（一处一层，不是两处）。
class FnthinkInboxService {
  FnthinkInboxService({DatabaseHelper? db}) : _db = db ?? DatabaseHelper();

  final DatabaseHelper _db;

  /// 收件列表，新到的在前。`limit`/`offset` 的口径与推送历史一致。
  Future<List<FnthinkInboxMessage>> list({
    int limit = 50,
    int offset = 0,
    bool unreadOnly = false,
  }) => _db.loadFnthinkInbox(
    limit: limit,
    offset: offset,
    unreadOnly: unreadOnly,
  );

  /// 标已读，回**有没有命中**那一行。false 的意思是"这条已经不在了"（被保留策略裁掉），
  /// 调用方要据此让界面消失一行，而不是把它显示成"已读" —— 给不存在的东西记已读，
  /// 表现就是未读数被凭空减掉。
  Future<bool> markRead(String messageId) =>
      _db.markFnthinkInboxRead(messageId);
}
