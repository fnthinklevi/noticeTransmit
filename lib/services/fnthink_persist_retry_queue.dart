import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/fnthink_inbox_message.dart';

/// P1-1：收件落库失败时的**本地待重试队列**。
///
/// 之前的行为（`fnthink_receive_loop.dart` 的不变量 ①）：这一条不 ack，交给服务端
/// 每轮重投（`delivery.js` 的 `no_ack`，3 次，`ackDeadlineSeconds=180`）。那条路只有
/// 3 分钟 —— 磁盘满、SQLCipher 密钥损坏、库文件损坏都不会在 3 分钟内自愈，于是消息
/// 在服务端重投耗尽后被静默丢弃（幽灵消息）。
///
/// 这里补的是**本机自己**的那一段：落库抛异常时先把整行原文扣在 prefs 里，下一轮
/// 开跑之前再试一次，一直试到成功、过期（[maxAgeMs]）或次数用尽（[maxAttempts]）。
/// 放弃的条数落一个本地事实（[abandonedCount]），界面据此给出明确计数，而不是只剩
/// 一行 debugPrint。
///
/// 为什么是 prefs 而不是新建 DB 表：
///  - 这条队列存在的**唯一前提**就是"写不进 DB"。把队列放进同一张库，等于让救命绳
///    系在要救的那个人身上。
///  - 也不走 `SecureStorageService`：它自己会抛/超时（`SecureStorageUnavailable`），
///    不能当"必成功"的落点。
///  - prefs 与 `FnthinkDeliveryLinkStore`、幻念转发待发队列同族，是这里已被验证过的
///    形状。**只写 String/int**（`shared_preferences_jni_integer_guard_test.dart`：
///    原生往 FlutterSharedPreferences 写过 Float 会让 `getAll` 抛 ArgumentError）。
///
/// 容量与期限（不许无限重试占满磁盘）：
///  - 最多 [maxRows] 条，超出时丢**最旧**的那条并记一次放弃；
///  - 单条最多留 [maxAgeMs]，超龄按放弃处理；
///  - 单条最多试 [maxAttempts] 次，用完按放弃处理。
///
/// 队列只存必要字段（复用 [FnthinkInboxMessage.toDbRow] 的 14 列形状），不带任何
/// 与入库无关的东西 —— 它迟早要变回一条普通的收件行。
class FnthinkPersistRetryQueue {
  FnthinkPersistRetryQueue({
    required this.persist,
    Future<SharedPreferences> Function()? prefs,
    int Function()? nowMs,
  }) : _prefs = prefs ?? SharedPreferences.getInstance,
       _nowMs = nowMs ?? _systemNowMs;

  /// 重试时用的落库钩子 —— 与收货循环那一格是**同一个**函数，不另开一条写入路。
  final Future<bool> Function(FnthinkInboxMessage message) persist;

  final Future<SharedPreferences> Function() _prefs;
  final int Function() _nowMs;

  /// 队列本体。值是一段 JSON 数组文本。
  static const String queueKey = 'fnthink.persist.retry.v1';

  /// 已放弃的累计条数（int）。
  static const String abandonedKey = 'fnthink.persist.abandoned.v1';

  /// 队列上限：再多的失败也只会占这么多条的位置。
  static const int maxRows = 50;

  /// 单条最长保留 24 小时，超龄即放弃。
  static const int maxAgeMs = 24 * 60 * 60 * 1000;

  /// 单条最多重试 20 次。
  static const int maxAttempts = 20;

  static int _systemNowMs() => DateTime.now().toUtc().millisecondsSinceEpoch;

  /// 把一条落库失败的行放进队列。
  ///
  /// 入队本身失败（prefs 写不进去）只记日志 —— 调用点已经在处理一次失败，不能
  /// 让第二层失败把收件循环打断。
  Future<void> enqueue(FnthinkInboxMessage message) async {
    try {
      final prefs = await _prefs();
      await prefs.reload();
      final rows = _read(prefs);
      rows.removeWhere((e) => e.row.messageId == message.messageId);
      rows.add(_Entry(row: message, at: _nowMs(), attempts: 0));
      var abandoned = 0;
      while (rows.length > maxRows) {
        rows.removeAt(0);
        abandoned += 1;
      }
      await prefs.setString(queueKey, _encode(rows));
      if (abandoned > 0) await _addAbandoned(prefs, abandoned);
      debugPrint(
        '[fnthink] 收件落库失败已进本地重试队列: ${message.messageId}'
        '（队列 ${rows.length} 条${abandoned > 0 ? '，挤掉 $abandoned 条旧的' : ''}）',
      );
    } catch (e) {
      debugPrint('[fnthink] 落库重试队列入队失败（这条只剩服务端重投）：${message.messageId} $e');
    }
  }

