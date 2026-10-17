import 'package:flutter/foundation.dart';
import 'package:fnthink_push/fnthink_push.dart';

import '../database/database_helper.dart';
import '../models/fnthink_inbox_message.dart';
import '../services/fnthink_settings.dart';

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
///
/// 这一片被砸过什么（反证报告在本地 outputs/_inbox_svc_falsify.report.txt，按约定不入库；
/// 四条全部 named + restored，逐条点名）：
///  - 把 DI 里那行注册摘掉 ⇒ 只有装配守卫「DI 里真的注册了它」红，其余 13 条全绿 ——
///    这就是"漏接时没人喊"的形状，所以那条守卫留着，别当成冗余删掉。
///  - 页面读侧退回直连表 ⇒ 红在「历史页的收件档走服务层」；写侧退回 ⇒ 红在同一条。
///  - 在这层里加一枚自己的排序常量（= 口径长出第二份）⇒ 红在「服务层只转发，没把查询自己抄一份」。
class FnthinkInboxService {
  FnthinkInboxService({DatabaseHelper? db, this.contract})
    : _db = db ?? DatabaseHelper();

  final DatabaseHelper _db;

  /// T47 的 prune 要经 `FnthinkSettings` 读保留档位，而后者构造要契约。
  /// 生产装配从契约装载器拿；测试不传 ⇒ pruneRetention 会跳过并记日志
  /// （不崩 —— 裁剪是维护性动作，协议没装载不该把它变成收货故障）。
  final FnthinkContract? contract;

  /// T47：按保留策略裁收件表。唯一调用点 = 首页启动/回前台那一发
  /// （`main_page_actions._startHealthProbeCadence` 同批）—— 不放进收货循环每一轮：
  /// prune 是一张表的删除扫描，5–60 秒一轮的频率对它毫无意义，而保留下界
  /// 也不需要那个频率。失败只记日志：裁不动这一轮下一轮还会再来，
  /// 断在收货链上才是事故。
  Future<({int byAge, int byCap})> pruneRetention() async {
    final c = contract;
    if (c == null) {
      debugPrint('[fnthink] 收件保留裁剪跳过：契约未装载');
      return (byAge: 0, byCap: 0);
    }
    final days = await FnthinkSettings(contract: c).retentionDays();
    try {
      return await _db.pruneFnthinkInbox(
        olderThanDays: days,
        maxRows: FnthinkSettings.inboxMaxRows,
      );
    } catch (e) {
      debugPrint('[fnthink] 收件保留裁剪失败（下一轮再来）: $e');
      return (byAge: 0, byCap: 0);
    }
  }

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

  /// 「我发过的」（T43）：同一张表的另一半，按同一个口径排序、同一个 limit。
  /// 未读与本方法无关 —— **发出的一条没有"未读"这回事**（未读是别人推给我、我还没看的那个数）。
  Future<List<FnthinkInboxMessage>> listSent({
    int limit = 50,
    int offset = 0,
  }) => _db.loadFnthinkInbox(
    limit: limit,
    offset: offset,
    direction: kFnthinkDirectionOut,
  );

  /// 未读数。首页那张入口卡、历史页收件档、推送页的状态行说的是**同一个数**，所以数法只留一处。
  /// ⚠ 别让调用方自己 `list(unreadOnly: true).length` 去数：列表有 `limit`，
  /// 收到第 51 条时那条口径就会开始少报，而它少报的样子和"真的没有未读"一模一样。
  /// ⚠ 它只数**收件**（`direction='in'` 那条 WHERE 在 `DatabaseHelper` 里）：把发出的那半也数
  /// 进来，表现是"回一条消息、首页未读立刻多一条"，而用户根本没收到任何东西。
  Future<int> unreadCount() => _db.countFnthinkInboxUnread();

  /// 标已读，回**有没有命中**那一行。false 的意思是"这条已经不在了"（被保留策略裁掉），
  /// 调用方要据此让界面消失一行，而不是把它显示成"已读" —— 给不存在的东西记已读，
  /// 表现就是未读数被凭空减掉。
  Future<bool> markRead(String messageId) =>
      _db.markFnthinkInboxRead(messageId);
}
