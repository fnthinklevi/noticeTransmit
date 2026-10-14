import 'package:flutter_test/flutter_test.dart';
import 'package:notice_transmit/database/database_helper.dart';
import 'package:notice_transmit/models/delivery_status.dart';

/// P1 历史搜索 SQL 构建纯函数单测。
/// 锁定 buildSearchSql 的 WHERE 拼接行为：条件组合、LIKE 转义、
/// 送达状态 JSON 粗筛（不引 JSON1 依赖）。
void main() {
  group('buildSearchSql', () {
    test('无条件时返回空 WHERE', () {
      final (where, args) = DatabaseHelper.buildSearchSql();
      expect(where, '');
      expect(args, isEmpty);
    });

    test('关键字匹配 title/content/app_name/package_name 四列', () {
      final (where, args) = DatabaseHelper.buildSearchSql(keyword: '验证码');
      expect(
        where,
        "WHERE (title LIKE ? ESCAPE '\\' OR content LIKE ? ESCAPE '\\' "
        "OR app_name LIKE ? ESCAPE '\\' OR package_name LIKE ? ESCAPE '\\')",
      );
      expect(args.length, 4);
      expect(args.every((a) => a == '%验证码%'), isTrue);
    });

    test('时间范围转为 post_time 区间（start 含、end 不含）', () {
      final (where, args) = DatabaseHelper.buildSearchSql(
        startTime: 1000,
        endTime: 2000,
      );
      expect(where, 'WHERE post_time >= ? AND post_time < ?');
      expect(args, [1000, 2000]);
    });

    test('应用名/包名 LIKE 条件', () {
      final (where, args) = DatabaseHelper.buildSearchSql(
        appName: '微信',
        packageName: 'com.tencent.mm',
      );
      expect(
        where,
        "WHERE app_name LIKE ? ESCAPE '\\' AND package_name LIKE ? ESCAPE '\\'",
      );
      expect(args, ['%微信%', '%com.tencent.mm%']);
    });

    test('送达状态那一档筛的是 delivery_bucket（T133 走 (c)：不再对 JSON 文本 LIKE）', () {
      // 旧形状是"SQL 拿 delivery_info 文本 LIKE 粗筛 + Dart 精筛"，两层必然宽窄不一 ⇒
      // 每页条数在跳、hasMore 说的不是用户看到的那个数。走 (c) 之后判据只有一遍，
      // 存成一列、SQL 等值筛。这里钉的是"筛的是桶列"与"档名当值用"这两件事。
      final (where1, args1) = DatabaseHelper.buildSearchSql(
        deliveryFilter: deliveryFilterNotDelivered,
      );
      expect(where1, 'WHERE delivery_bucket = ?');
      expect(args1, [deliveryBucketNotDelivered]);

      final (where2, args2) = DatabaseHelper.buildSearchSql(
        deliveryFilter: deliveryFilterDelivered,
      );
      expect(where2, 'WHERE delivery_bucket = ?');
      expect(args2, [deliveryBucketDelivered]);

      final (where3, args3) = DatabaseHelper.buildSearchSql(
        deliveryFilter: deliveryFilterAll,
      );
      expect(where3, '');
      expect(args3, isEmpty);
    });

    test('认不出的档名仍然 fail-closed：等值筛一个不在值域里的串，一行都不给', () {
      // 这一支是走 (c) 时最容易顺手丢掉的东西：旧那句精筛对陌生档名返回 false（什么都看不见），
      // 而"只认两个档名、其余不加 WHERE"的新写法会把同一个输入变成**全部记录** ——
      // 一个漂掉的旧 id（比如界面还在传 'failed'）就从"筛不到"变成"没筛"，读起来完全相反。
      final (where, args) = DatabaseHelper.buildSearchSql(
        deliveryFilter: 'failed',
      );
      expect(where, 'WHERE delivery_bucket = ?');
      expect(args, ['failed']);
    });

    test('LIKE 通配符转义：用户输入 % _ \\ 不引起意外匹配', () {
      final (where, args) = DatabaseHelper.buildSearchSql(
        keyword: r'50%_off\a',
      );
      expect(
        where,
        "WHERE (title LIKE ? ESCAPE '\\' OR content LIKE ? ESCAPE '\\' "
        "OR app_name LIKE ? ESCAPE '\\' OR package_name LIKE ? ESCAPE '\\')",
      );
      expect(args.every((a) => a == r'%50\%\_off\\a%'), isTrue);
    });

    test('组合条件按 AND 连接', () {
      final (where, args) = DatabaseHelper.buildSearchSql(
        keyword: '验证码',
        startTime: 1000,
        packageName: 'com.a',
        deliveryFilter: deliveryFilterNotDelivered,
      );
      expect(
        where,
        "WHERE (title LIKE ? ESCAPE '\\' OR content LIKE ? ESCAPE '\\' "
        "OR app_name LIKE ? ESCAPE '\\' OR package_name LIKE ? ESCAPE '\\') "
        "AND post_time >= ? AND package_name LIKE ? ESCAPE '\\' "
        'AND delivery_bucket = ?',
      );
      expect(args.length, 7);
      expect(args[4], 1000);
      expect(args[6], deliveryBucketNotDelivered);
      // ⚠ 这一层不该再出现任何状态词（'failed' / 'intercepted' / 'paused' / 'success'）：
      //   出现了就是"判据在这一层又抄了一遍"，而抄的那一份不会跟着词表动。
      expect(
        args.whereType<String>().where((a) => notDeliveredStatuses.contains(a)),
        isEmpty,
        reason: 'SQL 那一层的参数里出现了状态词',
      );
    });

    test('空白关键字视为无关键字', () {
      final (where, args) = DatabaseHelper.buildSearchSql(keyword: '   ');
      expect(where, '');
      expect(args, isEmpty);
    });
  });

  group('escapeLike', () {
    test('转义反斜杠/百分号/下划线并去除首尾空白', () {
      expect(DatabaseHelper.escapeLike(r'a\b%c%d_'), r'a\\b\%c\%d\_');
      expect(DatabaseHelper.escapeLike('  plain  '), 'plain');
    });
  });
}