  /// 下一轮开跑前调一次：把队列里的每一条再试一遍。
  ///
  /// 成功的移出队列；失败的累加次数；超龄或超次数的按放弃移出并计数。
  /// **不改调用方的 ack 判据** —— 重试成功只意味着这条现在在收件表里了，
  /// 它下一次被服务端重投时会走正常的 `known` 分支。
  Future<FnthinkPersistRetryReport> drain() async {
    var persisted = 0;
    var abandoned = 0;
    try {
      final prefs = await _prefs();
      await prefs.reload();
      final rows = _read(prefs);
      if (rows.isEmpty) return const FnthinkPersistRetryReport.empty();
      final now = _nowMs();
      final keep = <_Entry>[];
      for (final entry in rows) {
        if (now - entry.at > maxAgeMs || entry.attempts >= maxAttempts) {
          abandoned += 1;
          debugPrint('[fnthink] 落库重试已放弃（超龄或超次数）: ${entry.row.messageId}');
          continue;
        }
        try {
          await persist(entry.row);
          persisted += 1;
        } catch (e) {
          debugPrint('[fnthink] 落库重试仍失败: ${entry.row.messageId} $e');
          if (entry.attempts + 1 >= maxAttempts) {
            abandoned += 1;
          } else {
            keep.add(entry.nextAttempt());
          }
        }
      }
      await prefs.setString(queueKey, _encode(keep));
      if (abandoned > 0) await _addAbandoned(prefs, abandoned);
      if (persisted > 0 || abandoned > 0) {
        debugPrint(
          '[fnthink] 落库重试：入库 $persisted 条'
          '${abandoned > 0 ? '，放弃 $abandoned 条' : ''}，仍在队列 ${keep.length} 条',
        );
      }
      return FnthinkPersistRetryReport(
        persisted: persisted,
        abandoned: abandoned,
        pending: keep.length,
      );
    } catch (e) {
      debugPrint('[fnthink] 落库重试队列处理失败（下一轮再来）：$e');
      return FnthinkPersistRetryReport(
        persisted: persisted,
        abandoned: abandoned,
        pending: 0,
      );
    }
  }

  /// 队列里还剩几条（界面读来分辨"还会自己好"与"已经放弃"）。
  Future<int> pendingCount() async {
    try {
      final prefs = await _prefs();
      await prefs.reload();
      return _read(prefs).length;
    } catch (e) {
      debugPrint('[fnthink] 读落库重试队列条数失败：$e');
      return 0;
    }
  }

  /// 累计已放弃的条数 —— **这条是界面要的"明确计数"**。
  Future<int> abandonedCount() async {
    try {
      final prefs = await _prefs();
      await prefs.reload();
      return prefs.getInt(abandonedKey) ?? 0;
    } catch (e) {
      debugPrint('[fnthink] 读落库放弃条数失败：$e');
      return 0;
    }
  }

  /// 清掉放弃计数（用户看过之后由界面调；队列本体不动）。
  Future<void> clearAbandoned() async {
    try {
      final prefs = await _prefs();
      await prefs.reload();
      await prefs.remove(abandonedKey);
    } catch (e) {
      debugPrint('[fnthink] 清落库放弃条数失败：$e');
    }
  }

  Future<void> _addAbandoned(SharedPreferences prefs, int delta) async {
    final next = (prefs.getInt(abandonedKey) ?? 0) + delta;
    await prefs.setInt(abandonedKey, next);
  }

  List<_Entry> _read(SharedPreferences prefs) {
    final raw = prefs.getString(queueKey);
    if (raw == null || raw.isEmpty) return <_Entry>[];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return <_Entry>[];
      final out = <_Entry>[];
      for (final item in list) {
        final entry = _Entry.fromJson(item);
        // 坏形状整条跳过：一条读不出来不该把整队拖下水。
        if (entry != null) out.add(entry);
      }
      return out;
    } catch (e) {
      debugPrint('[fnthink] 落库重试队列读不出来（按空队列处理）：$e');
      return <_Entry>[];
    }
  }

  String _encode(List<_Entry> rows) =>
      jsonEncode(rows.map((e) => e.toJson()).toList());
}

/// 一次重试的结果。数值都对得上界面那一行提示。
@immutable
class FnthinkPersistRetryReport {
  const FnthinkPersistRetryReport({
    required this.persisted,
    required this.abandoned,
    required this.pending,
  });

  const FnthinkPersistRetryReport.empty()
    : persisted = 0,
      abandoned = 0,
      pending = 0;

  /// 这一轮补写进收件表的条数。
  final int persisted;

  /// 这一轮被判放弃的条数。
  final int abandoned;

  /// 处理完之后队列里还剩几条。
  final int pending;
}

/// 队列里的一格：整行原文 + 入队时刻 + 已经试过几次。
@immutable
class _Entry {
  const _Entry({required this.row, required this.at, required this.attempts});

  final FnthinkInboxMessage row;

  /// 入队时刻（毫秒）。超龄判据只用它。
  final int at;

  final int attempts;

  _Entry nextAttempt() => _Entry(row: row, at: at, attempts: attempts + 1);

  Map<String, Object?> toJson() => {'r': row.toDbRow(), 'a': at, 'n': attempts};

  static _Entry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final rowRaw = raw['r'];
    if (rowRaw is! Map) return null;
    final at = raw['a'];
    final attempts = raw['n'];
    if (at is! int || attempts is! int) return null;
    try {
      final row = FnthinkInboxMessage.fromDbRow(
        rowRaw.map((k, v) => MapEntry(k.toString(), v)),
      );
      return _Entry(row: row, at: at, attempts: attempts);
    } catch (e) {
      debugPrint('[fnthink] 落库重试队列里有一条读不回来（跳过）：$e');
      return null;
    }
  }
}
